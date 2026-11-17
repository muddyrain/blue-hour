class_name FieldRouteKernelLoader
extends RefCounted
## Optional public GDExtension. Never preload a library or let the editor scan it.

const MANIFEST: String = "res://src/features/expedition/native/route_kernel.cfg"
var status: String = "uninitialized"
var _attempted: bool = false


func prepare(manifest: String = MANIFEST) -> void:
	if _attempted:
		return
	_attempted = true
	var version: Dictionary = Engine.get_version_info()
	if version.major != 4 or version.minor != 7 or version.patch != 2 or OS.has_feature("double"):
		_finish("fallback: unsupported engine/precision")
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(manifest) != OK or not config.has_section("libraries"):
		_finish("fallback: manifest unavailable")
		return
	var selected: String = ""
	for key: String in config.get_section_keys("libraries"):
		var matches: bool = true
		for feature: String in key.split("."):
			matches = matches and OS.has_feature(feature)
		if matches:
			selected = key
			break
	if selected.is_empty():
		_finish("fallback: no platform library")
		return
	var path: String = str(config.get_value("libraries", selected))
	if OS.has_feature("editor"):
		path = ProjectSettings.globalize_path(path)
	else:
		var library_dir: String = OS.get_executable_path().get_base_dir()
		if OS.has_feature("macos"):
			library_dir = library_dir.path_join("../Frameworks").simplify_path()
		path = library_dir.path_join(path.get_file())
	if not FileAccess.file_exists(path):
		_finish("fallback: library missing (%s)" % selected)
		return
	# Generate only in user data, outside editor scanning and the exported PCK.
	# Use absolute sidecar paths so exported packages can be moved as a directory.
	config.erase_section("libraries")
	config.set_value("libraries", selected, path)
	var directory: String = "user://navigation-native"
	var descriptor: String = directory.path_join("route_kernel.gdextension")
	if DirAccess.make_dir_recursive_absolute(directory) != OK or config.save(descriptor) != OK:
		_finish("fallback: descriptor unavailable")
		return
	var result: int = GDExtensionManager.load_extension(ProjectSettings.globalize_path(descriptor))
	if result not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED] or not ClassDB.class_exists(&"FieldRouteKernel"):
		_finish("fallback: load failed (%d)" % result)
		return
	_finish("native: " + selected)


func _finish(value: String) -> void:
	status = value
	print("BH_NAVIGATION ", status, "; strict full validation enabled")


func create_kernel() -> RefCounted:
	prepare()
	if not status.begins_with("native:"):
		return null
	var kernel: RefCounted = ClassDB.instantiate(&"FieldRouteKernel") as RefCounted
	if kernel == null:
		print("BH_NAVIGATION fallback: instance unavailable; strict full validation enabled")
	return kernel
