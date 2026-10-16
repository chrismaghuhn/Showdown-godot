# Plugin API (v1)

A plugin is a folder with a `plugin.json` and an entry script.

```
my-plugin/
  plugin.json
  main.gd
```

## plugin.json

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "api_version": 1,
  "entry": "main.gd",
  "description": "What it does.",
  "permissions": ["ui"]
}
```

- `id`: lowercase letters, digits, dashes. Unique.
- `api_version`: must match the client's `PluginAPI.VERSION`, otherwise the plugin is not loaded.
- `permissions`: what the plugin may do (see below).

## Entry script

```gdscript
extends ClientPlugin

func _plugin_enable() -> void:
    api.on(&"battle_started", func(battle: BattleState) -> void:
        api.info("Battle started: " + battle.room_id))

func _plugin_disable() -> void:
    pass  # event subscriptions are removed automatically
```

## Events (`api.on(event, callback)`)

| Event | Arguments |
|---|---|
| `connection_state_changed` | `state: int` |
| `logged_in` | `username: String` |
| `message_received` | `msg: PSMessage` (every raw protocol message) |
| `room_joined` | `room_id: String, room_type: String` |
| `room_left` | `room_id: String` |
| `chat_message` | `room_id: String, user: String, text: String` |
| `private_message` | `from: String, to: String, text: String` |
| `battle_started` | `battle: BattleState` |
| `battle_updated` | `battle: BattleState, msg: PSMessage` (state already updated) |
| `battle_request` | `battle: BattleState, request: Dictionary` (the server's `|request|` JSON) |
| `battle_ended` | `battle: BattleState, winner: String` |

## Functions

| Function | Permission |
|---|---|
| `api.info(text)` | – |
| `api.get_username()` | – |
| `api.get_battle(room_id) -> BattleState` (read-only) | – |
| `api.send_command(room_id, text)` | `send_commands` |
| `api.choose(room_id, choice, rqid)` | `send_commands` |
| `api.add_panel(slot, control)` – slots: `&"sidebar"` | `ui` |
| `api.get_data_dir() -> String` (private `user://plugin_data/<id>/`) | `storage` |

## Installing and developing

- Installed plugins live in `user://plugins/<id>/`
  (Linux: `~/.local/share/godot/app_userdata/Showdown Desktop/plugins/`).
- During development: `tools/run_client.sh` loads the repo's `plugins/` folder.
  Enable plugins with `--enable-plugins=id1,id2`.

## Versioning

- Adding events or functions does not change `VERSION`.
- Removing or changing anything bumps `VERSION`. Plugins then need an update.

## Security – read this

GDScript plugins run **unsandboxed** with full access to the computer. Permissions are
enforced by `PluginAPI` but can be bypassed by malicious code. Until a sandboxed
runtime (Lua/WASM) exists, only install plugins whose source you trust.
