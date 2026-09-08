extends SceneTree
## Checks HUD telemetry against the real scene, including terrain obstruction.

var passed := 0
var failed := 0
var menu_events := 0
var start_events := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)

func _run() -> void:
	await process_frame
	var telemetry = load("res://scripts/battle_telemetry.gd")
	var game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.start_game()
	game.set_process(false)
	for tank in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	await physics_frame
	await process_frame
	var data: Dictionary = telemetry.collect(game)
	check(data["tactical_visible"], "live combat enables tactical telemetry")
	check(data["radar_contacts"].size() == 7, "radar includes six opponents and the locked boss, excluding the player")
	var locked_boss := false
	for contact: Dictionary in data["radar_contacts"]:
		locked_boss = locked_boss or (contact["boss"] and not contact["active"])
	check(locked_boss, "locked boss stays discoverable before activation")
	game.spawn_mine(game.player, Vector3(2, 0, 46))
	game.spawn_mine(game.enemies[0], Vector3(-2, 0, 46))
	data = telemetry.collect(game)
	var friendly := 0
	for mine: Dictionary in data["radar_mines"]:
		friendly += int(mine["friendly"])
	check(data["radar_mines"].size() == 2 and friendly == 1, "radar distinguishes friendly and hostile mines")
	game.emit_emp(game.player, 28.0)
	check(telemetry.collect(game)["radar_mines"].is_empty(), "defused mines disappear from radar immediately")
	game.player.aim_point = game.player.global_position + Vector3(0, 0, -24)
	game.player._update_turret(1.0)
	data = telemetry.collect(game)
	check(data["aim_visible"] and data["impact_visible"], "both requested aim and actual cannon endpoint project into the battle view")
	check(data["aim_screen"].distance_to(game.player.camera.unproject_position(game.player.aim_point)) < 0.01,
		"requested aim marker follows the world target under perspective")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0, 2, 38)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	data = telemetry.collect(game)
	check(data["aim_blocked"] and not data["aim_target"], "cannon reticle reports actual terrain obstruction before the requested target")
	check(data["aim_distance"] < 10.0, "obstruction range stops at the wall instead of continuing through it")
	var ui: Control = game.ui
	ui.update_snapshot(game.get_ui_snapshot())
	var overlay: Control = ui.get_node("BattleHUD/BattleOverlay")
	check(overlay.visible and overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tactical overlay remains passive during combat")
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var radar: Rect2 = overlay.map_rect()
		check(Rect2(Vector2.ZERO, overlay.size).encloses(radar.grow(12)), "radar stays inside %dx%d viewport" % [dimensions.x, dimensions.y])
		check(overlay.map_position(Vector2.ZERO).distance_to(radar.get_center()) < 0.01,
			"radar keeps world origin centered at %dx%d" % [dimensions.x, dimensions.y])
		var objective_rect := Rect2(float(dimensions.x) * 0.25, 20.0, float(dimensions.x) * 0.5, 64.0)
		var reserved_regions: Array[Rect2] = [objective_rect]
		overlay.set_hud_regions(reserved_regions)
		var label_position: Vector2 = overlay.marker_position(Vector2(float(dimensions.x) * 0.5, 40.0))
		var label_rect := Rect2(label_position - Vector2(30, 21), Vector2(77, 29))
		check(label_position != Vector2.INF and not objective_rect.grow(3).intersects(label_rect)
			and Rect2(Vector2.ZERO, overlay.size).encloses(label_rect),
			"enemy warning avoids the objective panel and viewport edges at %dx%d" % [dimensions.x, dimensions.y])
	check(overlay.map_position(Vector2(0, -50)).y < overlay.map_position(Vector2(0, 50)).y,
		"north-up radar agrees with forward movement and the fixed camera")
	game.pause_game()
	ui.update_snapshot(game.get_ui_snapshot())
	check(not overlay.visible, "pause hides the aiming overlay and radar")
	game.mode = "won"
	ui.update_snapshot(game.get_ui_snapshot())
	ui.menu_requested.connect(func(): menu_events += 1)
	ui.start_requested.connect(func(): start_events += 1)
	ui._result_primary_action()
	check(menu_events == 1 and start_events == 0, "victory primary action returns to menu instead of silently replaying the only chapter")
	game.free()
	await process_frame
	print("BATTLE_OVERLAY_RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
