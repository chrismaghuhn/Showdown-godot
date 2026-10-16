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
const DATA_MAX_AGE := 24 * 3600
const SPRITE_MAX_AGE := 30 * 24 * 3600

## The current Dex, or null until data was loaded once.
var dex: Dex

var _cache := HttpCache.new()
var _textures := {}
var _changed := false


func _ready() -> void:
	add_child(_cache)
	_cache.updated.connect(func(_url: String) -> void: _changed = true)
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
	var fetched := {}
	for key: String in DATA_FILES:
		fetched[key] = await _cache.fetch(data_url() + DATA_FILES[key], DATA_MAX_AGE)
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
