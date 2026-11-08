class_name CampaignRules
extends RefCounted
## PROJECT_TEMP short-run V1. Pure policy; settlement owns all progression writes.

const VERSION: int = 1
const MODE: String = "short_v1"
const PREPARATIONS: int = 4
const BREAKOUT_INTERVAL: float = 0.90
const KEYS: Array[String] = ["version","mode","run_id","preparations","outcome","result_transaction"]
const INVESTIGATION_VERSION: int = 2
const INVESTIGATION_MODE: String = "investigation_v1"
const MISSION_VERSION: int = 3
const MISSION_MODE: String = "mission_v1"
const ACTION_POLICY_VERSION: int = 1
const CLUE_IDS: Array[String] = ["dispatch_log", "checkpoint_pass"]
const CLUE_NAMES: Dictionary[String, String] = {"dispatch_log":"线路调度记录", "checkpoint_pass":"封锁通行记录"}
const INVESTIGATION_KEYS: Array[String] = ["version","mode","run_id","clues","outcome","result_transaction"]


static func initial(run_id: String) -> Dictionary:
	assert(_identity(run_id))
	return {"version":VERSION,"mode":MODE,"run_id":run_id,"preparations":0,"outcome":"ACTIVE","result_transaction":""}


static func initial_investigation(run_id: String) -> Dictionary:
	assert(_identity(run_id))
	return {"version":INVESTIGATION_VERSION, "mode":INVESTIGATION_MODE, "run_id":run_id,
		"clues":[], "outcome":"ACTIVE", "result_transaction":""}


static func initial_mission(run_id: String, action_choices: bool = false, midgame: bool = false,
		pump_station: bool = false, rare_sorties: bool = false) -> Dictionary:
	var value: Dictionary = initial_investigation(run_id)
	value.version = MISSION_VERSION
	value.mode = MISSION_MODE
	if action_choices or midgame:
		value.action_policy = ACTION_POLICY_VERSION
	if midgame:
		value.midgame = CampFacilities.initial()
	if midgame and pump_station:
		value.finale_policy = 1
		if rare_sorties:
			value.rare_policy = RareSortie.VERSION
	return value


static func is_mission(value: Variant) -> bool:
	return value is Dictionary and value.get("version") == MISSION_VERSION and value.get("mode") == MISSION_MODE


static func action_choices_enabled(value: Variant) -> bool:
	return is_mission(value) and SurvivalContracts.integer(value.get("action_policy"), ACTION_POLICY_VERSION, ACTION_POLICY_VERSION)


static func midgame_enabled(value: Variant) -> bool:
	return action_choices_enabled(value) and CampFacilities.marker_problem(value.get("midgame")).is_empty()

static func pump_station_enabled(value: Variant) -> bool:
	return midgame_enabled(value) and SurvivalContracts.integer(value.get("finale_policy"), 1, 1)


static func rare_sorties_enabled(value: Variant) -> bool:
	return pump_station_enabled(value) and SurvivalContracts.integer(value.get("rare_policy"), RareSortie.VERSION, RareSortie.VERSION)


static func is_investigation(value: Variant) -> bool:
	return is_mission(value) or (value is Dictionary and value.get("version") == INVESTIGATION_VERSION and value.get("mode") == INVESTIGATION_MODE)


static func next_clue(value: Dictionary) -> String:
	var count: int = value.clues.size()
	return CLUE_IDS[count] if count < CLUE_IDS.size() else ""


static func problem(value: Variant, run_id: String = "") -> String:
	if is_investigation(value):
		return _investigation_problem(value, run_id)
	if not value is Dictionary or value.size()!=KEYS.size() or not value.has_all(KEYS):
		return "CAMPAIGN_FIELDS"
	if not SurvivalContracts.integer(value.version,VERSION,VERSION) or value.mode!=MODE:
		return "CAMPAIGN_VERSION"
	if not value.run_id is String or not _identity(value.run_id) or (not run_id.is_empty() and value.run_id!=run_id):
		return "CAMPAIGN_IDENTITY"
	if not SurvivalContracts.integer(value.preparations,0,PREPARATIONS) or not value.outcome is String or value.outcome not in ["ACTIVE","VICTORY","DEFEAT"] or not value.result_transaction is String:
		return "CAMPAIGN_VALUES"
	if value.outcome=="ACTIVE":
		return "" if value.result_transaction.is_empty() else "CAMPAIGN_ACTIVE_RESULT"
	var parts: PackedStringArray = value.result_transaction.split(":")
	if parts.size()!=2 or parts[0]!=value.run_id or not parts[1].is_valid_int() or int(parts[1])<maxi(1,int(value.preparations)) or parts[1]!=str(int(parts[1])):
		return "CAMPAIGN_RESULT_BINDING"
	if value.outcome=="VICTORY" and (int(value.preparations)!=PREPARATIONS or int(parts[1])<=PREPARATIONS):
		return "CAMPAIGN_VICTORY_PREPARATIONS"
	return ""


