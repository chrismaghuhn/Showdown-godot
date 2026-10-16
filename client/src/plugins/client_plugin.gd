class_name ClientPlugin
extends Node
## Base class for plugins. A plugin's entry script must `extends ClientPlugin`.
##
##     extends ClientPlugin
##
##     func _plugin_enable() -> void:
##         api.on(&"battle_started", func(battle): api.info("New battle: " + battle.room_id))

## Set by the PluginManager before _plugin_enable() is called.
var api: PluginAPI


## Called once after the plugin was loaded. Subscribe to events here.
func _plugin_enable() -> void:
	pass


## Called before the plugin is unloaded. Event subscriptions are removed automatically.
func _plugin_disable() -> void:
	pass
