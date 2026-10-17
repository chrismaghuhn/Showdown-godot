# Notifications and sounds

Design: canvas "Settings · Notifications". Code: `NotificationEvents` (rules, pure),
`Notifier` (autoload, events → channels), `Sounds` (autoload, sound packs), `NativeNotifier`
(OS notifications), `ToastStack` (in-app toasts), settings screen.

## Events and defaults

| Event | In-app | Sound | Desktop | Fires when |
|---|---|---|---|---|
| Battle found | ✓ | ✓ | ✓ | a battle starts within 15 s after our search ended (matched), however long it took; not for battles that come back |
| Your turn | ✓ | ✓ | ✓ | a new `|request|` asks for a decision |
| Timer running low | ✓ | ✓ | ✓ | `|inactive|` reports ≤ the warning time (60/30/10 s, default 30) |
| Challenge received | ✓ | ✓ | – | a `|pm|` with `/challenge FORMAT|…` to us |
| Mentioned in chat | ✓ | – | ✓ | our name as a whole word in someone else's chat message (not in the backlog or replayed battle log sent with `|init|`) |
| Private message | ✓ | ✓ | ✓ | a `|pm|` that isn't a command (`/me` counts) |
| Battle ended | ✓ | – | – | `|win|` / `|tie|`; spectators get "NAME won"; not for a result already in the log when opening a battle (unless it came back after a reconnect or restart) |

**Only when in the background** (default on): sound and desktop notifications stay quiet while
the app has focus. In-app toasts are skipped while their subject (e.g. that battle) is on screen.
**Flash taskbar icon on your turn** (default on) uses `DisplayServer.window_request_attention()`.

Toasts: bottom-right, newest on top, at most `toast.max` (3). Info toasts close after
`toast.lifetime.info` (5 s), with actions `toast.lifetime.action` (8 s); your turn, challenges and
timer warnings stay until handled. Hover pauses the timer.

Headless runs and `--no-notifications` disable sounds and desktop notifications (tests, e2e bots).
`--notify-test` sends the settings' test notification.

## Desktop notifications

| OS | How | Tested |
|---|---|---|
| Linux / BSD | `notify-send` (libnotify) | yes |
| macOS | `osascript` `display notification`, texts passed as `argv` | not yet |
| Windows | PowerShell toast script in the user data folder, texts passed as `-File` parameters | not yet |

Texts come from the server (names, formats), so they are never pasted into a command or script.

## Sound packs

```
user://sounds/<pack-id>/
  sdsounds.json
  your-turn.ogg
  …
```

```json
{
  "format": 1,
  "name": "My pack",
  "author": "me",
  "sounds": {
    "battle_found": "found.ogg",
    "your_turn": "your-turn.ogg",
    "timer_low": "timer.ogg",
    "challenge": "challenge.ogg",
    "mention": "ping.ogg",
    "private_message": "ping.ogg",
    "battle_ended": "end.ogg"
  }
}
```

- Formats: `.wav`, `.ogg`, `.mp3`; at most 2 MB and 5 s per sound. Missing events fall back
  to the default pack.
- Per event, users can pick the pack sound, no sound, or their own file (Settings › Sounds).
  Own files are checked (signature, size, length) and copied to `user://sounds/custom/`.
- Notification volume is separate (Settings › Notifications, default 70 %).

The default pack uses CC0 sounds by ObsydianX, see [CREDITS.md](../CREDITS.md).
