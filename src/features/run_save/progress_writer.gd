class_name ProgressWriter
extends RefCounted
## OS-owned local lease. No connections or game/user payloads are accepted or transmitted.

var path: String:
	get:
		return _canonical
var reason: String = ""
var lease_port: int:
	get:
		return _port
var _canonical: String
var _port: int
var _lease: TCPServer = TCPServer.new()
var _held: bool = false


func _init(save_path: String) -> void:
	_canonical = ProjectSettings.globalize_path(save_path).replace("\\", "/").simplify_path()
	var identity: String = _canonical.to_lower() if OS.has_feature("windows") else _canonical
	_port = 49152 + identity.sha256_text().substr(0, 8).hex_to_int() % 16384


func acquire() -> Error:
	if _held:
		return ERR_ALREADY_IN_USE
	if not path.is_absolute_path() or path.begins_with("res://") or not _unlinked(path):
		reason = "WRITER_CANONICAL_PATH_REQUIRED"
		return ERR_INVALID_PARAMETER
	# A collision or denied bind blocks; never try another port for the same progress path.
	if _lease.listen(_port, "127.0.0.1") != OK:
		_lease.stop()
		reason = "PROGRESS_WRITER_BUSY"
		return ERR_BUSY
	_held = true
	return OK


func owns(save_path: String) -> bool:
	var other: String = ProjectSettings.globalize_path(save_path).replace("\\", "/").simplify_path()
	return _held and _lease.is_listening() and _lease.get_local_port() == _port and (_canonical.to_lower() == other.to_lower() if OS.has_feature("windows") else _canonical == other)


func release() -> void:
	_lease.stop()
	_held = false


static func _unlinked(source: String) -> bool:
	var current: String = source
	while current.get_base_dir() != current:
		var parent: String = current.get_base_dir()
		if DirAccess.dir_exists_absolute(parent):
			var access: DirAccess = DirAccess.open(parent)
			if access == null or access.is_link(current.get_file()):
				return false
		current = parent
	return true
