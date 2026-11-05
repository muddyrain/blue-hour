class_name WeaponDefinition
extends Resource
## Project sample parameters, never inferred from the reference weapon's appearance.

const MAGAZINES: Dictionary = {"carbine":{"capacity":12,"seconds":1.6},"long_rifle":{"capacity":5,"seconds":2.2}} # PROJECT_TEMP V1

@export var id: StringName
@export var display_name: String
@export var presentation: WeaponPresentation
@export var damage: float = 18.0
@export var interval: float = 0.65
@export var shot_range: float = 210.0
@export var repair_cost: int = 10


func shot_interval(personal_factor: float = 1.0) -> float:
	return interval * personal_factor


func magazine_capacity() -> int:
	return int(CombatEquipment.magazine(String(id)).get("capacity",0))


func reload_seconds() -> float:
	return float(CombatEquipment.magazine(String(id)).get("seconds",0.0))
