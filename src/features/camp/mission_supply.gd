class_name MissionSupply
extends Resource
## Source-specific sample rewards; source categories have evidence, amounts do not.

@export var id: StringName = &"supermarket"
@export var display_name: String = "超市"
@export_multiline var description: String = "东侧食物补给；北侧可搜集货币。"
@export_range(0, 1000) var cash_reward: int = 4
@export_range(0, 1000) var food_reward: int = 3
@export var has_weapon_sample: bool = true
@export var layout: StreetLayout


func supports(kind: StringName) -> bool:
	return (kind == &"cash" and cash_reward > 0) or (kind == &"food" and food_reward > 0)


func reward(kind: StringName) -> int:
	return cash_reward if kind == &"cash" else (food_reward if kind == &"food" else 0)
