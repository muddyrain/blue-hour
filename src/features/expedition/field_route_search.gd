class_name FieldRouteSearch
extends RefCounted
## Precise indexed JPS; loaded as an explicit dependency, never an Autoload.

static var _loader: FieldRouteKernelLoader = FieldRouteKernelLoader.new()
static var _load_mutex: Mutex = Mutex.new()
var _kernel: RefCounted


static func prepare_backend() -> void:
	_load_mutex.lock()
	_loader.prepare()
	_load_mutex.unlock()


func configure(size: Vector2i, solids: Array[Rect2i]) -> void:
	_load_mutex.lock()
	_kernel = _loader.create_kernel()
	_load_mutex.unlock()
	if _kernel == null:
		return
	var input: PackedInt32Array = [size.x, size.y, solids.size()]
	for box: Rect2i in solids:
		input.append_array(PackedInt32Array([box.position.x, box.position.y, box.size.x, box.size.y]))
	var ready: PackedInt32Array = _kernel.call(&"route", input)
	if ready != PackedInt32Array([1]):
		_kernel = null
		print("BH_NAVIGATION fallback: kernel configuration failed; strict full validation enabled")


func path(grid: AStarGrid2D, from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if _kernel == null:
		return grid.get_point_path(from, to)
	var cells: PackedInt32Array = _kernel.call(&"route", PackedInt32Array([0, from.x, from.y, to.x, to.y]))
	var result: PackedVector2Array = []
	result.resize(cells.size() / 2)
	for index: int in range(result.size()):
		result[index] = grid.get_point_position(Vector2i(cells[index * 2], cells[index * 2 + 1]))
	return result
