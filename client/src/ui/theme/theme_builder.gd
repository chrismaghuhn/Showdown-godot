class_name ThemeBuilder
extends RefCounted
## Compiles ThemeTokens into one Godot Theme resource (see the token -> theme item mapping in
## docs/theming.md). Every color, size and font in the UI comes from here; screens and
## components only pick a theme type variation, never a hard-coded color.

const BUNDLED_FONTS := {
	"Atkinson Hyperlegible Next": {
		400: "res://assets/fonts/AtkinsonHyperlegibleNext-Regular.ttf",
		600: "res://assets/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf",
		700: "res://assets/fonts/AtkinsonHyperlegibleNext-Bold.ttf",
	},
	"Atkinson Hyperlegible Mono": {
		400: "res://assets/fonts/AtkinsonHyperlegibleMono-Regular.ttf",
		600: "res://assets/fonts/AtkinsonHyperlegibleMono-SemiBold.ttf",
	},
}

static var _font_cache := {}

var t: ThemeTokens
var theme := Theme.new()
var _bw := 1
var _fonts := {}


static func build(tokens: ThemeTokens) -> Theme:
	var builder := ThemeBuilder.new()
	builder.t = tokens
	builder._build()
	return builder.theme


## Bundled font for a family/weight, or a system font as fallback (never a file path from a theme).
static func font(family: String, weight: int) -> Font:
	var cache_key := "%s|%d" % [family, weight]
	if _font_cache.has(cache_key):
		return _font_cache[cache_key]
	var result: Font
	if BUNDLED_FONTS.has(family):
		var weights: Dictionary = BUNDLED_FONTS[family]
		var best := 400
		for w: int in weights:
			if absi(w - weight) < absi(best - weight):
				best = w
		result = load(weights[best])
	else:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray([family])
		system_font.font_weight = weight
		result = system_font
	_font_cache[cache_key] = result
	return result


func _build() -> void:
	_bw = t.px("border.width.default")
	_fonts = {
		"ui": font(t.text("font.family.ui"), 400),
		"ui_semi": font(t.text("font.family.ui"), 600),
		"ui_bold": font(t.text("font.family.ui"), 700),
		"mono": font(t.text("font.family.mono"), 400),
		"mono_semi": font(t.text("font.family.mono"), 600),
	}
	theme.default_font = _fonts["ui"]
	theme.default_font_size = t.px("font.size.md")
	_build_containers()
	_build_panels()
	_build_labels()
	_build_badges()
	_build_buttons()
	_build_inputs()
	_build_tabs()
	_build_popups()
	_build_scrolling()
	_build_battle()


# --- Helpers ----------------------------------------------------------------------

func c(key: String) -> Color:
	return t.color(key)


func _box(bg: Color, border: Color, border_width: int, radius: int, pad_h: int, pad_v: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.anti_aliasing = true
	return box


func _shadow(box: StyleBoxFlat, size: String) -> StyleBoxFlat:
	box.shadow_color = c("shadow.%s.color" % size)
	box.shadow_size = t.px("shadow.%s.size" % size)
	box.shadow_offset = Vector2(0, t.num("shadow.%s.offset" % size))
	return box


## 2px focus ring with 2px offset, drawn over the control (design: "never removed").
func _focus(radius: int) -> StyleBoxFlat:
	var ring := t.px("border.width.focus")
	var box := _box(Color.TRANSPARENT, c("color.focus.ring"), ring, radius + ring, 0, 0)
	box.draw_center = false
	box.set_expand_margin_all(ring * 2)
	return box


func _variation(variation: String, base: String) -> void:
	theme.set_type_variation(variation, base)


func _label_style(type: String, color: Color, font_key: String, size_key: String) -> void:
	theme.set_color("font_color", type, color)
	theme.set_font("font", type, _fonts[font_key])
	theme.set_font_size("font_size", type, t.px(size_key))


# --- Containers and panels ----------------------------------------------------------

func _build_containers() -> void:
	var gap := t.px("space.sm")
	for type in ["BoxContainer", "HBoxContainer", "VBoxContainer", "FlowContainer", "HFlowContainer", "VFlowContainer"]:
		theme.set_constant("separation", type, gap)
	for type in ["FlowContainer", "HFlowContainer", "VFlowContainer"]:
		theme.set_constant("h_separation", type, gap)
		theme.set_constant("v_separation", type, gap)
	theme.set_constant("h_separation", "GridContainer", gap)
	theme.set_constant("v_separation", "GridContainer", gap)
	for type in ["SplitContainer", "HSplitContainer", "VSplitContainer"]:
		theme.set_constant("separation", type, gap)
	var line := StyleBoxLine.new()
	line.color = c("color.border.subtle")
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = c("color.border.subtle")
	vline.thickness = 1
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)


