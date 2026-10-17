class_name FieldConditions
extends RefCounted
## Display names and icons for weather, terrain, hazards and screens (design: Foundations ›
## "Field conditions · one icon per condition"). Pure.

## Protocol weather id -> [display name, icon]
const WEATHER := {
	"SunnyDay": ["Sun", "weather-sun"],
	"DesolateLand": ["Extremely harsh sun", "weather-sun"],
	"RainDance": ["Rain", "weather-rain"],
	"PrimordialSea": ["Heavy rain", "weather-rain"],
	"Sandstorm": ["Sandstorm", "weather-sandstorm"],
	"Snowscape": ["Snow", "weather-snow"],
	"Snow": ["Snow", "weather-snow"],
	"Hail": ["Hail", "weather-hail"],
	"DeltaStream": ["Strong winds", "weather-none"],
}

## Field or side condition name -> icon
const CONDITION_ICONS := {
	"Electric Terrain": "terrain-electric",
	"Grassy Terrain": "terrain-grassy",
	"Psychic Terrain": "terrain-psychic",
	"Misty Terrain": "terrain-misty",
	"Stealth Rock": "hazard-stealth-rock",
	"Spikes": "hazard-spikes",
	"Toxic Spikes": "hazard-toxic-spikes",
	"Sticky Web": "hazard-sticky-web",
	"Reflect": "screen-reflect",
	"Light Screen": "screen-light-screen",
	"Aurora Veil": "screen-aurora-veil",
}

## Effects that last a number of turns (shown with turns left) vs. layered hazards.
const TIMED := ["Reflect", "Light Screen", "Aurora Veil", "Tailwind", "Safeguard", "Mist",
	"Electric Terrain", "Grassy Terrain", "Psychic Terrain", "Misty Terrain", "Trick Room"]
const LAYERED := ["Spikes", "Toxic Spikes"]


static func weather_name(weather_id: String) -> String:
	return WEATHER[weather_id][0] if WEATHER.has(weather_id) else weather_id


static func weather_icon(weather_id: String) -> String:
	return WEATHER[weather_id][1] if WEATHER.has(weather_id) else "weather-none"


static func icon(condition: String) -> String:
	return CONDITION_ICONS.get(condition, "")


static func is_terrain(condition: String) -> bool:
	return condition.ends_with(" Terrain")
