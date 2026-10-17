# Showdown Desktop

[![CI](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/ci.yml/badge.svg)](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/ci.yml)
[![Build](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/build.yml/badge.svg)](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/build.yml)

A **native**, **fully customizable** desktop client for [Pokémon Showdown](https://pokemonshowdown.com),
built on an **open plugin platform**. Made with Godot 4, by and for the community.

> Status: early, playable. Start screen, sign-in, a lobby (formats, challenges, ratings), Random Battles
> in tabs, reconnecting, notifications, themes and plugins work. The Teambuilder, chat rooms and replays
> come next (see milestones).

## Why another client?

Most desktop options wrap the official web client in a browser shell. That is fast to build, but the
look can only be re-skinned and every upstream change can break add-ons. Showdown Desktop takes the
other route:

- **Native client.** Its own UI talks to the Showdown server protocol directly. It does not depend on the web client's code or page structure.
- **Fully customizable.** Every color, font and spacing value comes from design tokens. Community themes, per-area themes and UI scaling are core features, not CSS overrides.
- **Open plugin platform.** A documented, versioned [plugin API](docs/plugin-api.md) with typed access to battles, game data and UI slots, so anyone can build add-ons that survive updates.
- **Desktop first.** Local team storage with backups, native notifications, offline-cached game data, keyboard-driven workflows.
- **Open source, MIT.**

Planned features are tracked as [issues](https://github.com/chrismaghuhn/Showdown-godot/issues) and
[milestones](https://github.com/chrismaghuhn/Showdown-godot/milestones). Many come straight from
community wishes (label `community-wish`).

## Quick start

Requirements: Godot 4.7+, Node.js 18+ (for a local server).

```bash
# 1. Set up a local Showdown server once (next to this repo)
git clone https://github.com/smogon/pokemon-showdown.git ../pokemon-showdown
(cd ../pokemon-showdown && npm install)

# 2. Start it (no login server needed)
tools/local_server.sh

# 3. Start the client (second terminal). On the start screen click "Offline" (top right),
#    "Change server" -> "Local server", choose a name, then "Battle!" (Ctrl+Enter).
#    The server is remembered for next time.
tools/run_client.sh
```

To develop in the editor, open `client/project.godot` in Godot.

## Tests

```bash
tools/run_tests.sh     # unit tests (parser, battle state)
tools/e2e_battle.sh    # two headless clients play a full battle on the local server
tools/e2e_reconnect.sh # same, but one client loses its connection twice mid-battle
tools/e2e_ui.sh        # UI flows: sign-in, start screen, battle tabs, rejoin, lobby challenges and ratings
tools/check_data.sh    # loads game data + sample sprites from the configured source
```

Tests run with a throwaway settings file (`--settings-file`), so they never change your own settings.
They run in GitHub Actions on every push and pull request ([ci.yml](.github/workflows/ci.yml)).
The end-to-end test uses a pinned Showdown server commit (`PS_SERVER_REF`) and never touches the official servers.

## Builds

```bash
tools/export.sh        # Linux, Windows and macOS builds into build/dist/
```

Needs the export templates for the exact Godot version (editor: *Editor → Manage Export Templates*).
CI builds all three platforms on every push to `main` ([build.yml](.github/workflows/build.yml)) and
attaches them as a workflow artifact. Pushing a tag like `v0.1.0` creates a **draft** GitHub release
with the builds; review and publish it by hand.

macOS builds are ad-hoc signed, not notarized: on first start, right-click the app → *Open*.

## Repository layout

```
client/            Godot project
  src/
    app/           entry scene, dev automation
    protocol/      Showdown protocol parser (pure)
    data/          Dex: species, moves, items, abilities, type chart (pure)
    model/         battle state (pure)
    net/           websocket + login
    core/          config, event bus, room routing (autoloads)
    plugins/       plugin loader and public plugin API
    ui/            screens and components
  assets/          themes (design tokens), fonts (Atkinson Hyperlegible, OFL)
  tests/           unit tests + headless runner
plugins/           example and dev plugins
docs/              architecture.md, plugin-api.md
tools/             dev scripts (server, client, tests, export)
.github/           CI workflows and the setup-godot action
```

Battle screen: layout B "Desktop" from the design system — battlefield with sprites on the
spec'd stage, HUD cards with animated HP, field conditions, moves and switches from the server's
request (hotkeys 1–4, Shift+1–6, Esc), tera, timer, battle log, chat and the plugin sidebar.

Notifications: in-app toasts, sounds (exchangeable, sound packs) and native desktop notifications
for battle found, your turn, timer low, challenges, mentions, private messages and battle end —
configurable per event in Settings. See [docs/notifications.md](docs/notifications.md).

Themes: three built-in themes (Midnight Dark, Classic Light, High Contrast), community themes as
token-only JSON files, runtime switching and UI scaling. Open the **theme gallery** with
`tools/run_client.sh --screen=theme-gallery`, or turn on *Settings › General › Developer mode* and
use Ctrl+K.

App shell: a start screen at launch (welcome, the battle in progress with Rejoin, menu 1–5, quick
battle with Ctrl+Enter, release news), then tabs for Home, Teambuilder and one per battle with a
"your move" dot. Ctrl+1–9 and Ctrl+Tab switch tabs, Ctrl+W closes one, Ctrl+K opens the command
menu. The developer console only appears with `--dev` or developer mode.

See [docs/architecture.md](docs/architecture.md) for the layer rules,
[docs/plugin-api.md](docs/plugin-api.md) for writing plugins and
[docs/data-sources.md](docs/data-sources.md) for game data, caching and mirrors and
[docs/theming.md](docs/theming.md) for themes and design tokens,
[docs/notifications.md](docs/notifications.md) for notifications and sound packs,
[docs/official-server.md](docs/official-server.md) for how the client behaves on the official server.
Third-party assets are listed in [CREDITS.md](CREDITS.md).

## License

[MIT](LICENSE). Note: the official Pokémon Showdown *client* is AGPL-licensed, so do not copy code from it
into this repository. The Showdown *server* and its protocol docs are MIT.

## Legal

Pokémon and all related names and assets are © Nintendo / Game Freak / The Pokémon Company.
This is an unofficial fan project and is not affiliated with them or with Smogon / Pokémon Showdown.
