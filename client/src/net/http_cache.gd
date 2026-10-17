class_name HttpCache
extends Node
## Downloads files over HTTP and keeps them on disk.
##
## - Fresh files (younger than max_age) are served from disk without any request.
## - Stale files are revalidated with If-None-Match / If-Modified-Since (304 = keep).
## - If the network fails, the stale copy is used, so the client works offline.
## - At most MAX_CONCURRENT requests run at once; the same URL is never fetched twice in parallel.

## Emitted when a URL was downloaded with new content (not for cache hits or 304).
signal updated(url: String)
## While a download runs, once per frame: bytes so far and the total (-1 if unknown).
signal progress(url: String, downloaded: int, total: int)
signal _request_finished(url: String)

const MAX_CONCURRENT := 4

var root := "user://cache"
var _active := 0
var _in_flight := {}


func _init(cache_root := "user://cache") -> void:
	root = cache_root


## Returns the cached bytes for a URL without any network access ("" if not cached).
func read_cached(url: String) -> PackedByteArray:
	var path := path_for(url)
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


## Returns the file's bytes, downloading or revalidating it if needed. Empty on failure
## (e.g. 404, or offline with nothing cached). Must be awaited.
func fetch(url: String, max_age_sec: int) -> PackedByteArray:
	var path := path_for(url)
	var meta := {}
	var cached := false
	var now := 0
	while true:
		meta = _read_meta(path)
		cached = FileAccess.file_exists(path)
		now = int(Time.get_unix_time_from_system())
		if cached and now - int(meta.get("fetched_at", 0)) < max_age_sec:
			return read_cached(url)
		if _in_flight.has(url):
			# Another caller is already downloading this URL: wait and share its result.
			while _in_flight.has(url):
				await _request_finished
			return read_cached(url)
		if _active < MAX_CONCURRENT:
			break
		# All slots are busy. Check again after waiting: meanwhile another caller may have
		# started or finished downloading this URL.
		await _request_finished
	_active += 1
	_in_flight[url] = true

	# Name the client to the servers it downloads from (data, sprites, ratings, news).
	var headers := PackedStringArray([LoginClient.user_agent()])
	if cached and meta.has("etag"):
		headers.append("If-None-Match: " + str(meta["etag"]))
	if cached and meta.has("last_modified"):
		headers.append("If-Modified-Since: " + str(meta["last_modified"]))

	var response: Dictionary = await _request(url, headers)
	var code: int = response.get("code", 0)
	var response_headers: PackedStringArray = response.get("headers", PackedStringArray())
	var body: PackedByteArray = response.get("body", PackedByteArray())
	_active -= 1
	_in_flight.erase(url)

	var result := PackedByteArray()
	if code == 200:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(body)
			file.close()
		meta = {"url": url, "fetched_at": now}
		var etag := _header(response_headers, "etag")
		var last_modified := _header(response_headers, "last-modified")
		if not etag.is_empty():
			meta["etag"] = etag
		if not last_modified.is_empty():
			meta["last_modified"] = last_modified
		_write_meta(path, meta)
		result = body
		updated.emit(url)
	elif code == 304 and cached:
		meta["fetched_at"] = now
		_write_meta(path, meta)
		result = read_cached(url)
	elif cached:
		push_warning("Using stale cache for %s (HTTP %d)" % [url, code])
		result = read_cached(url)
	_request_finished.emit(url)
	return result


## Sends one GET request and waits for the answer. Returns {code: int, headers:
## PackedStringArray, body: PackedByteArray}, code 0 if the request failed (missing keys
## count as empty). Tests override this to answer without a network.
func _request(url: String, headers: PackedStringArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	var answer := {"code": 0, "headers": PackedStringArray(), "body": PackedByteArray()}
	if http.request(url, headers) == OK:
		var response: Array = []
		http.request_completed.connect(func(result: int, response_code: int, h: PackedStringArray, b: PackedByteArray) -> void:
			response.append_array([result, response_code, h, b]), CONNECT_ONE_SHOT)
		while response.is_empty():
			await get_tree().process_frame
			progress.emit(url, http.get_downloaded_bytes(), http.get_body_size())
		if response[0] == HTTPRequest.RESULT_SUCCESS:
			answer = {"code": response[1], "headers": response[2], "body": response[3]}
	http.queue_free()
	return answer


## Maps a URL to a readable cache path, e.g.
## https://play.pokemonshowdown.com/data/moves.json -> user://cache/play.pokemonshowdown.com/data/moves.json
func path_for(url: String) -> String:
	var rest := url.get_slice("://", 1) if url.contains("://") else url
	var parts := PackedStringArray()
	for part in rest.split("/", false):
		var safe := ""
		for c in part:
			var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") \
				or c == "." or c == "-" or c == "_"
			safe += c if ok else "_"
		if safe != "." and safe != "..":
			parts.append(safe)
	return root.path_join("/".join(parts))


func _read_meta(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path + ".meta")) \
		if FileAccess.file_exists(path + ".meta") else null
	return data if data is Dictionary else {}


func _write_meta(path: String, meta: Dictionary) -> void:
	var file := FileAccess.open(path + ".meta", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(meta))


static func _header(headers: PackedStringArray, header_name: String) -> String:
	for h in headers:
		var colon := h.find(":")
		if colon != -1 and h.substr(0, colon).strip_edges().to_lower() == header_name:
			return h.substr(colon + 1).strip_edges()
	return ""
