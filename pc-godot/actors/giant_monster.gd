class_name GiantMonster
extends CharacterBody3D
## Authored skinned horror creature, enlarged to city-block scale.
## The director owns rewards, the defendable objective and population limits.

const CREATURE := preload("res://assets/models/monsters/horror_creature/horror_creature.glb")
const FOREST := preload("res://assets/models/monsters/siege_beasts/forest.glb")
const REPTILE := preload("res://assets/models/monsters/siege_beasts/reptile.glb")
const GLUTTON := preload("res://assets/models/monsters/colossal/glutton.glb")
const GOLEM := preload("res://assets/models/monsters/colossal/golem.glb")
const SOURCE_HEIGHT := 1.86
const FALL_SECONDS := 2.6
const CORPSE_SECONDS := 28.0
const ATTACK_WINDUP := 1.65
const ATTACK_COOLDOWN := 4.6
const ROLES := {
	"shambler": {"height": 14.0, "hp": 170.0, "speed": 1.8, "damage": 38.0, "reward": 30, "name": "腐化巨尸", "tint": Color(0.70, 0.77, 0.66)},
	"brute": {"height": 24.0, "hp": 290.0, "speed": 1.55, "damage": 55.0, "reward": 55, "name": "暴虐巨尸", "tint": Color(0.87, 0.59, 0.46)},
	"titan": {"height": 42.0, "hp": 560.0, "speed": 1.3, "damage": 80.0, "reward": 110, "name": "灾厄泰坦", "tint": Color(0.50, 0.61, 0.70)},
	"forest": {"height": 22.0, "hp": 200.0, "speed": 1.5, "damage": 45.0, "reward": 40, "name": "枯林岩魔", "tint": Color(0.78, 0.81, 0.73)},
	"reaver": {"height": 30.0, "hp": 240.0, "speed": 1.7, "damage": 48.0, "reward": 50, "name": "裂脊猎兽", "tint": Color(0.63, 0.74, 0.62)},
	"kaiju": {"height": 60.0, "hp": 680.0, "speed": 1.15, "damage": 85.0, "reward": 150, "name": "灭城巨蜥", "tint": Color(0.44, 0.52, 0.55)},
	"glutton": {"height": 34.0, "hp": 270.0, "speed": 1.65, "damage": 48.0, "reward": 55, "name": "深渊吞噬者", "tint": Color(0.82, 0.71, 0.67)},
	"golem": {"height": 52.0, "hp": 390.0, "speed": 1.4, "damage": 62.0, "reward": 80, "name": "裂岩巨像", "tint": Color(0.80, 0.85, 0.87)},
	"juggernaut": {"height": 72.0, "hp": 820.0, "speed": 1.25, "damage": 88.0, "reward": 180, "name": "断岳巨神", "tint": Color(0.72, 0.65, 0.57)},
}
static var _skin_materials: Dictionary = {}
static var _deform_cache: Dictionary = {}
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
var _skins: Array[MeshInstance3D] = []
var _model: Node3D
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
var _deform_indices: Array[int] = []
var _sense_clock := 0.0
var _pursuing := false
var _aggro_remaining := 0.0
var _crowd_push := Vector3.ZERO


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
	move_speed = minf(4.8, float(role.speed) * 1.85 + float(maxi(0, wave - 1)) * 0.045)
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
	_sense_clock = float(get_instance_id() % 11) * 0.015
	_fall_roll = -0.11 if get_instance_id() % 2 else 0.11
	set_meta("monster_height", height)
	set_meta("height", height)
	set_meta("model_source", "CDmir / CC0" if archetype == "forest" else ("thecubber / CC BY 3.0" if archetype in ["reaver", "kaiju"] else "HorrorGameMaker / CC0"))
	if archetype == "glutton":
		set_meta("model_source", "Teh_Bucket / RayMooHawk / CC0")
	elif archetype in ["golem", "juggernaut"]:
		set_meta("model_source", "hendori-sama / umask007 / Dm3d / CC BY 3.0")


