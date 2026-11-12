extends "res://tests/m48_stale_cards_flow.gd"
## Keep the original stale-query assertions and wait for actual serial saves.

func _frame() -> void:
	await super._frame()
	var deadline: int = Time.get_ticks_msec() + 900000
	while is_instance_valid(app) and (app.get("_progress_busy") == true or app.get("_camp_commit_busy") == true) and Time.get_ticks_msec() < deadline:
		await process_frame
