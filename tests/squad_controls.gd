extends "res://tests/squad_long_run.gd"
## Directed legal eight-person App fixture, viewport events and native rendering.
## No physical mouse/keyboard, earned campaign or unit-selection feature is claimed.

const MAIN: PackedScene = preload("res://src/app/main.tscn")
var app: AppMain
var viewport: SubViewport
var output: String
var evidence: Array[Dictionary] = []
var assertions: Array[Dictionary] = []


func expect(value: bool, label: String) -> void:
	checks += 1
	assertions.append({"pass":value,"label":label})
	if not value:
		failures += 1
		printerr("BH_SQUAD_CONTROLS_FAIL " + label)


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	root.unfocusable = true
	output = ProjectSettings.globalize_path("res://.local/squad-controls/" + RunSave.new_profile_id())
	DirAccess.make_dir_recursive_absolute(output)
	await live_support()
	for casualty: bool in [false, true]:
		await scenario(casualty)
	var report: Dictionary = {"checks":assertions,"failures":failures,"evidence":evidence,
		"renderer":DisplayServer.get_name(),"input":"SubViewport.push_input: mouse press/release/motion/wheel, key press/release; real App/Main/Expedition handlers",
		"fixture":"validated directed eight-person camp mounted in original App/Expedition scenes; fixed-step simulation; background spawn clocks delayed; separate real two-person App session for E acceptance",
		"not_covered":["physical OS input or human play","earned eight-person campaign or eight-person persistence","unit selection/box selection/multiselect/count: absent in production","R successful release: initial loadout empty"],"output":output}
	var file: FileAccess = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BH_SQUAD_CONTROLS " + JSON.stringify({"checks":checks,"failures":failures,"report":output.path_join("report.json")}))
	quit(1 if failures else 0)


func live_support() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_2d = World2D.new()
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	app = MAIN.instantiate() as AppMain
	viewport.add_child(app)
	while app._startup_pending: await process_frame
	await activate(app._home_button)
	await activate(app._new_game_confirmation.get_ok_button())
	expect(not app._progress_blocked and app.crew.size() == 2, "real App new journey keeps original two-person start")
	await activate(app.camp_scene.hotspots[&"bus"])
	var deadline: int = Time.get_ticks_msec() + 90000
	while app.mission_select.loading and Time.get_ticks_msec() < deadline: await process_frame
	await activate(app.mission_select.choices[0])
	await activate(app.mission_select.depart_button)
	var world: Expedition = app.expedition
	expect(world != null and not app._progress_blocked, "real App departure starts signed two-person action")
	if world != null:
		world.set_process(false)
		world.set_physics_process(false)
		await advance(world, func() -> bool: return not world.bus_view.running(), 600)
		var patient: FieldActor = world.search_member(1)
		expect(patient.take_damage(40.0), "directed nonlethal injury uses real App persisted damage gate")
		var health: float = patient.health
		await key(KEY_E)
		expect(world.search_member(1).health > health and world.basic_support.snapshot().sequence == 1 and not world.is_paused, "E input heals through original App support transaction and snapshot apply")
		await key(KEY_E)
		expect(world.basic_support.snapshot().sequence == 1, "E reissue during cooldown does not replay acceptance")
		await key(KEY_R)
		expect(world._notice_text == "当前没有可释放的特技" and world.powers.accepted.is_empty(), "R initial empty loadout gives original feedback without acceptance")
	await dispose()


func activate(button: BaseButton) -> void:
	await settle()
	expect(button.is_visible_in_tree() and not button.disabled, "available production UI button: " + String(button.name))
	if not button.is_visible_in_tree() or button.disabled: return
	button.grab_focus()
	await key(KEY_ENTER)