func _build_panels() -> void:
	var lg := t.px("radius.lg")
	var md := t.px("radius.md")
	var pad := t.px("space.md")
	var panel := _box(c("color.surface.panel"), c("color.border.default"), _bw, lg, pad, pad)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	var variations := {
		"AppBackground": _box(c("color.surface.app"), Color.TRANSPARENT, 0, 0, 0, 0),
		"FieldPanel": _box(c("color.field.bg"), Color.TRANSPARENT, 0, lg, 0, 0),
		"RaisedPanel": _box(c("color.surface.raised"), c("color.border.default"), _bw, md, t.px("space.sm"), t.px("space.sm")),
		"SunkenPanel": _box(c("color.surface.sunken"), c("color.border.subtle"), _bw, md, t.px("space.sm"), t.px("space.sm")),
		"OverlayPanel": _shadow(_box(c("color.surface.overlay"), c("color.border.default"), _bw, lg, pad, pad), "md"),
		"FlatPanel": _box(c("color.surface.panel"), Color.TRANSPARENT, 0, 0, 0, 0),
	}
	for variation: String in variations:
		_variation(variation, "PanelContainer")
		theme.set_stylebox("panel", variation, variations[variation])


func _build_labels() -> void:
	_label_style("Label", c("color.text.primary"), "ui", "font.size.md")
	var labels := {
		"SecondaryLabel": [c("color.text.secondary"), "ui", "font.size.md"],
		"MutedLabel": [c("color.text.muted"), "ui", "font.size.sm"],
		"CapsLabel": [c("color.text.muted"), "ui_bold", "font.size.xs"],
		"HeadingLabel": [c("color.text.primary"), "ui_semi", "font.size.lg"],
		"TitleLabel": [c("color.text.primary"), "ui_bold", "font.size.xl"],
		"DisplayLabel": [c("color.text.primary"), "ui_bold", "font.size.2xl"],
		"MonoLabel": [c("color.text.primary"), "mono_semi", "font.size.md"],
		"MonoSmallLabel": [c("color.text.secondary"), "mono_semi", "font.size.sm"],
		"DangerLabel": [c("color.danger.text"), "ui_semi", "font.size.md"],
		"SuccessLabel": [c("color.success.text"), "ui_semi", "font.size.md"],
		"WarningLabel": [c("color.warning.text"), "ui_semi", "font.size.md"],
		"PluginLabel": [c("color.plugin.text"), "ui_semi", "font.size.sm"],
	}
	for variation: String in labels:
		var spec: Array = labels[variation]
		_variation(variation, "Label")
		_label_style(variation, spec[0], spec[1], spec[2])

	var rtl := "RichTextLabel"
	theme.set_color("default_color", rtl, c("color.text.primary"))
	theme.set_font("normal_font", rtl, _fonts["ui"])
	theme.set_font("bold_font", rtl, _fonts["ui_bold"])
	theme.set_font("mono_font", rtl, _fonts["mono"])
	for size_item in ["normal_font_size", "bold_font_size", "mono_font_size", "italics_font_size", "bold_italics_font_size"]:
		theme.set_font_size(size_item, rtl, t.px("font.size.md"))
	theme.set_color("selection_color", rtl, c("color.accent.subtle"))


