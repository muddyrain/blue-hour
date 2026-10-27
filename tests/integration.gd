extends SceneTree
## Exercise actual app bindings separately from service throttling/playback results.

const MainScene: PackedScene = preload("res://src/app/main.tscn")

var _checks: int = 0
var _failures: int = 0
var _requests: Array[Dictionary] = []
var _combat: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280,720)
	var main: Node = MainScene.instantiate()
	main.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_requests.append({"cue": cue, "world": world, "accepted": accepted})
	)
	root.add_child(main)
	await process_frame
	_expect(main.audio.available_cues().size() == 6, "app owns one real six-cue service")
	_expect(main.audio_preferences.settings_path().contains(".local"), "app checks use explicit isolated preferences")
	main.open_sound_settings()
	var panel: SoundSettingsPanel = main.sound_settings
	panel.sliders["master_volume"].value = 63
	panel.sliders["sfx_volume"].value = 23
	panel.sliders["ui_volume"].value = 91
	panel.mute_button.button_pressed = true
	_expect(main.audio_preferences.snapshot() == {"master_volume":0.63,"sfx_volume":0.23,"ui_volume":0.91,"muted":true}, "formal controls update the single shared preferences immediately")
	panel.save()
	var loaded: AudioPreferences = AudioPreferences.new(main.audio_preferences.settings_path())
	_expect(loaded.load_preferences() == OK and loaded.snapshot() == main.audio_preferences.snapshot(), "formal save writes the four actual fields")
	var good_preferences: AudioPreferences = panel.preferences
	panel.preferences = AudioPreferences.new(ProjectSettings.globalize_path("res://.local/"))
	panel.save()
	_expect(panel.message.text.begins_with("保存失败"), "formal UI never reports a directory write failure as saved")
	panel.preferences = good_preferences
	panel.mute_button.button_pressed = false
	_expect(is_equal_approx(main.audio._world_players[0].volume_linear,0.63*0.23*0.16), "formal controls immediately change real world player gain")
	panel.close_panel()
	main.open_practice()
	var practice: Expedition = main.expedition
	practice.set_physics_process(false)
	practice.combat_feedback.connect(func(event: Dictionary) -> void: _combat.append(event))
	_requests.clear()
	practice.step(1.4)
	var shots: int = 0
	var hits: int = 0
	for event: Dictionary in _combat:
		if event["kind"] == "shot":
			shots += 1
		if event.get("applied_damage", 0.0) > 0.0:
			hits += 1
	_expect(shots > 0 and hits > shots, "real combat includes player shots and enemy damage")
	_expect((practice._hud.view._members[0]["health"] as Label).text == "生命 196 / 200", "integrated C HUD reads actual practice health and stable identity")
	_expect(_cue_count(&"fire") == shots and _cue_count(&"hit") == hits, "exactly one request per real shot and positive applied hit, regardless of service throttling")
	practice.toggle_pause()
	_expect(main.audio._world_paused, "actual pause freezes world voices")
	_expect(not main.audio.play_world(&"bus_start"), "paused world requests are rejected")
	var before: float = practice.elapsed
	practice.step(5.0)
	_expect(practice.elapsed == before, "audio integration preserves the gameplay pause contract")
	practice.request_extraction()
	_expect(main.phase == main.Phase.RESULT and _world_stopped(main.audio), "accepted result stops every world voice")
	_expect(not practice.combat_feedback.is_connected(main._on_combat_feedback), "finish unbinds the app combat listener immediately")
	main.return_to_title()
	await process_frame
	main.open_expedition()
	var sortie: Expedition = main.expedition
	sortie.set_physics_process(false)
	_expect(not main.audio._world_paused, "new normal sortie explicitly clears previous pause state")
	_expect(sortie._hud.view._mission.text == sortie.mission_title and sortie._hud.view._bus_button.disabled,
		"normal HUD uses current mission and truthful not-ready bus state")
	_requests.clear()
	sortie.request_extraction()
	_expect(_cue_count(&"bus_start") == 0, "not-ready bus cannot emit success sound")
	sortie.step(sortie.tuning.bus_ready_seconds)
	sortie.request_extraction()
	sortie.request_extraction()
	_expect(_cue_count(&"bus_start") == 1, "accepted bus transition emits once, duplicate request is silent")
	var isolated_path: String = main.audio_preferences.settings_path()
	main.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	var damaged: FileAccess = FileAccess.open(isolated_path,FileAccess.WRITE)
	damaged.store_string("{invalid sound preferences")
	damaged.close()
	var broken: Node = MainScene.instantiate()
	root.add_child(broken)
	broken.open_sound_settings()
	_expect(broken.sound_settings.message.text.contains("读取失败") and FileAccess.get_file_as_string(isolated_path) == "{invalid sound preferences",
		"actual app visibly handles corrupt settings without automatic overwrite")
	broken.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("BH_INTEGRATION checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _world_stopped(service: B1AudioService) -> bool:
	for player: AudioStreamPlayer in service._world_players:
		if player.playing:
			return false
	return true


func _cue_count(cue: StringName) -> int:
	var count: int = 0
	for request: Dictionary in _requests:
		if request["cue"] == cue:
			count += 1
	return count


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL integration: " + label)
	else:
		print("PASS integration: " + label)