func _build_visual(tint: Color) -> void:
	_visual = Node3D.new()
	_visual.name = "FallingBody"
	add_child(_visual)
	var scene: PackedScene = FOREST if archetype == "forest" else (REPTILE if archetype in ["reaver", "kaiju"] else CREATURE)
	if archetype == "glutton":
		scene = GLUTTON
	elif archetype in ["golem", "juggernaut"]:
		scene = GOLEM
	var model := scene.instantiate() as Node3D
	_model = model
	model.name = "SkinnedCreature"
	# New assets are normalized to one metre, feet at zero, facing -Z.
	model.scale = Vector3.ONE * (height / SOURCE_HEIGHT if scene == CREATURE else height)
	model.rotation.y = PI if scene == CREATURE else 0.0
	_visual.add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		_skins.append(mesh)
		if _skin == null:
			_skin = mesh
		for surface in mesh.mesh.get_surface_count():
			var key := "%s/%s/%d" % [archetype, mesh.name, surface]
			if _skin_materials.has(key):
				mesh.set_surface_override_material(surface, _skin_materials[key])
				continue
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			var material := source.duplicate() as StandardMaterial3D if source != null else StandardMaterial3D.new()
			material.albedo_color *= tint
			material.metallic = 0.0
			material.roughness = 0.84
			# The old Maya map behaves as gloss in this asset. Use a physical
			# roughness value while retaining the authored skin/normal detail.
			material.roughness_texture = null
			material.normal_scale = 0.82
			_skin_materials[key] = material
			mesh.set_surface_override_material(surface, material)
		# Animated limbs and the larger falling envelope must not be culled
		# using the narrow imported walk-pose bounds.
		mesh.extra_cull_margin = 2.8
	var animations := model.find_children("*", "AnimationPlayer", true, false)
	if not animations.is_empty():
		_animation = animations[0] as AnimationPlayer
		_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in _animation.get_animation_list():
			if "walk" in clip.to_lower() or "run" in clip.to_lower():
				_walk_name = clip
				break
		if not _walk_name.is_empty():
			_animation.play(_walk_name)
			_animation.advance(0.0)
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		_skeleton = rigs[0] as Skeleton3D
		for bone_name in ["joint14", "joint14_001", "joint14.001", "upper_arm.L", "upper_arm.R", "Arm_L", "Arm_R", "upperhand.L", "upperhand.R", "Bone.002_L", "Bone.002_R"]:
			var index := _skeleton.find_bone(bone_name)
			if index >= 0:
				_arm_indices.append(index)
		_head_bone = _skeleton.find_bone("joint15")
		for mesh in _skins:
			for bone in deform_indices(mesh, _skeleton):
				if bone not in _deform_indices:
					_deform_indices.append(bone)
	_health_display = Label3D.new()
	_health_display.name = "MonsterIdentity"
	_health_display.position.y = minf(height + 0.8, 15.0)
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


static func deform_indices(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Array[int]:
	# Scan immutable weights once per shared mesh/skin, never on a combat death.
	var indices: Array[int] = []
	if mesh.skin == null:
		return indices
	var key := "%d/%d" % [mesh.mesh.get_instance_id(), mesh.skin.get_instance_id()]
	if _deform_cache.has(key):
		return _deform_cache[key]
	var used: Dictionary = {}
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in bones.size():
			if weights[index] > 0.001:
				used[bones[index]] = true
	for bind: int in used:
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
		if bone < 0:
			bone = mesh.skin.get_bind_bone(bind)
		if bone >= 0 and bone not in indices:
			indices.append(bone)
	_deform_cache[key] = indices
	return indices


static func warm_up_geometry() -> void:
	for scene: PackedScene in [CREATURE, FOREST, REPTILE, GLUTTON, GOLEM]:
		var model := scene.instantiate()
		var rigs := model.find_children("*", "Skeleton3D", true, false)
		if not rigs.is_empty():
			for mesh in model.find_children("*", "MeshInstance3D", true, false):
				deform_indices(mesh, rigs[0])
		model.free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.is_combat_running():
		return
	if destroyed:
		_tick_corpse(delta)
		return
	stunned = maxf(0.0, stunned - delta)
	_hit_clock = maxf(0.0, _hit_clock - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	_aggro_remaining = maxf(0.0, _aggro_remaining - delta)
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
	_sense_clock -= delta
	if _sense_clock <= 0.0:
		_sense_clock = 0.15
		_update_awareness(player)
	if _pursuing and is_instance_valid(player) and not bool(player.get("destroyed")):
		offset = player.global_position - global_position
		offset.y = 0.0
	var melee_range := height * 0.24 + 3.5
	if is_instance_valid(player) and not bool(player.get("destroyed")) and global_position.distance_to(player.global_position) < melee_range and _clear_reach(player.global_position):
		_begin_attack(player, false)
	elif not _pursuing and offset.length() < base_attack_range() and _clear_reach(goal):
		_begin_attack(null, true)
	else:
		var heading := offset.normalized()
		# Forward progress always wins over lateral crowd avoidance.
		heading = (heading + _crowd_push * 0.65).normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-heading.x, -heading.z), minf(1.0, delta * 1.8))
		velocity.x = heading.x * move_speed
		velocity.z = heading.z * move_speed
		move_and_slide()
		_tick_walk(delta)
	_update_identity(player)


