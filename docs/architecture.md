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
| `net/` | `Connection` (autoload), `LoginClient`, `ReconnectPolicy`, `SessionStore`, `HttpCache` | `protocol/`, `core/` |
| `core/` | `AppConfig`, `EventBus`, `Rooms`, `GameData`, `Sounds`, `Notifier` (autoloads), `NotificationEvents`, `NativeNotifier` | `protocol/`, `data/`, `model/`, `net/` |
| `plugins/` | `Plugins` (autoload), `PluginAPI`, `PluginManifest`, `ClientPlugin` | everything below |
| `ui/` | `screens/<name>/`, `components/`, `overlays/` (connection cards, banner, download progress), `theme/` (`Themes` autoload, `ThemeTokens`, `ThemeBuilder`) | everything below, **only via EventBus / public methods** |
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

## Connection, sign-in and reconnecting

`Connection.State`: `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `WAITING` (the next attempt is
scheduled). States are only ever appended, plugins see the number.

- **Attempts.** A socket that closes, or an attempt that doesn't reach `|challstr|` within
  12 s, is retried by `ReconnectPolicy`: 2, 4, 8, 16, 30 s (±20 % jitter), at most 5
  attempts, then `EventBus.connection_error` and "Try again". `disconnect_from_server()`
  ("Work offline") never reconnects.
- **Pacing.** `send()` queues messages and lets `SendThrottle` pace them like the server's
  chat throttle (a burst of 4, then one per 650 ms); line breaks become spaces. Details in
  [official-server.md](official-server.md).
- **Dead links.** A pulled cable doesn't close the socket. The websocket heartbeat pings every
  10 s (`--heartbeat=N` in tests); a missing pong closes the socket, which starts the attempts.
- **Signing in.** `Connection.login(name, password)`: without a login server (`--no-security`)
  it's `/trn name`, otherwise `LoginClient` gets an assertion (`login` with a password,
  `getassertion` without one, `upkeep` with the session cookie). The password only lives for
  that one request. "Stay signed in" keeps the name (settings) and the login server's `sid`
  cookie (`SessionStore`, `user://session.cfg`, owner-only) - never the password. With it on
  and something saved to sign in with, the app connects to the last server on launch, in
  the background (no modal card; `--offline` skips it).
- **After a reconnect** the client signs in again as `session_name` (cookie or unregistered
  name, no password), retrying a few times while the server still holds the old connection
  (`|nametaken|`), then emits `EventBus.reconnected`. The server rejoins a returning user's
  battle rooms itself and replays each from `|init|`; `Rooms` joins the rest (also running
  games from `|updatesearch|`), marks those `BattleState.restored` and emits
  `battles_restored(count)`. Restored battles never take over the screen.
- **UI** (`ui/overlays/`, design board "03 · Motion & app states"): `ConnectionFlow` decides,
  from `Connection.status()`, between the modal card (first connection, sign-in, gave up) and
  the banner (a connection that worked dropped). `--app-state=<id>` shows each state with
  sample data for screenshots.
- **Tests:** `tools/e2e_reconnect.sh` cuts and blackholes a bot's connection mid-battle
  through `tools/net_fault_proxy.py`; `tools/e2e_ui.sh` drives the sign-in card and the app shell.

A plugin whose scripts raise an engine error is paused (`Plugins.pause()`,
`EventBus.plugin_paused`) and shown as "<name> paused" with "Reload plugin" / "Disable".

## Where new features go

| Feature | Location |
|---|---|
| App shell, start screen | done: `app/main.gd` (header, tabs, keys), `ui/screens/start/`, header parts in `ui/components/` (`AppTabs`, `CommandButton`, `NotificationBell`, `AccountButton`) |
| Battle screen | done (layout B "Desktop"): `ui/screens/battle/`, one instance per battle tab (`bind(room_id)`), components in `ui/components/` (stage, HUD, log, slots, tooltips) |
| Battle layout A "Familiar", doubles | `ui/screens/battle/` as alternative layout, `StageLayout.DOUBLES` is ready |
| Lobby | done: `ui/screens/home/` (Home tab: find a battle with `FormatPicker`, challenges, your battles, ratings); state in `Rooms` (`formats`, `searching`, `challenges`, `ratings`) |
| Chat rooms | the lobby's aside (`ui/screens/home/`), chat model in `model/` if it needs state |
| Command palette | replaces `CommandButton`'s "Go to" menu (#8) |
| Teambuilder | `model/team/` (team format, import/export, pure + tested) and `ui/screens/teambuilder/` |
| Pokédex / move data | done: `data/` + `GameData`, see [data-sources.md](data-sources.md) |
| Move/item descriptions, icons | extend `GameData.DATA_FILES` / sprite helpers, parse in `data/` |
| Replays | feed a replay log through `PSParser` into a `BattleState` – no new parsing code |
| Themes, fonts | done: tokens in `client/assets/themes/`, fonts in `client/assets/fonts/`, see [theming.md](theming.md) |
| Plugin sandbox (Lua/WASM) | new loader in `plugins/`, same `PluginAPI` surface |

## Conventions

- Code, comments and identifiers in English; user-facing strings go through `tr()`.
- No hard-coded colors or font sizes in screens: use theme type variations or `Themes.color(token)`.
- Pure logic (`protocol/`, `model/`) gets unit tests in `client/tests/unit/`.
- Autoloads are internal. Plugins only see `PluginAPI`.
- Never commit Nintendo/Game Freak assets (sprites, sounds). Load them at runtime from the
  Showdown CDN and cache them in `user://`.
- `ui/screens/dev_console/` is a developer tool, not the product UI: only with `--dev`, the
  "Developer mode" setting or `--screen=dev-console`.
