extends SceneTree

const CombatEnumsRef = preload("res://data/combat_enums.gd")
const WeaponSpecRef = preload("res://data/weapon_spec.gd")
const FirstMissionSpecRef = preload("res://data/first_mission_spec.gd")
const HealthStateRef = preload("res://core/health_state.gd")
const DamageResolverRef = preload("res://core/damage_resolver.gd")
const BossPhaseTrackerRef = preload("res://core/boss_phase_tracker.gd")
const MineFieldRef = preload("res://core/mine_field.gd")
const MissionGateRef = preload("res://core/mission_gate.gd")
const CampaignProgressRef = preload("res://core/campaign_progress.gd")
const FixedStepRef = preload("res://core/fixed_step.gd")
const MovementMathRef = preload("res://core/movement_math.gd")
const SweepMathRef = preload("res://core/sweep_math.gd")

var _passed: int = 0
var _failed: int = 0
var _clock_position: Vector2 = Vector2.ZERO

const EXPECTED_CHECKS: int = 51


func _initialize() -> void:
	_run_all()
	if _passed + _failed != EXPECTED_CHECKS:
		_failed += 1
		push_error(
			"FAIL: test runner stopped early (%d of %d checks ran)"
			% [_passed + _failed - 1, EXPECTED_CHECKS]
		)
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		push_error("FAIL: " + message)
	else:
		_passed += 1
		print("PASS: " + message)


func _near(left: float, right: float, epsilon: float = 0.00001) -> bool:
	return absf(left - right) <= epsilon


func _run_all() -> void:
	_test_weapon_and_damage_contracts()
	_test_boss_phases_once()
	_test_mines_and_emp()
	_test_first_mission_gate()
	_test_active_run_idempotency()
	_test_fixed_step_and_normalized_movement()
	_test_swept_hits()


func _test_weapon_and_damage_contracts() -> void:
	var cannon := WeaponSpecRef.new(WeaponSpecRef.Preset.FALCON_CANNON)
	var machine_gun := WeaponSpecRef.new(
		WeaponSpecRef.Preset.SWARM_HEAVY_MACHINE_GUN
	)
	_check(cannon.is_valid(), "first-mission cannon data is valid")
	_check(machine_gun.is_valid(), "machine-gun data is valid")
	_check(
		cannon.damage_kind == CombatEnumsRef.DamageKind.EXPLOSIVE
		and machine_gun.damage_kind == CombatEnumsRef.DamageKind.KINETIC,
		"weapon data carries a strongly typed damage kind"
	)
	_check(
		cannon.cooldown_seconds > machine_gun.cooldown_seconds
		and cannon.damage > machine_gun.damage,
		"weapon parameters preserve distinct fire roles"
	)
	var enemy := HealthStateRef.new(CombatEnumsRef.Faction.ENEMY, 100.0)
	var ally := HealthStateRef.new(CombatEnumsRef.Faction.PLAYER, 100.0)
	_check(
		_near(
			DamageResolverRef.apply_damage(
				enemy, CombatEnumsRef.Faction.PLAYER, cannon.damage
			),
			32.0
		),
		"hostile cannon damage is applied"
	)
	_check(
		_near(
			DamageResolverRef.apply_damage(
				ally, CombatEnumsRef.Faction.PLAYER, cannon.damage
			),
			0.0
		),
		"friendly fire is rejected by faction"
	)
	enemy.shielded = true
	_check(
		_near(
			DamageResolverRef.apply_damage(
				enemy, CombatEnumsRef.Faction.PLAYER, 999.0
			),
			0.0
		),
		"shield blocks ordinary damage"
	)