func scenario(casualty: bool) -> void:
	var base: Dictionary = _fixture(8)
	expect(TransactionReceipt.camp_problem(base).is_empty(), "directed eight-person camp passes original validation")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1024, 576)
	viewport.world_2d = World2D.new()
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	app = MAIN.instantiate() as AppMain
	viewport.add_child(app)
	while app._startup_pending:
		await process_frame
	# Fixture composition only. Midgame registration is forbidden by the save
	# owner; do not bypass that check or fabricate a receipt history. The real
	# App receives all events, the real Expedition owns all commands/extraction.
	app.progress_session.close()
	app._apply_progress(base)
	app._hunger_consented = true
	var world: Expedition = app.ExpeditionScene.instantiate() as Expedition
	world.supply = DailyActions.supply(DailyActions.offers(base)[0])
	world.field_departure = base
	world.battle_survival = true
	world.sortie_id = "%s:%d" % [base.profile_id, int(base.settled_sorties) + 1]
	world.day = int(base.day)
	world.initial_food = int(base.food)
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	var rules: Dictionary = FrozenSettlement.pool_rules(base, world.supply)
	world.growth_binding = {"run_id":base.profile_id,"root_id":base.journey.root_id,"transaction_id":world.sortie_id,
		"base_hash":SurvivalContracts.fingerprint(base),"rules_hash":SurvivalContracts.fingerprint(rules)}
	world.ui_theme = app._screen.theme
	app.expedition = world
	app.phase = app.Phase.EXPEDITION
	app._screen.hide()
	app.camp_scene.hide()
	app.get_node("World").add_child(world)
	# Same original presentation invoked on finish; no settlement/save claim.
	world.finished.connect(func(_report: Dictionary) -> void: world.bus_view.departure())
	world.set_process(false)
	world.set_physics_process(false)
	world.camera.set_process(false)
	await advance(world, func() -> bool: return not world.bus_view.running(), 600)
	expect(world.setup_problem.is_empty() and world.survivors.size() == 8 and world.survivors.all(func(a: FieldActor) -> bool: return a.visible), "formal arrival disembarks all eight equipped actors")
	# This isolates operations; clock, contacts, work, navigation and extraction
	# remain original. It is not another night-pressure/performance test.
	world._spawn_clock = 1000000.0
	world._ai_clock = 1000000.0
	await inspect_portraits(world, Vector2i(1024, 576))
	viewport.size = Vector2i(1280, 720)
	await settle()
	await inspect_portraits(world, Vector2i(1280, 720))
	viewport.size = Vector2i(1024, 576)
	await settle()
	await inspect_commands(world)
	if casualty:
		var fallen: FieldActor = world.search_member(3)
		fallen.permanent_death_enabled = true
		fallen.damage_gate = func(_actor: FieldActor, _proposal: Dictionary) -> int: return OK
		expect(fallen.take_damage(fallen.health), "directed casualty enters original damage path (fixture ACK, no persistence claim)")
		expect(fallen.activity == FieldActor.Activity.DOWN and fallen.permanent_death and world.living_count() == 7, "real death removes exactly one living member")
		var prior: PackedVector2Array = fallen.path.duplicate()
		await key(KEY_Q)
		await map_click(world, world.layout.bus_door + Vector2(90, 90))
		expect(fallen.path == prior and fallen.activity == FieldActor.Activity.DOWN, "Q never commands the fallen actor")
		await map_click(world, fallen.position)
		expect(fallen.path == prior and fallen.activity == FieldActor.Activity.DOWN, "clicking fallen actor does not command or revive it")
		var hud: C1ExpeditionHud = world._hud.view
		for attempt: int in range(30):
			if hud._member_scroll.scroll_vertical == 0: break
			await wheel(hud._member_scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, 1)
		await tap(hud._persona_cards[2].portrait_button.get_global_rect().get_center())
		expect(hud._persona_id == 3 and hud.persona_details.visible and fallen.path == prior, "fallen portrait opens read-only details without commanding the dead")
		await key(KEY_ESCAPE)
		world._update_ui()
		await screenshot_both(world, "casualty")
	await inspect_boarding(world, casualty)
	await dispose()


