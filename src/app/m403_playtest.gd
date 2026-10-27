class_name M403Playtest
extends M402Playtest
## Identity/art proof uses ordinary UI and existing practice intents; never edits game values.

var _art_trace: Array[Dictionary] = []
var _art_key: String = ""
var _bad_costume: int = 0
var _grip_error: float = 0.0
var _identity_mode: String = "scavenge"
var _instant_labels: Dictionary[String, bool] = {}


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m402-mode="):
			_identity_mode = argument.trim_prefix("--m402-mode=")
	if _identity_mode in ["scavenge", "market", "reopen-scavenge", "reopen-market"]:
		await super._run()
		return
	_sequence = _identity_mode
	_mode = _identity_mode
	DirAccess.make_dir_recursive_absolute(output_dir)
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,"frame":Engine.get_frames_drawn()}))
	await _capture("m403-001-home")
	if _identity_mode == "corrupt":
		_expect(app._progress_blocked and app._backup_button.visible, "invalid save offers explicit checked backup")
		_expected = app._backup_save.duplicate(true)
		await _click_screen(app._backup_button.get_global_rect().get_center())
	elif app._requires_continue:
		_expected = app._pending_save.duplicate(true)
		await _click_screen(app._continue_button.get_global_rect().get_center())
	else:
		await _click_screen(app._home_button.get_global_rect().get_center())
	if not _expected.is_empty():
		_expect(app.camp_snapshot() == _expected and _hash(app.run_save.path) == _initial_save_hash, "native Continue/backup retains exact resources, health, names, ownership and original bytes")
		_expect(app.run_save.migrated_from == 0, "historical v4 needs no migration or extra identity save fields")
	_before = app.camp_snapshot()
	await _capture("m403-002-camp")
	if _identity_mode == "custom":
		await _rename(1, "蓝时归航观察员一号同行者")
		await _rename(2, "NorthStar_02")
		var after: Dictionary = app.camp_snapshot()
		var names_only: Dictionary = _before.duplicate(true)
		names_only.crew[0].call_sign = after.crew[0].call_sign
		names_only.crew[1].call_sign = after.crew[1].call_sign
		_expect(after == names_only, "native Chinese/English custom rename changes only call signs")
		_before = after
	await _profiles()
	await _click_screen(app.roster_panel.equipment_button.get_global_rect().get_center())
	await _capture("m403-005-equipment")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	if _identity_mode == "actions":
		await _actions()
	else:
		var bytes: String = _hash(app.run_save.path)
		await _enter_task()
		await _key(KEY_SPACE)
		await _capture("m403-006-identities-in-field")
		_expect(app.camp_snapshot() == _before and _hash(app.run_save.path) == bytes, "unsettled field entry preserves camp and saved bytes")
	await _finish_proof()


func _rename(member_id: int, value: String) -> void:
	if _identity_mode == "scavenge" and value in ["Azure", "Amber"]:
		value = SurvivorRoster.definition(member_id).default_display_name
	await super._rename(member_id, value)


func _profiles() -> void:
	if app.roster_panel == null or not app.roster_panel.visible:
		await _click_screen(app._roster_button.get_global_rect().get_center())
	for member_id: int in [1, 2]:
		await _click_screen(app.roster_panel.member_buttons[member_id - 1].get_global_rect().get_center())
		var definition: SurvivorDefinition = SurvivorRoster.definition(member_id)
		var panel: RosterPanel = app.roster_panel
		_expect(panel._identity.text == definition.default_display_name and panel._gender_title.definition == definition
			and panel._gender_detail.prefix == "性别：" and panel._gender_detail.definition == definition, "profile shows immutable formal name and both explicit gender badges for member%d" % member_id)
		_expect(panel._call_sign.text == "呼号：" + String(SurvivorRoster.member(app.crew, member_id).call_sign), "profile preserves full saved alias independently of formal name")
		_expect(panel._gender_detail.get_global_rect().end.y < panel.name_edit.get_global_rect().position.y
			and panel.back_button.get_global_rect().end.y <= 720.5, "gender is final detail line and profile controls remain visible")
		await super._capture("m403-profile-%02d" % member_id)


func _capture(file_name: String) -> void:
	if file_name == "m402-003-amber-profile":
		await _profiles()
	await super._capture(file_name)


func _enter_task() -> void:
	await super._enter_task()
	var camera: FieldCamera = app.expedition.camera
	var zoom: float = camera.zoom.x
	camera.zoom_at(Vector2(640,360),0.82 / zoom)
	await _capture("m403-arrival-default")
	camera.zoom_at(Vector2(640,360),zoom / camera.zoom.x)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if app.expedition == null or app.expedition.survivors.size() != 2:
		return
	var actor: FieldActor = app.expedition.survivors[1]
	var visual: ActorVisual = actor.visual
	var pose: Dictionary = visual.presentation_state()
	_grip_error = maxf(_grip_error, pose.grip.distance_to(pose.hand))
	if visual._body.texture != CrewAppearance.AMBER_LEGS or visual._upper.texture != CrewAppearance.AMBER_UPPER:
		_bad_costume += 1
	var key: String = "%s/%s/%s/%s/%s/%s" % [pose.state,pose.frame,pose.row,visual._body.flip_h,actor.visible,actor.activity]
	if key != _art_key:
		_art_key = key
		_art_trace.append({"frame":Engine.get_frames_drawn(),"elapsed":app.expedition.elapsed,
			"state":pose.state,"moving":pose.velocity.length_squared() > 1.0,"lower_frame":pose.frame,"aim_row":pose.row,"flipped":visual._body.flip_h,
			"visible":actor.visible,"activity":actor.activity,"position":[actor.position.x,actor.position.y],
			"weapon_layer":pose.weapon_layer,"grip_error":pose.grip.distance_to(pose.hand)})


