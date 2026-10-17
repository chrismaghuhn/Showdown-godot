class_name FormatList
extends RefCounted
## Parses the server's |formats| message into a list of formats.
##
##   |formats|,LL|,1|S/V Singles|[Gen 9] Random Battle,f|[Gen 9] OU,e|,2|...
##
## ",<n>" starts a section (the next entry is its name), ",LL" announces features. Each format
## is "Name,<hex flags>": 1 = the server provides the team (Random Battles), 2 = shown in
## ladder search, 4 = can be challenged, 8 = tournaments, 16 = level 50 teambuilder.


## [{id, name, section, preset_team, search, challenge, tournament}]
static func parse(text: String) -> Array[Dictionary]:
	var formats: Array[Dictionary] = []
	var entries := text.split("|")
	var section := ""
	var next_is_section := false
	for entry in entries:
		if next_is_section:
			section = entry
			next_is_section = false
		elif entry.begins_with(",") and (entry.length() == 1 or entry.substr(1).is_valid_int()):
			next_is_section = true
		elif entry.is_empty() or entry.begins_with(","):
			continue
		else:
			var name := entry
			var flags := -1
			var comma := entry.rfind(",")
			if comma != -1 and entry.substr(comma + 1).is_valid_hex_number():
				name = entry.substr(0, comma)
				flags = entry.substr(comma + 1).hex_to_int()
			if flags < 0:
				# Old servers: no flags, everything searchable and challengeable.
				flags = 2 | 4 | 8
			formats.append({
				"id": PSParser.to_id(name), "name": name, "section": section,
				"preset_team": flags & 1 != 0, "search": flags & 2 != 0,
				"challenge": flags & 4 != 0, "tournament": flags & 8 != 0,
			})
	return formats


## The formats a player can search without a team (v0.1: no teambuilder yet).
static func quick_battle_formats(formats: Array[Dictionary]) -> Array[Dictionary]:
	return formats.filter(func(f: Dictionary) -> bool: return f["search"] and f["preset_team"])


## "[Gen 9] Random Battle" for "gen9randombattle", or "" if unknown.
static func display_name(formats: Array[Dictionary], format_id: String) -> String:
	for f in formats:
		if f["id"] == format_id:
			return f["name"]
	return ""
