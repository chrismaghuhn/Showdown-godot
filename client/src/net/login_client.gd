class_name LoginClient
extends Node
## Talks to the Showdown login server (smogon/pokemon-showdown-loginserver, <api>/<action>):
##
##   login         name + pass + challstr   -> assertion; sets the "sid" session cookie
##   getassertion  userid + challstr        -> assertion (unregistered name, or the cookie's user)
##   upkeep        sid cookie + challstr    -> assertion for the signed-in session
##   logout        sid cookie + userid      -> ends the session
##
## Responses may start with "]" (anti JSON hijacking) and report errors as {"actionerror": ...}.
## Passwords are only held for the duration of one request and never stored. The session
## cookie is kept in memory (and saved by SessionStore only if the user stays signed in).

signal assertion_ready(username: String, assertion: String)
## The name is registered: ask for its password, then call request_assertion() again.
signal password_required(username: String)
signal failed(reason: String)
## The login server set or cleared the session cookie ("" = cleared).
signal session_changed(sid: String)
## upkeep found no valid session (cookie expired, or signed out elsewhere).
signal session_expired

enum Kind { NONE, LOGIN, ASSERTION, UPKEEP, LOGOUT }

const TIMEOUT_SEC := 15.0

## Raw value of the "sid" cookie ("" = no session).
var session_cookie := ""

var _http := HTTPRequest.new()
var _kind := Kind.NONE
var _username := ""


func _ready() -> void:
	_http.timeout = TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## Gets an assertion for `username`: with a password via "login", otherwise via
## "getassertion" (works for unregistered names and for the session cookie's own user).
func request_assertion(api_base: String, username: String, password: String, challstr: String) -> void:
	_username = username
	if not password.is_empty():
		_http_post(Kind.LOGIN, api_base + "login", "name=%s&pass=%s&challstr=%s" % [
			username.uri_encode(), password.uri_encode(), challstr.uri_encode()])
	else:
		_http_get(Kind.ASSERTION, api_base + "getassertion?userid=%s&challstr=%s" % [
			PSParser.to_id(username), challstr.uri_encode()])


## Resumes the session of the stored cookie (no password needed).
func request_upkeep(api_base: String, challstr: String) -> void:
	_username = ""
	_http_get(Kind.UPKEEP, api_base + "upkeep?challstr=" + challstr.uri_encode())


## Ends the login server session. The cookie is forgotten right away, whatever the answer.
func logout(api_base: String, userid: String) -> void:
	if session_cookie.is_empty():
		return
	_http_post(Kind.LOGOUT, api_base + "logout", "userid=" + userid.uri_encode())
	_set_cookie("")


## Drops the running request; its answer never arrives. (A logout still went out.)
func cancel() -> void:
	if _kind != Kind.NONE and _kind != Kind.LOGOUT:
		_http.cancel_request()
		_kind = Kind.NONE


func _http_get(kind: Kind, url: String) -> void:
	_start(kind, url, HTTPClient.METHOD_GET, "")


func _http_post(kind: Kind, url: String, body: String) -> void:
	_start(kind, url, HTTPClient.METHOD_POST, body)


func _start(kind: Kind, url: String, method: HTTPClient.Method, body: String) -> void:
	_http.cancel_request()
	_kind = kind
	var headers := PackedStringArray([user_agent()])
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/x-www-form-urlencoded")
	if not session_cookie.is_empty():
		headers.append("Cookie: sid=" + session_cookie)
	var err := _http.request(url, headers, method, body)
	if err != OK:
		_kind = Kind.NONE
		failed.emit(tr("Could not start the sign-in request (error %d)") % err)


func _on_request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _kind
	_kind = Kind.NONE
	if result == HTTPRequest.RESULT_SUCCESS:
		var cookie := sid_from_headers(headers)
		if cookie["found"]:
			_set_cookie(cookie["value"])
	if kind == Kind.LOGOUT or kind == Kind.NONE:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit(tr("The login server is not reachable (result %d)") % result)
		return
	var text := body.get_string_from_utf8()
	# An error page (502, 503, ...) is never an assertion (#50).
	var http_problem := http_error(code, text)
	if not http_problem.is_empty():
		failed.emit(http_problem)
		return
	var parsed: Dictionary
	match kind:
		Kind.LOGIN:
			parsed = parse_login(text)
		Kind.UPKEEP:
			parsed = parse_upkeep(text)
			if parsed.get("expired", false):
				_set_cookie("")
				session_expired.emit()
				return
			_username = parsed.get("username", "")
		_:
			parsed = parse_assertion(text)
	if parsed.has("assertion"):
		assertion_ready.emit(_username, parsed["assertion"])
	elif parsed.get("password_required", false):
		password_required.emit(_username)
	else:
		failed.emit(parsed.get("error", tr("Unexpected login server response")))


