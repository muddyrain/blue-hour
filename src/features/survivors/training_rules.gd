class_name TrainingRules
extends RefCounted
## PROJECT_TEMP one-food purchase. No I/O, dinner, XP, health or equipment side effects.

const RULESET: String = "BH_CAMP_TRAIT_TRAINING_V1"


static func edit_identity(identity: String, profile: String) -> bool:
	var parts: PackedStringArray = identity.split(":")
	return parts.size()==3 and parts[0]==profile and parts[1]=="edit" and parts[2].length()==32 and parts[2].is_valid_hex_number(false)


static func availability(before: Dictionary, member_id: int) -> String:
	if not (RescuePoolState.problem(before) if RescuePoolState.is_family(before) else TrainingState.problem(before)).is_empty() or before.journey.state!="ACTIVE":
		return "当前不是已确认的训练旅程营地。"
	var member: Dictionary = SurvivorRoster.member(before.crew,member_id)
	if member.is_empty() or member.health<=0 or not before.journey.active_member_ids.any(func(id: Variant) -> bool: return int(id)==member_id):
		return "只有已正式登记的存活幸存者可以训练。"
	if member_id>2 and not before.recruits.any(func(row: Dictionary) -> bool: return row.member_id==member_id and row.field_status=="RETURNED"):
		return "新同行必须成功归航登记后才能训练。"
	if member.growth.trait.level>=TraitRules.THRESHOLDS.size():
		return "已达当前Trait Lv5上限，不能购买训练。"
	if before.food<1:
		return "食物不足1份，未执行训练。"
	return ""


static func preview(before: Dictionary, member_id: int) -> Dictionary:
	var issue: String = availability(before,member_id)
	if not issue.is_empty():
		return {"error":issue}
	var member: Dictionary = SurvivorRoster.member(before.crew,member_id)
	var intent: Dictionary = {"ruleset_id":RULESET,"trait_ruleset_id":TraitRules.RULESET,
		"edit_id":before.profile_id+":edit:"+RunSave.new_profile_id(),"run_id":before.profile_id,
		"root_id":before.journey.root_id,"base_hash":SurvivalContracts.fingerprint(before),
		"member_id":member_id,"trait":member.growth.trait.duplicate(true),"cost":1,"gained":1}
	var request: Dictionary = {"kind":"train_trait","member_id":member_id,"value":JSON.stringify(intent)}
	var after: Dictionary = propose(before,request)
	return {"error":"", "request":request,"after":after,
		"risk":CampEconomy.rations(int(before.day),before.crew,int(after.food),RunSave.DefaultRules)}


static func intent_for(request: Dictionary) -> Dictionary:
	if not request.get("value") is String:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(request.value)!=OK or not parser.data is Dictionary:
		return {}
	return parser.data


static func propose(before: Dictionary, request: Dictionary) -> Dictionary:
	if request.size()!=3 or not request.get("kind") is String or request.kind!="train_trait" or not SurvivalContracts.integer(request.get("member_id"),1,5 if RescuePoolState.is_family(before) else 3) or not availability(before,int(request.member_id)).is_empty():
		return {}
	var intent: Dictionary = intent_for(request)
	if intent.size()!=10 or not intent.has_all(["ruleset_id","trait_ruleset_id","edit_id","run_id","root_id","base_hash","member_id","trait","cost","gained"]):
		return {}
	for key: String in ["ruleset_id","trait_ruleset_id","edit_id","run_id","root_id","base_hash"]:
		if not intent[key] is String:
			return {}
	if intent.ruleset_id!=RULESET or intent.trait_ruleset_id!=TraitRules.RULESET or intent.run_id!=before.profile_id or intent.root_id!=before.journey.root_id or intent.base_hash!=SurvivalContracts.fingerprint(before) or not edit_identity(intent.edit_id,before.profile_id) or not SurvivalContracts.integer(intent.member_id,int(request.member_id),int(request.member_id)) or not SurvivalContracts.integer(intent.cost,1,1) or not SurvivalContracts.integer(intent.gained,1,1) or not intent.trait is Dictionary:
		return {}
	var member: Dictionary = SurvivorRoster.member(before.crew,int(request.member_id))
	if not TransactionReceipt.same(intent.trait,member.growth.trait):
		return {}
	var after: Dictionary = before.duplicate(true)
	var target: Dictionary = SurvivorRoster.member(after.crew,int(request.member_id))
	target.growth.trait.progress += 1
	target.growth.trait.level = TraitRules.level_for(int(target.growth.trait.progress))
	after.food -= 1
	after.training.append({"ruleset_id":RULESET,"edit_id":intent.edit_id,"member_id":int(request.member_id),
		"trait_id":intent.trait.id,"progress_before":intent.trait.progress,"day":before.day,
		"food_before":before.food,"base_hash":intent.base_hash})
	return after if (RescuePoolState.problem(after) if RescuePoolState.is_family(after) else TrainingState.problem(after)).is_empty() else {}
