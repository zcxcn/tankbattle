extends Node3D
const Monster = preload("res://actors/giant_monster.gd")
var player: Node3D
var running := true
var killed := 0
var credits := 0
var base_damage := 0.0
var passed := 0
var failed := 0
func is_combat_running() -> bool:
	return running
func get_monster_goal(_monster: Node3D) -> Vector3:
	return Vector3(0, 0, 100)
func monster_reached_base(_monster: Node3D, damage: float) -> void:
	base_damage += damage
func monster_killed(_monster: Node3D, reward: int) -> void:
	killed += 1
	credits += reward
func _ready() -> void:
	call_deferred("run")
func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)
func spawn(role: String) -> CharacterBody3D:
	var actor := Monster.new()
	actor.game = self
	actor.director = self
	actor.archetype = role
	add_child(actor)
	actor.set_physics_process(false)
	return actor
func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	var actor := spawn("shambler")
	check(actor.height == 14.0 and actor.max_hp == 170.0 and actor.get_meta("height") == 14.0, "ordinary giant grows to fourteen metres without inflated first-wave health")
	check(actor._skeleton != null and actor._skeleton.get_bone_count() >= 60, "downloaded horror mesh retains its authored deform skeleton")
	check(actor._skin.mesh.get_surface_count() == 1, "each monster uses one skinned mesh draw surface")
	var skin := actor._skin.get_active_material(0) as StandardMaterial3D
	check(skin.albedo_texture != null and skin.normal_texture != null and skin.roughness >= 0.7, "source color and tangent normals retain physical rough skin response")
	check(skin.albedo_texture.get_width() == 2048 and skin.metallic == 0.0, "skin retains 2K detail and nonmetallic material response")
	check(not actor._walk_name.is_empty(), "source walk animation imports with a usable name")
	var bone: int = actor._skeleton.find_bone("joint6")
	var before: Quaternion = actor._skeleton.get_bone_pose_rotation(bone)
	actor._tick_walk(0.8)
	var after: Quaternion = actor._skeleton.get_bone_pose_rotation(bone)
	check(not before.is_equal_approx(after), "walk cycle actually moves the leg skeleton")
	check(actor.receive_damage(20, 1) == 0.0 and actor.receive_damage(-20, 0) == 0.0 and actor.receive_damage(NAN, 0) == 0.0, "friendly, negative and non-finite damage cannot alter monster health")
	var previous_hp: float = actor.hp
	check(is_equal_approx(actor.receive_damage(10, 0, Vector3(0, actor.height * 0.9, 0), "cannon"), 16.5), "direct fire to the upper head rewards accurate aiming")
	check(is_equal_approx(actor.receive_damage(10, 0, Vector3(0, actor.height * 0.9, 0), "blast"), 10.0), "explosion position cannot manufacture a headshot multiplier")
	check(is_equal_approx(previous_hp - actor.hp, 26.5), "damage values are consumed exactly once")
	actor.attack_remaining = 0.8
	actor.apply_emp(3.0)
	check(actor.stunned == 3.0 and actor.attack_remaining == 0.0 and actor.attack_cooldown >= 1.2, "EMP interrupts a committed attack and gives a real stun window")
	running = false
	var pose: Transform3D = actor._visual.transform
	actor._physics_process(1.0)
	check(actor.stunned == 3.0 and actor._visual.transform == pose and actor.receive_damage(10, 0) == 0.0, "paused simulation freezes movement, animation, stun timer and damage")
	running = true
	actor.receive_damage(10000, 0)
	check(killed == 1 and credits == 30 and actor.destroyed and not actor.alive, "kill registers one reward and a permanent dead state")
	actor.receive_damage(10000, 0)
	actor._die()
	check(killed == 1 and credits == 30, "subsequent projectiles cannot duplicate kill rewards")
	check(actor.collision_layer == 0 and not actor.is_targetable() and actor.is_in_group("monster_corpses"), "corpse stops blocking ammunition and joins the capped corpse pool")
	check(actor._visual.visible and is_instance_valid(actor._skin), "death preserves the actual textured body instead of deleting it")
	actor._tick_corpse(1.3)
	check(actor._visual.rotation.x < -0.01 and actor._visual.rotation.x > -1.48, "body visibly falls through an intermediate pose")
	running = false
	var age: float = actor.corpse_age
	actor._physics_process(4.0)
	check(actor.corpse_age == age, "pause freezes the falling body and corpse lifetime")
	running = true
	actor._tick_corpse(1.5)
	check(actor._visual.rotation.x < -1.4 and actor._death_impact, "fullbody fall ends with ground impact after a readable delay")
	actor._tick_corpse(23.8)
	check(actor._skin.transparency > 0.0 and actor._skin.transparency < 1.0, "old corpses fade before recycling")
	actor._tick_corpse(2.0)
	check(actor.is_queued_for_deletion(), "corpse lifetime is bounded even without director reclamation")
	var brute := spawn("brute")
	var titan := spawn("colossus")
	check(brute.height == 24.0 and titan.height == 42.0 and titan.archetype == "titan", "brute and titan grow to 24m and 42m and support colossus alias")
	check(brute.max_hp > 170.0 and titan.max_hp > brute.max_hp and titan.move_speed < actor.move_speed, "elite pressure comes from scale and resilience while movement stays slow")
	check(brute._skin.get_active_material(0) != titan._skin.get_active_material(0), "elite variants have distinct skin color materials")
	var another_brute := spawn("brute")
	check(brute._skin.get_active_material(0) == another_brute._skin.get_active_material(0), "same archetype instances share immutable PBR resources")
	for kind in ["forest", "reaver", "kaiju"]:
		var beast := spawn(kind)
		check(beast._skin.mesh != actor._skin.mesh, "%s uses a distinct downloaded mesh from the zombie" % kind)
		check(beast._skeleton != null and not beast._walk_name.is_empty(), "%s has a functioning skinned walk" % kind)
		var skeleton_before: Array[Quaternion] = []
		for index in beast._skeleton.get_bone_count():
			skeleton_before.append(beast._skeleton.get_bone_pose_rotation(index))
		beast._tick_walk(0.8)
		var moved := false
		for index in beast._skeleton.get_bone_count():
			moved = moved or not skeleton_before[index].is_equal_approx(beast._skeleton.get_bone_pose_rotation(index))
		check(moved, "%s walk changes actual deform bones" % kind)
	print("GIANT MONSTER TEST: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
