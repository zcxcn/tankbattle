extends RefCounted
## Let the real audio mixer retire its playback objects before test exit.

static func finish(tree: SceneTree, exit_code := 0) -> void:
	# Some pure logic runners execute before autoload _ready; wait one frame.
	await tree.process_frame
	tree.paused = true
	var audio_service := tree.root.get_node_or_null("AudioService")
	if audio_service != null:
		audio_service.shutdown()
	# --fixed-fps advances timers faster than wall time. Audio mixing runs on a
	# real-time thread, so wait for actual elapsed time even in fast simulations.
	var deadline := Time.get_ticks_msec() + 240
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
	tree.quit(exit_code)