func _test_boss_phases_once() -> void:
	var phases := BossPhaseTrackerRef.new()
	_check(phases.update(71.0, 100.0).is_empty(), "boss stays in phase zero above 70 percent")
	var phase_one: Array[int] = phases.update(70.0, 100.0)
	_check(phase_one.size() == 1 and phase_one[0] == 1, "boss enters phase one at 70 percent")
	_check(phases.update(60.0, 100.0).is_empty(), "boss phase one cannot retrigger")
	var phase_two: Array[int] = phases.update(35.0, 100.0)
	_check(phase_two.size() == 1 and phase_two[0] == 2, "boss enters phase two at 35 percent")
	_check(phases.update(5.0, 100.0).is_empty(), "boss phase two cannot retrigger")
	_check(phases.current_phase() == 2, "boss reports the final phase")
	var skipped := BossPhaseTrackerRef.new()
	var skipped_phases: Array[int] = skipped.update(20.0, 100.0)
	_check(
		skipped_phases.size() == 2
		and skipped_phases[0] == 1
		and skipped_phases[1] == 2,
		"one heavy hit crosses both boss phases once"
	)


func _test_mines_and_emp() -> void:
	var field := MineFieldRef.new()
	var player_mine = field.try_place(
		1,
		CombatEnumsRef.Faction.PLAYER,
		Vector3.ZERO,
		220.0,
		0.0
	)
	var enemy_mine = field.try_place(
		2,
		CombatEnumsRef.Faction.ENEMY,
		Vector3(10.0, 0.0, 0.0),
		75.0,
		0.0
	)
	_check(player_mine != null and enemy_mine != null, "both factions can place mines")
	_check(
		field.take_triggered(
			Vector3.ZERO, CombatEnumsRef.Faction.ENEMY, 1.19
		) == null,
		"mine cannot trigger before its 1.2 second arm delay"
	)
	_check(
		field.take_triggered(
			Vector3.ZERO, CombatEnumsRef.Faction.PLAYER, 1.2
		) == null,
		"friendly mine ignores its owner faction"
	)
	var triggered = field.take_triggered(
		Vector3.ZERO, CombatEnumsRef.Faction.ENEMY, 1.2
	)
	_check(
		triggered != null and _near(triggered.damage, 220.0),
		"armed player mine triggers once on an enemy"
	)
	var unarmed_enemy = field.try_place(
		3,
		CombatEnumsRef.Faction.ENEMY,
		Vector3(20.0, 0.0, 0.0),
		75.0,
		2.0,
		10.0
	)
	_check(unarmed_enemy != null, "enemy can deploy an unarmed mine")
	_check(
		field.clear_with_emp(Vector3.ZERO, 30.0, 2.1) == 2
		and field.mines.is_empty(),
		"EMP clears armed and unarmed mines from both factions"
	)
	var expiring = field.try_place(
		4,
		CombatEnumsRef.Faction.PLAYER,
		Vector3.ZERO,
		220.0,
		10.0
	)
	_check(
		expiring != null
		and field.prune_expired(99.999) == 0
		and field.prune_expired(100.0) == 1,
		"mine lifetime remains 90 seconds"
	)
	var swept_mine = field.try_place(
		5,
		CombatEnumsRef.Faction.PLAYER,
		Vector3.ZERO,
		220.0,
		200.0
	)
	_check(
		swept_mine != null
		and field.take_triggered_swept(
			Vector3(-10.0, 0.0, 0.0),
			Vector3(10.0, 0.0, 0.0),
			CombatEnumsRef.Faction.ENEMY,
			201.2
		) == swept_mine,
		"swept mine trigger prevents a fast tank from tunneling through"
	)


func _test_first_mission_gate() -> void:
	var gate := MissionGateRef.new(
		FirstMissionSpecRef.REGULAR_KILL_TARGET,
		FirstMissionSpecRef.BOSS_REQUIRED
	)
	for enemy_id: int in range(1, 7):
		_check(gate.record_destroyed(enemy_id, false), "regular enemy %d is credited" % enemy_id)
	_check(not gate.is_complete(), "six regular kills cannot bypass the boss")
	_check(not gate.record_destroyed(6, false), "duplicate enemy destruction is ignored")
	_check(gate.record_destroyed(99, true), "boss destruction is credited")
	_check(gate.is_complete(), "first mission requires six enemies and its boss")