func inspect_portraits(world: Expedition, dimensions: Vector2i) -> void:
	var hud: C1ExpeditionHud = world._hud.view
	var scroll: ScrollContainer = hud._member_scroll
	await settle()
	expect(hud._persona_cards.size() == 8, "production HUD contains all eight stable identities at " + str(dimensions))
	var zoom: Vector2 = world.camera.zoom
	for attempt: int in range(30):
		if scroll.scroll_vertical == 0: break
		await wheel(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, 1)
	expect(scroll.scroll_vertical == 0, "wheel reaches top of eight-person list")
	await screenshot(world, "eight-list-top")
	for index: int in range(8):
		var card: PersonaCard = hud._persona_cards[index]
		for attempt: int in range(30):
			if scroll.get_global_rect().encloses(card.portrait_button.get_global_rect()): break
			await wheel(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN, 1)
		expect(scroll.get_global_rect().encloses(card.portrait_button.get_global_rect()), "wheel makes actual portrait %d clickable" % (index + 1))
		var goal: Vector2 = world.goal
		await tap(card.portrait_button.get_global_rect().get_center())
		expect(hud.persona_details.visible and hud._persona_id == world.survivors[index].member_id, "portrait click opens matching stable-member details %d" % (index + 1))
		expect(world.goal == goal, "portrait inspection does not issue movement")
		await key(KEY_ESCAPE)
		expect(not hud.persona_details.visible and not app.pause_menu.root.visible, "App Esc closes portrait details without pausing")
	expect((scroll.scroll_vertical > 0 or hud._members_parent.size.y <= scroll.size.y) and world.camera.zoom == zoom, "list scrolling reaches all eight and does not zoom world")
	await screenshot(world, "eight-list-bottom")
	evidence.append({"size":str(dimensions),"portrait_scroll":scroll.scroll_vertical,"last_portrait":str(hud._persona_cards[7].get_global_rect()),"command_selection":"none; portraits inspect details"})