func _update_awareness(player: Node3D) -> void:
	_pursuing = false
	if is_instance_valid(player) and not bool(player.get("destroyed")):
		var distance := global_position.distance_to(player.global_position)
		var notice_range := maxf(48.0, height * 1.1)
		if distance < notice_range or (_aggro_remaining > 0.0 and distance < 110.0):
			_pursuing = _clear_reach(player.global_position)
	_crowd_push = Vector3.ZERO
	var crowd: Array = director.monsters if is_instance_valid(director) and director.get("monsters") is Array else get_tree().get_nodes_in_group("monsters")
	for other: Node3D in crowd:
		if not is_instance_valid(other) or other == self or other.destroyed:
			continue
		var apart := global_position - other.global_position
		apart.y = 0.0
		var safe_distance := (height + float(other.height)) * 0.18
		var squared := apart.length_squared()
		if squared > 0.01 and squared < safe_distance * safe_distance:
			var distance := sqrt(squared)
			_crowd_push += apart / distance * (1.0 - distance / safe_distance)


func _tick_walk(delta: float) -> void:
	if is_instance_valid(_animation) and not _walk_name.is_empty():
		var clip := _animation.get_animation(_walk_name)
		_walk_phase = fposmod(_walk_phase + delta * clampf(0.65 * sqrt(14.0 / height), 0.28, 0.75) * 1.5, clip.length)
		_animation.seek(_walk_phase, true)
	_step_clock -= delta
	if _step_clock <= 0.0 and Vector2(velocity.x, velocity.z).length() > 0.2:
		_step_clock = 1.45 * sqrt(height / 14.0) / 1.5
		step_count += 1
		_ground_contact(0.16, false)


func _clear_reach(at: Vector3) -> bool:
	var start := global_position + Vector3.UP * 2.2
	var end := at + Vector3.UP * 2.2
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func base_attack_range() -> float:
	# The 60m capsule touches the shelter well before its root reaches the door.
	return maxf(3.8, height * 0.145 + 1.6)


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
		if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < base_attack_range() + 0.7 and _clear_reach(goal):
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
	_aggro_remaining = 12.0
	_sense_clock = 0.0
	_hit_clock = 2.2
	_health_display.visible = true
	_health_display.text = "%s  %d%%" % [display_name, ceili(hp / max_hp * 100.0)]
	if amount >= 45.0 and attack_remaining <= 0.0:
		stunned = maxf(stunned, 0.16 if height >= 42.0 else 0.30)
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
		for bone in _deform_indices:
			_death_bone_points.append(skeleton_to_visual * _skeleton.get_bone_global_pose(bone).origin)
	if is_instance_valid(director):
		director.monster_killed(self, reward)
	AudioService.play_3d("explosion_tail", global_position + Vector3.UP * height * 0.6, -10.0, 0.65, 55)


func _tick_corpse(delta: float) -> void:
	corpse_age += delta
	var t := clampf(corpse_age / (FALL_SECONDS * maxf(1.0, sqrt(height / 24.0))), 0.0, 1.0)
	# A visible stagger, accelerating fall and settling shoulder give the
	# giant a readable weight. This is the same rigged body, never a swap.
	var fall := smoothstep(0.12, 1.0, t * t)
	# Long-tailed beasts collapse onto a flank so their tail settles along the
	# road instead of pointing vertically into the sky after a rigid forward fall.
	if archetype in ["reaver", "kaiju"]:
		_visual.rotation = Vector3(-0.22 * fall, 0.0, signf(_fall_roll) * 1.52 * fall)
	else:
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
		for mesh in _skins:
			mesh.transparency = clampf((corpse_age - (CORPSE_SECONDS - 3.0)) / 3.0, 0.0, 1.0)
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
		player.add_camera_shake(minf(1.25, strength * proximity * sqrt(height / 14.0)))


func _update_identity(player: Node3D) -> void:
	if attack_remaining > 0.0:
		return
	var close := is_instance_valid(player) and player.global_position.distance_to(global_position) < 38.0
	_health_display.visible = _hit_clock > 0.0 or close or height >= 42.0
	_health_display.text = "%s  %d%%" % [display_name, ceili(hp / max_hp * 100.0)]
