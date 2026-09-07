class_name IronBackdrop
extends Control
## Lightweight procedural menu background used when no authored key art is available.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	# Keep the command deck readable while allowing the live 3D hangar and title
	# tank to remain visible through the right half of the interface.
	draw_polygon(
		PackedVector2Array([
			Vector2.ZERO,
			Vector2(size.x, 0.0),
			Vector2(size.x, size.y),
			Vector2(0.0, size.y),
		]),
		PackedColorArray([
			Color(0.025, 0.045, 0.033, 0.97),
			Color(0.018, 0.027, 0.022, 0.31),
			Color(0.018, 0.027, 0.022, 0.48),
			Color(0.025, 0.045, 0.033, 0.97),
		])
	)
	var glow_center := Vector2(size.x * 0.72, size.y * 0.33)
	for ring in range(10, 0, -1):
		var radius := minf(size.x, size.y) * (0.08 + ring * 0.045)
		var alpha := 0.006 + float(10 - ring) * 0.002
		draw_circle(glow_center, radius, Color(0.35, 0.42, 0.23, alpha))
	var grid_step := clampf(size.y / 13.0, 54.0, 92.0)
	var grid_color := Color(0.43, 0.52, 0.39, 0.055)
	var x := fmod(size.x * 0.5, grid_step)
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid_color, 1.0)
		x += grid_step
	var y := fmod(size.y * 0.5, grid_step)
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_color, 1.0)
		y += grid_step
	for index in range(7):
		var scan_y := size.y * (0.12 + index * 0.13)
		draw_line(Vector2(0.0, scan_y), Vector2(size.x, scan_y), Color(1.0, 1.0, 1.0, 0.012), 1.0)
	var accent := PackedVector2Array([
		Vector2(size.x * 0.58, size.y),
		Vector2(size.x, size.y * 0.60),
		Vector2(size.x, size.y),
	])
	draw_colored_polygon(accent, Color(0.45, 0.20, 0.08, 0.065))
	draw_line(Vector2(size.x * 0.58, size.y), Vector2(size.x, size.y * 0.60), Color(0.93, 0.50, 0.24, 0.28), 2.0)
