class_name ReturnFeedback
extends RefCounted
## Shared wording for the frozen food ledger and its saved camp copy.


static func food_text(ledger: Dictionary) -> String:
	return "带回 %d 粮 · 入库 %d 粮 · 溢出 %d 粮\n口粮消耗 %d 粮 · 营地余 %d 粮" % [
		ledger.food_found, ledger.food_stored, ledger.food_overflow,
		ledger.food_consumed, ledger.food_after,
	]
