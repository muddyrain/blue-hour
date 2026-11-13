class_name WorldFurniture
extends Node2D
## Small original vector environment modules. Decorative and traversable by design.
var kind: String = "lamp"
var refined: bool = false
var variant: int = 0
func _draw() -> void:
	match kind:
		"lamp":
			IsoDraw.lamp(self)
		"planter":
			IsoDraw.planter(self)
		"crate":
			IsoDraw.crate(self)
		"fence":
			IsoDraw.wall(self, 100.0, 12.0)
		_:
			IsoDraw.tree(self)
