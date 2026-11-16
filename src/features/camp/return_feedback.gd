class_name ReturnFeedback
extends RefCounted
## Shared wording for the frozen food ledger and its saved camp copy.


static func food_text(ledger: Dictionary) -> String:
	var field: String = "带回 %d 粮 · 入库 %d 粮 · 溢出 %d 粮" % [ledger.food_found, ledger.food_stored, ledger.food_overflow]
	if int(ledger.get("facility_food", 0)) > 0:
		var offered: int = int(ledger.facility_food)
		var stored: int = int(ledger.facility_stored)
		field += "\n设施供粮 %d · 入库 %d · 溢出 %d" % [offered, stored, offered - stored]
	return field + "\n口粮消耗 %d 粮 · 营地余 %d 粮" % [ledger.food_consumed, ledger.food_after]


static func forecast(day: int, crew: Array, departure: Dictionary, food: int, found: int,
		per_member: int) -> Dictionary:
	# The same capped ledger as FrozenSettlement, with today's living departure
	# members and pre-departure facilities. This is a proposal, never a payout.
	return CampEconomy.post_battle_food(day, FieldJoinRules.meal_members(crew, departure),
		food, found, per_member, true, CampFacilities.offered_food(departure, day, true))


static func forecast_text(ledger: Dictionary) -> String:
	if ledger.is_empty():
		return "若归航：口粮预估暂不可用"
	return "若归航：本餐需 %d 粮 · 缺 %d 粮 · 餐后余 %d 粮" % [
		ledger.food_required, ledger.food_shortage, ledger.food_after]


static func return_text(battle: Dictionary, crew: Array, deaths: Array,
		transaction_id: String) -> String:
	var returned: PackedStringArray = []
	var fallen: PackedStringArray = []
	var waiting: PackedStringArray = []
	for member: Dictionary in battle.get("member_results", []):
		var source: Dictionary = SurvivorRoster.member(crew, int(member.id))
		var name: String = String(source.get("call_sign", "队员%d" % int(member.id)))
		if float(member.health) <= 0.0:
			fallen.append(name)
		elif battle.get("evacuated", false):
			returned.append(name)
		else:
			waiting.append(name)
	var text: String = "归航 %d 人：%s\n场内阵亡：%s" % [returned.size(),
		"、".join(returned) if not returned.is_empty() else "无",
		"、".join(fallen) if not fallen.is_empty() else "无"]
	if not waiting.is_empty():
		text += "\n未登车：" + "、".join(waiting)
	var starved: PackedStringArray = []
	for death: Dictionary in deaths:
		if death.transaction_id == transaction_id and death.cause in ["STARVATION", "HUNGER"]:
			var member: Dictionary = SurvivorRoster.member(crew, int(death.member_id))
			starved.append(String(member.get("call_sign", "队员%d" % int(death.member_id))))
	if not starved.is_empty():
		text += "\n餐后饥饿死亡：" + "、".join(starved)
	return text


static func result_heading(snapshot: Dictionary, battle: Dictionary) -> String:
	if snapshot.journey.state != "FAILED" and not CampaignState.ended(snapshot):
		return "幸存者归航" if battle.get("evacuated", false) else "未能归航"
	var current_deaths: Array = snapshot.journey.deaths.filter(func(death: Dictionary) -> bool:
		return death.transaction_id == snapshot.last_settlement_id)
	if current_deaths.any(func(death: Dictionary) -> bool: return death.cause in ["STARVATION", "HUNGER"]):
		return "旅程结束 · 口粮耗尽"
	var results: Array = battle.get("member_results", [])
	if not results.is_empty() and results.all(func(member: Dictionary) -> bool: return float(member.health) <= 0.0):
		return "旅程结束 · 全员阵亡"
	return "旅程结束 · 未能归航"
