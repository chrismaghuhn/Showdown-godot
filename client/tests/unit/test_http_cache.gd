extends "res://tests/test_case.gd"

const FakeCache := preload("res://tests/fake_http_cache.gd")


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
	var cache := FakeCache.new("user://test-cache-busy")
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
	cache.clear()
	cache.free()
