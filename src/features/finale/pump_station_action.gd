class_name PumpStationAction
extends RefCounted
## A fixed level within the existing exploration, work and settlement protocol.

const VERSION: int = 1
const CONSOLE: StringName = &"cash"
const WORK_SECONDS: float = 5.0
const TITLE: String = "突破封锁 · 河堤泵站"
static var _checked: ActionMemo = ActionMemo.new(32)


static func enabled(generated: Dictionary) -> bool:
	return generated.get("version") == 9 and generated.get("finale_policy") == VERSION


static func stopped(facts: Variant) -> bool:
	if not facts is Dictionary:
		return false
	var console: Variant = facts.get(String(CONSOLE))
	return console is Dictionary and console.get("searched") == true


static func freeze(context: Dictionary) -> Dictionary:
	var task: Dictionary = TaskActions._make(context.seed, int(context.day), int(context.slot),
		"supply", "industrial", "medium", 0)
	var value: Dictionary = ExplorationActions.source_from_task(task, context)
	if value.is_empty() or not value.campaign.is_finale or not PersonaActions.problem(value).is_empty():
		return {}
	var layout: Dictionary = PumpStationLayout.freeze()
	value.version = 9
	value.finale_policy = VERSION
	value.mission_policy = 1
	if FirstAidV1.enabled(context):
		value.first_aid_policy = FirstAidV1.VERSION
	if CampaignPressureV1.enabled(context):
		value.campaign_pressure = CampaignPressureV1.marker(int(context.day) - 2)
	value.worldgen = WorldgenLayout.policy(true)
	value.layout = layout
	value.cash = 0
	value.food = 0
	value.weapons = 0
	value.build.drops = []
	value.powers.sample = ""
	value.encounter.position = layout.pump_station.boss.duplicate()
	value.sites = [{"id":String(CONSOLE), "kind":"cash", "amount":0, "weapon":false,
		"building":"", "work_mode":"outdoor", "seconds":WORK_SECONDS, "point":layout.pump_station.console.duplicate()}]
	value.objective = {"task_id":value.id, "site_ids":[String(CONSOLE)], "member_id":0}
	value.exploration = {"version":1, "optional_objectives":[]}
	value.route_length = 0
	if value.powers.version == SpecialPowers.WAVE_VERSION:
		value = ContentWaveV1.freeze_action(value)
	return value


static func problem(value: Dictionary) -> String:
	if value.has("campaign_pressure") and not CampaignPressureV1.enabled(value):
		return "CAMPAIGN_PRESSURE_ACTION_POLICY"
	if not enabled(value) or not SurvivalContracts.json_value(value) or not _identity(value.get("seed")) \
			or not SurvivalContracts.integer(value.get("day"), 2, RunSave.MAX_COUNTER) \
			or not SurvivalContracts.integer(value.get("slot"), 0, 2):
		return "PUMP_ACTION_IDENTITY"
	var identity: String = RecordEncoding.fingerprint(value)
	if _checked.lookup(identity) == true:
		return ""
	var campaign: Variant = value.get("campaign")
	var build: Variant = value.get("build")
	var powers: Variant = value.get("powers")
	var persona: Variant = value.get("persona")
	if not campaign is Dictionary or not _identity(campaign.get("run_id")) \
			or not SurvivalContracts.integer(campaign.get("preparations"), CampaignRules.PREPARATIONS, CampaignRules.PREPARATIONS) \
			or not build is Dictionary or not build.get("owned") is Array or not build.get("slots") is Array \
			or not powers is Dictionary or not powers.get("owned") is Array or not PowerState.action_inventory_valid(powers.owned, PowerState.loadout(powers), int(value.day)) \
			or not persona is Dictionary or not persona.get("facts") is Dictionary:
		return "PUMP_ACTION_CONTEXT"
	var expected: Dictionary = freeze(value)
	if expected.is_empty() or identity != RecordEncoding.fingerprint(expected):
		return "PUMP_ACTION_CANONICAL"
	_checked.store(identity, true)
	return ""


static func supply(value: Dictionary) -> MissionSupply:
	var result: MissionSupply = MissionSupply.new()
	result.id = StringName(TaskActions.CONFIG.supply.mission)
	result.display_name = TITLE
	result.description = "前往控制柜停机，击败破阵者并归航。\n装卸道较短，检修道的折角墙可作掩护。"
	result.cash_reward = 0
	result.food_reward = 0
	result.has_weapon_sample = false
	result.generated = value.duplicate(true)
	result.layout = PumpStationLayout.resource(value.layout)
	return result


static func _identity(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number(false)
