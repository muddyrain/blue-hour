class_name CampRules
extends Resource
## TMP-115/116: sample seed and historical one-ration candidate; see source table.

const FOOD_LIMIT: int = 1_000_000_000

@export_range(0, 1000) var initial_food: int = 2
@export_range(0, 1000) var v1_migration_food: int = 2
@export_range(1, 100) var ration_per_member: int = 1