func inspect_commands(world: Expedition) -> void:
	frame_point(world, world.layout.world_bounds.get_center())
	for code: Key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		var start: Vector2 = world.camera.position
		await key(code)
		world.camera._process(0.1)
		expect(world.camera.position != start, "arrow event moves production camera: %d" % code)
	# Point/drag/Shift-click are characterized honestly: production has no
	# unit-selection state. The press issues the existing whole-party move.
	var actor: FieldActor = world.survivors[0]
	await map_click(world, actor.position)
	expect(world.goal.distance_to(actor.position) < 0.1, "field actor click follows existing ground-command path")
	var target: Vector2 = world.layout.bus_door + Vector2(96, 96)
	frame_point(world, target)
	await drag(screen_point(world, target), screen_point(world, target + Vector2(60, 20)))
	expect(world.goal.distance_to(target) < 0.1, "drag press retains original move target; no box-selection feature is claimed")
	await map_click(world, target + Vector2(24, 0), true)
	expect(world.goal.distance_to(target + Vector2(24, 0)) < 0.1, "Shift-click retains original whole-party command; no multiselect is claimed")
	await key(KEY_Q)
	expect(world.rally_aiming, "Q enters rally aim through App production key path")
	var prior: Vector2 = world.goal
	await key(KEY_ESCAPE)
	expect(not world.rally_aiming and world.goal == prior and not app.pause_menu.root.visible, "Esc cancels rally with no movement or menu")
	await key(KEY_Q)
	await tap(Vector2(650, 290), MOUSE_BUTTON_RIGHT)
	expect(not world.rally_aiming and world.goal == prior, "right click cancels rally without committing")
	await key(KEY_Q)
	await map_click(world, target)
	expect(not world.rally_aiming and world.goal.distance_to(target) < 0.1, "Q then map click commits rally")
	await advance(world, func() -> bool: return world.survivors.all(func(a: FieldActor) -> bool: return a.activity == FieldActor.Activity.IDLE), 900)
	expect(world.boarding_status().required == 8, "movement preserves eight living boarding requirements")
	# Generate one authentic enemy, then hold the fixture between input events.
	world._spawn_enemy()
	expect(not world.enemies.is_empty(), "original spawn owner supplies focus target")
	if not world.enemies.is_empty():
		var enemy: FieldActor = world.enemies[0]
		frame_point(world, enemy.position)
		await key(KEY_W)
		expect(world.focus_aiming, "W enters focus aim for original enemy")
		await tap(Vector2(650, 290), MOUSE_BUTTON_RIGHT)
		expect(not world.focus_aiming and world.focus_target == null, "focus cancellation has no target")
		await key(KEY_W)
		await map_click(world, enemy.position)
		expect(not world.focus_aiming and world.focus_target == enemy, "W then enemy click sets original focus target")
	await key(KEY_E)
	expect(world.basic_support.snapshot().sequence == 0 and not world.is_paused, "E on healthy eight-person fixture consumes no heal or cooldown")
	await key(KEY_R)
	expect(world._notice_text == "当前没有可释放的特技" and world.powers.accepted.is_empty(), "R empty-slot input preserves original unavailable feedback and consumes nothing")
	# A legal clear point near the unchanged map boundary; order through Q
	# to avoid confusing a facade hit with an edge movement request.
	var edge: Vector2 = Vector2.INF
	for x: int in range(32, int(world.layout.world_bounds.size.x), 32):
		var candidate: Vector2 = world.layout.world_bounds.position + Vector2(x, 32)
		frame_point(world, candidate)
		var screen: Vector2 = screen_point(world, candidate)
		var blocked: bool = world._hud.view.hud_exclusion_rects().any(func(rect: Rect2) -> bool: return rect.has_point(screen))
		if world.navigation.is_clear(candidate) and viewport.get_visible_rect().has_point(screen) and not blocked:
			edge = candidate
			break
	expect(edge.is_finite(), "unchanged map has an exposed clear boundary point for real input")
	if not edge.is_finite(): return
	await key(KEY_Q)
	await map_click(world, edge)
	expect(world.goal.distance_to(edge) < 0.1 and world.survivors.all(func(a: FieldActor) -> bool: return a.activity != FieldActor.Activity.DOWN), "map-edge rally is accepted without losing squad members")
	await key(KEY_Q)
	await map_click(world, world.layout.bus_door + Vector2(96, 96))
	expect(world.survivors.all(func(a: FieldActor) -> bool: return not a.path.is_empty()), "reissued rally replaces boundary routes for all eight")
	# Contacts can leave an actor moving within the existing approach radius of
	# a crowded slot. Record that state; this input test does not assert exact
	# collision-solver convergence or change that solver's arrival semantics.
	await advance(world, func() -> bool: return world.survivors.all(func(a: FieldActor) -> bool: return a.position.distance_to(world.goal + world._group_offset(a)) <= FieldContacts.APPROACH), 1200)
	evidence.append({"stage":"reissued-rally","actors":world.survivors.map(func(a: FieldActor) -> Dictionary: return {"id":a.member_id,"activity":a.activity,"slot_distance":a.position.distance_to(world.goal + world._group_offset(a))})})
	await screenshot_both(world, "rally-after-input")