func _set_cookie(value: String) -> void:
	if value == session_cookie:
		return
	session_cookie = value
	session_changed.emit(value)


## "User-Agent: ShowdownDesktop/0.1.0 (+https://github.com/...)" - lets server staff tell this
## client apart and find its maintainers.
static func user_agent() -> String:
	return "User-Agent: ShowdownDesktop/%s (+https://github.com/chrismaghuhn/Showdown-godot)" % \
		str(ProjectSettings.get_setting("application/config/version", "dev"))


# --- Response parsing (static, unit tested) ------------------------------------------------

static func strip_prefix(text: String) -> String:
	text = text.strip_edges()
	return text.substr(1) if text.begins_with("]") else text


## An assertion string: {"assertion"}, {"password_required": true} (";") or {"error"} (";;...").
static func parse_assertion(text: String) -> Dictionary:
	text = strip_prefix(text)
	if text.begins_with(";;"):
		return {"error": text.substr(2).strip_edges()}
	if text.begins_with(";"):
		return {"password_required": true}
	if text.is_empty():
		return {"error": "Empty response from the login server"}
	if text.begins_with("{"):
		var data: Variant = _parse_json(text)
		if data is Dictionary and data.has("actionerror"):
			return {"error": str(data["actionerror"])}
		return {"error": "Unexpected login server response"}
	# Assertions are comma-separated fields in one line; anything else (an HTML page) isn't.
	if text.begins_with("<") or text.contains("\n") or text.contains(" "):
		return {"error": "Unexpected login server response"}
	return {"assertion": text}


## "" for HTTP 200, else the error to show: the server's actionerror if it sent one, or
## "The login server returned HTTP 502".
static func http_error(code: int, text: String) -> String:
	if code == 200:
		return ""
	var data: Variant = _parse_json(strip_prefix(text))
	if data is Dictionary and data.has("actionerror"):
		return str(data["actionerror"])
	return "The login server returned HTTP %d" % code


## The "login" action: {"actionsuccess", "assertion", "curuser"} or {"actionerror"}.
static func parse_login(text: String) -> Dictionary:
	var data: Variant = _parse_json(strip_prefix(text))
	if not data is Dictionary:
		return {"error": "Unexpected login server response"}
	if data.has("actionerror"):
		return {"error": str(data["actionerror"])}
	var assertion: Variant = data.get("assertion", false)
	if not data.get("actionsuccess", false) or not assertion is String:
		return {"error": "The login server did not accept the sign-in."}
	return parse_assertion(assertion)


## The "upkeep" action: {"assertion", "username", "loggedin"}. {"expired": true} when the
## cookie no longer belongs to a signed-in user.
static func parse_upkeep(text: String) -> Dictionary:
	var data: Variant = _parse_json(strip_prefix(text))
	if not data is Dictionary:
		return {"error": "Unexpected login server response"}
	if data.has("actionerror"):
		return {"error": str(data["actionerror"])}
	var username := str(data.get("username", ""))
	if not data.get("loggedin", false) or username.is_empty():
		return {"expired": true}
	var result := parse_assertion(str(data.get("assertion", "")))
	result["username"] = username
	return result


## The "sid" cookie from Set-Cookie headers: {"found": bool, "value": String}. A cleared
## cookie (empty value or Max-Age=0) is found with value "".
static func sid_from_headers(headers: PackedStringArray) -> Dictionary:
	for header in headers:
		var colon := header.find(":")
		if colon == -1 or header.substr(0, colon).strip_edges().to_lower() != "set-cookie":
			continue
		var cookie := header.substr(colon + 1).strip_edges()
		var pair := cookie.get_slice(";", 0).strip_edges()
		if not pair.begins_with("sid="):
			continue
		var value := pair.substr(4)
		var cleared := value.is_empty() or cookie.to_lower().replace(" ", "").contains("max-age=0")
		return {"found": true, "value": "" if cleared else value}
	return {"found": false, "value": ""}


## Parses JSON without logging an engine error for non-JSON answers (e.g. an HTML error page).
static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## The user name stored in a sid cookie ("name,session,hash", URL-encoded), or "".
static func cookie_username(sid: String) -> String:
	return sid.uri_decode().get_slice(",", 0) if not sid.is_empty() else ""
