class_name ReconKnowledge
extends RefCounted
## A row-major, least-significant-bit-first bitmap aligned with the frozen map.

var bounds: Rect2
var columns: int
var rows: int
var _bits: PackedByteArray


func _init(generated: Dictionary) -> void:
	bounds = WorldLayout.rect(generated.layout.bounds)
	columns = ceili(bounds.size.x / ReconActionV1.CELL)
	rows = ceili(bounds.size.y / ReconActionV1.CELL)
	_bits.resize(ceili(float(columns * rows) / 8.0))


func cell_index(point: Vector2) -> int:
	if not bounds.has_point(point):
		return -1
	var cell: Vector2i = Vector2i(((point - bounds.position) / ReconActionV1.CELL).floor())
	return cell.y * columns + cell.x


func cell_rect(index: int) -> Rect2:
	return ReconActionV1.cell_rect(bounds, Vector2i(index % columns, floori(float(index) / columns)))


func is_cell_explored(index: int) -> bool:
	return index >= 0 and index < columns * rows and (_bits[index >> 3] & (1 << (index & 7))) != 0


func explored(point: Vector2) -> bool:
	return is_cell_explored(cell_index(point))


func site_known(generated: Dictionary, id: String, point: Vector2, completed: bool) -> bool:
	return explored(point) or (completed and (id == generated.recon.primary_id or id == generated.recon.optional_id))


func reveal(point: Vector2) -> bool:
	var own: int = cell_index(point)
	if own < 0:
		return false
	var changed: bool = _mark(own)
	var relative: Vector2 = point - bounds.position
	var radius: Vector2 = Vector2.ONE * ReconActionV1.RADIUS
	var first: Vector2i = Vector2i(((relative - radius) / ReconActionV1.CELL).floor())
	var last: Vector2i = Vector2i(((relative + radius) / ReconActionV1.CELL).floor())
	for row: int in range(maxi(0, first.y), mini(rows - 1, last.y) + 1):
		for column: int in range(maxi(0, first.x), mini(columns - 1, last.x) + 1):
			var index: int = row * columns + column
			if cell_rect(index).get_center().distance_squared_to(point) <= ReconActionV1.RADIUS * ReconActionV1.RADIUS:
				changed = _mark(index) or changed
	return changed


func _mark(index: int) -> bool:
	var byte: int = index >> 3
	var marked: int = _bits[byte] | (1 << (index & 7))
	if _bits[byte] == marked:
		return false
	_bits[byte] = marked
	return true


func snapshot(progress: float) -> Dictionary:
	return {"bits":_bits.hex_encode(), "progress":progress, "completed":progress == ReconActionV1.SECONDS}


func restore(state: Dictionary) -> void:
	_bits = String(state.bits).hex_decode()


func problem(state: Variant, elapsed: float) -> String:
	if not state is Dictionary or state.size() != 3 or not state.has_all(["bits", "progress", "completed"]):
		return "RECON_FIELDS"
	if not state.bits is String or state.bits.length() != _bits.size() * 2:
		return "RECON_BITS"
	for index: int in range(state.bits.length()):
		var code: int = state.bits.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return "RECON_BITS"
	var last_bits: int = (columns * rows) & 7
	if last_bits != 0 and (state.bits.right(2).hex_to_int() >> last_bits) != 0:
		return "RECON_BITS_PADDING"
	if not state.completed is bool or not SurvivalContracts.number(state.progress) or state.progress < 0.0 \
			or state.progress > ReconActionV1.SECONDS or state.progress > elapsed + 0.000001 \
			or state.completed != (state.progress == ReconActionV1.SECONDS):
		return "RECON_PROGRESS"
	return ""


static func claimed(receipt: Dictionary) -> Dictionary:
	return receipt.envelope.world.get("recon", {}) if receipt.get("phase") == "RESUME_CLAIMED" else {}


static func history_problem(before: Dictionary, next: Dictionary) -> String:
	if before.is_empty() or next.phase != "SUSPEND_READY":
		return ""
	var after: Dictionary = next.envelope.world.get("recon", {})
	if after.is_empty() or after.progress < before.progress:
		return "RECON_HISTORY_PROGRESS"
	if after.bits != before.bits:
		var old_bits: PackedByteArray = String(before.bits).hex_decode()
		var new_bits: PackedByteArray = String(after.bits).hex_decode()
		if new_bits.size() != old_bits.size():
			return "RECON_HISTORY_BITS"
		for index: int in range(old_bits.size()):
			if (old_bits[index] & new_bits[index]) != old_bits[index]:
				return "RECON_HISTORY_BITS"
	return ""
