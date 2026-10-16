# Showdown Desktop

[![CI](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/ci.yml/badge.svg)](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/ci.yml)
[![Build](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/build.yml/badge.svg)](https://github.com/chrismaghuhn/Showdown-godot/actions/workflows/build.yml)

A community-built desktop client for [Pokémon Showdown](https://pokemonshowdown.com), made with Godot 4.
Fully customizable, with plugin support.

> Status: early skeleton. Connecting, logging in, random battles and plugins work through a developer console.
> The real UI is not built yet.

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
    model/         battle state (pure)
    net/           websocket + login
    core/          config, event bus, room routing (autoloads)
    plugins/       plugin loader and public plugin API
    ui/            screens and components
  assets/          themes, fonts (own assets only)
  tests/           unit tests + headless runner
plugins/           example and dev plugins
docs/              architecture.md, plugin-api.md
tools/             dev scripts (server, client, tests, export)
.github/           CI workflows and the setup-godot action
```

See [docs/architecture.md](docs/architecture.md) for the layer rules and
[docs/plugin-api.md](docs/plugin-api.md) for writing plugins.

## License

[MIT](LICENSE). Note: the official Pokémon Showdown *client* is AGPL-licensed, so do not copy code from it
into this repository. The Showdown *server* and its protocol docs are MIT.

## Legal

Pokémon and all related names and assets are © Nintendo / Game Freak / The Pokémon Company.
This is an unofficial fan project and is not affiliated with them or with Smogon / Pokémon Showdown.
