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
