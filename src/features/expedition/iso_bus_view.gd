class_name IsoBusView
extends Node2D
## Cream minibus sprite. The parent sprite holds the logical-to-view position.


func _ready() -> void:
	z_as_relative = true
	position = Vector2.ZERO
	IsoAtlas.attach(self, "props/bus.png")


func _draw() -> void:
	pass