func _test_active_run_idempotency() -> void:
	var progress := CampaignProgressRef.new()
	_check(progress.begin_run("run-a"), "valid active run starts")
	_check(progress.credit_run_kills("run-a", 2) == 2, "first cumulative kill report is credited")
	_check(progress.credit_run_kills("run-a", 2) == 0, "duplicate cumulative kill report is ignored")
	_check(progress.credit_run_kills("stale", 7) == 0, "stale run report is ignored")
	_check(
		progress.credit_run_kills("run-a", CampaignProgressRef.MAX_LIFETIME_KILLS + 1) == 0,
		"untrusted cumulative kill reports are range checked"
	)
	_check(progress.credit_run_kills("run-a", 5) == 3, "only cumulative kill delta is credited")
	_check(progress.lifetime_kills == 5, "active run total remains idempotent")
	_check(progress.settle_run("run-a", 6), "active run settles once and credits its final delta")
	_check(not progress.settle_run("run-a", 9), "settled run cannot settle twice")
	_check(progress.credit_run_kills("run-a", 9) == 0, "settled run rejects late reports")
	_check(progress.lifetime_kills == 6, "late reports cannot inflate lifetime kills")


func _integrate_clock_step(delta_seconds: float) -> void:
	_clock_position = MovementMathRef.integrate(
		_clock_position,
		Vector2(1.0, 1.0),
		18.0,
		delta_seconds
	)


func _simulate_for_two_seconds(render_fps: int) -> Vector2:
	_clock_position = Vector2.ZERO
	var clock := FixedStepRef.new()
	for _frame: int in range(render_fps * 2):
		clock.advance(1.0 / float(render_fps), _integrate_clock_step)
	return _clock_position


func _test_fixed_step_and_normalized_movement() -> void:
	var straight := MovementMathRef.integrate(Vector2.ZERO, Vector2.RIGHT, 18.0, 1.0)
	var diagonal := MovementMathRef.integrate(Vector2.ZERO, Vector2.ONE, 18.0, 1.0)
	_check(
		_near(straight.length(), diagonal.length()),
		"diagonal movement is normalized"
	)
	var at_30 := _simulate_for_two_seconds(30)
	var at_60 := _simulate_for_two_seconds(60)
	var at_120 := _simulate_for_two_seconds(120)
	_check(at_30.distance_to(at_60) < 0.0001, "60 Hz simulation matches a 30 Hz render loop")
	_check(at_60.distance_to(at_120) < 0.0001, "60 Hz simulation matches a 120 Hz render loop")
	_check(_near(at_60.length(), 36.0, 0.001), "two simulated seconds move exactly 36 meters")


func _test_swept_hits() -> void:
	var wall_fraction := SweepMathRef.segment_rect_fraction(
		Vector2.ZERO,
		Vector2(100.0, 0.0),
		Rect2(30.0, -10.0, 3.0, 20.0)
	)
	var near_enemy := SweepMathRef.segment_circle_fraction(
		Vector2.ZERO,
		Vector2(100.0, 0.0),
		Vector2(50.0, 0.0),
		10.0
	)
	var far_enemy := SweepMathRef.segment_circle_fraction(
		Vector2.ZERO,
		Vector2(100.0, 0.0),
		Vector2(80.0, 0.0),
		10.0
	)
	_check(_near(wall_fraction, 0.3), "swept ray returns the wall's first impact")
	_check(_near(near_enemy, 0.4), "swept ray returns the near target's first impact")
	_check(_near(far_enemy, 0.7), "swept ray returns the far target's first impact")
	_check(
		_near(SweepMathRef.nearest_fraction(
			PackedFloat32Array([far_enemy, wall_fraction, near_enemy])
		), wall_fraction),
		"swept projectile hits blocking cover before targets"
	)
