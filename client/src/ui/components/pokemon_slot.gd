class_name PokemonSlot
extends Button
## 48px team slot: mini sprite (initials, type tint), name, small HP bar, exact HP and status.
## Active = selected style; fainted or trapped = disabled. Hotkey tag (e.g. "Shift+2") shows on
## hover and keyboard focus.

var mon: BattlePokemon
## Returns a custom tooltip Control; set by the battle screen.
var tooltip_builder: Callable
var _mini := PanelContainer.new()
var _initials := Label.new()
var _name := Label.new()
var _bar := HPBar.new()
var _meta := Label.new()
var _status := StatusBadge.new()
var _hotkey := Label.new()


func _init() -> void:
	theme_type_variation = &"SlotButton"
	toggle_mode = true
	custom_minimum_size = Vector2(150, 48)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_mini.theme_type_variation = &"MiniSprite"
	_mini.custom_minimum_size = Vector2(28, 28)
	_mini.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initials.theme_type_variation = &"MiniSpriteLabel"
	_initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mini.add_child(_initials)
	row.add_child(_mini)

	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 3)
	row.add_child(body)
	_name.theme_type_variation = &"SlotNameLabel"
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	body.add_child(_name)
	_bar.bar_height = 4
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_bar)
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(meta)
	_meta.theme_type_variation = &"SlotMetaLabel"
	_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_meta)
	meta.add_child(_status)

	_hotkey.theme_type_variation = &"KbdLabel"
	_hotkey.position = Vector2(0, -12)
	_hotkey.visible = false
	add_child(_hotkey)
	for node: Control in [_name, _meta, _initials, _hotkey]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(_update_hotkey)
	mouse_exited.connect(_update_hotkey)
	focus_entered.connect(_update_hotkey)
	focus_exited.connect(_update_hotkey)
	resized.connect(func() -> void: _hotkey.position.x = size.x - _hotkey.size.x - 6)


## own: exact HP; otherwise percent. tint: the Pokémon's first type color.
func show_pokemon(pokemon: BattlePokemon, own: bool, tint: Color, hotkey := "") -> void:
	mon = pokemon
	_initials.text = pokemon.species.left(2)
	var mini_box := (_mini.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	if mini_box != null:
		mini_box.bg_color = Color(tint, 0.25) if not pokemon.fainted else Color.TRANSPARENT
		_mini.add_theme_stylebox_override("panel", mini_box)
	_name.text = pokemon.name
	_name.theme_type_variation = &"SlotNameLabelDisabled" if pokemon.fainted else &"SlotNameLabel"
	_bar.percent = pokemon.hp_percent()
	_bar.visible = not pokemon.fainted
	_meta.text = tr("Fainted") if pokemon.fainted else ("%d/%d" % [pokemon.hp, pokemon.max_hp] if own else "%d%%" % roundi(pokemon.hp_percent()))
	_status.visible = not pokemon.status.is_empty()
	if _status.visible:
		_status.status = pokemon.status
	button_pressed = pokemon.active
	_hotkey.text = hotkey
	tooltip_text = "%s (%s) · %s" % [pokemon.name, pokemon.species, _meta.text]
	_update_hotkey()


func _update_hotkey() -> void:
	var hovered := get_global_rect().has_point(get_global_mouse_position()) if is_inside_tree() else false
	_hotkey.visible = not _hotkey.text.is_empty() and not disabled and (hovered or has_focus())


## Returns the tooltip Control (set by the battle screen); falls back to tooltip_text.
func _make_custom_tooltip(_for_text: String) -> Object:
	return tooltip_builder.call() if tooltip_builder.is_valid() else null
