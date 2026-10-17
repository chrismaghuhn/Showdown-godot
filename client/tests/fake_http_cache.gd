extends HttpCache
## HttpCache for tests: requests wait until the test calls answer_all(), then get 200 with
## the URL as body, or 304 for cached files if not_modified is set. Sprite URLs (.png) get
## a real 1x1 PNG.

signal _answer

var requests: Array[String] = []
var pending := 0
var not_modified := false


## Starts with an empty cache directory.
func _init(cache_root: String) -> void:
	super(cache_root)
	clear()


## Answers every request that is waiting right now.
func answer_all() -> void:
	_answer.emit()


## Writes a file into the cache as if it had been downloaded.
func store(url: String, text: String) -> void:
	var path := path_for(url)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Deletes the cache directory.
func clear(path := root) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir in DirAccess.get_directories_at(path):
		clear(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


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
