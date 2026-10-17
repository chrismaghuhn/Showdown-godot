extends Node
## Autoload "EventBus": the single place where app-wide events are declared.
##
## UI and plugins subscribe here instead of talking to the network layer directly.
## Plugins may only use the events listed in PluginAPI.EVENTS - adding a signal here
## does not automatically make it part of the public plugin API.

# Connection
## Connection.State: DISCONNECTED, CONNECTING, CONNECTED, WAITING (next attempt scheduled).
signal connection_state_changed(state: int)
## Unrecoverable: unknown server, or still no connection after the last allowed attempt.
signal connection_error(reason: String)
## The connection is gone; attempt `attempt` of `max_attempts` starts in `delay` seconds.
signal reconnect_scheduled(attempt: int, max_attempts: int, delay: float)
## The connection is back after a drop (and signed in again, if it was before).
signal reconnected
signal message_received(msg: PSMessage)
signal logged_in(username: String)
signal login_failed(reason: String)
## The chosen name is registered: ask for its password.
signal password_required(username: String)
signal signed_out
## Something (header status, start screen) asks for the connect / sign-in card.
signal sign_in_requested

# Rooms and chat
signal room_joined(room_id: String, room_type: String)
signal room_left(room_id: String)
signal chat_message(room_id: String, user: String, text: String)
signal private_message(from: String, to: String, text: String)
signal popup(text: String)
## After a reconnect: how many battles came back with their full log.
signal battles_restored(count: int)

# Battles
signal battle_started(battle: BattleState)
signal battle_updated(battle: BattleState, msg: PSMessage)
signal battle_request(battle: BattleState, request: Dictionary)
signal battle_ended(battle: BattleState, winner: String)

# Game data
signal data_loaded(dex: Dex)
signal data_failed(reason: String)
## While the data files download: {fraction, bytes, files: [{key, label, state}]}
## (state: "pending", "loading", "done" or "failed"). See GameData.progress.
signal data_progress(progress: Dictionary)

# Appearance and navigation
signal theme_changed(theme_id: String)
signal ui_scale_changed(scale: float)
## Asks the app to show a screen, e.g. &"dev-console" or &"theme-gallery".
signal navigation_requested(screen: StringName)
## The visible screen changed (emitted by Main).
signal screen_changed(screen: StringName)

# Notifications
## {event, title, body, actions: [[label, Callable]], key, persistent}
signal toast_requested(toast: Dictionary)
## Withdraw a toast by key (e.g. "your_turn:<room id>") once it was handled.
signal toast_dismissed(key: String)

# Plugins
signal plugin_panel_added(plugin_id: String, slot: StringName, control: Control)
## A plugin caused an error and was switched off until reloaded (Plugins.reload()).
signal plugin_paused(plugin_id: String, reason: String)
