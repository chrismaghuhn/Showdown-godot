class_name NewsFeed
extends Node
## Client release notes for the start screen's "News", from this project's GitHub releases.
## Cached for NEWS_MAX_AGE (the API allows 60 unauthenticated requests per hour), shown from the
## cache right away and offline; --no-data-fetch never asks the network.

signal loaded(items: Array[Dictionary])

const REPO_URL := "https://github.com/chrismaghuhn/Showdown-godot"
const RELEASES_API := "https://api.github.com/repos/chrismaghuhn/Showdown-godot/releases?per_page=5"
const NEWS_MAX_AGE := 6 * 3600
const SUMMARY_LENGTH := 120

var _cache := HttpCache.new()


func _ready() -> void:
	add_child(_cache)


func load_news() -> void:
	var cached := _cache.read_cached(RELEASES_API)
	if not cached.is_empty():
		loaded.emit(parse_releases(cached.get_string_from_utf8()))
	if AppConfig.has_cli("no-data-fetch"):
		return
	var bytes := await _cache.fetch(RELEASES_API, NEWS_MAX_AGE)
	if not bytes.is_empty():
		loaded.emit(parse_releases(bytes.get_string_from_utf8()))


## GitHub's releases JSON -> [{tag, title, date (unix), summary, url}], newest first, without
## drafts. The summary is the first line of the notes as plain text.
static func parse_releases(json: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var parser := JSON.new()
	if parser.parse(json) != OK or not parser.data is Array:
		return items
	for entry: Variant in parser.data:
		if not entry is Dictionary or entry.get("draft", false):
			continue
		var tag := str(entry.get("tag_name", ""))
		var url := str(entry.get("html_url", ""))
		items.append({
			"tag": tag,
			"title": str(entry.get("name", "")) if not str(entry.get("name", "")).is_empty() else tag,
			"date": int(Time.get_unix_time_from_datetime_string(str(entry.get("published_at", "")).trim_suffix("Z"))),
			"summary": summary(str(entry.get("body", ""))),
			# Only ever open pages of this repository.
			"url": url if url.begins_with(REPO_URL + "/") else REPO_URL + "/releases",
		})
	return items


## First meaningful line of Markdown release notes, without markup, shortened.
static func summary(markdown: String) -> String:
	for raw_line in markdown.split("\n"):
		var line := raw_line.strip_edges()
		line = line.lstrip("#").lstrip("-*> ").strip_edges()
		if line.is_empty() or line.begins_with("<!--"):
			continue
		for mark in ["**", "__", "`"]:
			line = line.replace(mark, "")
		# [text](link) -> text
		var link := RegEx.create_from_string("\\[([^\\]]*)\\]\\([^)]*\\)")
		line = link.sub(line, "$1", true)
		if line.length() > SUMMARY_LENGTH:
			line = line.left(SUMMARY_LENGTH - 1).strip_edges() + "…"
		return line
	return ""


## 1760572800 -> "Oct 16"
static func short_date(unix: int) -> String:
	if unix <= 0:
		return ""
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var date := Time.get_datetime_dict_from_unix_time(unix)
	return "%s %d" % [months[int(date["month"]) - 1], int(date["day"])]
