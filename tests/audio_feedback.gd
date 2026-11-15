extends SceneTree
## Isolated contracts: actual weapon commits, warning edges, mixing and settings.

var checks: int = 0
var failures: int = 0
var preferences: AudioPreferences
var service: B1AudioService


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	preferences = AudioPreferences.new(ProjectSettings.globalize_path("res://.local/audio-contract/settings.json"))
	service = B1AudioService.new(preferences)
	root.add_child(service)
	_check_registry()
	_check_settings()
	_check_pool_and_pause()
	_check_missing()
	_check_field_events()
	service.shutdown()
	_check(not service.play_ui(&"ui_confirm") and not preferences.changed.is_connected(service._apply_preferences),
		"shutdown disconnects preferences and rejects playback")
	await create_timer(0.2).timeout
	service.free()
	print("BH_AUDIO_FEEDBACK checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_registry() -> void:
	_check(service.available_cues().size() == 15 and B1AudioService.CUES.size() == 15,
		"all fifteen registered cues have imported streams")
	for cue: StringName in B1AudioService.CUES:
		_check(service.available_cues().has(cue), "resource exists for " + String(cue))
		var stream: AudioStreamWAV = service._streams.get(cue) as AudioStreamWAV
		_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
			"one-shot never loops: " + String(cue))
	_check(service.get_child_count() == 8, "six world plus two UI players, no per-event allocation")


func _check_settings() -> void:
	_check(preferences.snapshot() == AudioPreferences.DEFAULTS, "existing defaults are preserved")
	var panel: SoundSettingsPanel = SoundSettingsPanel.new()
	panel.preferences = preferences
	root.add_child(panel)
	panel.sliders["master_volume"].value = 50
	panel.sliders["sfx_volume"].value = 25
	panel.sliders["ui_volume"].value = 75
	_check(is_equal_approx(service._world_players[0].volume_linear, 0.5 * 0.25 * B1AudioService.VOICE_GAIN)
		and is_equal_approx(service._ui_players[0].volume_linear, 0.5 * 0.75 * B1AudioService.VOICE_GAIN),
		"real panel sliders immediately apply master and separate category gains")
	_check(service.play_world(&"bus_start"), "world enabled before mute")
	panel.mute_button.button_pressed = true
	_check(not service._world_players.any(func(p: AudioStreamPlayer) -> bool: return p.playing), "mute stops existing tails")
	for cue: StringName in B1AudioService.CUES:
		_check(not (service.play_ui(cue) if B1AudioService.CUES[cue].channel == &"ui" else service.play_world(cue)),
			"mute rejects every cue: " + String(cue))
	panel.mute_button.button_pressed = false
	panel.sliders["sfx_volume"].value = 0
	_check(not service.play_world(&"fire") and service.play_ui(&"ui_confirm"), "world off leaves UI available")
	panel.sliders["sfx_volume"].value = 100
	panel.sliders["ui_volume"].value = 0
	_check(service.play_world(&"fire") and not service.play_ui(&"ui_back"), "UI off leaves world available")
	panel.sliders["master_volume"].value = 0
	_check(not service.play_world(&"nightfall") and not service.play_ui(&"ui_back"), "zero master gates both channels")
	panel.free()
	for key: String in AudioPreferences.VOLUME_KEYS:
		preferences.set_volume(key, 1.0)
	service.stop_world()


func _check_pool_and_pause() -> void:
	for cue: StringName in [&"fire", &"melee_swing", &"hit", &"survivor_hit"]:
		_check(service.play_world(cue), "combat occupies one slot: " + String(cue))
	service._last_played.erase(&"fire")
	_check(not service.play_world(&"fire"), "combat cannot occupy two reserved world slots")
	_check(service.play_world(&"bus_start") and service.play_world(&"collect_complete"), "notifications fill reserved slots")
	_check(service.play_world(&"screamer_warning"), "warning replaces lower-priority voice in full pool")
	_check(service.get_child_count() == 8, "saturated requests keep fixed voice count")
	service.stop_world()
	_check(service.play_world(&"nightfall") and not service.play_world(&"nightfall"), "retrigger interval coalesces spam")
	service.set_world_paused(true)
	_check(service._world_players.all(func(p: AudioStreamPlayer) -> bool: return p.stream_paused), "existing world voices freeze")
	_check(not service.play_world(&"fire") and service.play_ui(&"ui_back"), "pause blocks world while UI stays live")
	service.stop_world()
	_check(not service.play_world(&"fire"), "stopping does not resume the world")
	service.set_world_paused(false)
	_check(service.play_world(&"fire"), "resume has no backlog and permits fresh sounds")
	service.stop_world()


