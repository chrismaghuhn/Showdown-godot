extends Node
## Autoload "EventBus": the single place where app-wide events are declared.
##
## UI and plugins subscribe here instead of talking to the network layer directly.
## Plugins may only use the events listed in PluginAPI.EVENTS - adding a signal here
## does not automatically make it part of the public plugin API.

# Connection
signal connection_state_changed(state: int)
signal connection_error(reason: String)
signal message_received(msg: PSMessage)
signal logged_in(username: String)
signal login_failed(reason: String)

# Rooms and chat
signal room_joined(room_id: String, room_type: String)
signal room_left(room_id: String)
signal chat_message(room_id: String, user: String, text: String)
signal private_message(from: String, to: String, text: String)
signal popup(text: String)

# Battles
signal battle_started(battle: BattleState)
signal battle_updated(battle: BattleState, msg: PSMessage)
signal battle_request(battle: BattleState, request: Dictionary)
signal battle_ended(battle: BattleState, winner: String)

# Game data
signal data_loaded(dex: Dex)
signal data_failed(reason: String)

# Plugins
signal plugin_panel_added(plugin_id: String, slot: StringName, control: Control)
