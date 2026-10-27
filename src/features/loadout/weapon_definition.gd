class_name WeaponDefinition
extends Resource
## Project sample parameters, never inferred from the reference weapon's appearance.

@export var id: StringName
@export var display_name: String
@export var presentation: WeaponPresentation
@export var damage: float = 18.0
@export var interval: float = 0.65
@export var shot_range: float = 210.0
@export var repair_cost: int = 10
