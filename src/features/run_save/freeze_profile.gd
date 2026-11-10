class_name FreezeProfile
extends RefCounted
## Opt-in aggregate timings; never persisted into a receipt or used for authority.

static var enabled: bool = false
static var active: bool = false
static var latest: Dictionary = {}
static var _rows: Dictionary = {}
static var _stack: Array[Dictionary] = []
static var _meta: Dictionary = {}
static var _marks: Dictionary = {}
static var _started: int = 0


static func start(metadata: Dictionary) -> void:
	if not enabled or active:
		return
	active = true
	_rows.clear()
	_stack.clear()
	_marks.clear()
	_meta = metadata.duplicate(true)
	_started = Time.get_ticks_usec()


static func enter(label: String) -> int:
	if not _recording():
		return 0
	var stamp: int = Time.get_ticks_usec()
	_stack.append({"label":label, "started":stamp, "children":0})
	return stamp


static func leave(label: String, stamp: int) -> void:
	if stamp == 0 or not _recording():
		return
	var row: Dictionary = _stack.pop_back()
	assert(row.label == label and row.started == stamp)
	var elapsed: int = Time.get_ticks_usec() - stamp
	_record(label, elapsed, elapsed - int(row.children))
	if not _stack.is_empty():
		_stack[-1].children += elapsed


static func sample(label: String, stamp: int) -> void:
	if not _recording():
		return
	var elapsed: int = Time.get_ticks_usec() - stamp
	_record(label, elapsed, elapsed)
	if not _stack.is_empty():
		_stack[-1].children += elapsed


static func scale(label: String, value: int) -> void:
	if _recording():
		_meta[label] = maxi(int(_meta.get(label, 0)), value)


static func count(label: String) -> void:
	if _recording():
		_meta[label] = int(_meta.get(label, 0)) + 1


static func mark(label: String, stamp: int = 0) -> void:
	if _recording() and not _marks.has(label):
		_marks[label] = stamp if stamp > 0 else Time.get_ticks_usec()


static func finish() -> void:
	if not active:
		return
	var elapsed: int = Time.get_ticks_usec() - _started
	assert(_stack.is_empty())
	latest = {"total_usec":elapsed, "synchronous_callback_usec":elapsed,
		"metadata":_meta.duplicate(true), "stages":_rows.duplicate(true), "marks":_marks.duplicate(),
		"mode":"synchronous; inclusive durations nest; self_usec excludes measured children"}
	active = false


static func _recording() -> bool:
	# Background generation must never append to a synchronous callback's stack.
	return active and OS.get_thread_caller_id() == OS.get_main_thread_id()


static func _record(label: String, elapsed: int, own: int) -> void:
	if not _rows.has(label):
		_rows[label] = {"calls":0, "inclusive_usec":0, "self_usec":0, "max_usec":0}
	var row: Dictionary = _rows[label]
	row.calls += 1
	row.inclusive_usec += elapsed
	row.self_usec += own
	row.max_usec = maxi(row.max_usec, elapsed)
