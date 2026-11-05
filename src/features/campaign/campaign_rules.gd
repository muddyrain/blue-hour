class_name CampaignRules
extends RefCounted
## PROJECT_TEMP short-run V1. Pure policy; settlement owns all progression writes.

const VERSION: int = 1
const MODE: String = "short_v1"
const PREPARATIONS: int = 4
const BREAKOUT_INTERVAL: float = 0.90
const KEYS: Array[String] = ["version","mode","run_id","preparations","outcome","result_transaction"]


static func initial(run_id: String) -> Dictionary:
	assert(_identity(run_id))
	return {"version":VERSION,"mode":MODE,"run_id":run_id,"preparations":0,"outcome":"ACTIVE","result_transaction":""}


static func problem(value: Variant, run_id: String = "") -> String:
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


static func context(value: Dictionary) -> Dictionary:
	assert(problem(value).is_empty())
	var count: int = int(value.preparations)
	var stage: String = "finale" if count==PREPARATIONS else "breakout" if count>=2 else "preparation"
	return {"version":VERSION,"stage":stage,"is_finale":stage=="finale","pressure":BREAKOUT_INTERVAL if stage=="breakout" else 1.0}


static func can_depart(value: Dictionary) -> bool:
	return problem(value).is_empty() and value.outcome=="ACTIVE"


static func display(value: Dictionary) -> Dictionary:
	var action: Dictionary = context(value)
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
