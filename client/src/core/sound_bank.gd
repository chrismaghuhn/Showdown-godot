extends Node
## Autoload "Sounds": notification sounds from sound packs, with per-event overrides.
##
## Packs: res://assets/sounds/<id>/sdsounds.json (built in) and user://sounds/<id>/sdsounds.json
##   {"format": 1, "name": "...", "author": "...", "sounds": {"your_turn": "file.wav", ...}}
## Per event (settings section "sounds"): "<event>" = "pack" (default) | "none" | "custom:<file>"
## Custom files are copied to user://sounds/custom/ so they keep working if the original moves.
## Only .wav, .ogg and .mp3 up to MAX_BYTES and MAX_SECONDS are accepted.
## Output device (settings "sounds/output_device"): "Default" follows the system; a saved device
## that is no longer connected falls back to the system default.

const BUILTIN_DIR := "res://assets/sounds"
const USER_DIR := "user://sounds"
const CUSTOM_DIR := "user://sounds/custom"
const DEFAULT_PACK := "default"
const EXTENSIONS := ["wav", "ogg", "mp3"]
const MAX_BYTES := 2 * 1024 * 1024
const MAX_SECONDS := 5.0
const SYSTEM_DEFAULT := "Default"

## pack id -> {"name", "author", "dir", "sounds": {event: file}, "builtin": bool}
var packs := {}
var _streams := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	for i in 3:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	discover()
	_apply_output_device()


func discover() -> void:
	packs.clear()
	_streams.clear()
	for dir_and_flag: Array in [[BUILTIN_DIR, true], [USER_DIR, false]]:
		var base: String = dir_and_flag[0]
		for sub in DirAccess.get_directories_at(base):
			var manifest := base.path_join(sub).path_join("sdsounds.json")
			if sub == "custom" or not FileAccess.file_exists(manifest):
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
			if not (data is Dictionary and int(data.get("format", 0)) == 1 and data.get("sounds") is Dictionary):
				push_warning("Sound pack %s ignored: invalid sdsounds.json" % sub)
				continue
			if packs.has(sub) and packs[sub]["builtin"]:
				continue
			packs[sub] = {"name": str(data.get("name", sub)).left(64), "author": str(data.get("author", "")).left(96),
				"dir": base.path_join(sub), "sounds": data["sounds"], "builtin": dir_and_flag[1]}


# --- Output device --------------------------------------------------------------------------

func output_devices() -> PackedStringArray:
	return AudioServer.get_output_device_list()


## The saved device ("Default" = system default), even if it is not connected right now.
func get_output_device() -> String:
	return str(AppConfig.get_setting("sounds", "output_device", SYSTEM_DEFAULT))


func set_output_device(device: String) -> void:
	AppConfig.set_setting("sounds", "output_device", device)
	_apply_output_device()


func _apply_output_device() -> void:
	AudioServer.output_device = resolve_device(get_output_device(), output_devices())


## The device to use: the saved one if it is available, otherwise the system default.
static func resolve_device(saved: String, available: PackedStringArray) -> String:
	return saved if saved in available else SYSTEM_DEFAULT


## Readable name for a device. PulseAudio/PipeWire report sink ids like
## "alsa_output.usb-HP__Inc_HyperX_Cloud_III_000000000000-00.analog-stereo"; other platforms
## already report readable names, which are returned unchanged.
static func device_label(device: String) -> String:
	if device == SYSTEM_DEFAULT:
		return TranslationServer.translate("System default")
	if not device.begins_with("alsa_output.") and not device.begins_with("bluez_output."):
		return device
	var kind := ""
	if device.contains(".hdmi"):
		kind = "HDMI"
	var core := device.get_slice(".", 1)
	for prefix in ["usb-", "pci-", "platform-"]:
		core = core.trim_prefix(prefix)
	var words := PackedStringArray()
	for word in core.replace("-", "_").split("_", false):
		# Drop serial numbers and bus ids ("0000KT5a170000389", "000000000000", "00", "06").
		var digits := 0
		for c in word:
			if c >= "0" and c <= "9":
				digits += 1
		if word.is_valid_int() or (word.length() >= 10 and digits * 2 >= word.length()):
			continue
		if words.is_empty() or words[words.size() - 1] != word:
			words.append(word)
	var label := " ".join(words).strip_edges()
	if device.begins_with("alsa_output.pci-") and kind.is_empty() and label.is_empty():
		label = TranslationServer.translate("Built-in audio")
	if kind == "HDMI":
		return "HDMI" if label.is_empty() or device.begins_with("alsa_output.pci-") else label + " (HDMI)"
	return label if not label.is_empty() else device


