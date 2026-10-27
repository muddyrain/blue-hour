class_name WeaponPresentation
extends Resource
## Local rendering data only; changing this resource cannot alter combat rules.

@export var id: StringName = &"carbine"
@export var display_name: String = "卡宾枪"
@export var texture: Texture2D
@export var grip_pixel: Vector2 = Vector2.ZERO
@export var muzzle_pixel: Vector2 = Vector2.ZERO
@export var display_scale: float = 0.17
@export var direction_layers: PackedInt32Array = PackedInt32Array([2, 0, 2])
@export var direction_scales: PackedVector2Array = PackedVector2Array([
	Vector2.ONE, Vector2(1.0, -1.0), Vector2(0.70, 1.0),
])
