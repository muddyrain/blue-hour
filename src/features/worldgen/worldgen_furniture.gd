class_name WorldgenFurniture
extends Node2D
## Static frozen scenery, no input, timers, search sites or gameplay state.
var detail: Dictionary


func _ready() -> void:
	var kind: String = str(detail.get("kind", detail.get("slot", "")))
	var art: String = IsoBuildingArt.prop_for(kind, int(detail.get("variant", 0)))
	if not art.is_empty():
		IsoAtlas.attach(self, art)
		set_meta("iso_kind", kind)


func _draw() -> void:
	if has_meta("iso_art"):
		return
	var kind: String = str(detail.get("kind", detail.get("slot", "")))
	var width: float = float(detail.get("width", 36.0))
	if kind == "wall" or kind == "courtyard_edge":
		IsoDraw.wall(self, maxf(width, 16.0), 16.0)
	elif kind == "lamp" or kind.ends_with("lamp") or kind == "LAMP":
		IsoDraw.lamp(self)
	elif "tree" in kind or "planter" in kind:
		IsoDraw.tree(self) if "tree" in kind else IsoDraw.planter(self)
	elif "crate" in kind or "box" in kind:
		IsoDraw.crate(self)
	elif "vending" in kind:
		IsoDraw.vending(self)
	else:
		IsoDraw.box(self, Vector2(maxf(width * 0.35, 22.0), 20.0), 28.0, IsoDraw.ROOF, IsoDraw.WALL_LEFT, IsoDraw.WALL_RIGHT)
