extends "res://tests/playable_flow.gd"
## Clean checkout native title/continue and actual Quit controls on an isolated desktop.

func _frame() -> void:
	await super._frame()
	while is_instance_valid(app) and (app.get("_progress_busy") == true or app.get("_camp_commit_busy") == true):
		await process_frame


func _journey() -> void:
	_check(not app._requires_continue and not FileAccess.file_exists(app.progress_path), "clean title has no player data")
	await _quit_from_ui()


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked, "clean checkout continues the original bound camp")
	await _quit_from_ui()


func _quit_from_ui() -> void:
	await _shot("clean-checkout-ready")
	app.request_exit("quit")
	await _hold(3)
	_check(app.pause_menu.confirming and app._exit_target == "quit", "native close reaches the actual confirmation")
	_write("report.json", {"pid":OS.get_process_id(), "failures":failures, "checks":rows,
		"native":DisplayServer.get_name() != "headless", "input":"isolated desktop viewport events",
		"physical_input":"NOT_VERIFIED", "path":app.progress_path})
	await _tap(app.pause_menu.buttons[1])
	_check(false, "confirmed Quit exits normally")


func _shot(label: String) -> void:
	await _hold(2)
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"native clean-checkout image is retained")
