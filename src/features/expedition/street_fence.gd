class_name StreetFence
extends Node2D
## The visible posts and rail sit exactly on the authored navigation blocker.

var footprint: Rect2


func _draw() -> void:
	IsoDraw.wall(self, footprint.size.x, maxf(footprint.size.y, 10.0))
