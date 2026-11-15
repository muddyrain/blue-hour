class_name CampaignPressureV1
extends RefCounted
## PROJECT_TEMP cross-day reinforcement pressure. Daily actions freeze the selected tier.

const VERSION: int = 1
const INTERVAL_FACTORS: Array[float] = [1.0, 0.9, 0.8]
const TIER_NAMES: Array[String] = ["I", "II", "III"]
const BLOCKADE_POLICY: Dictionary = {"version":1, "first_day":4, "period":3, "replacement_period":3}
const BLOCKADE_WARNING: String = "封锁夜预告 · 入夜后重压与疾奔结伴来袭；建议天黑前集合回车。"


static func blockade_night(action: Dictionary) -> bool:
	if not enabled(action) or int(action.day) < int(BLOCKADE_POLICY.first_day) or (int(action.day) - int(BLOCKADE_POLICY.first_day)) % int(BLOCKADE_POLICY.period) != 0:
		return false
	if action.get("campaign", {}).get("is_finale", false):
		return false
	for key: String in ["finale_policy", "investigation", "rare_policy", "event_sortie"]:
		if action.has(key):
			return false
	return true


static func blockade_kind(action: Dictionary, ordinary: String, index: int, stage: int) -> String:
	# Replace only ambient ordinary rolls, retaining special-species priority, cap,
	# safe entrances, interval and the original atmosphere / daylight curves.
	if not blockade_night(action) or stage < ThreatDirector.Stage.NIGHT or ordinary != EnemyRules.NORMAL:
		return ordinary
	if index % int(BLOCKADE_POLICY.replacement_period) == 0:
		return EnemyRules.HEAVY
	if index % int(BLOCKADE_POLICY.replacement_period) == 1:
		return EnemyRules.RUSH
	return ordinary


static func tier_for(settled_sorties: int) -> int:
	if settled_sorties >= 5:
		return 2
	if settled_sorties >= 3:
		return 1
	return 0


static func marker(settled_sorties: int) -> Dictionary:
	return {"version":VERSION, "tier":tier_for(settled_sorties)}


static func enabled(generated: Dictionary) -> bool:
	var pressure: Variant = generated.get("campaign_pressure")
	var day: Variant = generated.get("day")
	return (generated.get("version") == 9
		and SurvivalContracts.integer(generated.get("mission_policy"), 1, 1)
		and SurvivalContracts.integer(day, 2, RunSave.MAX_COUNTER)
		and pressure is Dictionary
		and pressure.size() == 2
		and SurvivalContracts.integer(pressure.get("version"), VERSION, VERSION)
		and SurvivalContracts.integer(pressure.get("tier"), 0, INTERVAL_FACTORS.size() - 1)
		# RunSave authenticates day == settled_sorties + 2 in every departure camp.
		and int(pressure.tier) == tier_for(int(day) - 2))


static func spawn_factor(generated: Dictionary) -> float:
	var campaign: Dictionary = generated.get("campaign", {})
	var original: float = float(campaign.get("pressure", 1.0))
	if not enabled(generated):
		return original
	return original * INTERVAL_FACTORS[int(generated.campaign_pressure.tier)]


static func label(tier: int) -> String:
	return "跨日敌情 %s · 增援间隔 ×%.2f" % [TIER_NAMES[tier], INTERVAL_FACTORS[tier]]
