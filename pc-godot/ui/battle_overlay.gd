extends Control
## A single passive draw layer: aim intent, physical impact and a north-up map.

const WORLD_BOUNDS := Rect2(-95, -66, 190, 132)
const FRIENDLY := Color("72e1df")
const HOSTILE := Color("ef7665")
const AMBER := Color("e9bf70")
var snapshot: Dictionary = {}

func _init() -> void:
	name = "BattleOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func update_snapshot(value: Dictionary) -> void:
	snapshot = value
	visible = bool(value.get("tactical_visible", false)) and value.get("mode", "") == "playing"
	queue_redraw()

func map_rect() -> Rect2:
	var margin := clampf(size.x * (0.035 if size.x / maxf(size.y, 1.0) < 2.0 else 0.065), 24.0, 180.0)
	return Rect2(size.x - margin - 240.0, clampf(size.y * 0.032, 18.0, 58.0) + 154.0, 240.0, 167.0)

func map_position(world: Vector2) -> Vector2:
	var fraction := (world - WORLD_BOUNDS.position) / WORLD_BOUNDS.size
	fraction = fraction.clamp(Vector2.ZERO, Vector2.ONE)
	return map_rect().position + fraction * map_rect().size

func _draw() -> void:
	if not visible:
		return
	_draw_radar()
	var aim: Vector2 = snapshot.get("aim_screen", Vector2.ZERO)
	var impact: Vector2 = snapshot.get("impact_screen", Vector2.ZERO)
	var viewport := Rect2(Vector2(18, 18), size - Vector2(36, 36))
	if snapshot.get("aim_visible", false) and viewport.has_point(aim):
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var edge: Vector2 = aim + corner * 12.0
			draw_line(edge, edge - Vector2(corner.x * 5.0, 0), Color("e9eee9"), 1.5, true)
			draw_line(edge, edge - Vector2(0, corner.y * 5.0), Color("e9eee9"), 1.5, true)
	if not snapshot.get("impact_visible", false) or not viewport.has_point(impact):
		return
	var reload := maxf(0.0, float(snapshot.get("reload", 0.0)))
	var blocked: bool = snapshot.get("aim_blocked", false)
	var color := HOSTILE if blocked or snapshot.get("aim_target", false) else (AMBER if reload > 0.01 else FRIENDLY)
	draw_circle(impact, 5.0, Color("0a100dcc"))
	draw_arc(impact, 6.5, 0.0, TAU, 24, color, 1.8, true)
	draw_circle(impact, 1.5, color)
	if reload > 0.01:
		var fraction := clampf(reload / maxf(0.01, float(snapshot.get("fire_interval", 1.0))), 0.0, 1.0)
		draw_arc(impact, 10.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - fraction), 32, AMBER, 2.0, true)
	var caption := "受阻" if blocked else ("装填 %.1fs" % reload if reload > 0.01 else "%dm" % roundi(float(snapshot.get("aim_distance", 0.0))))
	_text(impact + Vector2(15, 5), caption, color, 14)

func _draw_radar() -> void:
	var rect := map_rect()
	draw_rect(Rect2(rect.position - Vector2(10, 30), rect.size + Vector2(20, 53)), Color("101812db"))
	draw_rect(rect, Color("566350"), false, 1.0)
	_text(rect.position + Vector2(0, -11), "战术雷达", AMBER, 14)
	_text(rect.position + Vector2(rect.size.x - 38, -11), "N ↑", FRIENDLY, 13)
	# Keep road orientation identical to WASD, left stick and the battle camera.
	var road := Color("58605466")
	draw_rect(Rect2(map_position(Vector2(-12, -66)), Vector2(rect.size.x * 24.0 / 190.0, rect.size.y)), road)
	for z in [-36.0, 0.0, 36.0]:
		var start := map_position(Vector2(-95, z - 9))
		draw_rect(Rect2(start, Vector2(rect.size.x, rect.size.y * 18.0 / 132.0)), road)
	for mine: Dictionary in snapshot.get("radar_mines", []):
		var color := FRIENDLY if mine.get("friendly", false) else HOSTILE
		var point := map_position(mine["position"])
		draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), color, false, 1.0)
	for contact: Dictionary in snapshot.get("radar_contacts", []):
		var point := map_position(contact["position"])
		if contact.get("boss", false):
			var diamond := PackedVector2Array([point + Vector2(0, -6), point + Vector2(6, 0), point + Vector2(0, 6), point + Vector2(-6, 0), point + Vector2(0, -6)])
			draw_polyline(diamond, AMBER, 2.0, true)
			if contact.get("active", false):
				draw_circle(point, 2.0, HOSTILE)
		else:
			draw_circle(point, 3.0, HOSTILE)
	var player := map_position(snapshot.get("radar_player", Vector2.ZERO))
	var yaw := float(snapshot.get("radar_heading", 0.0))
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([player + forward * 7.0, player - forward * 4.0 + right * 4.0, player - forward * 4.0 - right * 4.0]), FRIENDLY)
	_text(rect.end + Vector2(-rect.size.x, 16), "青：我方   红：敌军   ◇：首领", Color("a8b49c"), 11)

func _text(at: Vector2, value: String, color: Color, font_size: int) -> void:
	var font := get_theme_default_font()
	draw_string(font, at + Vector2.ONE, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("030605"))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
