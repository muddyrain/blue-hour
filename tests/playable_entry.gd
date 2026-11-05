extends SceneTree
## Default routing and narrow canonical-path permission; no player profiles.
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	assert(value, label)
	checks += 1

func _run() -> void:
	assert("/.local/" in OS.get_user_data_dir().replace("\\","/"), "isolated HOME required")
	var config: Dictionary = PlayableEntry.resolve([])
	_expect(config.playable, "no gameplay flags starts playable")
	_expect(config.progress == PlayableEntry.progress_path(), "stable canonical progress")
	_expect(config.audio == "user://playable-v1/audio.json", "independent settings")
	for flag: String in PlayableEntry.FEATURE_ARGUMENTS:
		_expect(flag in config.arguments, "existing unified feature chain: "+flag)
	for flag: String in PlayableEntry.LEGACY_ARGUMENTS:
		var old: Dictionary = PlayableEntry.resolve(PackedStringArray([flag]))
		_expect(not old.playable and old.progress == "user://saves/run.json", "explicit old entry remains: "+flag)
	_expect(not PlayableEntry.owns_path("user://playable-v1/run.enemy-v1.json"), "owner requires resolved absolute path")
	_expect(not PlayableEntry.owns_path(config.progress+".other"), "no arbitrary sibling accepted")
	var session: ProductionProgress = ProductionProgress.new(config.progress,true,true,true,true,true,true,true,true,true,true,true,true,true)
	_expect(session.inspect().state == "EMPTY", "canonical playable permission opens only empty independent journey")
	session.close()
	var wrong: ProductionProgress = ProductionProgress.new("/tmp/blue-hour-not-playable/run.enemy-v1.json",true,true,true,true,true,true,true,true,true,true,true,true,true)
	_expect(wrong.inspect().reason == "EXPLICIT_ISOLATED_TRANSACTION_PATH_REQUIRED", "playable flag does not permit arbitrary disk path")
	wrong.close()
	var legacy: ProductionProgress = ProductionProgress.new("user://saves/run.json",true,true,true,true,true,true,true,true,true,true,true,true)
	_expect(legacy.inspect().reason == "EXPLICIT_ISOLATED_TRANSACTION_PATH_REQUIRED", "old default never silently enters new protocol")
	legacy.close()
	print("BH_PLAYABLE_ENTRY checks=%d PASS" % checks)
	quit()
