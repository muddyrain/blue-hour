class_name SurvivorDefinition
extends Resource
## Original identity/display data; no unverified progression bonuses.

@export var id: StringName
@export var member_id: int
@export var default_display_name: String
@export var gender: StringName
@export var colour: Color
@export var portrait: Texture2D
@export var visual_variant: int = -1


func gender_text() -> String:
	match gender:
		&"male":
			return "♂ 男"
		&"female":
			return "♀ 女"
	return "未设"
