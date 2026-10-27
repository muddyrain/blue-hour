extends SceneTree
## Windows runner holds an OS file handle; no production fault-injection flag.


func _initialize() -> void:
	var target: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--locked-save="):
			target = argument.trim_prefix("--locked-save=")
	if not target.contains(".local"):
		quit(1)
		return
	var store: RunSave = RunSave.new(target)
	if store.load_save() != OK:
		quit(1)
		return
	var data: Dictionary = store.snapshot.duplicate(true)
	data.day += 1
	data.cash += 4
	data.settled_sorties += 1
	data.last_settlement_id = "%s:%d" % [data.profile_id, int(data.settled_sorties)]
	var error: Error = store.save(data)
	print("BH_LOCKED_SAVE error=%d diagnostic=%s" % [error, store.diagnostic])
	quit(0 if error != OK else 1)
