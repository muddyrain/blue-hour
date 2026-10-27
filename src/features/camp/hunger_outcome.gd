class_name HungerOutcome
extends RefCounted
## DD-WEB-001/003 candidate only. Never selects victims or mutates crew/save data.


static func candidate(ledger: Dictionary) -> Dictionary:
	if ledger.is_empty():
		return {"loss_count":0,"victim_ids":[],"applied":false}
	return {"loss_count":mini(int(ledger.food_shortage), ledger.ration_member_ids.size()),
		"victim_ids":[],"applied":false}


static func description(ledger: Dictionary) -> String:
	var result: Dictionary = candidate(ledger)
	if int(result.loss_count) == 0:
		return "本次口粮足够。"
	return "缺粮 %d：成员损失候选 %d 人，尚未应用；原作可能减员。" % [ledger.food_shortage, result.loss_count]
