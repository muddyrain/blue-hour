extends "res://tests/playable_flow.gd"
## Native clean-clone title and the actual two-step Quit controls; no journey is created.
func _journey() -> void:
	_check(not app._requires_continue and not FileAccess.file_exists(app.progress_path),"clean native title has no player progress")
	_check(root.has_focus() == false,"background title never claims desktop focus")
	await _shot("clean-clone-title")
	await _tap(app.get_node("Interface/Screen/Title/Quit"))
	_check(app.pause_menu.confirming and app._exit_target == "quit","actual title Quit opens its native confirmation")
	await _shot("clean-clone-quit-confirmation")
	_write("report.json",{"pid":OS.get_process_id(),"failures":failures,"checks":rows,"root_focused":root.has_focus(),"native":true,"scope":"CLEAN_CLONE_NATIVE_TITLE_AND_REAL_QUIT_CONTROLS","quit_control_requested":true})
	await _tap(app.pause_menu.buttons[1])
	# An actual quit terminates before this line; any return is a failed close.
	_check(false,"native Quit must end its own process")


func _shot(label: String) -> void:
	await _hold(2)
	RenderingServer.force_draw()
	var captured: Image = viewport.get_texture().get_image()
	_check(captured.get_size() == viewport.size
		and captured.save_png(output.path_join(label + ".png")) == OK, "native viewport capture " + label)
