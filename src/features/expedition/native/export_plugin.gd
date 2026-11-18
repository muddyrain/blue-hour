@tool
extends EditorPlugin

var _exporter: EditorExportPlugin


class NavigationExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "BlueHourOptionalNavigation"


	func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		var manifest: String = "res://src/features/expedition/native/route_kernel.cfg"
		var config: ConfigFile = ConfigFile.new()
		if config.load(manifest) == OK:
			# A universal app must carry both slices. Do not pick the first thin
			# library just because both architecture feature tags are present.
			if features.has("macos") and features.has("universal"):
				var universal: String = "res://.local/navigation-native/route_kernel.dylib"
				for architecture: String in ["arm64", "x86_64"]:
					config.set_value("libraries", "macos." + architecture, universal)
				add_file(manifest, config.encode_to_text().to_utf8_buffer(), false)
				if FileAccess.file_exists(universal):
					add_shared_object(universal, PackedStringArray(["macos"]), "")
					print("BH_NAVIGATION_EXPORT native: macos.universal")
				else:
					print("BH_NAVIGATION_EXPORT fallback: strict AStarGrid2D; no universal helper")
				return
			add_file(manifest, FileAccess.get_file_as_bytes(manifest), false)
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
