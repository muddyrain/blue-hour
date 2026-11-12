extends "res://tests/m48_archive_flow.gd"
## Identical immutable source read in both versions; no state mutation for timings.

func _tap(button: BaseButton) -> void:
	await super._tap(button)
	var deadline: int = Time.get_ticks_msec() + 600000
	while (app.get("_progress_busy") == true or app.get("_camp_commit_busy") == true) and Time.get_ticks_msec() < deadline:
		await _frame()


func _measure_archives() -> void:
	_check(_archives().size() == _archive_target, "exact original archive scale")
	var samples: Array[Dictionary] = []
	var reader: CatalogProgress = CatalogProgress.new(app.progress_path)
	var count: int = 10 if "--ten-refreshes" in OS.get_cmdline_user_args() else 4
	for index: int in range(count):
		FreezeProfile.enabled = true
		FreezeProfile.start({"operation":"complete_catalog", "iteration":index, "archives":_archive_target})
		var started: int = Time.get_ticks_usec()
		var projection: Dictionary = reader.refresh(Callable())
		var elapsed: int = Time.get_ticks_usec() - started
		FreezeProfile.finish()
		_check(projection.get("error") == OK, "complete source validation and projection")
		samples.append({"kind":"specialty_read", "iteration":index, "wall_ms":elapsed/1000.0,
			"profile":FreezeProfile.latest.duplicate(true), "static_memory_bytes":OS.get_static_memory_usage(),
			"peak_static_memory_bytes":OS.get_static_memory_peak_usage(), "result":projection})
		_write("catalog-samples.json", {"pid":OS.get_process_id(), "archive_count":_archive_target,
			"samples":samples, "path":app.progress_path, "source_kind":"WINDOWS_ORIGINAL_BOUND_BYTES"})
	if await _open_original_camp():
		await _shot("confirmed-camp")
	if "--measure-catalog-ui" in OS.get_cmdline_user_args():
		var ui_samples: Array[Dictionary] = []
		for index: int in range(4):
			var ui: Dictionary = await preload("res://tests/m49_native_probe.gd").measure(app, viewport,
				app.camp_scene.footer_buttons[&"specialties"], func() -> bool:
					return is_instance_valid(app._equipment_catalog) and app._equipment_catalog.is_visible_in_tree() and app.get("_progress_busy") != true)
			_check(not ui.get("timeout", false), "actual catalog button publishes its full verified result")
			ui.iteration = index
			ui_samples.append(ui)
			_write("catalog-ui.json", {"pid":OS.get_process_id(), "samples":ui_samples, "path":app.progress_path})
			if index == 0:
				await _shot("specialty-catalog-ui")
			await _tap(app._equipment_catalog.close_button)
	if app.has_method("_open_equipment_catalog"):
		app._open_equipment_catalog()
	else:
		app._show_equipment_catalog(app.progress_session.refresh_catalog())
	while app.get("_progress_busy") == true or app.get("_camp_commit_busy") == true:
		await _frame()
	await _shot("specialty-catalog")
