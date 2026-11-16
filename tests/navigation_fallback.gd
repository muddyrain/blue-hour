extends SceneTree
## Fresh processes keep deliberate loader failures away from the normal backend.

const Oracle = preload("res://tests/support/navigation_oracle.gd")
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			_child(argument.trim_prefix("--case="))
			return
	for scenario: String in ["missing", "platform", "load", "manifest", "configuration"]:
		var output: Array = []
		var result: int = OS.execute(OS.get_executable_path(), PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"), "--audio-driver", "Dummy",
			"--script", "res://tests/navigation_fallback.gd", "--", "--case=" + scenario]), output, true)
		checks += 1
		if result != 0 or not str(output).contains("BH_NAV_FALLBACK_CHILD_PASS " + scenario):
			failures += 1
			printerr("BH_NAV_FALLBACK_FAIL ", scenario, " ", output)
	print("BH_NAV_FALLBACK ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures == 0 else 1)


func _child(scenario: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("configuration", "entry_symbol", "bh_route_init")
	config.set_value("configuration", "compatibility_minimum", "4.7.2")
	var key: String = "windows.x86_64" if OS.has_feature("windows") else "linux.x86_64"
	if scenario == "platform":
		key = "wrong_platform.x86_64"
	var library: String = "user://missing-navigation-library.so"
	if scenario == "load":
		library = ProjectSettings.globalize_path("user://invalid-navigation-library.so")
		var file: FileAccess = FileAccess.open(library, FileAccess.WRITE)
		file.store_string("Deliberately invalid shared library")
		file.close()
	config.set_value("libraries", key, library)
	var manifest: String = "user://navigation-test.cfg"
	assert(config.save(manifest) == OK)
	var loader: FieldRouteKernelLoader = FieldRouteKernelLoader.new()
	if scenario != "configuration":
		loader.prepare("user://missing-manifest.cfg" if scenario == "manifest" else manifest)
		assert(loader.status.begins_with("fallback:"))
		assert((scenario != "load") or loader.status.begins_with("fallback: load failed"))
		FieldRouteSearch._loader = loader
	# All cases compare full paths, including unreachable, tie and start correction.
	var nav: FieldNavigation = FieldNavigation.new()
	var oracle: Oracle = Oracle.new()
	var blockers: Array[Rect2] = [Rect2(160, 0, 32, 256), Rect2(320, 64, 32, 96)]
	var bounds: Rect2 = Rect2(0, 0, 12288, 256)
	nav.configure(blockers, bounds)
	oracle.configure(blockers, bounds)
	var endpoints: Array[Vector2] = [Vector2(24, 24), Vector2(100.5, 100.5), Vector2(600, 200),
		Vector2(12000, 200), Vector2(-12, 20), Vector2(160, 64)]
	for start: Vector2 in endpoints:
		for goal: Vector2 in endpoints:
			assert(nav.path_between(start, goal) == oracle.path_between(start, goal))
	if scenario == "configuration" and nav._search._kernel != null:
		# Allocation/invalid mask failure must not be mistaken for an unreachable path.
		nav._search.configure(Vector2i.ZERO, [])
		assert(nav._search._kernel == null)
		assert(nav._search.path(nav._grid, Vector2i(1, 1), Vector2i(4, 4)) == nav._grid.get_point_path(Vector2i(1, 1), Vector2i(4, 4)))
	print("BH_NAV_FALLBACK_CHILD_PASS ", scenario)
	quit()