func current_pack() -> String:
	var pack := str(AppConfig.get_setting("sounds", "pack", DEFAULT_PACK))
	return pack if packs.has(pack) else DEFAULT_PACK


func set_pack(pack_id: String) -> void:
	AppConfig.set_setting("sounds", "pack", pack_id)
	_streams.clear()


## "pack", "none" or "custom:<file>"
func get_choice(event: String) -> String:
	return str(AppConfig.get_setting("sounds", event, "pack"))


func set_choice(event: String, choice: String) -> void:
	AppConfig.set_setting("sounds", event, choice)
	_streams.erase(event)


## Validates and copies a user's audio file for an event. Returns "" or an error message.
func import_custom(event: String, source_path: String) -> String:
	var ext := source_path.get_extension().to_lower()
	if not ext in EXTENSIONS:
		return tr("Use a .wav, .ogg or .mp3 file.")
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		return tr("The file could not be read.")
	if bytes.size() > MAX_BYTES:
		return tr("The file is larger than 2 MB.")
	var stream := _stream_from_bytes(bytes, ext)
	if stream == null:
		return tr("The file is not a valid %s sound.") % ext.to_upper()
	if stream.get_length() > MAX_SECONDS:
		return tr("The sound is longer than %d seconds.") % int(MAX_SECONDS)
	var file_name := "%s.%s" % [event, ext]
	var target := FileAccess.open(CUSTOM_DIR.path_join(file_name), FileAccess.WRITE)
	if target == null:
		return tr("The sound could not be saved.")
	target.store_buffer(bytes)
	target.close()
	set_choice(event, "custom:" + file_name)
	return ""


func stream_for(event: String) -> AudioStream:
	if _streams.has(event):
		return _streams[event]
	var stream: AudioStream = null
	var choice := get_choice(event)
	if choice.begins_with("custom:"):
		var path := CUSTOM_DIR.path_join(choice.substr(7).get_file())
		stream = _stream_from_bytes(FileAccess.get_file_as_bytes(path), path.get_extension().to_lower())
		if stream == null:
			push_warning("Custom sound for %s missing or invalid, using the pack sound" % event)
	if stream == null and choice != "none":
		stream = _pack_stream(current_pack(), event)
		if stream == null and current_pack() != DEFAULT_PACK:
			stream = _pack_stream(DEFAULT_PACK, event)
	_streams[event] = stream
	return stream


## Plays an event's sound at the notification volume (0..1). Returns false if there is none.
func play(event: String, volume: float) -> bool:
	var stream := stream_for(event)
	if stream == null or volume <= 0.0:
		return false
	var player := _players[0]
	for candidate in _players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = stream
	player.volume_db = linear_to_db(clampf(volume, 0.0, 1.0))
	player.play()
	return true


func _pack_stream(pack_id: String, event: String) -> AudioStream:
	var pack: Dictionary = packs.get(pack_id, {})
	var file := str(pack.get("sounds", {}).get(event, "")).get_file()
	if file.is_empty() or not file.get_extension().to_lower() in EXTENSIONS:
		return null
	var path: String = pack["dir"].path_join(file)
	if pack["builtin"]:
		return load(path) if ResourceLoader.exists(path) else null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_BYTES:
		return null
	return _stream_from_bytes(bytes, file.get_extension().to_lower())


static func _stream_from_bytes(bytes: PackedByteArray, ext: String) -> AudioStream:
	if not looks_like(bytes, ext):
		return null
	match ext:
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
	return null


## Checks the file signature first, so obviously wrong files are rejected quietly instead of
## making the engine log decoder errors.
static func looks_like(bytes: PackedByteArray, ext: String) -> bool:
	if bytes.size() < 12:
		return false
	match ext:
		"wav":
			return bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE"
		"ogg":
			return bytes.slice(0, 4).get_string_from_ascii() == "OggS"
		"mp3":
			return bytes.slice(0, 3).get_string_from_ascii() == "ID3" or (bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0)
	return false