func _on_feedback(event: Dictionary) -> void:
	super._on_feedback(event)
	if event.get("actor") != 1 or event.get("kind") not in ["shot", "hit"]:
		return
	var key: String = "m403-xia-hit"
	if event.kind == "shot":
		var facing: Vector2 = event.facing
		var direction: String = ("north" if facing.y < 0 else "south") if absf(facing.y) > absf(facing.x) * 0.8 else ("west" if facing.x < 0 else "east")
		key = "m403-xia-%s-%s-%s" % [event.weapon,direction,"moving" if event.moving else "standing"]
	if not _instant_labels.has(key):
		_instant_labels[key] = true
		_instant_capture.call_deferred(key)


func _instant_capture(label: String) -> void:
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	_expect(picture.save_png(output_dir.path_join(label + ".png")) == OK, "native action frame captured: " + label)
	_captures.append({"file":label + ".png","movie_frame":Engine.get_frames_drawn(),"app_phase":app.phase,"world":_world_state(app.expedition)})


func _incoming_at_xia(practice: Expedition, direction: Vector2, distance: float = 175.0) -> void:
	var offset: Vector2 = practice.survivors[1].position + direction * distance - practice.survivors[0].position
	practice.practice_incoming(offset.normalized(), offset.length())


func _actions() -> void:
	var camp_bytes: String = _hash(app.run_save.path)
	await _click_control("Interface/Screen/Title/Practice")
	var practice: Expedition = app.expedition
	_expect(practice != null and practice.is_practice, "existing isolated practice opened through actual button")
	_incoming_at_xia(practice, Vector2.DOWN, 12.0)
	var limit: int = 0
	while not _instant_labels.has("m403-xia-hit") and limit < 120:
		await _wait(0.05)
		limit += 1
	_expect(practice.survivors[1].health < 200.0 and _instant_labels.has("m403-xia-hit"), "Xia receives ordinary enemy damage and actual hit animation")
	practice.command_move(practice.survivors[1].position + Vector2.RIGHT * 100)
	await _wait(1.6)
	var directions: Array[Vector2] = [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]
	var labels: Array[String] = ["east","west","north","south"]
	for view: WeaponPresentation in [ActorVisual.CarbineView, ActorVisual.LongRifleView]:
		practice.practice_weapon(view)
		for index: int in range(directions.size()):
			var direction: Vector2 = directions[index]
			var first: int = _feedback.size()
			_incoming_at_xia(practice,direction)
			await _wait(0.8)
			_incoming_at_xia(practice,direction)
			await _capture("m403-action-%s-%s-standing" % [view.id,labels[index]])
			await _wait(1.2)
			var centre: Vector2 = (practice.survivors[0].position + practice.survivors[1].position) * 0.5
			practice.command_move(centre + direction * 112)
			_incoming_at_xia(practice,direction)
			await _wait(0.25)
			_incoming_at_xia(practice,direction)
			await _capture("m403-action-%s-%s-moving" % [view.id,labels[index]])
			await _wait(1.4)
			var standing: bool = false
			var moving: bool = false
			for event: Dictionary in _feedback.slice(first):
				if event.kind == "shot" and event.actor == 1 and event.weapon == String(view.id) and (event.facing as Vector2).dot(direction) > 0.75:
					standing = standing or not event.moving
					moving = moving or event.moving
			_expect(standing and moving, "Xia actually fires %s standing and moving toward %s" % [view.id,labels[index]])
	practice.request_extraction()
	await _capture("m403-practice-finished")
	await _check_finished(practice)
	await _click_control("Interface/Screen/Result/Continue")
	_expect(app.camp_snapshot() == _before and _hash(app.run_save.path) == camp_bytes, "practice injury and weapon views never mutate saved campaign")


func _finish_proof() -> void:
	_expect(_bad_costume == 0 and _grip_error < 0.001, "new dress parts remain active with calibrated grip across actual movement, aim, fire and search")
	if _identity_mode == "actions":
		_expect(_art_trace.any(func(sample: Dictionary) -> bool: return sample.state == "hit" and sample.moving), "ordinary hit preserves moving dress animation without a new movement lock")
		for frame: int in [1,2,3,5,6,7,9,10,11]:
			_expect(_art_trace.any(func(sample: Dictionary) -> bool: return sample.lower_frame == frame), "actual movement displays dress walk frame%d" % frame)
	_write_json("identity-art-report.json", {"mode":_identity_mode,"costume_fallback_frames":_bad_costume,"maximum_grip_error":_grip_error,
		"camp_art":CampBackdrop.ART.resource_path,"upper":CrewAppearance.AMBER_UPPER.resource_path,
		"lower":CrewAppearance.AMBER_LEGS.resource_path,"samples":_art_trace,"instant_action_frames":_instant_labels.keys(),
		"identity":[{"id":1,"name":SurvivorRoster.definition(1).default_display_name,"gender":SurvivorRoster.definition(1).gender_text()},
			{"id":2,"name":SurvivorRoster.definition(2).default_display_name,"gender":SurvivorRoster.definition(2).gender_text()}]})
	await super._finish_proof()
