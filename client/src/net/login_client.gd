class_name LoginClient
extends Node
## Fetches a login assertion from the Showdown login server over HTTP.
## See `|challstr|` in PROTOCOL.md. Passwords are only held for the duration of one request.

signal assertion_ready(username: String, assertion: String)
signal failed(reason: String)

var _http := HTTPRequest.new()
var _username := ""
var _with_password := false


func _ready() -> void:
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func request_assertion(api_base: String, username: String, password: String, challstr: String) -> void:
	_http.cancel_request()
	_username = username
	_with_password = not password.is_empty()
	var err: int
	if _with_password:
		var body := "name=%s&pass=%s&challstr=%s" % [
			username.uri_encode(), password.uri_encode(), challstr.uri_encode()]
		err = _http.request(api_base + "login",
			["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, body)
	else:
		err = _http.request(api_base + "getassertion?userid=%s&challstr=%s" % [
			PSParser.to_id(username), challstr.uri_encode()])
	if err != OK:
		failed.emit("Could not start login request (error %d)" % err)


func _on_request_completed(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Login server not reachable (result %d)" % result)
		return
	var text := body.get_string_from_utf8().strip_edges()
	if text.begins_with("]"):
		text = text.substr(1)

	var assertion := text
	if _with_password:
		var data: Variant = JSON.parse_string(text)
		if not (data is Dictionary and data.has("assertion")):
			failed.emit("Unexpected login server response")
			return
		assertion = str(data["assertion"])

	if assertion.begins_with(";;"):
		failed.emit(assertion.substr(2))
	elif assertion.begins_with(";"):
		failed.emit("This name is registered. Please enter its password.")
	elif assertion.is_empty():
		failed.emit("Empty response from login server")
	else:
		assertion_ready.emit(_username, assertion)
