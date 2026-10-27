class_name AudioPreferences
extends RefCounted
## Dedicated sound preferences only. The caller owns and explicitly supplies the file.

signal changed
signal diagnosed(message: String)

const DEFAULTS: Dictionary = {
	"master_volume": 0.8, "sfx_volume": 0.75, "ui_volume": 0.7, "muted": false,
}
const VOLUME_KEYS: Array[String] = ["master_volume", "sfx_volume", "ui_volume"]
const MAX_FILE_BYTES: int = 4096

var last_diagnostic: String = ""
var _path: String
var _values: Dictionary = DEFAULTS.duplicate()


func _init(settings_path: String) -> void:
	# No default user:// path: tests and the app must choose their own storage.
	_path = settings_path


func snapshot() -> Dictionary:
	return _values.duplicate()


func settings_path() -> String:
	return _path


func set_volume(key: String, value: float) -> bool:
	if key not in VOLUME_KEYS or not is_finite(value):
		_report("Rejected invalid volume: %s" % key)
		return false
	_values[key] = clampf(value, 0.0, 1.0)
	changed.emit()
	return true


func set_muted(value: bool) -> void:
	_values["muted"] = value
	changed.emit()


func load_preferences() -> Error:
	if not _valid_path():
		return ERR_INVALID_PARAMETER
	if DirAccess.dir_exists_absolute(_path):
		_report("Read failed: settings path is a directory: %s" % _path)
		return ERR_FILE_CANT_READ
	if not FileAccess.file_exists(_path):
		_values = DEFAULTS.duplicate()
		changed.emit()
		_report("First use: no sound preferences; using project defaults: %s" % _path)
		return ERR_FILE_NOT_FOUND
	var file: FileAccess = FileAccess.open(_path, FileAccess.READ)
	if file == null:
		var error: Error = FileAccess.get_open_error()
		_report("Read failed (%s); current values retained: %s" % [error_string(error), _path])
		return error
	if file.get_length() > MAX_FILE_BYTES:
		_report("Read rejected: sound preferences exceed 4096 bytes; file retained")
		return ERR_FILE_CORRUPT
	var json: JSON = JSON.new()
	var result: Error = json.parse(file.get_as_text())
	file.close()
	if result != OK or not json.data is Dictionary:
		_report("Damaged sound preferences; file and current values retained: %s (line %d: %s)" % [
			_path, json.get_error_line(), json.get_error_message()])
		return ERR_FILE_CORRUPT
	var data: Dictionary = json.data
	var repaired: PackedStringArray = []
	var next: Dictionary = DEFAULTS.duplicate()
	for key: String in VOLUME_KEYS:
		var value: Variant = data.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			next[key] = clampf(float(value), 0.0, 1.0)
			if next[key] != value:
				repaired.append(key + " clamped")
		else:
			repaired.append(key + " defaulted")
	if data.get("muted") is bool:
		next["muted"] = data["muted"]
	else:
		repaired.append("muted defaulted")
	if data.size() != DEFAULTS.size() or not data.has_all(DEFAULTS.keys()):
		repaired.append("only the four sound fields are used")
	_values = next
	changed.emit()
	_report("Loaded sound preferences: %s%s" % [_path,
		"; " + "; ".join(repaired) if not repaired.is_empty() else ""])
	return OK


func save_preferences() -> Error:
	if not _valid_path():
		return ERR_INVALID_PARAMETER
	if DirAccess.dir_exists_absolute(_path):
		_report("Save failed: settings path is a directory: %s" % _path)
		return ERR_FILE_CANT_WRITE
	var error: Error = DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	if error != OK:
		return _save_error(error)
	var temporary: String = _path + ".tmp"
	var backup: String = _path + ".bak"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _save_error(FileAccess.get_open_error())
	file.store_string(JSON.stringify(_values, "\t") + "\n")
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return _save_error(error)
	var verification: JSON = JSON.new()
	if verification.parse(FileAccess.get_file_as_string(temporary)) != OK or verification.data != _values:
		return _save_error(ERR_FILE_CORRUPT)
	var had_original: bool = FileAccess.file_exists(_path)
	if had_original:
		# Preserve the previous bytes, including a damaged file, on explicit save.
		error = DirAccess.rename_absolute(_path, backup)
		if error != OK:
			return _save_error(error)
	error = DirAccess.rename_absolute(temporary, _path)
	if error != OK:
		if had_original:
			var rollback: Error = DirAccess.rename_absolute(backup, _path)
			if rollback != OK:
				_report("Save and rollback failed; previous file remains at %s" % backup)
				return rollback
		return _save_error(error)
	_report("Saved sound preferences: %s" % _path)
	return OK


func _valid_path() -> bool:
	if _path.is_empty() or _path.begins_with("res://") or not _path.is_absolute_path():
		_report("An explicit absolute or user:// sound settings path is required")
		return false
	return true


func _save_error(error: Error) -> Error:
	_report("Save failed (%s); previous preferences retained: %s" % [error_string(error), _path])
	return error


func _report(message: String) -> void:
	last_diagnostic = message
	print("B1_PREFS " + message)
	diagnosed.emit(message)
