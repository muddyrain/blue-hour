extends SceneTree
## Reauthenticate retained final-media inputs after a stricter result validator; never create a run.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2); return
	var app: Node = load("res://src/app/main.tscn").instantiate(); root.add_child(app)
	await process_frame
	var state: Dictionary = app.progress_session.inspect()
	var valid: bool = state.error==OK and state.state=="CAMP" and state.camp.last_day.has("task") and state.camp.last_day.task.status in ["COMPLETED","EARLY"]
	if valid: valid=app.progress_session._transaction._journal.read_all().error==OK
	print("TASK_RECHECK valid=",valid," state=",state.get("state")," reason=",state.get("reason"))
	app.audio.shutdown(); app.queue_free(); await process_frame
	quit(0 if valid else 1)
