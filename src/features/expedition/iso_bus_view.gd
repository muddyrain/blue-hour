class_name IsoBusView
extends Node2D
## Procedural cream minibus placeholder. The parent sprite holds the logical-to-view position.


func _ready() -> void:
	z_as_relative = true
	position = Vector2.ZERO


func _draw() -> void:
	IsoDraw.bus(self)
