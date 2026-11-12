extends "res://tests/m48_campaign_flow.gd"
## Fresh normal camp; use m49_recovery_flow prepare for a funded long source.

func _frame() -> void:
	await super._frame()
	while is_instance_valid(app) and (app.get("_progress_busy") == true or app.get("_camp_commit_busy") == true):
		await process_frame


func _journey() -> void:
	if await _new_trip("scavenge", true):
		_write("source.json", {"camp":app.camp_snapshot(), "pid":OS.get_process_id(), "path":app.progress_path})


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_write("source.json", {"camp":app.camp_snapshot(), "pid":OS.get_process_id(), "path":app.progress_path})
