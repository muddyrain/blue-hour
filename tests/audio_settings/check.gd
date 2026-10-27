extends SceneTree
## Real file IO and real players with Dummy output; never a listening verdict.

const AuditionScene: PackedScene = preload("res://src/features/audio_settings/audition.tscn")
const RESTART_VALUES: Dictionary = {
	"master_volume": 0.63, "sfx_volume": 0.24, "ui_volume": 0.91, "muted": true,
}

var _failures: int = 0
var _checks: int = 0
var _directory: String
var _mode: String = "exercise"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--b1-test-dir="):
			_directory = argument.trim_prefix("--b1-test-dir=")
		if argument.begins_with("--b1-test-mode="):
			_mode = argument.trim_prefix("--b1-test-mode=")
	var allowed: String = ProjectSettings.globalize_path("res://.local/")
	_directory = _validated_test_directory(_directory, allowed)
	if _directory.is_empty() or AudioServer.get_driver_name() != "Dummy" or DisplayServer.get_name() != "headless":
		push_error("B1 checks require B .local storage, headless display and Dummy audio")
		quit(2)
		return
	_check_directory_boundary(allowed)
	_expect(DirAccess.make_dir_recursive_absolute(_directory) == OK, "isolated test directory exists")
	print("B1_ENV driver=%s display=%s directory=%s mode=%s" % [
		AudioServer.get_driver_name(), DisplayServer.get_name(), _directory, _mode])
	if _mode == "restart":
		var restored: AudioPreferences = AudioPreferences.new(_directory.path_join("restart.json"))
		_expect(restored.load_preferences() == OK and restored.snapshot() == RESTART_VALUES,
			"new engine process restores exactly the saved sound preferences")
		var reopened: B1Audition = AuditionScene.instantiate() as B1Audition
		reopened.settings_override = _directory.path_join("scene.json")
		root.add_child(reopened)
		await process_frame
		_expect(reopened._sliders["master_volume"].value == 42 and reopened._mute.button_pressed
			and is_zero_approx(reopened.audio._world_players[0].volume_linear),
			"new process reopens audition with saved controls and muted players")
		reopened.queue_free()
		await create_timer(0.15).timeout
	else:
		_check_storage()
		await _check_audio()
		await _check_scene()
		# AudioServer processes stop/removal on its mixer thread, after node release.
		await create_timer(0.15).timeout
	print("B1_CHECK mode=%s checks=%d failures=%d" % [_mode, _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _validated_test_directory(path: String, allowed_root: String) -> String:
	var normalized: String = path.replace("\\", "/").simplify_path().trim_suffix("/")
	var allowed: String = allowed_root.replace("\\", "/").simplify_path().trim_suffix("/")
	if not normalized.is_absolute_path() or not allowed.is_absolute_path():
		return ""
	if normalized == allowed or normalized.begins_with(allowed + "/"):
		return normalized
	return ""


func _check_directory_boundary(allowed_root: String) -> void:
	var root_path: String = allowed_root.replace("\\", "/").simplify_path().trim_suffix("/")
	var normal: String = root_path.path_join("b1-user-data/path-check/../normalized").replace("/", "\\")
	_expect(_validated_test_directory(normal, allowed_root) == root_path.path_join("b1-user-data/normalized"),
		"mixed separators and safe dot segments return one canonical test directory")
	# Pure validation only: the negative path stays in B and is never created.
	var escaped: String = root_path.path_join("b1-user-data/../../b1-outside-probe")
	_expect(_validated_test_directory(escaped, allowed_root).is_empty(), "dot segments escaping .local are rejected before IO")
	_expect(_validated_test_directory(root_path + "-other/probe", allowed_root).is_empty()
		and _validated_test_directory("relative/probe", allowed_root).is_empty(), "directory boundary and absolute path are required")


func _check_storage() -> void:
	var path: String = _directory.path_join("restart.json")
	var prefs: AudioPreferences = AudioPreferences.new(path)
	_expect(prefs.load_preferences() == ERR_FILE_NOT_FOUND and prefs.snapshot() == AudioPreferences.DEFAULTS,
		"first use supplies defaults without writing")
	_expect(not FileAccess.file_exists(path) and not prefs.last_diagnostic.is_empty(), "missing file has readable diagnostic")
	for key: String in AudioPreferences.VOLUME_KEYS:
		prefs.set_volume(key, RESTART_VALUES[key])
	prefs.set_muted(true)
	_expect(prefs.save_preferences() == OK, "four sound fields saved")
	var bytes: String = FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.parse_string(bytes)
	_expect(data.size() == 4 and data == RESTART_VALUES, "on-disk payload contains only sound preferences")
	prefs.set_volume("master_volume", 0.1)
	_expect(prefs.load_preferences() == OK and prefs.snapshot() == RESTART_VALUES, "same process reload restores saved values")
	_expect(prefs.save_preferences() == OK and prefs.save_preferences() == OK,
		"repeated replacement saves work, including existing backup")
	_expect(FileAccess.get_file_as_string(path + ".bak") == bytes, "replacement retains previous bytes in backup")
	var invalid_path: String = _directory.path_join("invalid.json")
	_write(invalid_path, '{"master_volume":2,"sfx_volume":-1,"ui_volume":"loud","muted":"false","cash":999}')
	var invalid: AudioPreferences = AudioPreferences.new(invalid_path)
	_expect(invalid.load_preferences() == OK and invalid.snapshot() == {
		"master_volume": 1.0, "sfx_volume": 0.0, "ui_volume": 0.7, "muted": false},
		"bad types default, finite extremes clamp, non-audio fields excluded")
	_expect(invalid.last_diagnostic.contains("clamped") and invalid.last_diagnostic.contains("defaulted"),
		"repair is reported instead of silently accepted")
	_expect(not invalid.set_volume("ui_volume", NAN) and not invalid.set_volume("cash", 1), "nonfinite and foreign live keys rejected")
	_write(invalid_path, "{ damaged sound preferences")
	var prior: Dictionary = invalid.snapshot()
	_expect(invalid.load_preferences() == ERR_FILE_CORRUPT and invalid.snapshot() == prior,
		"damaged JSON retains current values")
	_expect(FileAccess.get_file_as_string(invalid_path) == "{ damaged sound preferences", "damaged bytes are not rewritten on load")
	_expect(invalid.save_preferences() == OK and FileAccess.get_file_as_string(invalid_path + ".bak") == "{ damaged sound preferences",
		"explicit repair save preserves damaged bytes in backup")
	_write(invalid_path, "[]")
	_expect(invalid.load_preferences() == ERR_FILE_CORRUPT, "non-object JSON rejected")
	_write(invalid_path, "x".repeat(4097))
	_expect(invalid.load_preferences() == ERR_FILE_CORRUPT, "oversized preferences rejected before parsing")
	var directory_path: AudioPreferences = AudioPreferences.new(_directory)
	_expect(directory_path.load_preferences() != OK and directory_path.save_preferences() != OK,
		"directory cannot be read or overwritten as a settings file")
	var blocker: String = _directory.path_join("blocked_parent")
	_write(blocker, "keep this unrelated file")
	var denied: AudioPreferences = AudioPreferences.new(blocker.path_join("audio.json"))
	_expect(denied.save_preferences() != OK and FileAccess.get_file_as_string(blocker) == "keep this unrelated file",
		"real IO failure preserves existing file and reports failure")
	for bad_path: String in ["", "relative.json", "res://audio.json"]:
		var rejected: AudioPreferences = AudioPreferences.new(bad_path)
		_expect(rejected.load_preferences() == ERR_INVALID_PARAMETER and rejected.save_preferences() == ERR_INVALID_PARAMETER,
			"no implicit or project-resource settings path: " + bad_path)


func _check_audio() -> void:
	var bus_count: int = AudioServer.bus_count
	var prefs: AudioPreferences = AudioPreferences.new(_directory.path_join("audio.json"))
	var service: B1AudioService = B1AudioService.new(prefs)
	root.add_child(service)
	await process_frame
	_expect(service.available_cues().size() == 6 and service.get_child_count() == 8, "six imported streams and fixed 6 world / 2 UI players")
	for cue: StringName in service.available_cues():
		var stream: AudioStreamWAV = service._streams[cue] as AudioStreamWAV
		_expect(stream != null and stream.get_length() > 0.05 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED
			and stream.format == AudioStreamWAV.FORMAT_16_BITS,
			"decoded non-looping WAV: " + String(cue))
	prefs.set_volume("master_volume", 0.5)
	prefs.set_volume("sfx_volume", 0.25)
	prefs.set_volume("ui_volume", 0.75)
	_expect(service.play_world(&"bus_start") and service.play_ui(&"ui_confirm"), "both channels play real streams")
	_expect(is_equal_approx(service._world_players[0].volume_linear, 0.02)
		and is_equal_approx(service._ui_players[0].volume_linear, 0.06), "separate channel products applied to active players")
	var before: Dictionary = prefs.snapshot()
	prefs.set_muted(true)
	_expect(is_zero_approx(service._world_players[0].volume_linear) and is_zero_approx(service._ui_players[0].volume_linear),
		"mute silences both active channels")
	prefs.set_muted(false)
	_expect(prefs.snapshot() == before and is_equal_approx(service._world_players[0].volume_linear, 0.02),
		"unmute restores original volumes")
	prefs.set_volume("sfx_volume", 0.0)
	_expect(is_zero_approx(service._world_players[0].volume_linear) and is_equal_approx(service._ui_players[0].volume_linear, 0.06),
		"world zero leaves UI gain unchanged")
	prefs.set_volume("sfx_volume", 0.25)
	await create_timer(0.14).timeout
	service.set_world_paused(true)
	paused = true
	await create_timer(0.06).timeout
	var position: float = service._world_players[0].get_playback_position()
	var ui_before: AudioStreamPlayer = service._ui_players[0]
	_expect(service.play_ui(&"ui_back") and not service.play_world(&"fire"), "UI works while world and SceneTree pause reject new world sounds")
	await create_timer(0.24).timeout
	_expect(service._world_players[0].stream_paused and absf(service._world_players[0].get_playback_position() - position) < 0.025,
		"paused world stream retains cursor")
	_expect(not ui_before.playing and _playing(service._ui_players) == 0, "UI finishes naturally while tree paused")
	paused = false
	service.set_world_paused(false)
	await create_timer(0.12).timeout
	_expect(service._world_players[0].get_playback_position() > position + 0.04, "world resumes at retained cursor")
	service.stop_world()
	_expect(_playing(service._world_players) == 0, "stop terminates all world voices")
	_expect(not service.play_world(&"absent") and not service.play_ui(&"fire"), "unknown and wrong-channel cues safely refused")
	var accepted: int = 0
	for index: int in range(500):
		if service.play_world(&"fire"):
			accepted += 1
		service.play_world(StringName("absent_" + str(index)))
	_expect(accepted == 1 and service.get_child_count() == 8 and service._warned.size() <= 2,
		"500 immediate repetitions coalesce, unknown bookkeeping stays bounded")
	# Saturate actual players with the longest production cue; bypass only the gate
	# so full-pool behavior is independent of asset duration and scheduler timing.
	service.stop_world()
	for index: int in range(B1AudioService.WORLD_VOICES):
		service._last_played.erase(&"bus_start")
		_expect(service.play_world(&"bus_start"), "fill real voice %d" % index)
	service._last_played.erase(&"bus_start")
	_expect(not service.play_world(&"bus_start") and _playing(service._world_players) == 6,
		"full world pool drops newest without allocating or stealing")
	service.set_world_paused(true)
	service.stop_world()
	service.set_world_paused(false)
	_expect(_playing(service._world_players) == 0, "stopped paused sounds never reappear on resume")
	service.play_world(&"fire")
	await create_timer(0.24).timeout
	_expect(_playing(service._world_players) == 0, "short world stream ends naturally")
	service.play_world(&"bus_start")
	service.play_ui(&"ui_confirm")
	service.shutdown()
	service.shutdown()
	_expect(_playing(service._world_players) == 0 and _playing(service._ui_players) == 0 and not service.play_world(&"fire"),
		"shutdown is idempotent, stops both channels and rejects further playback")
	service.queue_free()
	await process_frame
	_expect(not is_instance_valid(service) and prefs.changed.get_connections().is_empty(), "freed service leaves no preference connection")
	var missing: B1AudioService = B1AudioService.new(prefs, "res://assets/audio/b1/not_present")
	root.add_child(missing)
	_expect(missing.available_cues().is_empty() and not missing.play_world(&"fire"), "missing resources fail locally without crashing")
	missing.queue_free()
	await process_frame
	_expect(AudioServer.bus_count == bus_count, "module leaves global bus layout unchanged")


func _check_scene() -> void:
	var scene: B1Audition = AuditionScene.instantiate() as B1Audition
	scene.settings_override = _directory.path_join("scene.json")
	root.add_child(scene)
	await create_timer(0.16).timeout
	_expect(scene.preferences != null and scene._world_elapsed > 0, "independent scene loads and simulated world advances")
	scene._sliders["master_volume"].value = 42
	scene._mute.button_pressed = true
	_expect(scene.preferences.snapshot()["master_volume"] == 0.42 and scene.preferences.snapshot()["muted"],
		"real slider/checkbutton signals update preferences")
	scene._save()
	scene._sliders["master_volume"].value = 12
	scene._reload()
	_expect(scene._sliders["master_volume"].value == 42, "scene save/reload refreshes controls")
	var burst_button: Button
	for button: Node in scene.find_children("*", "Button", true, false):
		if (button as Button).text == "连续触发 × 12":
			burst_button = button as Button
	_expect(burst_button != null, "continuous audition button is connected")
	scene.stop_demo()
	scene.set_demo_paused(true)
	burst_button.pressed.emit()
	_expect(scene._burst_left == 0 and scene._status.text == "请恢复世界后再连续试听",
		"paused button refuses a new burst and explains how to continue")
	scene.set_demo_paused(false)
	await create_timer(0.12).timeout
	_expect(scene._burst_left == 0 and _playing(scene.audio._world_players) == 0,
		"resuming after rejected click cannot start a queued burst")
	burst_button.pressed.emit()
	await create_timer(0.12).timeout
	scene.set_demo_paused(true)
	var remaining: int = scene._burst_left
	var burst_clock: float = scene._burst_clock
	burst_button.pressed.emit()
	_expect(remaining > 0 and remaining < 12 and scene._burst_left == remaining and scene._burst_clock == burst_clock,
		"paused click does not reset a previously running burst")
	scene.set_demo_paused(false)
	await create_timer(0.12).timeout
	_expect(scene._burst_left < remaining, "previously running burst resumes its remaining rounds")
	scene.stop_demo()
	scene.audio.play_world(&"bus_start")
	scene.set_demo_paused(true)
	var elapsed: float = scene._world_elapsed
	await create_timer(0.25).timeout
	_expect(scene._world_elapsed == elapsed and paused, "scene pause actually freezes simulated world timer")
	scene.set_demo_paused(false)
	await create_timer(0.14).timeout
	_expect(scene._world_elapsed > elapsed, "scene resume restarts simulated world timer")
	var service: B1AudioService = scene.audio
	var player: AudioStreamPlayer = service._world_players[0]
	root.remove_child(scene)
	_expect(not player.playing and service._closed, "scene exit stops active playback before freeing")
	scene.queue_free()
	await process_frame
	_expect(not is_instance_valid(service) and not is_instance_valid(player), "scene release frees owned players")


func _playing(players: Array[AudioStreamPlayer]) -> int:
	var count: int = 0
	for player: AudioStreamPlayer in players:
		if player.playing:
			count += 1
	return count


func _write(path: String, contents: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "fixture created: " + path.get_file())
	if file != null:
		file.store_string(contents)
		file.close()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS B1 " + message)
	else:
		_failures += 1
		push_error("FAIL B1 " + message)
