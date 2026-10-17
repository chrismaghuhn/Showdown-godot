extends "res://tests/test_case.gd"
## Login server responses, as sent by smogon/pokemon-showdown-loginserver.


func test_assertion_strings() -> void:
	assert_eq(LoginClient.parse_assertion("4a1b2c,alice,2,1700000000,sim3,deadbeef"),
		{"assertion": "4a1b2c,alice,2,1700000000,sim3,deadbeef"}, "plain assertion")
	assert_eq(LoginClient.parse_assertion("]4a1b2c,alice"), {"assertion": "4a1b2c,alice"}, "] prefix")
	assert_eq(LoginClient.parse_assertion(";"), {"password_required": true}, "registered name")
	assert_eq(LoginClient.parse_assertion(";;Your username contains invalid characters."),
		{"error": "Your username contains invalid characters."}, ";; error")
	assert_eq(LoginClient.parse_assertion("  "), {"error": "Empty response from the login server"}, "empty")
	assert_eq(LoginClient.parse_assertion(']{"actionerror":"Malformed request"}'),
		{"error": "Malformed request"}, "action error")


func test_login_action() -> void:
	assert_eq(LoginClient.parse_login(']{"actionsuccess":true,"assertion":"abc,alice","curuser":{"loggedin":true}}'),
		{"assertion": "abc,alice"}, "signed in")
	assert_eq(LoginClient.parse_login(']{"actionerror":"Wrong password."}'), {"error": "Wrong password."}, "wrong password")
	assert_eq(LoginClient.parse_login(']{"actionsuccess":false,"assertion":false}'),
		{"error": "The login server did not accept the sign-in."}, "refused")
	assert_eq(LoginClient.parse_login(']{"actionsuccess":true,"assertion":";;Your account is locked."}'),
		{"error": "Your account is locked."}, "assertion error inside a successful login")
	assert_eq(LoginClient.parse_login("<html>502</html>"), {"error": "Unexpected login server response"}, "not json")


func test_upkeep_action() -> void:
	assert_eq(LoginClient.parse_upkeep(']{"assertion":"abc,alice","username":"Alice","loggedin":true}'),
		{"assertion": "abc,alice", "username": "Alice"}, "session resumed")
	assert_eq(LoginClient.parse_upkeep(']{"assertion":"","username":"","loggedin":false}'),
		{"expired": true}, "no session")
	assert_eq(LoginClient.parse_upkeep(']{"assertion":"","username":"Alice","loggedin":false}'),
		{"expired": true}, "logged out elsewhere")
	assert_eq(LoginClient.parse_upkeep(']{"actionerror":"Internal Server Error"}'),
		{"error": "Internal Server Error"}, "error")


func test_session_cookie_from_headers() -> void:
	var set := PackedStringArray(["Content-Type: text/plain",
		"Set-Cookie: sid=Alice%2C3%2Cf00d; Max-Age=31363200; Domain=pokemonshowdown.com; Path=/; Secure; SameSite=None"])
	assert_eq(LoginClient.sid_from_headers(set), {"found": true, "value": "Alice%2C3%2Cf00d"}, "set")
	var cleared := PackedStringArray(["set-cookie: sid=%2C%2Cf00d; Max-Age=0; Path=/; Secure"])
	assert_eq(LoginClient.sid_from_headers(cleared), {"found": true, "value": ""}, "deleted with Max-Age=0")
	assert_eq(LoginClient.sid_from_headers(PackedStringArray(["Set-Cookie: sid=;Max-Age=0"])),
		{"found": true, "value": ""}, "empty value")
	assert_eq(LoginClient.sid_from_headers(PackedStringArray(["Set-Cookie: other=1"])),
		{"found": false, "value": ""}, "other cookies are ignored")
	assert_eq(LoginClient.cookie_username("Alice%2C3%2Cf00d"), "Alice", "cookie user")


func test_session_store_round_trip() -> void:
	var path := "user://test_session.cfg"
	var api := "https://play.pokemonshowdown.com/api/"
	SessionStore.save_cookie(api, "Alice%2C3%2Cf00d", path)
	assert_eq(SessionStore.load_cookie(api, path), "Alice%2C3%2Cf00d", "saved")
	assert_eq(SessionStore.load_cookie("https://other.example/api/", path), "", "per login server")
	SessionStore.clear(api, path)
	assert_eq(SessionStore.load_cookie(api, path), "", "cleared")
	DirAccess.remove_absolute(path)


func test_user_agent_names_the_client() -> void:
	assert_true(LoginClient.user_agent().begins_with("User-Agent: ShowdownDesktop/"), "user agent")


func test_http_errors_are_not_assertions() -> void:
	assert_eq(LoginClient.http_error(200, "abc,alice"), "", "200 is fine")
	assert_eq(LoginClient.http_error(502, "<!DOCTYPE html><html>Bad Gateway</html>"),
		"The login server returned HTTP 502", "error page (#50)")
	assert_eq(LoginClient.http_error(500, ']{"actionerror":"Internal Server Error"}'),
		"Internal Server Error", "the server's own message")
	assert_eq(LoginClient.parse_assertion("<!DOCTYPE html>\n<html>"),
		{"error": "Unexpected login server response"}, "HTML is never an assertion")
