class_name DataProgressPanel
extends MarginContainer
## First launch: "Downloading game data 42%" with a progress bar, the files and "Continue in
## background" (design: frame 04). If nothing could be downloaded, a blocking error with
## "Try again" takes its place. Hidden whenever a Dex is available.

var _panel := PanelContainer.new()
var _percent := Label.new()
var _bar := ProgressBar.new()
var _bytes := Label.new()
var _files := Label.new()
var _error_slot := VBoxContainer.new()
var _dismissed := false
var _failed := ""
## Dev automation: a fixed progress dictionary to render.
var _preview := {}


func _ready() -> void:
	for side in ["left", "right", "top"]:
		add_theme_constant_override("margin_" + side, 16)
	add_theme_constant_override("margin_bottom", 0)
	_panel.theme_type_variation = &"SectionPanel"
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = tr("Downloading game data")
	title.theme_type_variation = &"DockTitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_percent.theme_type_variation = &"MonoLabel"
	head.add_child(_percent)
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 8
	_bar.max_value = 1.0
	_bar.step = 0.0
	column.add_child(_bar)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	column.add_child(foot)
	_bytes.theme_type_variation = &"MonoSmallLabel"
	foot.add_child(_bytes)
	_files.theme_type_variation = &"MutedLabel"
	_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(_files)
	var later := StateCard.make_button(tr("Continue in background"), &"SmallGhostButton", func() -> void:
		_dismissed = true
		_refresh())
	foot.add_child(later)
	add_child(_error_slot)

	EventBus.data_progress.connect(func(_p: Dictionary) -> void: _refresh())
	EventBus.data_loaded.connect(func(_d: Dex) -> void:
		_failed = ""
		_refresh())
	EventBus.data_failed.connect(func(reason: String) -> void:
		_failed = reason
		_refresh())
	_refresh()


func preview(progress: Dictionary) -> void:
	_preview = progress
	_dismissed = false
	_refresh()


func _refresh() -> void:
	var progress := _preview if not _preview.is_empty() else GameData.progress
	var loading := not _preview.is_empty() or (GameData.dex == null and GameData.loading)
	var failed := _preview.is_empty() and GameData.dex == null and not _failed.is_empty() and not GameData.loading
	_panel.visible = loading and not _dismissed
	_show_error(failed)
	visible = _panel.visible or failed
	if not _panel.visible:
		return
	var fraction := float(progress.get("fraction", 0.0))
	_bar.value = fraction
	_percent.text = "%d%%" % roundi(fraction * 100.0)
	_bytes.text = format_bytes(int(progress.get("bytes", 0)))
	_files.text = files_line(progress.get("files", []))


func _show_error(failed: bool) -> void:
	if failed == (_error_slot.get_child_count() > 0):
		return
	for child in _error_slot.get_children():
		child.queue_free()
	if failed:
		_error_slot.add_child(ErrorBox.blocking(tr("Couldn’t download game data"),
			tr("Pokédex and moves are needed for battles. Check your connection. (%s)") % _failed,
			[[tr("Try again"), func() -> void:
				_failed = ""
				GameData.load_data()]]))


## "Pokédex ✓ · Moves ✓ · Items · Abilities · Type chart"
static func files_line(files: Array) -> String:
	var parts := PackedStringArray()
	for file: Dictionary in files:
		var label := _t(str(file.get("label", "")))
		match str(file.get("state", "")):
			"done":
				label += " ✓"
			"failed":
				label += " ✕"
		parts.append(label)
	return " · ".join(parts)


## 18400000 -> "18.4 MB", 5300 -> "5 KB"
static func format_bytes(bytes: int) -> String:
	if bytes >= 1000000:
		return "%.1f MB" % (bytes / 1000000.0)
	return "%d KB" % roundi(bytes / 1000.0)


static func _t(text: String) -> String:
	return str(TranslationServer.translate(text))
