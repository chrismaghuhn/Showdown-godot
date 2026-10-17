extends SceneTree
## Runs one end-to-end flow from tests/e2e/ inside the app, with the autoloads ready:
##   godot --headless --path client -s res://tests/e2e/run.gd -- --e2e=sign_in_flow
## The flow is a Node script; it quits with exit code 0 (passed) or 1.

var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		var flow_name := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--e2e="):
				flow_name = arg.trim_prefix("--e2e=")
		var script: Script = load("res://tests/e2e/%s.gd" % flow_name) if not flow_name.is_empty() else null
		if script == null:
			print("[e2e] unknown flow '%s'" % flow_name)
			quit(1)
			return false
		root.add_child(script.new())
	return false
