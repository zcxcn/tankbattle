extends Node
## Versioned, validated and crash-resistant local profile storage.

signal profile_loaded(recovered_from_backup: bool)
signal profile_saved
signal save_failed(message: String)

const SCHEMA_VERSION := 1
const NORMAL_DIR := "user://saves"
const TEST_DIR := "user://tests"
const PROFILE_FILE := "profile_0.json"
const BACKUP_FILE := "profile_0.backup.json"

var profile: Dictionary = {}
var recovered_from_backup := false
var last_error := ""
var _directory := NORMAL_DIR


func _ready() -> void:
	if "--test" in OS.get_cmdline_user_args():
		_directory = TEST_DIR
	load_profile()


func default_profile() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"completed_missions": [],
		"lifetime_kills": 0,
		"best_score": 0,
		"upgrade_points": 0,
		"tank_level": 1,
		"selected_chassis": 1,
		"selected_weapon": 0,
		"active_run": {},
	}


func load_profile() -> Dictionary:
	recovered_from_backup = false
	last_error = ""
	var primary := _read_and_validate(_path(PROFILE_FILE))
	if not primary.is_empty():
		profile = primary
		profile_loaded.emit(false)
		return profile
	var backup := _read_and_validate(_path(BACKUP_FILE))
	if not backup.is_empty():
		profile = backup
		recovered_from_backup = true
		var recovery_message := "主存档无法读取，已恢复最近备份。"
		# Do not rotate a known-corrupt primary over the only valid backup.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(PROFILE_FILE)))
		save_now()
		last_error = recovery_message
		profile_loaded.emit(true)
		return profile
	profile = default_profile()
	profile_loaded.emit(false)
	return profile


func begin_run(run_id: String) -> void:
	if run_id.is_empty() or run_id.length() > 100:
		return
	profile["active_run"] = {
		"id": run_id,
		"credited_kills": 0,
		"settled": false,
	}
	save_now()


func credit_run_kills(run_id: String, cumulative_kills: int) -> int:
	var active: Dictionary = profile.get("active_run", {})
	if active.get("id", "") != run_id or bool(active.get("settled", false)):
		return 0
	var already := maxi(0, int(active.get("credited_kills", 0)))
	var accepted := maxi(0, cumulative_kills - already)
	if accepted == 0:
		return 0
	active["credited_kills"] = cumulative_kills
	profile["active_run"] = active
	profile["lifetime_kills"] = maxi(0, int(profile.get("lifetime_kills", 0))) + accepted
	profile["tank_level"] = _level_for_kills(int(profile["lifetime_kills"]))
	save_now()
	return accepted


func settle_run(run_id: String, won: bool, score: int, mission: int = 0) -> bool:
	var active: Dictionary = profile.get("active_run", {})
	if active.get("id", "") != run_id or bool(active.get("settled", false)):
		return false
	active["settled"] = true
	profile["active_run"] = active
	profile["best_score"] = maxi(int(profile.get("best_score", 0)), score)
	if won:
		var completed: Array = profile.get("completed_missions", [])
		if mission not in completed:
			completed.append(mission)
			completed.sort()
			profile["upgrade_points"] = int(profile.get("upgrade_points", 0)) + 2
		profile["completed_missions"] = completed
	save_now()
	return true


func save_now() -> bool:
	profile = _sanitize(profile)
	var absolute_dir := ProjectSettings.globalize_path(_directory)
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return _fail("无法创建存档目录（%d）。" % error)
	var temp_path := _path(PROFILE_FILE + ".tmp")
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		return _fail("无法写入临时存档。")
	temp.store_string(JSON.stringify(profile, "\t"))
	temp.flush()
	temp.close()
	var target_abs := ProjectSettings.globalize_path(_path(PROFILE_FILE))
	var backup_abs := ProjectSettings.globalize_path(_path(BACKUP_FILE))
	var backup_temp_abs := ProjectSettings.globalize_path(_path(BACKUP_FILE + ".tmp"))
	var temp_abs := ProjectSettings.globalize_path(temp_path)
	var backup_warning := ""
	if FileAccess.file_exists(_path(PROFILE_FILE)):
		DirAccess.remove_absolute(backup_temp_abs)
		var copy_error := DirAccess.copy_absolute(target_abs, backup_temp_abs)
		if copy_error != OK:
			DirAccess.remove_absolute(temp_abs)
			return _fail("无法创建存档备份（%d）。" % copy_error)
		DirAccess.remove_absolute(target_abs)
	var rename_error := DirAccess.rename_absolute(temp_abs, target_abs)
	if rename_error != OK:
		if FileAccess.file_exists(_path(BACKUP_FILE + ".tmp")):
			DirAccess.copy_absolute(backup_temp_abs, target_abs)
			DirAccess.remove_absolute(backup_temp_abs)
		return _fail("无法提交存档（%d）。" % rename_error)
	if FileAccess.file_exists(_path(BACKUP_FILE + ".tmp")):
		DirAccess.remove_absolute(backup_abs)
		var backup_error := DirAccess.rename_absolute(backup_temp_abs, backup_abs)
		if backup_error != OK:
			# The new primary is already valid; keep the recoverable temporary copy.
			backup_warning = "主存档已保存，但备份轮换失败（%d）。" % backup_error
	last_error = backup_warning
	profile_saved.emit()
	return true


func reset_for_tests() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(PROFILE_FILE)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(BACKUP_FILE)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(BACKUP_FILE + ".tmp")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(PROFILE_FILE + ".tmp")))
	profile = default_profile()


func _path(file_name: String) -> String:
	return _directory.path_join(file_name)


func _read_and_validate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	if int(parsed.get("schema_version", -1)) != SCHEMA_VERSION:
		return {}
	for required_key: String in ["completed_missions", "lifetime_kills", "best_score", "upgrade_points", "active_run"]:
		if not parsed.has(required_key):
			return {}
	return _sanitize(parsed)


func _sanitize(value: Dictionary) -> Dictionary:
	var result := default_profile()
	var completed: Array = []
	if value.get("completed_missions", []) is Array:
		for entry: Variant in value["completed_missions"]:
			if entry is int and entry >= 0 and entry < 18 and entry not in completed:
				completed.append(entry)
	completed.sort()
	result["completed_missions"] = completed
	result["lifetime_kills"] = clampi(int(value.get("lifetime_kills", 0)), 0, 1000000000)
	result["best_score"] = clampi(int(value.get("best_score", 0)), 0, 1000000000)
	result["upgrade_points"] = clampi(int(value.get("upgrade_points", 0)), 0, 1000)
	result["tank_level"] = _level_for_kills(int(result["lifetime_kills"]))
	result["selected_chassis"] = clampi(int(value.get("selected_chassis", 1)), 0, 2)
	result["selected_weapon"] = clampi(int(value.get("selected_weapon", 0)), 0, 6)
	var active: Variant = value.get("active_run", {})
	if active is Dictionary and active.get("id", "") is String and not active.get("id", "").is_empty() and active.get("id", "").length() <= 100:
		result["active_run"] = {
			"id": active.get("id", ""),
			"credited_kills": clampi(int(active.get("credited_kills", 0)), 0, 1000000000),
			"settled": bool(active.get("settled", false)),
		}
	return result


func _level_for_kills(kills: int) -> int:
	# Mirrors the campaign's accelerating thirty-level career without coupling saves to combat scenes.
	var level := 1
	var requirement := 3
	while level < 30 and kills >= requirement:
		level += 1
		requirement += 4 + int(pow(float(level - 1), 1.18))
	return level


func _fail(message: String) -> bool:
	last_error = message
	save_failed.emit(message)
	push_error(message)
	return false
