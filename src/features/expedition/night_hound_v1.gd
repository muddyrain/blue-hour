class_name NightHoundV1
extends RefCounted
## PROJECT_TEMP. The ordinary spawn ledger retains the one allocation after defeat.

const VERSION: int = 1
const KIND: String = "night_hound_v1"
const HP: float = 32.0
const SPEED: float = 64.0
const RANGE: float = 28.0
const WINDUP: float = 0.45
const DAMAGE: float = 5.0
const INTERVAL: float = 0.90
const POLICY: Dictionary = {"version":VERSION, "kind":KIND, "hp":HP, "speed":SPEED,
	"range":RANGE, "windup":WINDUP, "damage":DAMAGE, "interval":INTERVAL,
	"first_stage":ThreatDirector.Stage.NIGHT}


static func campaign_enabled(campaign: Variant) -> bool:
	return ContentWaveV1.campaign_enabled(campaign) 		and SurvivalContracts.integer(campaign.get("night_hound_policy"), VERSION, VERSION)


static func enabled(action: Dictionary) -> bool:
	return ContentWaveV1.eligible(action) 		and SurvivalContracts.integer(action.get("night_hound_policy"), VERSION, VERSION)


static func ordinary_slot(rolled: String, kind: String, stage: int) -> bool:
	return stage >= ThreatDirector.Stage.NIGHT and rolled == EnemyRules.NORMAL 		and kind not in [ScreamerPolicyV1.KIND, BurstRuntimeV1.KIND]


static func enemy_problem(row: Dictionary, world: Dictionary, summoned: bool) -> String:
	var actor: Dictionary = row.state
	var behavior: Dictionary = row.behavior
	var source: Dictionary = world.combat.spawns.get(str(int(actor.actor_id)), {})
	if summoned or not enabled(world.generated) or source.get("kind") != KIND 			or source.get("stage") != behavior.spawn_stage or behavior.spawn_stage < ThreatDirector.Stage.NIGHT:
		return "HOUND_ENEMY_SOURCE"
	if actor.max_health != HP or actor.speed != SPEED or actor.cooldown > INTERVAL 			or behavior.state not in ["chase", "windup"] or behavior.windup_remaining < 0.0 			or behavior.windup_remaining > WINDUP:
		return "HOUND_ENEMY_STATS"
	var target: Dictionary = SortieSnapshot._member(world.survivors, int(behavior.target_id))
	if behavior.state == "windup":
		# The locked target may have moved or died. The bite will recheck it at release.
		if target.is_empty() or actor.activity != FieldActor.Activity.IDLE or actor.cooldown != 0.0 				or not actor.path.is_empty():
			return "HOUND_ENEMY_WINDUP"
	elif behavior.windup_remaining != 0.0 or (behavior.target_id != 0 and (target.is_empty() 			or target.state.health <= 0.0 or not target.state.visible 			or int(target.state.activity) in [FieldActor.Activity.SEARCHING, FieldActor.Activity.DOWN])):
		return "HOUND_ENEMY_TARGET"
	return ""