func _check_missing() -> void:
	var missing: B1AudioService = B1AudioService.new(preferences, "res://.local/audio-contract/absent")
	var diagnostics: Array[String] = []
	missing.diagnosed.connect(func(message: String) -> void: diagnostics.append(message))
	root.add_child(missing)
	_check(diagnostics.size() == B1AudioService.CUES.size(), "missing resources diagnose after subscribers attach")
	_check(not missing.play_world(&"fire") and not missing.play_world(&"fire")
		and diagnostics.size() == B1AudioService.CUES.size(), "missing resource stays silent and warns once")
	missing.play_world(&"unknown_one")
	missing.play_ui(&"unknown_two")
	_check(diagnostics.size() == B1AudioService.CUES.size() + 1, "unknown IDs share one bounded warning")
	missing.shutdown()
	missing.free()
	var wrong: Array[String] = []
	service.diagnosed.connect(func(message: String) -> void: wrong.append(message))
	_check(not service.play_ui(&"fire") and not service.play_ui(&"fire") and wrong.size() == 1,
		"wrong-channel requests respect category settings and diagnose once")


func _check_field_events() -> void:
	# Same minimal actor setup as weapon_holding: real rule commits, no player save.
	var world: Expedition = Expedition.new()
	world.supply = MissionSupply.new()
	world.supply.generated = {"version":8, "build":{"slots":["", ""]}}
	world._effects = Node2D.new()
	root.add_child(world._effects)
	var app: AppMain = AppMain.new()
	app.expedition = world
	app.audio = service
	world.combat_feedback.connect(app._on_combat_feedback)
	world.audio_cue_requested.connect(app._request_audio.bind(true))
	world.search_completed.connect(app._on_search_completed)
	world.engine_started.connect(app._on_engine_started)
	var cues: Array[StringName] = []
	app.audio_requested.connect(func(cue: StringName, _world: bool, _accepted: bool) -> void: cues.append(cue))
	var actor: FieldActor = FieldActor.new()
	actor.member_id = 1
	actor.position = Vector2(400, 400)
	root.add_child(actor)
	var target: FieldActor = FieldActor.new()
	target.is_enemy = true
	target.actor_id = 2
	target.position = actor.position + Vector2(32, 0)
	root.add_child(target)
	world.survivors = [actor]
	world.enemies = [target]
	for id: String in ["fire_axe_v1", "rescue_hammer_v1", "shotgun_v1"]:
		service.stop_world()
		cues.clear()
		target.health = 1000.0
		actor.weapon_definition = CombatEquipment.definition(id)
		actor.visual.set_weapon(actor.weapon_definition.presentation)
		actor.cooldown = 0.0
		actor.magazine = null if CombatEquipment.melee(id) else WeaponMagazine.new("audio:test", id)
		world.combat.actions.clear()
		world.combat.attack(world, actor, 0.0)
		if CombatEquipment.melee(id):
			_check(cues.is_empty(), "melee windup stays silent before commit")
			world.combat.attack(world, actor, float(CombatEquipment.melee_policy(id).windup))
		_check(cues.count(&"melee_swing" if CombatEquipment.melee(id) else &"fire") == 1
			and cues.count(&"hit") == 1, "real " + id + " commit produces action and one impact cue")
	cues.clear()
	actor.weapon_definition = WeaponInventory.definition("carbine")
	actor.visual.set_weapon(actor.weapon_definition.presentation)
	actor.magazine = null
	actor.cooldown = 0.0
	target.health = 1000.0
	actor.aim = Vector2.RIGHT
	world._fire_ranged(actor, target, world.evaluate_attack(actor, target))
	_check(cues.count(&"fire") == 1 and cues.count(&"hit") == 1, "ranged has one fire and one impact without duplication")
	cues.clear()
	world._hit_effect(actor.position, 6.0, true)
	world._hit_effect(actor.position, 0.0, true)
	_check(cues == [&"survivor_hit"], "positive survivor damage uses padded cue; zero stays silent")
	# Actual windups: warning circles appear here, rather than at spawn or redraw.
	target.enemy_behavior = EnemyBehavior.new()
	target.enemy_behavior.kind = ScreamerPolicyV1.KIND
	world.combat.screamer = ScreamerRuntimeV1.new()
	world.combat.screamer.spawned(world, target)
	cues.clear()
	world.combat.screamer.advance(world, 0.0)
	world.combat.screamer.present(world)
	_check(cues.count(&"screamer_warning") == 1, "screamer warns on real windup circle, never spawn/redraw")
	target.enemy_behavior.kind = BurstRuntimeV1.KIND
	world.combat.burst = BurstRuntimeV1.new()
	world.combat.burst.spawned(world, target)
	cues.clear()
	world.combat.burst.advance(world, 0.0)
	_check(cues.count(&"burst_warning") == 1, "burst warns at real pressure-ring windup")
	_check_warning_edges(world, cues)
	cues.clear()
	world.search_completed.emit(3)
	world.engine_started.emit()
	_check(cues.has(&"collect_complete") and cues.has(&"bus_start"), "search and engine reach production callbacks")
	var journey: BusJourney = BusJourney.new()
	journey.world = world
	journey.stage = "exploring"
	journey.skip_button = Button.new()
	journey.audio_cue_requested.connect(app._request_audio.bind(true))
	world.phase = Expedition.Phase.FINISHED
	cues.clear()
	journey.departure()
	journey.departure()
	journey.advance(BusJourney.EMBARK)
	_check(cues == [&"bus_board", &"bus_depart"], "real boarding and departure stages each sound once")
	journey.skip_button.free()
	journey.free()
	world._effects.free()
	actor.free()
	target.free()
	world.free()
	app.free()


