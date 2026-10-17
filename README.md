# Showdown Desktop

[![CI](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/ci.yml/badge.svg)](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/ci.yml)
[![Build](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/build.yml/badge.svg)](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/build.yml)

A **native**, **fully customizable** desktop client for [Pokémon Showdown](https://pokemonshowdown.com),
built on an **open plugin platform**. Made with Godot 4, by and for the community.

> Status: early skeleton. Connecting, logging in, random battles, game data and plugins work through a
> developer console. The real UI is not built yet.

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

# 3. Start the client (second terminal), choose "Local server", enter a name, Connect, Search
tools/run_client.sh
```

To develop in the editor, open `client/project.godot` in Godot.

## Tests

```bash
tools/run_tests.sh     # unit tests (parser, battle state)
tools/e2e_battle.sh    # two headless clients play a full battle on the local server
tools/e2e_reconnect.sh # same, but one client loses its connection twice mid-battle
tools/e2e_sign_in.sh   # signs in and out through the app's sign-in card
tools/check_data.sh    # loads game data + sample sprites from the configured source
```

Both run in GitHub Actions on every push and pull request ([ci.yml](.github/workflows/ci.yml)).
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
token-only JSON files, runtime switching and UI scaling. Open the **theme gallery** from the dev
console or with `tools/run_client.sh --screen=theme-gallery`.

See [docs/architecture.md](docs/architecture.md) for the layer rules,
[docs/plugin-api.md](docs/plugin-api.md) for writing plugins and
[docs/data-sources.md](docs/data-sources.md) for game data, caching and mirrors and
[docs/theming.md](docs/theming.md) for themes and design tokens,
[docs/notifications.md](docs/notifications.md) for notifications and sound packs.
Third-party assets are listed in [CREDITS.md](CREDITS.md).

## License

[MIT](LICENSE). Note: the official Pokémon Showdown *client* is AGPL-licensed, so do not copy code from it
into this repository. The Showdown *server* and its protocol docs are MIT.

## Legal

Pokémon and all related names and assets are © Nintendo / Game Freak / The Pokémon Company.
This is an unofficial fan project and is not affiliated with them or with Smogon / Pokémon Showdown.
