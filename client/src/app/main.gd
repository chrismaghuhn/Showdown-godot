extends Node
## App entry point. Owns the current screen; for now that is the developer console.

const DevConsoleScene := preload("res://src/ui/screens/dev_console/dev_console.tscn")
const DevAutomation := preload("res://src/app/dev_automation.gd")


func _ready() -> void:
	add_child(DevConsoleScene.instantiate())
	add_child(DevAutomation.new())
