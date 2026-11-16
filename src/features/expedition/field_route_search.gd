class_name FieldRouteSearch
extends RefCounted
## Precise indexed JPS; loaded as an explicit dependency, never an Autoload.

const KERNEL: GDExtension = preload("res://src/features/expedition/native/route_kernel.gdextension")
var _kernel: RefCounted = ClassDB.instantiate(&"FieldRouteKernel") as RefCounted


func configure(size: Vector2i, solids: Array[Rect2i]) -> void:
	var input: PackedInt32Array = [size.x, size.y, solids.size()]
	for box: Rect2i in solids:
		input.append_array(PackedInt32Array([box.position.x, box.position.y, box.size.x, box.size.y]))
	_kernel.call(&"route", input)


func path(grid: AStarGrid2D, from: Vector2i, to: Vector2i) -> PackedVector2Array:
	var cells: PackedInt32Array = _kernel.call(&"route", PackedInt32Array([0, from.x, from.y, to.x, to.y]))
	var result: PackedVector2Array = []
	result.resize(cells.size() / 2)
	for index: int in range(result.size()):
		result[index] = grid.get_point_position(Vector2i(cells[index * 2], cells[index * 2 + 1]))
	return result
