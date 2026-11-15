class_name StationGround
extends Node2D
## Flat rail bed and a low platform sit below the shared Y-sorted actors.


func _ready() -> void:
	for row: Dictionary in [
		{"art":"station/track.svg", "point":Vector2(1216, 288)},
		{"art":"station/platform.svg", "point":Vector2(1232, 448)},
	]:
		var prop: Node2D = Node2D.new()
		IsoAtlas.attach(prop, row.art)
		prop.position = IsoSpace.to_view(row.point)
		add_child(prop)