static func _investigation_problem(value: Dictionary, run_id: String) -> String:
	var version: int = MISSION_VERSION if is_mission(value) else INVESTIGATION_VERSION
	var has_action_policy: bool = value.has("action_policy")
	var has_midgame: bool = value.has("midgame")
	var has_finale: bool = value.has("finale_policy")
	var has_rare: bool = value.has("rare_policy")
	if value.size() != INVESTIGATION_KEYS.size() + int(has_action_policy) + int(has_midgame) + int(has_finale) + int(has_rare) or not value.has_all(INVESTIGATION_KEYS) or not SurvivalContracts.integer(value.version,version,version):
		return "INVESTIGATION_FIELDS"
	if has_action_policy and not action_choices_enabled(value):
		return "INVESTIGATION_ACTION_POLICY"
	if has_midgame and not midgame_enabled(value):
		return "MIDGAME_CAMPAIGN_POLICY"
	if has_finale and not pump_station_enabled(value):
		return "PUMP_CAMPAIGN_POLICY"
	if has_rare and not rare_sorties_enabled(value):
		return "RARE_CAMPAIGN_POLICY"
	if not value.run_id is String or not _identity(value.run_id) or (not run_id.is_empty() and run_id != value.run_id):
		return "INVESTIGATION_IDENTITY"
	if not value.clues is Array or value.clues.size() > CLUE_IDS.size() or value.outcome not in ["ACTIVE","VICTORY","DEFEAT"] or not value.result_transaction is String:
		return "INVESTIGATION_VALUES"
	var previous: int = 0
	for index: int in range(value.clues.size()):
		var clue: Variant = value.clues[index]
		if not clue is Dictionary or clue.size() != 4 or not clue.has_all(["id","transaction_id","action_id","site_id"]):
			return "INVESTIGATION_CLUE_FIELDS"
		if clue.id != CLUE_IDS[index] or clue.site_id != "cash" or not clue.action_id is String or clue.action_id.length() != 64 or not clue.action_id.is_valid_hex_number(false):
			return "INVESTIGATION_CLUE_IDENTITY"
		var ordinal: int = _transaction_ordinal(clue.transaction_id, value.run_id)
		if ordinal <= previous:
			return "INVESTIGATION_CLUE_TRANSACTION"
		previous = ordinal
	if value.outcome == "ACTIVE":
		return "" if value.result_transaction.is_empty() else "INVESTIGATION_ACTIVE_RESULT"
	if _transaction_ordinal(value.result_transaction, value.run_id) <= previous:
		return "INVESTIGATION_RESULT_BINDING"
	return "INVESTIGATION_VICTORY_CLUES" if value.outcome == "VICTORY" and not next_clue(value).is_empty() else ""


static func _transaction_ordinal(identity: Variant, run_id: String) -> int:
	if not identity is String:
		return 0
	var parts: PackedStringArray = identity.split(":")
	if parts.size() != 2 or parts[0] != run_id or not parts[1].is_valid_int():
		return 0
	var ordinal: int = int(parts[1])
	return ordinal if parts[1] == str(ordinal) and ordinal > 0 else 0


static func context(value: Dictionary) -> Dictionary:
	assert(problem(value).is_empty())
	if is_investigation(value):
		var finale: bool = next_clue(value).is_empty()
		return {"version":int(value.version),"stage":"finale" if finale else "investigation","is_finale":finale,"pressure":1.0}
	var count: int = int(value.preparations)
	var stage: String = "finale" if count==PREPARATIONS else "breakout" if count>=2 else "preparation"
	return {"version":VERSION,"stage":stage,"is_finale":stage=="finale","pressure":BREAKOUT_INTERVAL if stage=="breakout" else 1.0}


static func can_depart(value: Dictionary) -> bool:
	return problem(value).is_empty() and value.outcome=="ACTIVE"


static func display(value: Dictionary) -> Dictionary:
	var action: Dictionary = context(value)
	if is_investigation(value):
		var clue_progress: String = "调查线索 %d/%d" % [value.clues.size(), CLUE_IDS.size()]
		if value.outcome != "ACTIVE":
			return {"title":"旅程胜利" if value.outcome == "VICTORY" else "旅程失败",
				"detail":"本旅程已结束，可查看队伍与结果，或开始新旅程。","progress":clue_progress}
		if action.is_finale:
			if pump_station_enabled(value):
				return {"title":"突破封锁 · 河堤泵站","detail":"停机后击败破阵者，再集合并确认归航。提前撤离会保留线索，可再次挑战。",
					"progress":clue_progress + " · 泵站已开放"}
			return {"title":"终局 · 突破封锁","detail":"可继续补给。击败破阵者并确认归航才获胜，提前撤离后可重试。",
				"progress":clue_progress + " · 终局已开放"}
		return {"title":"街区调查","detail":"下一份线索：%s。搜索标记建筑并确认归航。" % CLUE_NAMES[next_clue(value)],
			"progress":clue_progress}
	var progress: String = "准备归航 %d/%d" % [int(value.preparations),PREPARATIONS]
	if value.outcome!="ACTIVE":
		return {"title":"旅程胜利" if value.outcome=="VICTORY" else "旅程失败","detail":"本旅程已结束，可查看队伍与结果，或开始新旅程。","progress":progress}
	if action.is_finale:
		return {"title":"终局 · 突破封锁","detail":"击败破阵者后返回巴士；确认归航保存成功才获胜。提前撤离后可再次挑战。","progress":progress+" · 终局已开放"}
	var title: String = "阶段 2 · 突围" if action.stage=="breakout" else "阶段 1 · 筹备"
	var detail: String = "刷怪基础间隔 ×0.90；暮色与夜间压力在此基础上应用。" if action.stage=="breakout" else "沿用当前自然敌人与刷怪基线。"
	return {"title":title,"detail":detail+" 提前撤离并确认归航也消耗一次准备机会。","progress":progress+" · 本次准备 %d/%d" % [int(value.preparations)+1,PREPARATIONS]}


static func _identity(value: String) -> bool:
	return value.length()==32 and value.is_valid_hex_number(false)
