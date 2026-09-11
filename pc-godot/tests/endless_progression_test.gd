extends Node
## Run-local purchases, production weapon clocks and isolated save records.

const Loadout = preload("res://data/combat_loadout.gd")
const Upgrades = preload("res://data/endless_upgrades.gd")
var passed := 0
var failed := 0


func _ready() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _purchase_checks() -> void:
	var upgrades := Upgrades.new()
	check(upgrades.scrap == 0 and upgrades.catalog().size() == 5, "new defense starts with five choices and no salvage")
	check(not upgrades.can_purchase("firepower") and upgrades.purchase("firepower").is_empty(), "unaffordable upgrade cannot be purchased")
	upgrades.add_reward(30)
	upgrades.add_reward(30)
	check(upgrades.can_purchase("firepower"), "two normal kills buy the first weapon upgrade")
	var effect := upgrades.purchase("firepower")
	check(int(effect.damage_level) == 1 and int(effect.reload_level) == 0 and upgrades.scrap == 0, "damage purchase charges salvage and returns its applied level")
	check(upgrades.purchase("not_an_upgrade").is_empty() and upgrades.scrap == 0, "invalid purchase never charges currency")
	upgrades.add_reward(-100)
	check(upgrades.scrap == 0, "negative reward cannot remove salvage")
	upgrades.add_reward(9223372036854775807)
	upgrades.add_reward(9223372036854775807)
	check(upgrades.scrap == Upgrades.MAX_SCRAP, "oversized repeated rewards stay within the currency cap")
	for id: String in ["firepower", "autoloader", "fortification"]:
		var previous_cost := 0
		var purchases := 0
		while upgrades.can_purchase(id):
			var item: Dictionary = {}
			for candidate: Dictionary in upgrades.catalog():
				if candidate.id == id:
					item = candidate
			check(int(item.cost) > previous_cost, "%s price rises before purchase %d" % [id, int(item.level) + 1])
			previous_cost = int(item.cost)
			var before := upgrades.scrap
			effect = upgrades.purchase(id)
			check(upgrades.scrap == before - int(effect.cost), "%s consumes its exact quoted price" % id)
			if id == "fortification":
				check(float(effect.base_max_hp) == 150.0 and float(effect.base_heal) == 150.0, "fortification increases and repairs base durability")
			purchases += 1
			if purchases > 8:
				break
		var max_level := 8 if id == "firepower" else 6
		check(int(upgrades.levels[id]) == max_level and upgrades.purchase(id).is_empty(), "%s stops at its maximum level" % id)
	var repair := upgrades.purchase("repair")
	check(float(repair.player_heal) == 140.0 and float(repair.base_heal) == 240.0, "repair returns separate tank and base healing")
	check(not upgrades.purchase("repair").is_empty(), "field repair can be purchased repeatedly")
	check(bool(upgrades.purchase("ammo").get("resupply", false)), "ammo purchase explicitly requests resupply")
	check(not upgrades.purchase("ammo").is_empty(), "ammo can be purchased repeatedly")
	check(Upgrades.new().levels.firepower == 0, "new run never inherits the last run's upgrade levels")


