# The official server

What Showdown Desktop does when it talks to the official Pokémon Showdown servers, what has been
checked, and what is still open before a public release (issue #24).

## Endpoints

| What | Where | Notes |
|---|---|---|
| Game server | `wss://sim3.psim.us/showdown/websocket` | the raw websocket endpoint (no SockJS) |
| Login server | `https://play.pokemonshowdown.com/api/<action>` | `login`, `getassertion`, `upkeep`, `logout` |
| Ladder ratings | `https://pokemonshowdown.com/users/<userid>.json` | the server's `/rank` only points to the web client |
| Game data, sprites | `https://play.pokemonshowdown.com/data/`, `/sprites/` | see [data-sources.md](data-sources.md) |
| Client news | `https://api.github.com/repos/chrismaghuhn/Showdown-godot/releases` | this project only |

Every request names the client: `User-Agent: ShowdownDesktop/<version>
(+https://github.com/chrismaghuhn/Showdown-godot)` - the websocket handshake, the login server,
and every download (data, sprites, ratings, news).

## Being a good citizen

- **Pacing.** The server runs one chat message or command per 600 ms for a normal user, holds
  five more and drops the rest with "typing too quickly" (`server/users.ts`, `User.chat`).
  `Connection` paces itself a little slower (`SendThrottle`: a burst of 4, then one message every
  650 ms, in order), because the server's timers run late. If the server drops one anyway, the
  client pauses for 2 s (nothing refills meanwhile) and tells the user once.
  Closing on purpose ("Work offline", quitting) sends what's still queued first, so a move
  isn't lost; a dropped connection discards it (the server repeats the request on rejoin).
  Local test servers started with `--no-security` don't throttle, so the e2e tests can't show
  throttle problems; the unit tests cover the pacing.
- **One command per message.** The server runs every line of a message as a command; line
  breaks in anything the client sends become spaces.
- **Names as ids.** Challenges, accepting and declining send user and format ids only.
- **Reconnecting.** 2, 4, 8, 16 and 30 s (±20 % jitter, so clients don't return all at once
  after a restart), at most 5 attempts, then the user decides. A dead link is noticed by a
  websocket ping every 10 s; sim3 answers pings (checked: a guest connection with 5 s pings
  stayed open).
- **No `/cmd` polling.** The client sends no periodic commands. Ratings come from the user JSON
  at sign-in and after rated battles (cached 60 s).
- **Data and sprites.** Cached on disk: data files are revalidated about once a day with
  `ETag` / `If-Modified-Since`, sprites after 30 days. A typical user downloads ~1 MB of data
  once. No mirror for now; see "Questions for the Showdown team".

## Sign-in: checked against the login server's source

`LoginClient` follows [smogon/pokemon-showdown-loginserver](https://github.com/smogon/pokemon-showdown-loginserver)
(`src/actions.ts`, `src/server.ts`, `src/user.ts`):

- **Registered name with password:** `POST login` with `name`, `pass`, `challstr` returns
  `{actionsuccess, assertion}` and sets the `sid` cookie. A wrong password comes back as
  `{"actionerror": "Wrong password."}`.
- **Unregistered name:** `GET getassertion?userid=…&challstr=…` returns the assertion as plain
  text; `;` means the name is registered (the client then asks for the password), `;;…` is an
  error. GET parameters are accepted (`src/server.ts` reads the query string).
- **Stay signed in:** `upkeep?challstr=…` with the `sid` cookie returns
  `{assertion, username, loggedin}`. The cookie is saved owner-only; the password never is.
- **Errors:** answers start with `]`, errors arrive as `{"actionerror": …}`, and a non-200 answer
  (e.g. a 502 page) is never taken as an assertion.

Also checked on the live login server: steps 2–5 of the manual test log below.

## Manual test log

Done by a person on the official server. No bots on the main server.

Run on 2026-10-17 by the project lead on Linux, with the release build 0.1.0-dev-bb61a8d
(including the Random Battle) and from source. Which other steps ran on which wasn't noted.

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Start the app, Connect → official server | connects, "Online · sim3" | passed |
| 2 | Choose an unregistered name | signed in under that name | passed |
| 3 | Sign out, choose your registered name, enter the password | password step, then signed in | passed |
| 4 | Wrong password once | inline "Wrong password." | passed |
| 5 | "Stay signed in", quit, start again | signed in without a password | passed |
| 6 | Quick battle: [Gen 9] Random Battle | battle tab opens, moves work to the end | passed (won) |
| 7 | Challenge a friend (and get challenged) | send, accept, decline, cancel | passed |
| 8 | Pull the network cable mid-battle, plug it back in | banner, reconnect, battle restored | passed |
| 9 | Lobby | your ratings appear after a rated battle | passed |

Seen along the way:

- The release build logs Godot errors ("Attempt to disconnect a nonexistent connection …
  'focus_entered'") whenever a tooltip or popup closes. A harmless Godot bug
  (godotengine/godot#87626) that only shows in release builds; see #82.
- On a first launch, the format picker showed the raw id (`gen9randombattle`) until the
  server's list arrived. #81 fixes it.

Repeat the log with the release candidate before tagging the release (#25).

## Contacting the Showdown team

Status: **not contacted yet.** The project lead posts this personally, for example in the
Pokémon Showdown "Development" chat room or the Smogon forum's Pokémon Showdown section.

Draft:

> Hi! I'm working on Showdown Desktop, an open source (MIT) desktop client for Pokémon Showdown
> built with Godot: https://github.com/chrismaghuhn/Showdown-godot. It talks to the server
> protocol directly (raw websocket at sim3.psim.us), signs in through the login server API
> (`login` / `getassertion` / `upkeep`), and identifies itself with a `ShowdownDesktop/<version>`
> User-Agent on every request. It paces its own commands a bit slower than your chat throttle
> (one per 650 ms after a short burst), backs off reconnects (2–30 s with jitter, max 5), and caches data files and sprites
> (data revalidated daily, sprites monthly). Before a public release I'd like to make sure
> this is welcome and done the way you prefer:
>
> 1. Is a third-party client like this okay on the main server, and is there anything you'd
>    like it to do differently (connection, login, ratings via users/<id>.json)?
> 2. Is loading data files and sprites from play.pokemonshowdown.com acceptable at this
>    caching level, or would you rather we mirror the data files (and leave sprites to you)?
> 3. Anything you'd like the client to show or link (rules, staff contact, news)?
>
> Happy to change anything. Thanks for Showdown!

Their answer goes here once it arrives.

## Questions for the Showdown team

- Data files and sprites: fine to load from `play.pokemonshowdown.com` with the caching above,
  or should the client use a mirror for data files?
- Ratings from `pokemonshowdown.com/users/<id>.json`: okay, or is there a preferred source?
- Anything they want from third-party clients (identification, rate limits, links).
