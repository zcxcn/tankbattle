class_name GiantMonster
extends CharacterBody3D
## Authored skinned horror creature, enlarged to city-block scale.
## The director owns rewards, the defendable objective and population limits.

const CREATURE := preload("res://assets/models/monsters/horror_creature/horror_creature.glb")
const SOURCE_HEIGHT := 1.86
const FALL_SECONDS := 2.6
const CORPSE_SECONDS := 28.0
const ATTACK_WINDUP := 1.65
const ATTACK_COOLDOWN := 4.6
const ROLES := {
	"shambler": {"height": 9.0, "hp": 170.0, "speed": 1.8, "damage": 38.0, "reward": 30, "name": "腐化巨尸", "tint": Color(0.70, 0.77, 0.66)},
	"brute": {"height": 12.0, "hp": 340.0, "speed": 1.55, "damage": 62.0, "reward": 55, "name": "暴虐巨尸", "tint": Color(0.87, 0.59, 0.46)},
	"titan": {"height": 16.0, "hp": 620.0, "speed": 1.3, "damage": 95.0, "reward": 110, "name": "灾厄泰坦", "tint": Color(0.50, 0.61, 0.70)},
}
static var _skin_materials: Dictionary = {}
var game: Node
var director: Node
var archetype := "shambler"
var wave := 1
var team := 1
var alive := true
var destroyed := false
var hp := 170.0
var max_hp := 170.0
var height := 9.0
var move_speed := 1.8
var attack_damage := 38.0
var reward := 30
var display_name := "腐化巨尸"
var stunned := 0.0
var attack_remaining := 0.0
var attack_cooldown := 1.8
var corpse_age := 0.0
var step_count := 0
var _visual: Node3D
var _skin: MeshInstance3D
var _animation: AnimationPlayer
var _skeleton: Skeleton3D
var _walk_name := ""
var _walk_phase := 0.0
var _step_clock := 0.8
var _hit_clock := 0.0
var _base_attack := false
var _attack_target: Node3D
var _death_impact := false
var _fall_roll := 0.0
var _death_bone_points: Array[Vector3] = []
var _arm_indices: Array[int] = []
var _head_bone := -1
var _eye_glow: OmniLight3D
var _health_display: Label3D


func _ready() -> void:
	add_to_group("monsters")
	if archetype == "colossus":
		archetype = "titan"
	if not ROLES.has(archetype):
		archetype = "shambler"
	var role: Dictionary = ROLES[archetype]
	height = role.height
	# Health grows faster than speed: later waves stay ponderous and readable.
	max_hp = float(role.hp) * (1.0 + 0.16 * float(maxi(0, wave - 1)))
	hp = max_hp
	move_speed = minf(2.65, float(role.speed) + float(maxi(0, wave - 1)) * 0.035)
	attack_damage = float(role.damage) * (1.0 + minf(1.0, float(maxi(0, wave - 1)) * 0.055))
	reward = int(role.reward)
	display_name = role.name
	collision_layer = 4
	# Giants yield through soft crowd separation instead of forming an
	# unbreakable physics queue. They still collide with terrain and the tank.
	collision_mask = 1 | 2
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(42.0)
	var collider := CollisionShape3D.new()
	collider.name = "MonsterBody"
	var capsule := CapsuleShape3D.new()
	capsule.radius = height * 0.145
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	add_child(collider)
	_build_visual(role.tint)
	_step_clock += float(get_instance_id() % 19) * 0.04
	_fall_roll = -0.11 if get_instance_id() % 2 else 0.11
	set_meta("monster_height", height)
	set_meta("height", height)
	set_meta("model_source", "HorrorGameMaker / CC0")