func _loadout_checks() -> void:
	var campaign := Loadout.new()
	var baseline := campaign.fire(3.1)
	check(is_equal_approx(float(baseline.damage), 62.0) and is_equal_approx(float(baseline.damage_multiplier), 1.0), "campaign cannon damage remains unchanged")
	check(is_equal_approx(float(campaign.snapshot().reload), 3.1), "campaign chassis reload override remains unchanged")
	var loadout := Loadout.new()
	loadout.set_endless_upgrades(2, 3)
	var first := loadout.fire(3.1)
	check(is_equal_approx(float(first.damage), 62.0 * 1.4) and is_equal_approx(float(first.damage_multiplier), 1.4), "endless cannon returns enhanced damage and chassis multiplier")
	check(is_equal_approx(float(loadout.snapshot().reload), 3.1 * 0.76), "autoloader reduces the actual chassis reload override")
	check(is_equal_approx(float(loadout.snapshot().reload_max), float(loadout.snapshot().reload)), "reload bar maximum equals the actual upgraded cannon cycle")
	loadout.select(2)
	check(not loadout.can_fire(), "switching to HE cannot bypass the upgraded shared breech")
	check(is_equal_approx(float(loadout.snapshot().reload_max), 3.1 * 0.76), "shared HE breech displays the upgraded cycle")
	loadout.tick(1.0)
	var cooldown_before := float(loadout.snapshot().reload)
	var ammo_before := int(loadout.snapshot().ammo)
	loadout.set_endless_upgrades(8, 6)
	check(is_equal_approx(float(loadout.snapshot().reload), cooldown_before), "mid-reload upgrade preserves remaining shared cooldown")
	check(int(loadout.snapshot().ammo) == ammo_before, "buying an upgrade never generates ammunition")
	loadout.tick(10.0)
	var he := loadout.fire()
	check(is_equal_approx(float(he.damage), 52.0 * 2.6), "maximum firepower upgrades HE damage")
	check(is_equal_approx(float(loadout.snapshot().reload), 3.8 * 0.52), "maximum autoloader keeps a finite HE cycle")
	loadout.select(0)
	check(not loadout.can_fire(), "upgraded HE locks AP until its actual reload completes")
	loadout.select(3)
	var rocket := loadout.fire()
	check(is_equal_approx(float(rocket.damage), 88.0 * 2.6), "firepower upgrades rockets")
	check(is_equal_approx(float(loadout.snapshot().reload), 5.8 * 0.52), "autoloader upgrades rocket reload")
	loadout.select(1)
	var machine_gun := loadout.fire()
	check(is_equal_approx(float(machine_gun.damage), 3.4 * 2.6), "firepower upgrades machine gun bullets")
	check(is_equal_approx(float(loadout.snapshot().reload), 0.15 * 0.52), "autoloader upgrades machine gun firing cadence")
	for shot in 39:
		loadout.tick(0.15)
		loadout.fire()
	check(int(loadout.snapshot().ammo) == 0 and bool(loadout.snapshot().belt_reloading), "fortieth machine gun round starts the real belt reload")
	check(is_equal_approx(float(loadout.snapshot().reload), 4.4 * 0.52), "autoloader also reduces belt replacement time")
	loadout.set_endless_upgrades(0, 0)
	check(is_equal_approx(float(loadout.snapshot().reload), 4.4 * 0.52), "changing upgrades cannot clear an active belt reload")
	check(int(loadout.snapshot().reserve) == 240, "reload upgrade does not consume or duplicate reserve ammunition")
	loadout.tick(4.4)
	check(int(loadout.snapshot().ammo) == 40 and int(loadout.snapshot().reserve) == 200, "belt completion transfers exactly forty existing reserve rounds")
	loadout.set_endless_upgrades(999, 999)
	machine_gun = loadout.fire()
	check(is_equal_approx(float(machine_gun.damage_multiplier), 2.6) and is_equal_approx(float(machine_gun.interval), 0.15 * 0.52), "upgrade levels clamp to the designed maxima")
	cooldown_before = float(loadout.snapshot().reload)
	loadout.resupply()
	check(is_equal_approx(float(loadout.snapshot().reload), cooldown_before) and int(loadout.snapshot().ammo) == 40, "purchased resupply fills ammo without bypassing firing cooldown")
	loadout.set_endless_upgrades(-20, -20)
	loadout.tick(1.0)
	machine_gun = loadout.fire()
	check(is_equal_approx(float(machine_gun.damage), 3.4) and is_equal_approx(float(machine_gun.interval), 0.15), "negative upgrade levels safely restore baseline behavior")
	check(is_equal_approx(float(Loadout.WEAPONS[1].damage), 3.4), "upgrading one loadout never mutates shared weapon definitions")


