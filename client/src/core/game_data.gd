extends Node
## Autoload "GameData": loads the Dex and sprites from a configurable source and caches them.
##
## Startup: the cached Dex is available immediately (works offline), then the files are
## revalidated in the background. EventBus.data_loaded fires whenever a new Dex is ready.
##
## Sources (settings section "data", or command line):
##   data_url    --data-url=...      default https://play.pokemonshowdown.com/data/
##   sprite_url  --sprite-url=...    default https://play.pokemonshowdown.com/sprites/
##   --no-data-fetch                 only use what is already cached (CI, offline tests)
## A mirror (e.g. your own server) must serve the same file names and folders.

const DEFAULT_DATA_URL := "https://play.pokemonshowdown.com/data/"
const DEFAULT_SPRITE_URL := "https://play.pokemonshowdown.com/sprites/"

## key -> file name under data_url
const DATA_FILES := {
	"pokedex": "pokedex.json",
	"moves": "moves.json",
	"items": "items.js",
	"abilities": "abilities.js",
	"typechart": "typechart.js",
}
const DATA_LABELS := {
	"pokedex": "Pokédex", "moves": "Moves", "items": "Items", "abilities": "Abilities", "typechart": "Type chart",
}
const DATA_MAX_AGE := 24 * 3600
const SPRITE_MAX_AGE := 30 * 24 * 3600

## The current Dex, or null until data was loaded once.
var dex: Dex
## Download progress of the data files (also sent as EventBus.data_progress):
## {fraction: 0..1, bytes: int, files: [{key, label, state}]}, state "pending", "loading",
## "done" or "failed". Empty until the first fetch starts.
var progress := {}
## True while the data files are being fetched or revalidated.
var loading := false

var _cache := HttpCache.new()
var _textures := {}
var _changed := false
## key -> downloaded bytes of the running fetch
var _file_bytes := {}
## share of the file currently downloading (0..1)
var _partial := 0.0


func _ready() -> void:
	add_child(_cache)
	_cache.updated.connect(_on_cache_updated)
	_cache.progress.connect(_on_download_progress)
	load_data()


func data_url() -> String:
	return _with_slash(AppConfig.cli("data-url", str(AppConfig.get_setting("data", "data_url", DEFAULT_DATA_URL))))


func sprite_url() -> String:
	return _with_slash(AppConfig.cli("sprite-url", str(AppConfig.get_setting("data", "sprite_url", DEFAULT_SPRITE_URL))))


## Loads the cached Dex first, then refreshes from the network. Safe to call again.
func load_data() -> void:
	var cached := {}
	for key: String in DATA_FILES:
		cached[key] = _cache.read_cached(data_url() + DATA_FILES[key])
	var from_cache := _build_dex(cached)
	if from_cache != null:
		_set_dex(from_cache, "cache")

	if AppConfig.has_cli("no-data-fetch"):
		if dex == null:
			EventBus.data_failed.emit("No cached data and --no-data-fetch is set")
		return

	_changed = false
	loading = true
	_start_progress()
	var fetched := {}
	for key: String in DATA_FILES:
		_set_file_state(key, "loading")
		fetched[key] = await _cache.fetch(data_url() + DATA_FILES[key], DATA_MAX_AGE)
		_set_file_state(key, "done" if not (fetched[key] as PackedByteArray).is_empty() else "failed")
	loading = false
	if dex == null or _changed:
		var fresh := _build_dex(fetched)
		if fresh != null:
			_set_dex(fresh, "network")
	if dex == null:
		EventBus.data_failed.emit("Could not load game data from " + data_url())


## Returns a sprite texture, or null if it does not exist / cannot be loaded. Must be awaited.
## `species` may be a species name ("Rotom-Wash") or a sprite id ("rotom-wash").
func get_sprite(species: String, back := false, shiny := false) -> Texture2D:
	var entry: DexSpecies = dex.get_species(species) if dex != null else null
	var sprite_id := entry.sprite_id() if entry != null else species.to_lower()
	var folder := "gen5" + ("-back" if back else "") + ("-shiny" if shiny else "")
	var url := sprite_url() + folder + "/" + sprite_id + ".png"
	if _textures.has(url):
		return _textures[url]
	var bytes: PackedByteArray
	if AppConfig.has_cli("no-data-fetch"):
		bytes = _cache.read_cached(url)
	else:
		bytes = await _cache.fetch(url, SPRITE_MAX_AGE)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[url] = texture
	return texture


func _start_progress() -> void:
	var files: Array[Dictionary] = []
	for key: String in DATA_FILES:
		files.append({"key": key, "label": DATA_LABELS.get(key, key), "state": "pending"})
	progress = {"fraction": 0.0, "bytes": 0, "files": files}
	_file_bytes.clear()
	_partial = 0.0
	EventBus.data_progress.emit(progress)


func _set_file_state(key: String, file_state: String) -> void:
	for file: Dictionary in progress.get("files", []):
		if file["key"] == key:
			file["state"] = file_state
	if file_state != "loading":
		_partial = 0.0
	_update_fraction()


## Only new data files change the Dex; sprites come from the same cache.
func _on_cache_updated(url: String) -> void:
	for key: String in DATA_FILES:
		if url == data_url() + DATA_FILES[key]:
			_changed = true
			return


func _on_download_progress(url: String, downloaded: int, total: int) -> void:
	if not loading:
		return
	for key: String in DATA_FILES:
		if url == data_url() + DATA_FILES[key]:
			_file_bytes[key] = downloaded
			_partial = clampf(float(downloaded) / total, 0.0, 1.0) if total > 0 else 0.0
			_update_fraction()
			return


## Progress counts finished files, plus the share of the one downloading (if its size is known).
func _update_fraction() -> void:
	var files: Array = progress.get("files", [])
	if files.is_empty():
		return
	var finished := 0
	for file: Dictionary in files:
		if file["state"] == "done" or file["state"] == "failed":
			finished += 1
	var total_bytes := 0
	for key: String in _file_bytes:
		total_bytes += int(_file_bytes[key])
	progress["fraction"] = minf((finished + _partial) / files.size(), 1.0)
	progress["bytes"] = total_bytes
	EventBus.data_progress.emit(progress)


func _set_dex(new_dex: Dex, source: String) -> void:
	dex = new_dex
	print("Game data loaded from %s: %d species, %d moves, %d items, %d abilities" % [
		source, dex.species.size(), dex.moves.size(), dex.items.size(), dex.abilities.size()])
	EventBus.data_loaded.emit(dex)


## Parses raw file bytes into a Dex. Returns null if any file is missing or invalid.
static func _build_dex(files: Dictionary) -> Dex:
	var parsed := {}
	for key: String in DATA_FILES:
		var bytes: PackedByteArray = files.get(key, PackedByteArray())
		if bytes.is_empty():
			return null
		var text := bytes.get_string_from_utf8()
		var data: Variant = JSON.parse_string(text) if DATA_FILES[key].ends_with(".json") \
			else JsObjectParser.parse_exports(text)
		if not data is Dictionary:
			push_warning("Game data file %s could not be parsed" % DATA_FILES[key])
			return null
		parsed[key] = data
	return Dex.from_sources(parsed["pokedex"], parsed["moves"], parsed["items"],
		parsed["abilities"], parsed["typechart"])


static func _with_slash(url: String) -> String:
	return url if url.ends_with("/") else url + "/"
