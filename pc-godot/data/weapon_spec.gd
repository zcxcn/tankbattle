class_name WeaponSpec
extends Resource

const CombatEnumsRef = preload("res://data/combat_enums.gd")

enum Preset {
	FALCON_CANNON = 0,
	SWARM_HEAVY_MACHINE_GUN = 1,
}

@export var weapon_id: StringName = &"cannon"
@export var display_name: String = "猎隼加农炮"
@export var damage_kind: CombatEnumsRef.DamageKind = CombatEnumsRef.DamageKind.EXPLOSIVE
@export_range(0.0, 10000.0, 0.1, "or_greater") var damage: float = 32.0
@export_range(0.01, 30.0, 0.01, "or_greater") var cooldown_seconds: float = 0.46
@export_range(0.0, 1000.0, 0.1, "or_greater") var projectile_speed_mps: float = 62.0
@export_range(1, 32, 1, "or_greater") var pellet_count: int = 1
@export_range(0.0, 3.14159, 0.001) var spread_radians: float = 0.0
@export_range(0.0, 100.0, 0.1, "or_greater") var splash_radius_m: float = 0.0
@export_range(0, 32, 1, "or_greater") var extra_penetrations: int = 0
@export_range(0.0, 30.0, 0.1, "or_greater") var slow_seconds: float = 0.0
@export var homing: bool = false
@export var infinite_ammo: bool = true


func _init(initial_preset: Preset = Preset.FALCON_CANNON) -> void:
	apply_preset(initial_preset)


func apply_preset(preset: Preset) -> void:
	match preset:
		Preset.FALCON_CANNON:
			weapon_id = &"falcon_cannon"
			display_name = "猎隼加农炮"
			damage_kind = CombatEnumsRef.DamageKind.EXPLOSIVE
			damage = 32.0
			cooldown_seconds = 0.46
			projectile_speed_mps = 62.0
			pellet_count = 1
			spread_radians = 0.0
			splash_radius_m = 0.0
			extra_penetrations = 0
			slow_seconds = 0.0
			homing = false
			infinite_ammo = true
		Preset.SWARM_HEAVY_MACHINE_GUN:
			weapon_id = &"swarm_hmg"
			display_name = "蜂群重机枪"
			damage_kind = CombatEnumsRef.DamageKind.KINETIC
			damage = 6.4
			cooldown_seconds = 0.1288
			projectile_speed_mps = 74.4
			pellet_count = 1
			spread_radians = 0.0
			splash_radius_m = 0.0
			extra_penetrations = 0
			slow_seconds = 0.0
			homing = false
			infinite_ammo = false


func is_valid() -> bool:
	return (
		weapon_id != StringName()
		and not display_name.is_empty()
		and damage >= 0.0
		and cooldown_seconds > 0.0
		and projectile_speed_mps > 0.0
		and pellet_count > 0
		and splash_radius_m >= 0.0
		and extra_penetrations >= 0
		and slow_seconds >= 0.0
	)
