class_name WorldFurniture
extends Node2D
## Small original environment modules. Decorative and traversable by design.
var kind: String = "lamp"
var refined: bool = false
var variant: int = 0


func _ready() -> void:
	var art: String = IsoBuildingArt.prop_for(kind, variant)
	if not art.is_empty():
		IsoAtlas.attach(self, art)
		set_meta("iso_kind", kind)


func _draw() -> void:
	if has_meta("iso_art"):
		return
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
