# Showdown Desktop

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
tools/             dev scripts (server, client, tests)
```

See [docs/architecture.md](docs/architecture.md) for the layer rules and
[docs/plugin-api.md](docs/plugin-api.md) for writing plugins.

## Legal

Pokémon and all related names and assets are © Nintendo / Game Freak / The Pokémon Company.
This is an unofficial fan project and is not affiliated with them or with Smogon / Pokémon Showdown.
