class_name PluginAPI
extends RefCounted
## The public, versioned surface plugins talk to. Each plugin gets its own instance.
##
## Rules for maintainers:
## - Never remove or change anything here without bumping VERSION.
## - Adding events/functions is fine within a version.
## - Plugins must not need anything outside this class (autoloads are internal).
##
## NOTE: GDScript plugins are not sandboxed. Permissions are enforced by this API,
## but a malicious plugin could bypass it. See docs/plugin-api.md.

const VERSION := 1

## EventBus signals plugins may subscribe to.
const EVENTS: Array[StringName] = [
	&"connection_state_changed",
	&"logged_in",
	&"message_received",
	&"room_joined",
	&"room_left",
	&"chat_message",
	&"private_message",
	&"battle_started",
	&"battle_updated",
	&"battle_request",
	&"battle_ended",
	&"data_loaded",
]

var manifest: PluginManifest
var _connections: Array[Dictionary] = []


func _init(plugin_manifest: PluginManifest) -> void:
	manifest = plugin_manifest


func has_permission(permission: String) -> bool:
	return permission in manifest.permissions


## Subscribes to an event from EVENTS. Disconnected automatically when the plugin is disabled.
func on(event: StringName, callback: Callable) -> bool:
	if not event in EVENTS:
		push_error("[plugin:%s] unknown event '%s'" % [manifest.id, event])
		return false
	EventBus.connect(event, callback)
	_connections.append({"event": event, "callback": callback})
	return true


func info(text: String) -> void:
	print("[plugin:%s] %s" % [manifest.id, text])


# --- Read access -------------------------------------------------------------

func get_username() -> String:
	return Connection.username


## Returns the BattleState for a room. Treat it as read-only.
func get_battle(room_id: String) -> BattleState:
	return Rooms.get_battle(room_id)


## Game data (species, moves, items, abilities, type chart). Null until loaded; listen to
## the "data_loaded" event. Treat it as read-only.
func get_dex() -> Dex:
	return GameData.dex


## Loads a sprite texture (cached). Must be awaited: `var tex = await api.get_sprite("Garchomp")`.
func get_sprite(species: String, back := false, shiny := false) -> Texture2D:
	return await GameData.get_sprite(species, back, shiny)


# --- "send_commands" permission ----------------------------------------------

func send_command(room_id: String, text: String) -> bool:
	if not _require("send_commands"):
		return false
	Connection.send(room_id, text)
	return true


func choose(room_id: String, choice: String, rqid := -1) -> bool:
	if not _require("send_commands"):
		return false
	Connection.choose(room_id, choice, rqid)
	return true


# --- "ui" permission ----------------------------------------------------------

## Adds a control to a UI slot. Known slots: &"sidebar".
func add_panel(slot: StringName, control: Control) -> bool:
	if not _require("ui"):
		return false
	Plugins.register_panel(manifest.id, slot, control)
	return true


# --- "storage" permission -----------------------------------------------------

## A private folder for this plugin's files (settings, caches).
func get_data_dir() -> String:
	if not _require("storage"):
		return ""
	var path := "user://plugin_data/%s" % manifest.id
	DirAccess.make_dir_recursive_absolute(path)
	return path


# --- Internal -----------------------------------------------------------------

func _require(permission: String) -> bool:
	if has_permission(permission):
		return true
	push_error("[plugin:%s] missing permission '%s' in plugin.json" % [manifest.id, permission])
	return false


func _disconnect_all() -> void:
	for c in _connections:
		if EventBus.is_connected(c["event"], c["callback"]):
			EventBus.disconnect(c["event"], c["callback"])
	_connections.clear()
