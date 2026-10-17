extends "res://tests/test_case.gd"


func test_path_for_is_readable_and_safe() -> void:
	var cache := HttpCache.new("user://test-cache")
	assert_eq(cache.path_for("https://play.pokemonshowdown.com/data/moves.json"),
		"user://test-cache/play.pokemonshowdown.com/data/moves.json", "plain url")
	assert_eq(cache.path_for("https://example.com/sprites/gen5/mr.mime.png?v=2"),
		"user://test-cache/example.com/sprites/gen5/mr.mime.png_v_2", "query is sanitized")
	assert_eq(cache.path_for("https://evil.example/../../etc/passwd"),
		"user://test-cache/evil.example/etc/passwd", "no parent directory escapes")
	cache.free()


func test_header_lookup_is_case_insensitive() -> void:
	var headers := PackedStringArray(["Content-Type: application/json", "ETag: \"abc\"", "last-modified: Fri"])
	assert_eq(HttpCache._header(headers, "etag"), "\"abc\"", "etag")
	assert_eq(HttpCache._header(headers, "last-modified"), "Fri", "last-modified")
	assert_eq(HttpCache._header(headers, "missing"), "", "missing")


func test_one_request_per_url_while_all_slots_are_busy() -> void:
	var cache := FakeCache.new(_fresh_root("user://test-cache-busy"))
	var results: Array[String] = []
	var start := func(url: String) -> void: results.append((await cache.fetch(url, 3600)).get_string_from_utf8())
	for i in HttpCache.MAX_CONCURRENT:
		start.call("https://example.com/busy%d" % i)
	start.call("https://example.com/shared.json")
	start.call("https://example.com/shared.json")
	assert_eq(cache.requests.size(), HttpCache.MAX_CONCURRENT, "both fetches of one URL wait for a slot")

	cache.answer_all()
	assert_eq(cache.requests.count("https://example.com/shared.json"), 1, "one request for it started")
	cache.answer_all()
	assert_eq(cache.requests.count("https://example.com/shared.json"), 1, "and no second one after it")
	assert_eq(results.size(), HttpCache.MAX_CONCURRENT + 2, "every caller got an answer")
	assert_eq(results.count("https://example.com/shared.json"), 2, "both share the download")
	cache.free()
	_remove_dir("user://test-cache-busy")


func test_sprite_download_does_not_reload_the_dex() -> void:
	var game_data: Node = load("res://src/core/game_data.gd").new()
	game_data._cache.free()
	var cache := FakeCache.new(_fresh_root("user://test-cache-dex"))
	cache.not_modified = true
	game_data._cache = cache
	var files := {
		"pokedex": JSON.stringify({"pikachu": {"num": 25, "name": "Pikachu", "types": ["Electric"]}}),
		"moves": "{}",
		"items": "exports.BattleItems = {};",
		"abilities": "exports.BattleAbilities = {};",
		"typechart": FileAccess.get_file_as_string("res://tests/fixtures/typechart.js"),
	}
	for key: String in files:
		_store(cache.path_for(game_data.data_url() + game_data.DATA_FILES[key]), files[key])
	var loaded: Array[Dex] = []
	var on_loaded := func(dex: Dex) -> void: loaded.append(dex)
	EventBus.data_loaded.connect(on_loaded)

	# Revalidate (all data files answer 304) while a sprite downloads with new content.
	var no_fetch: Variant = AppConfig._cli.get("no-data-fetch")
	AppConfig._cli.erase("no-data-fetch")
	game_data._ready()
	game_data.get_sprite("Pikachu")
	AppConfig._cli["no-data-fetch"] = no_fetch
	assert_eq(loaded.size(), 1, "the cached Dex is loaded")
	assert_eq(cache.requests.size(), 2, "first data file and the sprite are requested")
	while cache.pending > 0:
		cache.answer_all()
	assert_true(not game_data.loading, "revalidation finished")
	assert_eq(cache.requests.size(), 1 + game_data.DATA_FILES.size(), "every data file was revalidated")
	assert_eq(loaded.size(), 1, "unchanged data files do not load the Dex again")

	EventBus.data_loaded.disconnect(on_loaded)
	game_data.free()
	_remove_dir("user://test-cache-dex")


## Answers requests only when the test says so: 200 with the URL as body, or 304 for
## cached files if not_modified is set. Sprite URLs (.png) get a real 1x1 PNG.
class FakeCache extends HttpCache:
	signal _answer
	var requests: Array[String] = []
	var pending := 0
	var not_modified := false

	func answer_all() -> void:
		_answer.emit()

	func _request(url: String, _headers: PackedStringArray) -> Dictionary:
		requests.append(url)
		pending += 1
		await _answer
		pending -= 1
		if not_modified and FileAccess.file_exists(path_for(url)):
			return {"code": 304, "headers": PackedStringArray(), "body": PackedByteArray()}
		var body := url.to_utf8_buffer()
		if url.ends_with(".png"):
			body = Image.create(1, 1, false, Image.FORMAT_RGBA8).save_png_to_buffer()
		return {"code": 200, "headers": PackedStringArray(), "body": body}


func _fresh_root(root: String) -> String:
	_remove_dir(root)
	return root


func _store(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
