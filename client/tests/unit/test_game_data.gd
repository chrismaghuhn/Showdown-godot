extends "res://tests/test_case.gd"

const FakeCache := preload("res://tests/fake_http_cache.gd")


func test_sprite_download_does_not_reload_the_dex() -> void:
	var game_data := OnlineGameData.new()
	game_data._cache.free()
	var cache := FakeCache.new("user://test-cache-dex")
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
		cache.store(game_data.data_url() + game_data.DATA_FILES[key], files[key])

	# Revalidate (all data files answer 304) while a sprite downloads with new content.
	game_data._ready()
	game_data.get_sprite("Pikachu")
	assert_eq(game_data.loaded, ["cache"] as Array[String], "the cached Dex is loaded")
	assert_eq(cache.requests.size(), 2, "first data file and the sprite are requested")
	for i in 20:
		if cache.pending == 0:
			break
		cache.answer_all()
	assert_true(not game_data.loading, "revalidation finished")
	assert_eq(cache.requests.size(), 1 + game_data.DATA_FILES.size(), "every data file was revalidated")
	assert_eq(game_data.loaded, ["cache"] as Array[String], "unchanged data files do not load the Dex again")
	cache.clear()
	game_data.free()


## GameData that fetches even though the tests run with --no-data-fetch, and records each
## Dex it loads instead of sending EventBus.data_loaded to the real listeners.
class OnlineGameData extends "res://src/core/game_data.gd":
	var loaded: Array[String] = []

	func _fetch_enabled() -> bool:
		return true

	func _set_dex(new_dex: Dex, source: String) -> void:
		dex = new_dex
		loaded.append(source)