func _save_checks() -> void:
	var saves: Node = get_tree().root.get_node("SaveService")
	var original_directory: String = saves._directory
	var original_profile: Dictionary = saves.profile.duplicate(true)
	saves._directory = "user://tests/endless_progression_%d" % OS.get_process_id()
	saves.reset_for_tests()
	check(int(saves.profile.endless_best_wave) == 0 and float(saves.profile.endless_best_time) == 0.0, "fresh profiles start with empty endless records")
	saves.profile.completed_missions = [0, 1]
	saves.profile.lifetime_kills = 17
	saves.profile.best_score = 840
	saves.profile.upgrade_points = 4
	saves.begin_run("campaign-kept-open")
	saves.credit_run_kills("campaign-kept-open", 3)
	var campaign_before: Dictionary = saves.profile.duplicate(true)
	check(saves.record_endless_result(4, 23, 137.25), "new endless record persists successfully")
	check(not saves.record_endless_result(4, 23, 137.25), "repeated settlement is idempotent")
	check(not saves.record_endless_result(1, 2, 30.0), "lower result cannot overwrite personal bests")
	check(saves.record_endless_result(3, 30, 150.0), "independent kill and time records improve without lowering wave record")
	saves.profile = {}
	saves.load_profile()
	check(int(saves.profile.endless_best_wave) == 4 and int(saves.profile.endless_best_kills) == 30 and is_equal_approx(float(saves.profile.endless_best_time), 150.0), "endless records survive a real JSON save and reload")
	for key: String in ["completed_missions", "lifetime_kills", "best_score", "upgrade_points", "tank_level", "selected_chassis", "selected_weapon", "active_run"]:
		check(saves.profile[key] == campaign_before[key], "endless result preserves campaign field %s" % key)
	check(not saves.record_endless_result(-1, 2, 10.0) and not saves.record_endless_result(1, -2, 10.0), "negative endless wave and kill counts are rejected")
	check(not saves.record_endless_result(1, 2, -1.0) and not saves.record_endless_result(1, 2, INF) and not saves.record_endless_result(1, 2, NAN), "negative and non-finite survival times are rejected")
	check(saves.record_endless_result(9223372036854775807, 9223372036854775807, 1.0e30), "oversized finite records save with bounded values")
	check(int(saves.profile.endless_best_wave) == 1000000 and int(saves.profile.endless_best_kills) == 1000000000 and float(saves.profile.endless_best_time) == 315360000.0, "record caps prevent unbounded profile values")
	var malformed: Dictionary = saves.default_profile()
	malformed.endless_best_wave = "broken"
	malformed.endless_best_kills = INF
	malformed.endless_best_time = NAN
	malformed.completed_missions = [0.0, 1, 1.0, 1.5, INF, NAN, "2", -1, 18, 17.0]
	var sanitized: Dictionary = saves._sanitize(malformed)
	check(int(sanitized.endless_best_wave) == 0 and int(sanitized.endless_best_kills) == 0 and float(sanitized.endless_best_time) == 0.0, "malformed persisted endless values sanitize to safe defaults")
	check(sanitized.completed_missions == [0, 1, 17], "JSON numeric mission IDs survive while fractions, duplicates and invalid entries are rejected")
	var legacy: Dictionary = campaign_before.duplicate(true)
	for key: String in ["endless_best_wave", "endless_best_kills", "endless_best_time"]:
		legacy.erase(key)
	var file := FileAccess.open(saves._path("profile_0.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	saves.load_profile()
	check(not saves.recovered_from_backup and int(saves.profile.schema_version) == 1 and int(saves.profile.endless_best_wave) == 0, "schema-one legacy profiles load without recovery or migration loss")
	check(saves.profile.completed_missions == campaign_before.completed_missions and saves.profile.active_run == campaign_before.active_run, "legacy campaign progress survives addition of endless records")
	saves.reset_for_tests()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saves._directory))
	saves._directory = original_directory
	saves.profile = original_profile


func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	_purchase_checks()
	_loadout_checks()
	_save_checks()
	print("Endless progression tests: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
