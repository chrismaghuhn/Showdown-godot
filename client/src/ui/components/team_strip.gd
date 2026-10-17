class_name TeamStrip
extends HBoxContainer
## Six small team icons in the battle header: tinted by the Pokémon's first type, a ring on
## the active one, a cross for fainted ones, empty squares for not-yet-seen opponents.
## Each icon has a tooltip (never color alone).


class TeamIcon extends Control:
	var tint := Color.TRANSPARENT
	var is_active := false
	var is_fainted := false
	var is_unknown := false

	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(4)
		box.bg_color = get_theme_color("unknown", "TeamIcon") if is_unknown else (Color.TRANSPARENT if is_fainted else tint)
		box.border_color = get_theme_color("ring", "TeamIcon") if is_active else get_theme_color("border", "TeamIcon")
		box.set_border_width_all(2 if is_active else 1)
		if is_active:
			box.set_expand_margin_all(1)
		draw_style_box(box, rect)
		if is_fainted:
			var c := get_theme_color("fainted", "TeamIcon")
			draw_line(Vector2(5, 5), size - Vector2(5, 5), c, 1.5, true)
			draw_line(Vector2(size.x - 5, 5), Vector2(5, size.y - 5), c, 1.5, true)


func _init() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## mons: BattlePokemon list in team order; team_size: total (unknown ones are drawn empty).
func show_team(mons: Array, team_size: int, dex: Dex) -> void:
	for child in get_children():
		child.queue_free()
	var count := maxi(team_size, mons.size())
	for i in count:
		var icon := TeamIcon.new()
		if i < mons.size():
			var mon: BattlePokemon = mons[i]
			icon.is_active = mon.active
			icon.is_fainted = mon.fainted
			var species: DexSpecies = dex.get_species(mon.species) if dex != null else null
			var type_id := species.types[0].to_lower() if species != null and not species.types.is_empty() else "normal"
			icon.tint = Themes.color("color.type.%s.bg" % type_id)
			icon.tint.a = 0.35
			icon.tooltip_text = mon.name + (" · " + tr("fainted") if mon.fainted else (" · " + tr("active") if mon.active else ""))
		else:
			icon.is_unknown = true
			icon.tooltip_text = tr("Not revealed yet")
		add_child(icon)
