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
