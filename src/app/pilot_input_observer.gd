class_name PilotInputObserver
extends Node
## Explicit OS acceptance observer. Never drives input, world time or business writes.

var app: Node
var output_dir: String
var _elapsed: float = 0.0
var _samples: int = 0
var _log: FileAccess


func _ready() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\", "/") or FileAccess.file_exists(output_dir.path_join("events.jsonl")):
		set_process(false)
		set_process_input(false)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	_log = FileAccess.open(output_dir.path_join("events.jsonl"), FileAccess.WRITE)
	_record("start")


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		_record(event.as_text())


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.25 and _samples < 1200:
		_elapsed = 0.0
		_samples += 1
		_record("sample")


func _record(event: String) -> void:
	if _log == null:
		return
	var view: Dictionary = {"pid":OS.get_process_id(),"event":event,"ticks":Time.get_ticks_msec(),"focused":DisplayServer.window_is_focused(),"phase":app.phase,"camp_open":app._camp_open,"progress_blocked":app._progress_blocked}
	if app.expedition != null:
		view.merge({"paused":app.expedition.is_paused,"elapsed":app.expedition.elapsed,"goal":str(app.expedition.goal),"zoom":str(app.expedition.camera.zoom),"camera":str(app.expedition.camera.position)})
	var focus: Control = get_viewport().gui_get_focus_owner()
	view.focus_control = str(focus.get_path()) if focus != null else ""
	_log.store_line(JSON.stringify(view))
	_log.flush()