## Badges and chips are Labels with a background stylebox ("normal"); every one carries text.
func _build_badges() -> void:
	var sm := t.px("radius.sm")
	var badge_border := c("color.badge.border")
	for type_id in ThemeTokens.TYPES:
		_badge("TypeBadge_" + type_id, c("color.type.%s.bg" % type_id), c("color.type.%s.fg" % type_id), badge_border, "ui_bold", "font.size.xs", sm)
	for status in ThemeTokens.STATUSES:
		_badge("StatusBadge_" + status, c("color.status.%s.bg" % status), c("color.status.%s.fg" % status), badge_border, "ui_bold", "font.size.xs", sm)
	_badge("BoostUpChip", c("color.boost.up.bg"), c("color.boost.up.fg"), badge_border, "mono_semi", "font.size.sm", sm)
	_badge("BoostDownChip", c("color.boost.down.bg"), c("color.boost.down.fg"), badge_border, "mono_semi", "font.size.sm", sm)
	_badge("VolatileChip", c("color.surface.sunken"), c("color.text.secondary"), c("color.border.default"), "ui_semi", "font.size.xs", sm)
	_badge("PluginBadge", c("color.plugin.subtle"), c("color.plugin.text"), badge_border, "ui_bold", "font.size.xs", sm)
	_badge("FieldChip", c("color.surface.panel"), c("color.text.primary"), c("color.border.default"), "ui_semi", "font.size.sm", t.px("space.md"))
	_badge("KbdLabel", c("color.surface.overlay"), c("color.text.primary"), c("color.border.strong"), "mono_semi", "font.size.xs", sm)


func _badge(variation: String, bg: Color, fg: Color, border: Color, font_key: String, size_key: String, radius: int) -> void:
	_variation(variation, "Label")
	_label_style(variation, fg, font_key, size_key)
	var pad_h := t.px("space.sm") if variation != "KbdLabel" else t.px("space.xs")
	theme.set_stylebox("normal", variation, _box(bg, border, maxi(_bw, 1), radius, pad_h, 2))


# --- Buttons ------------------------------------------------------------------------

## states: {normal, hover, pressed, disabled} -> [bg, border]; colors: [fg, hover_fg, disabled_fg]
func _button(type: String, states: Dictionary, colors: Array, pad_h: int, pad_v: int, font_key := "ui_semi", size_key := "font.size.md", radius_key := "radius.md") -> void:
	var radius := t.px(radius_key)
	for state: String in states:
		var spec: Array = states[state]
		theme.set_stylebox(state, type, _box(spec[0], spec[1], _bw, radius, pad_h, pad_v))
	theme.set_stylebox("focus", type, _focus(radius))
	theme.set_color("font_color", type, colors[0])
	theme.set_color("font_focus_color", type, colors[0])
	theme.set_color("font_hover_color", type, colors[1])
	theme.set_color("font_pressed_color", type, colors[1])
	theme.set_color("font_hover_pressed_color", type, colors[1])
	theme.set_color("font_disabled_color", type, colors[2])
	theme.set_color("icon_normal_color", type, colors[0])
	theme.set_color("icon_hover_color", type, colors[1])
	theme.set_color("icon_pressed_color", type, colors[1])
	theme.set_color("icon_disabled_color", type, colors[2])
	theme.set_font("font", type, _fonts[font_key])
	theme.set_font_size("font_size", type, t.px(size_key))
	theme.set_constant("h_separation", type, t.px("space.sm"))
	theme.set_constant("icon_max_width", type, 16)