func _build_visual(tint: Color) -> void:
	_visual = Node3D.new()
	_visual.name = "FallingBody"
	add_child(_visual)
	var model := CREATURE.instantiate() as Node3D
	model.name = "SkinnedCreature"
	model.scale = Vector3.ONE * (height / SOURCE_HEIGHT)
	model.rotation.y = PI
	_visual.add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		_skin = meshes[0] as MeshInstance3D
		if not _skin_materials.has(archetype):
			var material := _skin.get_active_material(0).duplicate() as StandardMaterial3D
			material.albedo_color = tint
			material.metallic = 0.0
			material.roughness = 0.84
			# The old Maya map behaves as gloss in this asset. Use a physical
			# roughness value while retaining the authored skin/normal detail.
			material.roughness_texture = null
			material.normal_scale = 0.82
			_skin_materials[archetype] = material
		_skin.material_override = _skin_materials[archetype]
		# Animated limbs and the larger falling envelope must not be culled
		# using the narrow imported walk-pose bounds.
		_skin.extra_cull_margin = 2.8
	var animations := model.find_children("*", "AnimationPlayer", true, false)
	if not animations.is_empty():
		_animation = animations[0] as AnimationPlayer
		_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in _animation.get_animation_list():
			if "walk" in clip.to_lower():
				_walk_name = clip
				break
		if not _walk_name.is_empty():
			_animation.play(_walk_name)
			_animation.advance(0.0)
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		_skeleton = rigs[0] as Skeleton3D
		for bone_name in ["joint14", "joint14_001", "joint14.001"]:
			var index := _skeleton.find_bone(bone_name)
			if index >= 0:
				_arm_indices.append(index)
		_head_bone = _skeleton.find_bone("joint15")
	_health_display = Label3D.new()
	_health_display.name = "MonsterIdentity"
	_health_display.position.y = height + 0.8
	_health_display.font_size = 42
	_health_display.pixel_size = 0.017
	_health_display.outline_size = 8
	_health_display.modulate = Color(1.0, 0.58, 0.37)
	_health_display.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_display.no_depth_test = false
	_health_display.visible = false
	add_child(_health_display)
	# A restrained red bounce from the head keeps the face readable in fog.
	_eye_glow = OmniLight3D.new()
	_eye_glow.position = Vector3(0, height * 0.82, -height * 0.1)
	_eye_glow.light_color = Color(1.0, 0.16, 0.055)
	_eye_glow.light_energy = 0.7 if archetype == "titan" else 0.35
	_eye_glow.omni_range = height * 0.30
	_eye_glow.shadow_enabled = false
	_visual.add_child(_eye_glow)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.is_combat_running():
		return
	if destroyed:
		_tick_corpse(delta)
		return
	stunned = maxf(0.0, stunned - delta)
	_hit_clock = maxf(0.0, _hit_clock - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if not is_on_floor():
		velocity.y -= 16.0 * delta
	else:
		velocity.y = 0.0
	if stunned > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_visual.rotation.x = -0.11 * sin(stunned * 8.0)
		return
	_visual.rotation.x = move_toward(_visual.rotation.x, 0.0, delta * 1.1)
	if attack_remaining > 0.0:
		_tick_attack(delta)
		move_and_slide()
		return
	var goal: Vector3 = director.get_monster_goal(self) if is_instance_valid(director) else global_position
	var offset := goal - global_position
	offset.y = 0.0
	var player := game.get("player") as Node3D
	var melee_range := height * 0.24 + 3.5
	if is_instance_valid(player) and not bool(player.get("destroyed")) and global_position.distance_to(player.global_position) < melee_range and _clear_reach(player.global_position):
		_begin_attack(player, false)
	elif offset.length() < 3.8 and _clear_reach(goal):
		_begin_attack(null, true)
	else:
		var heading := offset.normalized()
		var separation := Vector3.ZERO
		for other: Node in get_tree().get_nodes_in_group("monsters"):
			if other == self or bool(other.get("destroyed")):
				continue
			var apart := global_position - (other as Node3D).global_position
			apart.y = 0.0
			var safe_distance := (height + float(other.get("height"))) * 0.18
			if apart.length_squared() > 0.01 and apart.length() < safe_distance:
				separation += apart.normalized() * (1.0 - apart.length() / safe_distance)
		# Forward progress always wins over lateral crowd avoidance.
		heading = (heading + separation * 0.65).normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-heading.x, -heading.z), minf(1.0, delta * 1.8))
		velocity.x = heading.x * move_speed
		velocity.z = heading.z * move_speed
		move_and_slide()
		_tick_walk(delta)
	_update_identity(player)


