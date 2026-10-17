# Game data and sprites

The client loads species, moves, items, abilities, the type chart and sprites at runtime.
Nothing from Nintendo/Game Freak is stored in this repository.

## How loading works

1. On startup `GameData` builds the `Dex` from the **local cache** at once (works offline).
2. It then checks the source in the background:
   - files younger than 24 h (sprites: 30 days) are not requested at all,
   - older files are revalidated with `If-None-Match` / `If-Modified-Since`;
     an unchanged file costs one tiny `304` response,
   - if the network fails, the cached copy keeps being used.
3. `EventBus.data_loaded(dex)` fires whenever a new `Dex` is ready.

Each user downloads the data (~1 MB) once and then only revalidates it about once a day.

Cache location (Linux): `~/.local/share/godot/app_userdata/Showdown Desktop/cache/`.
Delete that folder to force a full reload.

## Configuring the source

| Setting (`settings.cfg`, section `data`) | Command line | Default |
|---|---|---|
| `data_url` | `--data-url=...` | `https://play.pokemonshowdown.com/data/` |
| `sprite_url` | `--sprite-url=...` | `https://play.pokemonshowdown.com/sprites/` |
| – | `--no-data-fetch` | off: only use the cache (tests, CI, offline) |

Check a source with:

```bash
tools/check_data.sh --data-url=https://example.com/data/ --sprite-url=https://example.com/sprites/
```

## Running your own mirror

A mirror only has to serve the same file names as Showdown:

```
<data_url>pokedex.json
<data_url>moves.json
<data_url>items.js
<data_url>abilities.js
<data_url>typechart.js
<sprite_url>gen5/<sprite-id>.png          e.g. gen5/rotom-wash.png
<sprite_url>gen5-back/<sprite-id>.png
<sprite_url>gen5-shiny/<sprite-id>.png
<sprite_url>gen5-back-shiny/<sprite-id>.png
```

Whether to use a mirror for the official server is one of the questions for the Showdown team,
see [official-server.md](official-server.md).

Recommendations:
- Serve `ETag` or `Last-Modified` headers (nginx and Caddy do by default) so revalidation stays cheap.
- Sync the data files from Showdown on a schedule (e.g. daily), not per user request.
- **Sprites are Nintendo/Game Freak assets.** Hosting them yourself means you distribute them.
  Talk to the Showdown team before mirroring sprites; mirroring only the data files is the safer start.

## Known gaps

- Move/item/ability **descriptions** are not part of Showdown's `data/` files. They exist in the
  server repository (`data/text/*.ts`, MIT). A mirror could generate a `descriptions.json` from them.
- Only gen 5 style sprites are used so far (no animated sprites, no item/type icons yet).
