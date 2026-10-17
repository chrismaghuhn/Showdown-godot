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

- `id`: lowercase letters, digits, dashes. Unique, and the same as the plugin's folder name.
- `entry`: a `.gd` file inside the plugin folder (`main.gd`, `lib/main.gd`; no `..` or absolute paths).
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
| `connection_state_changed` | `state: int` – 0 disconnected, 1 connecting, 2 connected, 3 waiting for the next reconnect attempt |
| `logged_in` | `username: String` |
| `message_received` | `msg: PSMessage` (every raw protocol message; `msg.backlog` is true for the lines of an `|init|` frame, i.e. a room's chat backlog or a battle log replayed on (re)join) |
| `room_joined` | `room_id: String, room_type: String` |
| `room_left` | `room_id: String` |
| `chat_message` | `room_id: String, user: String, text: String` |
| `private_message` | `from: String, to: String, text: String` |
| `battle_started` | `battle: BattleState` – also after a reconnect, when the server replays a running battle from the start: then `battle.restored` is true and it's a new `BattleState` for the same `room_id` (reset per-battle state you keep) |
| `battle_updated` | `battle: BattleState, msg: PSMessage` (state already updated) |
| `battle_request` | `battle: BattleState, request: Dictionary` (the server's `|request|` JSON) |
| `battle_ended` | `battle: BattleState, winner: String` |
| `data_loaded` | `dex: Dex` (game data ready or updated) |
| `theme_changed` | `theme_id: String` (redraw custom-drawn UI) |

## Functions

| Function | Permission |
|---|---|
| `api.info(text)` | – |
| `api.get_username()` | – |
| `api.get_battle(room_id) -> BattleState` (read-only) | – |
| `api.get_dex() -> Dex` (read-only, null until `data_loaded`) | – |
| `await api.get_sprite(species, back, shiny) -> Texture2D` (cached, null if missing) | – |
| `api.get_token(key) -> Variant` (design token of the current theme, e.g. `"color.hp.high"`) | – |
| `api.send_command(room_id, text)` | `send_commands` |
| `api.choose(room_id, choice, rqid)` | `send_commands` |
| `api.add_panel(slot, control)` – slots: `&"sidebar"` | `ui` |
| `api.get_data_dir() -> String` (private `user://plugin_data/<id>/`) | `storage` |

## Look and feel

Panels added with `add_panel()` inherit the current theme automatically. Use the standard theme
type variations (see [theming.md](theming.md)) and `api.get_token()` for custom drawing — never
hard-coded colors. The host draws the plugin badge and source line; a plugin cannot hide where
its UI comes from.

## Installing and developing

- Installed plugins live in `user://plugins/<id>/`
  (Linux: `~/.local/share/godot/app_userdata/Showdown Desktop/plugins/`).
- During development: `tools/run_client.sh` loads the repo's `plugins/` folder.
  Enable plugins with `--enable-plugins=id1,id2`.
- If the same id is found twice, the first loadable copy wins (installed before development)
  and any other loadable copy is listed as not loadable ("duplicate id").

A plugin that raises an engine or script error is **paused**: it is switched off, the user
sees "<name> paused" with "Reload plugin" / "Disable", and the battle goes on.

## Versioning

- Adding events or functions does not change `VERSION`.
- Removing or changing anything bumps `VERSION`. Plugins then need an update.

## Security – read this

GDScript plugins run **unsandboxed** with full access to the computer. Permissions are
enforced by `PluginAPI` but can be bypassed by malicious code. Until a sandboxed
runtime (Lua/WASM) exists, only install plugins whose source you trust.