func _tick_walk(delta: float) -> void:
	if is_instance_valid(_animation) and not _walk_name.is_empty():
		var clip := _animation.get_animation(_walk_name)
		_walk_phase = fposmod(_walk_phase + delta * 0.42 * (9.0 / height), clip.length)
		_animation.seek(_walk_phase, true)
	_step_clock -= delta
	if _step_clock <= 0.0 and Vector2(velocity.x, velocity.z).length() > 0.2:
		_step_clock = 1.45 * (height / 9.0)
		step_count += 1
		_ground_contact(0.16, false)


func _clear_reach(at: Vector3) -> bool:
	var start := global_position + Vector3.UP * 2.2
	var end := at + Vector3.UP * 2.2
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _begin_attack(target: Node3D, is_base: bool) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if attack_cooldown > 0.0:
		return
	_attack_target = target
	_base_attack = is_base
	attack_remaining = ATTACK_WINDUP
	if is_instance_valid(target):
		var direction := target.global_position - global_position
		rotation.y = atan2(-direction.x, -direction.z)
	_health_display.visible = true
	_health_display.text = "%s · 重击蓄力" % display_name
	AudioService.play_3d("boss_warning", global_position + Vector3.UP * height * 0.6, -12.0, 0.55, 45)


func _tick_attack(delta: float) -> void:
	attack_remaining = maxf(0.0, attack_remaining - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	var progress := 1.0 - attack_remaining / ATTACK_WINDUP
	_visual.rotation.x = -sin(progress * PI) * 0.19 + smoothstep(0.76, 1.0, progress) * 0.38
	if is_instance_valid(_animation):
		_animation.seek(0.18, true)
	if is_instance_valid(_skeleton):
		for bone in _arm_indices:
			var pose := _skeleton.get_bone_pose_rotation(bone)
			_skeleton.set_bone_pose_rotation(bone, pose * Quaternion(Vector3.FORWARD, sin(progress * PI) * 0.85))
	if attack_remaining > 0.0:
		return
	attack_cooldown = ATTACK_COOLDOWN
	_ground_contact(0.7, true)
	if _base_attack and is_instance_valid(director):
		var goal: Vector3 = director.get_monster_goal(self)
		if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 4.5 and _clear_reach(goal):
			director.monster_reached_base(self, attack_damage)
	elif is_instance_valid(_attack_target) and not bool(_attack_target.get("destroyed")):
		var distance := global_position.distance_to(_attack_target.global_position)
		# The tank can escape during the telegraph; a locked swing cannot hit
		# a retreating player from arbitrarily far away or through a building.
		if distance < height * 0.24 + 4.2 and _clear_reach(_attack_target.global_position):
			_attack_target.call("receive_damage", attack_damage, team, global_position, "blast")
	_attack_target = null


func receive_damage(amount: float, attacker_team: int, hit_position := Vector3.ZERO, weapon_kind := "blast") -> float:
	if destroyed or attacker_team == team or amount <= 0.0 or not is_finite(amount):
		return 0.0
	if is_instance_valid(game) and not game.is_combat_running():
		return 0.0
	var accepted := amount
	# Direct head shots reward careful third-person aiming. Blast damage has
	# no accidental head bonus from its explosion origin.
	if weapon_kind in ["cannon", "machine_gun", "he", "rocket"] and hit_position.y - global_position.y > height * 0.77:
		accepted *= 1.65
	accepted = minf(hp, accepted)
	hp = maxf(0.0, hp - accepted)
	_hit_clock = 2.2
	_health_display.visible = true
	_health_display.text = "%s  %d%%" % [display_name, ceili(hp / max_hp * 100.0)]
	if amount >= 45.0 and attack_remaining <= 0.0:
		stunned = maxf(stunned, 0.16 if archetype == "titan" else 0.30)
	if hp <= 0.0:
		_die()
	return accepted


func is_targetable() -> bool:
	return alive and not destroyed


func apply_emp(seconds: float) -> void:
	if destroyed:
		return
	stunned = maxf(stunned, clampf(seconds, 0.0, 5.0))
	attack_remaining = 0.0
	attack_cooldown = maxf(attack_cooldown, 1.2)
	_attack_target = null
	_health_display.text = "%s · 脉冲震慑" % display_name
	_health_display.visible = true


func _die() -> void:
	if destroyed:
		return
	destroyed = true
	alive = false
	velocity = Vector3.ZERO
	attack_remaining = 0.0
	collision_layer = 0
	collision_mask = 0
	remove_from_group("monsters")
	add_to_group("monster_corpses")
	_health_display.visible = false
	_eye_glow.light_energy = 0.0
	if is_instance_valid(_animation):
		_animation.seek(0.28, true)
	if is_instance_valid(_skeleton):
		var skeleton_to_visual := _visual.global_transform.affine_inverse() * _skeleton.global_transform
		for index in _skeleton.get_bone_count():
			_death_bone_points.append(skeleton_to_visual * _skeleton.get_bone_global_pose(index).origin)
	if is_instance_valid(director):
		director.monster_killed(self, reward)
	AudioService.play_3d("explosion_tail", global_position + Vector3.UP * height * 0.6, -10.0, 0.65, 55)


func _tick_corpse(delta: float) -> void:
	corpse_age += delta
	var t := clampf(corpse_age / FALL_SECONDS, 0.0, 1.0)
	# A visible stagger, accelerating fall and settling shoulder give the
	# giant a readable weight. This is the same rigged body, never a swap.
	var fall := smoothstep(0.12, 1.0, t * t)
	_visual.rotation = Vector3(-1.55 * fall, 0.0, _fall_roll * fall)
	# Fit the actual frozen pose to the ground. A fixed offset leaves a
	# floating chest on some stride phases and buries hands on others.
	var lowest := 0.0
	for point in _death_bone_points:
		lowest = minf(lowest, (_visual.basis * point).y)
	_visual.position.y = maxf(0.0, -lowest + height * 0.018) * fall
	if t > 0.88 and not _death_impact:
		_death_impact = true
		_ground_contact(1.05, true)
	if corpse_age > CORPSE_SECONDS - 3.0:
		if is_instance_valid(_skin):
			_skin.transparency = clampf((corpse_age - (CORPSE_SECONDS - 3.0)) / 3.0, 0.0, 1.0)
	if corpse_age >= CORPSE_SECONDS:
		queue_free()


func _ground_contact(strength: float, heavy: bool) -> void:
	var at := global_position - global_basis.z * (height * 0.28 if destroyed else 0.6)
	AudioService.play_3d("explosion_tail" if heavy else "ground_hit", at, -4.0 if heavy else -13.0, 0.65 if heavy else 0.48, 50 if heavy else 20)
	if heavy and is_instance_valid(game) and game.has_method("spawn_impact"):
		game.spawn_impact(at, false, "ground", Vector3.UP, "he")
	var player := game.get("player") as Node3D if is_instance_valid(game) else null
	if is_instance_valid(player) and player.has_method("add_camera_shake"):
		var distance := global_position.distance_to(player.global_position)
		var proximity := clampf(1.0 - distance / 72.0, 0.0, 1.0)
		player.add_camera_shake(strength * proximity * (height / 9.0))


func _update_identity(player: Node3D) -> void:
	if attack_remaining > 0.0:
		return
	var close := is_instance_valid(player) and player.global_position.distance_to(global_position) < 38.0
	_health_display.visible = _hit_clock > 0.0 or close or archetype == "titan"
	_health_display.text = "%s  %d%%" % [display_name, ceili(hp / max_hp * 100.0)]
