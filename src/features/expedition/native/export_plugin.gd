@tool
extends EditorPlugin

var _exporter: EditorExportPlugin


class NavigationExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "BlueHourOptionalNavigation"


	func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		var manifest: String = "res://src/features/expedition/native/route_kernel.cfg"
		add_file(manifest, FileAccess.get_file_as_bytes(manifest), false)
		var config: ConfigFile = ConfigFile.new()
		if config.load(manifest) == OK:
			for key: String in config.get_section_keys("libraries"):
				var tags: PackedStringArray = key.split(".")
				var matches: bool = true
				for tag: String in tags:
					matches = matches and features.has(tag)
				if not matches:
					continue
				var library: String = str(config.get_value("libraries", key))
				if FileAccess.file_exists(library):
					add_shared_object(library, tags, "")
					print("BH_NAVIGATION_EXPORT native: ", key)
					return
		print("BH_NAVIGATION_EXPORT fallback: strict AStarGrid2D; no target helper")


func _enter_tree() -> void:
	_exporter = NavigationExport.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	remove_export_plugin(_exporter)