func inspect_boarding(world: Expedition, casualty: bool) -> void:
	var site: Expedition.SearchSite = world.search_site(&"food")
	frame_point(world, site.door)
	await map_click(world, site.door)
	expect(world.search_assignments.ordered().size() == 1, "production site click assigns one original search job")
	await advance(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds, 600)
	var job: Dictionary = world.search_assignments.snapshot()
	var goal: Vector2 = world.goal
	await key(KEY_B)
	expect(world.phase == Expedition.Phase.ENGINE and world.goal == goal and world.search_assignments.snapshot() == job, "first B starts engine without recall or search cancellation")
	await key(KEY_B)
	expect(world.phase == Expedition.Phase.ENGINE and world.goal == goal, "B during engine startup does not recall")
	await advance(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING, 300)
	expect(world.goal == goal and world.phase != Expedition.Phase.FINISHED, "engine completion does not recall or depart with missing survivors")
	await screenshot_both(world, "engine-waiting")
	# Yellow bus region follows the same action as B. This was the broken
	# production branch: request_extraction silently rejected BOARDING.
	frame_point(world, world.layout.bus_block.get_center())
	await map_click(world, world.layout.bus_block.get_center())
	expect(world.goal == world.layout.bus_door and world.boarding_status().ordered, "yellow bus mouse click after engine completion issues gather")
	await key(KEY_B)
	expect(world.goal == world.layout.bus_door, "second B reissues original gather")
	await screenshot_both(world, "boarding-gather")
	# Cancel exactly the original site job and reissue through production Q/B.
	if world.search_assignments.ordered().size() > 0:
		frame_point(world, site.door)
		await map_click(world, site.door)
		expect(world.search_assignments.ordered().is_empty(), "second site click cancels its worker without cancelling gather")
	await key(KEY_B)
	# Hold one real actor temporarily (directed congestion/stale-route fixture).
	# Seven reaching the door must not depart; releasing and reissuing B must
	# recover the eighth without resetting the world or bypassing extraction.
	var delayed: FieldActor = world.search_member(8)
	delayed.clear_order()
	await advance(world, func() -> bool: return world.boarding_status().arrived == world.living_count() - 1, 1500)
	var status: Dictionary = world.boarding_status(true)
	expect(world.phase == Expedition.Phase.BOARDING and status.arrived == status.required - 1 and status.waiting.size() == 1 and status.waiting[0].id == 8, "every living member is required; one delayed actor blocks departure with correct waiting identity")
	expect(world._hud.view._bus_status.text == "已集合 %d/%d" % [status.arrived, status.required], "actual HUD arrival count matches moved living actors")
	await screenshot_both(world, "one-waiting")
	await key(KEY_B)
	await advance(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED, 1200)
	expect(world.phase == Expedition.Phase.FINISHED and world.bus_view.final_boarding == Vector2i(7, 7) if casualty else world.phase == Expedition.Phase.FINISHED and world.bus_view.final_boarding == Vector2i(8, 8), "B reissue recovers delayed member; all living members produce one evacuation")
	var paths: Array[PackedVector2Array] = []
	for a: FieldActor in world.survivors: paths.append(a.path.duplicate())
	await key(KEY_Q)
	await map_click(world, world.layout.bus_door + Vector2(120, 120))
	await key(KEY_W)
	await key(KEY_E)
	await key(KEY_R)
	for index: int in range(world.survivors.size()):
		expect(world.survivors[index].path == paths[index], "finished/boarding actor receives no new path %d" % (index + 1))
	await advance(world, func() -> bool: return not world.bus_view.running(), 1800)
	expect(world.survivors.all(func(a: FieldActor) -> bool: return a.health <= 0.0 or not a.visible), "real boarding hides every evacuated living actor")
	await key(KEY_Q)
	await map_click(world, world.layout.bus_door + Vector2(100, 100))
	for index: int in range(world.survivors.size()):
		expect(world.survivors[index].path == paths[index], "fully boarded/hidden actor receives no new command %d" % (index + 1))
	evidence.append({"casualty":casualty,"final_boarding":str(world.bus_view.final_boarding),"app_phase":app.phase,"blocked":app._progress_blocked,"living":world.living_count()})


func screen_point(world: Expedition, point: Vector2) -> Vector2:
	return world.get_global_transform_with_canvas() * IsoSpace.to_view(point)


func frame_point(world: Expedition, point: Vector2) -> void:
	world.camera.pan_by(IsoSpace.to_view(point) - world.camera.position)
	world.camera.force_update_scroll()


func map_click(world: Expedition, point: Vector2, shift: bool = false) -> void:
	frame_point(world, point)
	await settle()
	await tap(screen_point(world, point), MOUSE_BUTTON_LEFT, shift)


