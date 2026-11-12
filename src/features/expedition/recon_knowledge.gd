class_name ReconKnowledge
extends RefCounted
## A row-major, least-significant-bit-first bitmap aligned with the frozen map.

const CLOCK_EPSILON: float = 0.0001
const WORK_TICK_GRACE: float = 1.0 / 30.0
const MAX_WORK_PERIODS: int = 1024

var bounds: Rect2
var columns: int
var rows: int
var _bits: PackedByteArray
var _source_version: bool
var _reveals: Array = []
var _work: Array = []


func _init(generated: Dictionary) -> void:
	bounds = WorldLayout.rect(generated.layout.bounds)
	_source_version = generated.recon.version == ReconActionV1.SOURCE_VERSION
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


func observe(member_id: int, point: Vector2, elapsed: float) -> bool:
	var changed: bool = reveal(point)
	if changed and _source_version and elapsed > 0.0:
		# Exact receipts decode numbers as float. Keep live history in that same
		# representation so strict nested-prefix equality survives an ACK.
		_reveals.append([float(member_id), elapsed, point.x, point.y])
	return changed


func record_work(member_id: int, point: Vector2, start: float, end: float) -> void:
	if not _source_version:
		return
	if not _work.is_empty():
		var last: Array = _work.back()
		if last[0] == member_id and absf(float(last[2]) - start) <= CLOCK_EPSILON:
			last[2] = end
			return
	_work.append([float(member_id), start, end, point.x, point.y])


func snapshot(progress: float) -> Dictionary:
	var state: Dictionary = {"bits":_bits.hex_encode(), "progress":progress, "completed":progress == ReconActionV1.SECONDS}
	if _source_version:
		state.reveals = _reveals.duplicate(true)
		state.work = _work.duplicate(true)
	return state


func restore(state: Dictionary) -> void:
	_bits = String(state.bits).hex_decode()
	if _source_version:
		_reveals = state.reveals.duplicate(true)
		_work = state.work.duplicate(true)


func problem(state: Variant, elapsed: float) -> String:
	if not state is Dictionary or state.size() != (5 if _source_version else 3) or not state.has_all(["bits", "progress", "completed"]):
		return "RECON_FIELDS"
	if _source_version and (not state.get("reveals") is Array or state.reveals.size() > columns * rows
			or not state.get("work") is Array or state.work.size() > MAX_WORK_PERIODS):
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


func source_problem(world: Dictionary) -> String:
	if not _source_version:
		return ""
	var generated: Dictionary = world.generated
	var state: Dictionary = world.recon
	var elapsed: float = world.sim.elapsed
	var derived: ReconKnowledge = ReconKnowledge.new(generated)
	var starts: Dictionary = {}
	var latest: Dictionary = {}
	var speed_limits: Dictionary = {}
	var layout: Dictionary = generated.layout
	if world.survivors.size() > layout.arrivals.size():
		return "RECON_ARRIVAL_SOURCE"
	derived.reveal(WorldLayout.point(layout.bus.door))
	for index: int in range(world.survivors.size()):
		var actor: Dictionary = world.survivors[index].state
		var id: int = int(actor.member_id)
		var start: Vector2 = WorldLayout.point(layout.arrivals[index])
		starts[id] = start
		latest[id] = [0.0, start]
		# Contact separation and cooperative yielding can add to powered walking.
		speed_limits[id] = float(actor.speed) * float(SpecialPowers.POLICY[SpecialPowers.SPEED].move_factor) \
			+ FieldContacts.RECOVERY_SPEED + FieldContacts.YIELD_SPEED * (world.survivors.size() - 1)
		derived.reveal(start)
	var previous_time: float = 0.0
	for row: Variant in state.reveals:
		if not _source_row(row, 4, starts):
			return "RECON_BITS_SOURCE"
		var id: int = int(row[0])
		var time: float = row[1]
		var point: Vector2 = Vector2(row[2], row[3])
		var prior: Array = latest[id]
		if time < previous_time or time <= float(prior[0]) or time > elapsed \
				or point.distance_to(prior[1]) > float(speed_limits[id]) * (time - float(prior[0])) + CLOCK_EPSILON \
				or not derived.reveal(point):
			return "RECON_BITS_SOURCE"
		latest[id] = [time, point]
		previous_time = time
	if derived._bits.hex_encode() != state.bits:
		return "RECON_BITS_SOURCE"
	var work_end: float = 0.0
	var total: float = 0.0
	var station: Vector2 = ReconActionV1.point(generated)
	for row: Variant in state.work:
		if not _source_row(row, 5, starts):
			return "RECON_WORK_SOURCE"
		var id: int = int(row[0])
		var start: float = row[1]
		var end: float = row[2]
		var point: Vector2 = Vector2(row[3], row[4])
		if start < 0.0 or start < work_end - CLOCK_EPSILON or end <= start or end > elapsed + CLOCK_EPSILON \
				or point.distance_to(station) > ReconActionV1.WORK_RANGE or not derived.explored(point) \
				or point.distance_to(starts[id]) > float(speed_limits[id]) * minf(end, start + WORK_TICK_GRACE) + CLOCK_EPSILON:
			return "RECON_WORK_SOURCE"
		total += end - start
		work_end = end
	if (state.progress > 0.0) != (not state.work.is_empty()) or absf(total - float(state.progress)) > CLOCK_EPSILON:
		return "RECON_WORK_SOURCE"
	return ""


static func _source_row(row: Variant, size: int, members: Dictionary) -> bool:
	if not row is Array or row.size() != size or not SurvivalContracts.integer(row[0], 1, SurvivalContracts.MAX_ID) \
			or not members.has(int(row[0])):
		return false
	for index: int in range(1, size):
		if not SurvivalContracts.number(row[index]):
			return false
	return true


static func claimed(receipt: Dictionary) -> Dictionary:
	if receipt.get("phase") != "RESUME_CLAIMED":
		return {}
	var world: Dictionary = receipt.envelope.world
	var state: Dictionary = world.get("recon", {})
	if not state.has("reveals"):
		return state
	var context: Dictionary = state.duplicate(false)
	context.elapsed = world.sim.elapsed
	return context


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
	if not before.has("reveals"):
		return ""
	if not after.has("reveals") or next.envelope.world.sim.elapsed < before.elapsed:
		return "RECON_HISTORY_CLOCK"
	var reveals: Array = before.reveals
	var new_reveals: Array = after.reveals
	if new_reveals.size() < reveals.size() or new_reveals.slice(0, reveals.size()) != reveals:
		return "RECON_HISTORY_BITS"
	if new_reveals.size() > reveals.size() and new_reveals[reveals.size()][1] <= before.elapsed:
		return "RECON_HISTORY_CLOCK"
	var work: Array = before.work
	var new_work: Array = after.work
	if new_work.size() < work.size():
		return "RECON_HISTORY_PROGRESS"
	if not work.is_empty():
		var last: int = work.size() - 1
		var previous: Array = work[last]
		var current: Array = new_work[last]
		if new_work.slice(0, last) != work.slice(0, last) or current[2] < previous[2]:
			return "RECON_HISTORY_PROGRESS"
		var original_end: Array = current.duplicate()
		original_end[2] = previous[2]
		if original_end != previous or (current[2] > previous[2] and absf(float(previous[2]) - before.elapsed) > CLOCK_EPSILON):
			return "RECON_HISTORY_PROGRESS"
	if new_work.size() > work.size() and new_work[work.size()][1] < before.elapsed - CLOCK_EPSILON:
		return "RECON_HISTORY_CLOCK"
	return ""
