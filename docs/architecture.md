# Architecture

The client is built in layers. **Each layer may only depend on the layers below it.**
This rule is what keeps the codebase from needing rewrites as features grow.

```
 ui/            screens and components (Godot scenes)
  │
 plugins/       plugin loader + the public PluginAPI
 core/          app services: config, event bus, room routing
 net/           websocket connection, login, HTTP cache
  │
 model/         battle state (pure data, no Nodes, no autoloads)
 data/          Dex: species, moves, items, abilities, type chart (pure)
  │
 protocol/      parser for the Showdown text protocol (pure, static)
```

| Folder (`client/src/…`) | Contains | May use |
|---|---|---|
| `protocol/` | `PSParser`, `PSMessage` | nothing |
| `data/` | `Dex`, `DexSpecies`, `DexMove`, `DexEntry`, `JsObjectParser` | `protocol/` |
| `model/` | `BattleState`, `BattleSide`, `BattlePokemon` | `protocol/`, `data/` |
| `net/` | `Connection` (autoload), `LoginClient`, `HttpCache` | `protocol/`, `core/` |
| `core/` | `AppConfig`, `EventBus`, `Rooms`, `GameData` (autoloads) | `protocol/`, `data/`, `model/`, `net/` |
| `plugins/` | `Plugins` (autoload), `PluginAPI`, `PluginManifest`, `ClientPlugin` | everything below |
| `ui/` | `screens/<name>/`, `components/` | everything below, **only via EventBus / public methods** |
| `app/` | entry scene, wiring, dev automation | everything |

## Data flow

1. `Connection` receives a websocket frame → `PSParser.parse_frame()` → `PSMessage`s.
2. Every message is published as `EventBus.message_received`.
3. `Rooms` routes battle messages into a `BattleState` and publishes higher-level events:
   `battle_started`, `battle_updated`, `battle_request`, `battle_ended`, `chat_message`, …
4. UI and plugins only listen to EventBus signals. Sending goes through `Connection.send()` /
   `Connection.choose()` (plugins: `api.send_command()` / `api.choose()`).

The server runs all game mechanics. The client never simulates a battle; it mirrors state
from the protocol and offers the choices the server lists in `|request|`.

## Where new features go

| Feature | Location |
|---|---|
| Real battle screen | `ui/screens/battle/` (reads `BattleState`, listens to battle events) |
| Lobby, chat rooms | `ui/screens/lobby/`, chat model in `model/` if it needs state |
| Teambuilder | `model/team/` (team format, import/export, pure + tested) and `ui/screens/teambuilder/` |
| Pokédex / move data | done: `data/` + `GameData`, see [data-sources.md](data-sources.md) |
| Move/item descriptions, icons | extend `GameData.DATA_FILES` / sprite helpers, parse in `data/` |
| Replays | feed a replay log through `PSParser` into a `BattleState` – no new parsing code |
| Themes, fonts | `client/assets/themes/`, `client/assets/fonts/` |
| Plugin sandbox (Lua/WASM) | new loader in `plugins/`, same `PluginAPI` surface |

## Conventions

- Code, comments and identifiers in English; user-facing strings go through `tr()`.
- Pure logic (`protocol/`, `model/`) gets unit tests in `client/tests/unit/`.
- Autoloads are internal. Plugins only see `PluginAPI`.
- Never commit Nintendo/Game Freak assets (sprites, sounds). Load them at runtime from the
  Showdown CDN and cache them in `user://`.
- `ui/screens/dev_console/` is a developer tool, not the product UI.