func _build_buttons() -> void:
	var clear := Color.TRANSPARENT
	var md := t.px("space.md")
	var sm := t.px("space.sm")
	var primary_fg := c("color.text.primary")
	var disabled := [clear, c("color.border.subtle")]
	var secondary := {
		"normal": [c("color.surface.raised"), c("color.border.default")],
		"hover": [c("color.surface.hover"), c("color.border.strong")],
		"pressed": [c("color.surface.pressed"), c("color.border.strong")],
		"disabled": disabled,
	}
	var secondary_colors := [primary_fg, primary_fg, c("color.text.disabled")]
	for type in ["Button", "OptionButton", "MenuButton"]:
		_button(type, secondary, secondary_colors, md, 7)
	theme.set_color("font_color", "OptionButton", primary_fg)

	_variation("PrimaryButton", "Button")
	_button("PrimaryButton", {
		"normal": [c("color.accent.default"), c("color.accent.default")],
		"hover": [c("color.accent.hover"), c("color.accent.hover")],
		"pressed": [c("color.accent.pressed"), c("color.accent.pressed")],
		"disabled": disabled,
	}, [c("color.text.on-accent"), c("color.text.on-accent"), c("color.text.disabled")], md, 7)

	_variation("GhostButton", "Button")
	_button("GhostButton", {
		"normal": [clear, clear],
		"hover": [c("color.surface.hover"), clear],
		"pressed": [c("color.surface.pressed"), clear],
		"disabled": [clear, clear],
	}, [c("color.text.secondary"), primary_fg, c("color.text.disabled")], md, 7)

	_variation("DangerButton", "Button")
	_button("DangerButton", {
		"normal": [clear, c("color.border.default")],
		"hover": [c("color.danger.subtle"), c("color.danger.text")],
		"pressed": [c("color.danger.subtle"), c("color.danger.default")],
		"disabled": disabled,
	}, [c("color.danger.text"), c("color.danger.text"), c("color.text.disabled")], md, 7)

	_variation("SmallButton", "Button")
	_button("SmallButton", secondary, secondary_colors, sm, 5, "ui_semi", "font.size.sm")

	_variation("IconButton", "Button")
	_button("IconButton", {
		"normal": [clear, clear],
		"hover": [c("color.surface.hover"), clear],
		"pressed": [c("color.surface.pressed"), clear],
		"disabled": [clear, clear],
	}, [c("color.text.muted"), primary_fg, c("color.text.disabled")], 6, 6)

	# Toggle-style list entries: Pokémon slots, team rows. "pressed" = selected.
	_variation("SlotButton", "Button")
	_button("SlotButton", {
		"normal": [c("color.surface.raised"), c("color.border.default")],
		"hover": [c("color.surface.hover"), c("color.border.strong")],
		"pressed": [c("color.surface.selected"), c("color.accent.default")],
		"disabled": disabled,
	}, secondary_colors, sm, sm)

	for type in ["CheckBox", "CheckButton"]:
		var flat := _box(clear, clear, 0, t.px("radius.md"), 4, 4)
		for state in ["normal", "pressed", "disabled", "hover_pressed"]:
			theme.set_stylebox(state, type, flat)
		theme.set_stylebox("hover", type, _box(c("color.surface.hover"), clear, 0, t.px("radius.md"), 4, 4))
		theme.set_stylebox("focus", type, _focus(t.px("radius.md")))
		for item in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			theme.set_color(item, type, primary_fg)
		theme.set_color("font_disabled_color", type, c("color.text.disabled"))


# --- Inputs, tabs, popups -------------------------------------------------------------