func _check_warning_edges(world: Expedition, cues: Array[StringName]) -> void:
	cues.clear()
	world.combat.toxic = ToxicV1.initial()
	var caster: Dictionary = {"id":2, "foot":world.enemies[0].position, "alive":true, "available":true}
	var member: Dictionary = {"id":1, "foot":world.survivors[0].position, "alive":true, "available":true}
	world.combat.toxic = ToxicV1.plan(world.combat.toxic, 0.0, [caster], [member], []).state
	var snapshot: Dictionary = world.combat.snapshot()
	world._feedback._refresh_audio()
	world._feedback._refresh_audio()
	_check(cues.count(&"toxic_warning") == 1 and world.combat.snapshot() == snapshot,
		"real toxic intent warns once; redraw never advances rule state")
	world.combat.toxic.casters["2"].sequence += 1
	world._feedback._refresh_audio()
	_check(cues.count(&"toxic_warning") == 2, "a new toxic cast sequence gets a fresh warning")
	world.enemies[0].enemy_behavior.kind = NightHoundV1.KIND
	world.enemies[0].enemy_behavior.state = "windup"
	world._feedback._refresh_audio()
	world._feedback._refresh_audio()
	_check(cues.count(&"hound_warning") == 1, "hound windup warns once despite repeated refresh")
	world.enemies[0].enemy_behavior.state = "chase"
	world._feedback._refresh_audio()
	world.enemies[0].enemy_behavior.state = "windup"
	world._feedback._refresh_audio()
	_check(cues.count(&"hound_warning") == 2, "later hound windup can warn again")
	world.elapsed = world.tuning.daylight_seconds
	world._feedback._refresh_audio()
	world._feedback._refresh_audio()
	world.elapsed *= 2.0
	world._feedback._refresh_audio()
	_check(cues.count(&"nightfall") == 1, "nightfall is one edge, including deep night")
	var restored: Expedition = Expedition.new()
	restored.is_paused = true
	restored.elapsed = restored.tuning.daylight_seconds + 1.0
	restored.audio_cue_requested.connect(func(cue: StringName) -> void: cues.append(cue))
	restored._feedback._refresh_audio()
	restored.is_paused = false
	restored._feedback._refresh_audio()
	_check(cues.count(&"nightfall") == 1, "paused restored night seeds presentation without replay")
	restored.free()


func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("BH_AUDIO_FEEDBACK " + label)