func tap(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
		event.pressed = down
		event.shift_pressed = shift
		viewport.push_input(event, true)
		await process_frame
	await settle()


func drag(from: Vector2, to: Vector2) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = from
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	viewport.push_input(press, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(motion, true)
	press.position = to
	press.pressed = false
	press.button_mask = 0
	viewport.push_input(press, true)
	await settle()


func wheel(point: Vector2, button: MouseButton, count: int) -> void:
	for index: int in range(count): await tap(point, button)


func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		viewport.push_input(event, true)
		await process_frame
	await settle()


func settle() -> void:
	for frame: int in range(3): await process_frame


func advance(world: Expedition, done: Callable, cap: int) -> void:
	for tick: int in range(cap):
		if done.call() or world.is_paused: break
		world.step(STEP)
		if tick % 30 == 0: await process_frame
	expect(done.call(), "bounded formal simulation reaches requested input checkpoint: phase=%d boarding=%s actors=%s" % [world.phase, str(world.boarding_status()), str(world.survivors.map(func(a: FieldActor) -> Dictionary: return {"id":a.member_id,"activity":a.activity,"path":a.path.size(),"position":str(a.position)}))])


func screenshot(world: Expedition, label: String) -> void:
	world._update_ui()
	await settle()
	# Frozen input checkpoints still need the normal following UI refresh after
	# Containers settle, as they receive on the next production physics frame.
	world._update_ui()
	await settle()
	var overlaps: int = 0
	var covered_faces: int = 0
	var covered_by_hud: int = 0
	var hud_rects: Array[Rect2] = world._hud.view.hud_exclusion_rects()
	for i: int in range(world._readouts.entries.size()):
		var a: Dictionary = world._readouts.entries[i]
		if a.alpha < 0.05: continue
		if hud_rects.any(func(rect: Rect2) -> bool: return rect.intersects(a.rect)): covered_by_hud += 1
		for actor: FieldActor in world.survivors:
			if not actor.visible or actor.activity == FieldActor.Activity.DOWN: continue
			var face: Vector2 = world.get_global_transform_with_canvas() * (IsoSpace.to_view(actor.position) + actor.visual.position + Vector2(0, -48))
			if a.rect.has_point(face): covered_faces += 1
		for j: int in range(i):
			var b: Dictionary = world._readouts.entries[j]
			if b.alpha >= 0.05 and a.rect.intersects(b.rect): overlaps += 1
	var visible_count: int = world._readouts.entries.filter(func(e: Dictionary) -> bool: return e.alpha >= 0.05).size()
	evidence.append({"stage":label,"size":str(viewport.size),"hp_visible":visible_count,"hp_overlaps":overlaps,"hp_covered_faces":covered_faces,"hp_covered_by_hud":covered_by_hud,"boarding":world.boarding_status(true),"notice":world._notice_text})
	expect(overlaps == 0, "visible HP readouts do not overlap: " + label + str(viewport.size))
	expect(covered_faces == 0, "HP readouts leave actual squad faces clear: " + label + str(viewport.size))
	expect(visible_count > 0 and covered_by_hud == 0, "HP group remains visible outside the settled production HUD: " + label + str(viewport.size))
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw()
	var path: String = output.path_join("%s-%dx%d-%d.png" % [label, viewport.size.x, viewport.size.y, evidence.size()])
	var image: Image = viewport.get_texture().get_image()
	expect(image.get_size() == viewport.size and image.save_png(path) == OK, "native viewport saves unscaled formal rendering: " + path.get_file())


func screenshot_both(world: Expedition, label: String) -> void:
	var original: Vector2i = viewport.size
	await screenshot(world, label)
	viewport.size = Vector2i(1280, 720)
	await settle()
	await screenshot(world, label)
	viewport.size = original
	await settle()


func dispose() -> void:
	app.audio.shutdown()
	app.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
