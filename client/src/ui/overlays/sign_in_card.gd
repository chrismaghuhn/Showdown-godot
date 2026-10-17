class_name SignInCard
extends StateCard
## "Choose a name" (design: frame 02). A registered name asks for its password in a second
## step. The password goes straight to Connection.login() and the field is cleared right
## after - nothing keeps it. "Stay signed in" keeps the name and the login server's session
## cookie, never the password.

signal submitted(name: String, password: String, stay_signed_in: bool)
## "Not now" on the name step.
signal dismissed
## "Use another name" on the password step.
signal other_name

const MAX_NAME_LENGTH := 18

var _name := LineEdit.new()
var _password := LineEdit.new()
var _password_field: Control
var _note := HBoxContainer.new()
var _stay := CheckBox.new()
var _error_slot := VBoxContainer.new()
var _submit := Button.new()
var _secondary := Button.new()
var _password_step := false
var _busy := false


func _init() -> void:
	super()
	add_title(tr("Choose a name"))
	_name.max_length = MAX_NAME_LENGTH
	_name.placeholder_text = tr("Your Showdown name")
	_name.text_changed.connect(func(_t: String) -> void: _update_buttons())
	_name.text_submitted.connect(func(_t: String) -> void: _submit_form())
	add_field(tr("Name"), _name)

	_note.add_theme_constant_override("separation", 8)
	var info := IconView.new("ui-info", "color.text.secondary")
	info.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_note.add_child(info)
	var note_text := Label.new()
	note_text.text = tr("This name is registered. Enter its password to continue.")
	note_text.theme_type_variation = &"SmallSecondaryLabel"
	note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.add_child(note_text)
	rows.add_child(_note)

	_password.secret = true
	_password.placeholder_text = tr("Password")
	_password.text_changed.connect(func(_t: String) -> void: _update_buttons())
	_password.text_submitted.connect(func(_t: String) -> void: _submit_form())
	_password_field = add_field(tr("Password"), _password)

	_stay.text = tr("Stay signed in")
	_stay.tooltip_text = tr("Keeps your name and the login session on this computer. Your password is never saved.")
	rows.add_child(_stay)
	rows.add_child(_error_slot)

	var buttons := add_row()
	_submit.theme_type_variation = &"PrimaryButton"
	_submit.pressed.connect(_submit_form)
	buttons.add_child(_submit)
	_secondary.theme_type_variation = &"GhostButton"
	_secondary.pressed.connect(func() -> void:
		if _password_step:
			other_name.emit()
		else:
			dismissed.emit())
	buttons.add_child(_secondary)
	setup("", "", "", false, false)


## name: prefilled name; password_for: the registered name that needs a password ("" = name
## step); error: shown inline; busy: a sign-in is running.
func setup(name: String, password_for: String, error: String, stay: bool, busy: bool) -> void:
	if _name.text.is_empty() or not password_for.is_empty():
		_name.text = password_for if not password_for.is_empty() else name
	_password_step = not password_for.is_empty()
	_stay.button_pressed = stay
	_note.visible = _password_step
	_password_field.visible = _password_step
	_secondary.text = tr("Use another name") if _password_step else tr("Not now")
	for child in _error_slot.get_children():
		child.queue_free()
	if not error.is_empty():
		_error_slot.add_child(ErrorBox.inline(error, PackedStringArray()))
	_error_slot.visible = not error.is_empty()
	set_busy(busy)


func set_busy(busy: bool) -> void:
	_busy = busy
	_submit.text = tr("Signing in…") if busy else tr("Sign in")
	_name.editable = not busy
	_password.editable = not busy
	_update_buttons()


func clear_name() -> void:
	_name.clear()
	_update_buttons()


## Puts the cursor where the user types next.
func focus_first() -> void:
	if _password_step:
		_password.grab_focus()
	else:
		_name.grab_focus()
		_name.caret_column = _name.text.length()


func _update_buttons() -> void:
	var ready := not _name.text.strip_edges().is_empty() and (not _password_step or not _password.text.is_empty())
	_submit.disabled = _busy or not ready


func _submit_form() -> void:
	if _submit.disabled:
		return
	var password := _password.text if _password_step else ""
	_password.clear()
	submitted.emit(_name.text.strip_edges(), password, _stay.button_pressed)


## Fills the fields for screenshots (dev automation): `password` only fills the secret field.
func fill_for_preview(name: String, password: String) -> void:
	_name.text = name
	_password.text = password
	_update_buttons()