func _build_inputs() -> void:
	var md := t.px("radius.md")
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, _box(c("color.surface.sunken"), c("color.border.control"), _bw, md, t.px("space.sm"), 6))
		theme.set_stylebox("focus", type, _focus(md))
		theme.set_stylebox("read_only", type, _box(c("color.surface.panel"), c("color.border.subtle"), _bw, md, t.px("space.sm"), 6))
		theme.set_color("font_color", type, c("color.text.primary"))
		theme.set_color("font_placeholder_color", type, c("color.text.muted"))
		theme.set_color("font_uneditable_color", type, c("color.text.disabled"))
		theme.set_color("font_readonly_color", type, c("color.text.disabled"))
		theme.set_color("caret_color", type, c("color.text.primary"))
		theme.set_color("selection_color", type, c("color.accent.subtle"))
		theme.set_color("font_selected_color", type, c("color.text.primary"))
		theme.set_font("font", type, _fonts["ui"])
		theme.set_font_size("font_size", type, t.px("font.size.md"))
	theme.set_color("clear_button_color", "LineEdit", c("color.text.muted"))
	theme.set_color("clear_button_color_pressed", "LineEdit", c("color.text.primary"))

	theme.set_stylebox("slider", "HSlider", _box(c("color.hp.track"), Color.TRANSPARENT, 0, t.px("radius.full"), 0, 2))
	theme.set_stylebox("grabber_area", "HSlider", _box(c("color.accent.default"), Color.TRANSPARENT, 0, t.px("radius.full"), 0, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(c("color.accent.hover"), Color.TRANSPARENT, 0, t.px("radius.full"), 0, 2))
	theme.set_stylebox("focus", "HSlider", _focus(t.px("radius.md")))


func _build_tabs() -> void:
	var pad := t.px("space.md")
	var selected := _box(Color.TRANSPARENT, c("color.accent.default"), 0, 0, pad, pad)
	selected.border_width_bottom = 2
	var plain := _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, pad, pad)
	plain.border_width_bottom = 2
	var hovered := _box(c("color.surface.hover"), Color.TRANSPARENT, 0, 0, pad, pad)
	hovered.border_width_bottom = 2
	for type in ["TabBar", "TabContainer"]:
		theme.set_stylebox("tab_selected", type, selected)
		theme.set_stylebox("tab_unselected", type, plain)
		theme.set_stylebox("tab_hovered", type, hovered)
		theme.set_stylebox("tab_disabled", type, plain)
		theme.set_stylebox("tab_focus", type, _focus(0))
		theme.set_color("font_selected_color", type, c("color.text.primary"))
		theme.set_color("font_hovered_color", type, c("color.text.primary"))
		theme.set_color("font_unselected_color", type, c("color.text.secondary"))
		theme.set_color("font_disabled_color", type, c("color.text.disabled"))
		theme.set_font("font", type, _fonts["ui_semi"])
		theme.set_font_size("font_size", type, t.px("font.size.md"))
	theme.set_stylebox("panel", "TabContainer", _box(c("color.surface.panel"), c("color.border.default"), _bw, t.px("radius.lg"), t.px("space.md"), t.px("space.md")))
	theme.set_stylebox("tabbar_background", "TabContainer", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0, 0))


func _build_popups() -> void:
	var overlay := _shadow(_box(c("color.surface.overlay"), c("color.border.default"), _bw, t.px("radius.lg"), t.px("space.xs"), t.px("space.xs")), "md")
	theme.set_stylebox("panel", "PopupMenu", overlay)
	theme.set_stylebox("panel", "PopupPanel", overlay)
	theme.set_stylebox("hover", "PopupMenu", _box(c("color.surface.hover"), Color.TRANSPARENT, 0, t.px("radius.sm"), t.px("space.sm"), 4))
	var separator := StyleBoxLine.new()
	separator.color = c("color.border.subtle")
	theme.set_stylebox("separator", "PopupMenu", separator)
	theme.set_color("font_color", "PopupMenu", c("color.text.primary"))
	theme.set_color("font_hover_color", "PopupMenu", c("color.text.primary"))
	theme.set_color("font_disabled_color", "PopupMenu", c("color.text.disabled"))
	theme.set_color("font_separator_color", "PopupMenu", c("color.text.muted"))
	theme.set_font("font", "PopupMenu", _fonts["ui"])
	theme.set_font_size("font_size", "PopupMenu", t.px("font.size.md"))

	var pad := t.px("space.md")
	theme.set_stylebox("panel", "TooltipPanel", _shadow(_box(c("color.surface.overlay"), c("color.border.default"), _bw, t.px("radius.lg"), pad, t.px("space.sm")), "md"))
	theme.set_color("font_color", "TooltipLabel", c("color.text.primary"))
	theme.set_font("font", "TooltipLabel", _fonts["ui"])
	theme.set_font_size("font_size", "TooltipLabel", t.px("font.size.sm"))


