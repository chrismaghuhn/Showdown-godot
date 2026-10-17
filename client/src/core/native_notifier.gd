class_name NativeNotifier
extends RefCounted
## Desktop (OS) notifications. Godot has no API for them, so this calls the platform tool:
##   Linux:   notify-send (libnotify)
##   macOS:   osascript "display notification"
##   Windows: a PowerShell toast script (written to user://)
## Texts come from the server (user names, formats), so they are only ever passed as separate
## arguments — never pasted into a shell command or script source.

const APP_NAME := "Showdown Desktop"


## Returns true if a notification was handed to the OS.
static func post(title: String, body: String) -> bool:
	title = _clean(title, 120)
	body = _clean(body, 400)
	match OS.get_name():
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return _run("notify-send", ["--app-name=" + APP_NAME, "--", title, body])
		"macOS":
			# argv items are passed as data, not as AppleScript source.
			return _run("osascript", ["-e", "on run argv", "-e",
				"display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run", title, body])
		"Windows":
			var script := _windows_script()
			return not script.is_empty() and _run("powershell.exe", ["-NoProfile", "-NonInteractive",
				"-ExecutionPolicy", "Bypass", "-File", script, "-Title", title, "-Body", body])
	return false


static func is_available() -> bool:
	match OS.get_name():
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return _has_command("notify-send")
		"macOS", "Windows":
			return true
	return false


static func _run(command: String, args: PackedStringArray) -> bool:
	return OS.create_process(command, args) > 0


static func _has_command(command: String) -> bool:
	var output := []
	return OS.execute("sh", ["-c", "command -v \"$0\"", command], output) == 0


## Control characters out, length limited (notifications are short).
static func _clean(text: String, max_length: int) -> String:
	var out := ""
	for c in text:
		out += c if c.unicode_at(0) >= 32 or c == "\n" else " "
	return out.strip_edges().left(max_length)


## PowerShell script that shows a toast; parameters arrive as plain strings (-File mode).
static func _windows_script() -> String:
	var path := OS.get_user_data_dir().path_join("notify.ps1")
	if not FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return ""
		file.store_string("""param([string]$Title, [string]$Body)
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
$template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
$texts = $xml.GetElementsByTagName('text')
$texts.Item(0).AppendChild($xml.CreateTextNode($Title)) > $null
$texts.Item(1).AppendChild($xml.CreateTextNode($Body)) > $null
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
""")
		file.close()
	return path
