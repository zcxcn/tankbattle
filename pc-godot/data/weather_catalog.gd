extends RefCounted
## A deployment resolves random weather once; menu redraws never reroll it.

const KINDS := ["dry", "light_rain", "heavy_rain", "snow", "fog"]
const LABELS := ["晴天", "小雨", "大雨", "雪天", "雾天"]
const MODE_COUNT := 6

static func resolve(mode: int, seed_value: int) -> String:
	if mode > 0 and mode < MODE_COUNT:
		return KINDS[mode - 1]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return KINDS[rng.randi_range(0, KINDS.size() - 1)]

static func weather_label(kind: String) -> String:
	var index := KINDS.find(kind)
	return LABELS[index] if index >= 0 else LABELS[0]

static func mode_label(mode: int, current: String) -> String:
	return "随机 · 当前%s" % weather_label(current) if mode == 0 else weather_label(KINDS[clampi(mode - 1, 0, KINDS.size() - 1)])

static func wetness(kind: String) -> float:
	match kind:
		"heavy_rain": return 1.0
		"light_rain": return 0.55
		"snow": return 0.2
	return 0.0