func _build_scrolling() -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var track := _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 4, 4)
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track)
		theme.set_stylebox("grabber", type, _box(c("color.border.strong"), Color.TRANSPARENT, 0, 4, 4, 4))
		theme.set_stylebox("grabber_highlight", type, _box(c("color.text.muted"), Color.TRANSPARENT, 0, 4, 4, 4))
		theme.set_stylebox("grabber_pressed", type, _box(c("color.text.secondary"), Color.TRANSPARENT, 0, 4, 4, 4))
	theme.set_stylebox("panel", "ItemList", _box(c("color.surface.sunken"), c("color.border.subtle"), _bw, t.px("radius.md"), 4, 4))
	theme.set_stylebox("hovered", "ItemList", _box(c("color.surface.hover"), Color.TRANSPARENT, 0, t.px("radius.sm"), 4, 4))
	theme.set_stylebox("selected", "ItemList", _box(c("color.surface.selected"), Color.TRANSPARENT, 0, t.px("radius.sm"), 4, 4))
	theme.set_stylebox("selected_focus", "ItemList", _box(c("color.surface.selected"), c("color.focus.ring"), 1, t.px("radius.sm"), 4, 4))
	theme.set_color("font_color", "ItemList", c("color.text.primary"))
	theme.set_color("font_selected_color", "ItemList", c("color.text.primary"))
	theme.set_color("font_hovered_color", "ItemList", c("color.text.primary"))


# --- Battle components ----------------------------------------------------------------

func _build_battle() -> void:
	# HP bar (src/ui/components/hp_bar.gd) reads these.
	theme.set_color("high", "HPBar", c("color.hp.high"))
	theme.set_color("mid", "HPBar", c("color.hp.mid"))
	theme.set_color("low", "HPBar", c("color.hp.low"))
	theme.set_color("track", "HPBar", c("color.hp.track"))
	theme.set_color("outline", "HPBar", c("color.hp.outline"))
	theme.set_constant("height", "HPBar", 8)
	theme.set_constant("outline_width", "HPBar", _bw if c("color.hp.outline").a > 0.0 else 0)

	# Move buttons: surface.raised tinted by the move's type (design: mix.type.tint).
	var tint := t.num("mix.type.tint")
	var sm := t.px("space.sm")
	for type_id: String in [""] + ThemeTokens.TYPES:
		var variation := "MoveButton" + ("_" + type_id if not type_id.is_empty() else "")
		var type_color := c("color.type.%s.bg" % type_id) if not type_id.is_empty() else c("color.surface.raised")
		_variation(variation, "Button")
		_button(variation, {
			"normal": [c("color.surface.raised").lerp(type_color, tint), c("color.border.default")],
			"hover": [c("color.surface.hover").lerp(type_color, tint), c("color.border.strong")],
			"pressed": [c("color.surface.selected").lerp(type_color, tint), c("color.accent.default")],
			"disabled": [c("color.surface.panel"), c("color.border.subtle")],
		}, [c("color.text.primary"), c("color.text.primary"), c("color.text.disabled")], sm, sm)

	_variation("MoveNameLabel", "Label")
	_label_style("MoveNameLabel", c("color.text.primary"), "ui_semi", "font.size.md")
	_variation("MoveNameLabelDisabled", "Label")
	_label_style("MoveNameLabelDisabled", c("color.text.disabled"), "ui_semi", "font.size.md")
	_variation("MoveMetaLabel", "Label")
	_label_style("MoveMetaLabel", c("color.text.secondary"), "mono_semi", "font.size.sm")
