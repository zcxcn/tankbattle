class_name CampaignProgress
extends RefCounted

var lifetime_kills: int = 0
var active_run_id: String = ""
var active_run_credited_kills: int = 0
var active_run_settled: bool = false

const MAX_LIFETIME_KILLS: int = 1_000_000_000


func begin_run(run_id: String) -> bool:
	if run_id.is_empty() or run_id.length() > 100:
		return false
	active_run_id = run_id
	active_run_credited_kills = 0
	active_run_settled = false
	return true


## Accepts a cumulative kill count and returns only the newly credited delta.
func credit_run_kills(run_id: String, cumulative_kills: int) -> int:
	if (
		run_id != active_run_id
		or active_run_settled
		or cumulative_kills < 0
		or cumulative_kills > MAX_LIFETIME_KILLS
		or cumulative_kills <= active_run_credited_kills
	):
		return 0
	var delta := cumulative_kills - active_run_credited_kills
	active_run_credited_kills = cumulative_kills
	lifetime_kills = mini(MAX_LIFETIME_KILLS, lifetime_kills + delta)
	return delta


func settle_run(run_id: String, cumulative_kills: int) -> bool:
	if (
		run_id != active_run_id
		or active_run_settled
		or cumulative_kills < 0
		or cumulative_kills > MAX_LIFETIME_KILLS
	):
		return false
	credit_run_kills(run_id, cumulative_kills)
	active_run_settled = true
	return true


func to_save_dictionary() -> Dictionary[String, Variant]:
	var active_run: Variant = null
	if not active_run_id.is_empty():
		active_run = {
			"id": active_run_id,
			"credited_kills": active_run_credited_kills,
			"settled": active_run_settled,
		}
	return {
		"schema_version": 1,
		"kills": lifetime_kills,
		"active_run": active_run,
	}
