extends SceneTree
## Capacity, permanent identities, admission, persistence and actual eight-person views.

const PROFILE: String = "0123456789abcdef0123456789abcdef"
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BH_SQUAD_RECRUIT_FAIL " + label)


static func camp(count: int = 8) -> Dictionary:
	var crew: Array[Dictionary] = SurvivorRoster.new_crew()
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	var initial: Dictionary = {"schema_version":5, "profile_id":PROFILE, "day":2,
		"cash":CampRules.INITIAL_CASH, "food":RunSave.DefaultRules.initial_food,
		"crew":crew, "last_day":{}, "settled_sorties":0, "last_settlement_id":"", "camp_spending":0}
	WeaponInventory.initialize(initial, "initial")
	var value: Dictionary = RosterState.snapshot(initial, RosterState.initial("squad-eight"), [], [])
	while value.crew.size() < count:
		var identity: String = "%s:%d" % [PROFILE, int(value.settled_sorties) + 1]
		var event: Dictionary = FieldJoinRules.event(value, identity, 10000)
		var joined: Dictionary = FieldJoinRules.action_base(value, [event])
		# Same departure-only first meal as FrozenSettlement, no revival or extra grants.
		var after: Dictionary = returned(value)
		after.crew = joined.crew
		after.weapons = joined.weapons
		after.loadout = joined.loadout
		after.recruits = joined.recruits
		value = RosterState.snapshot(after, after.journey, after.recruits, after.training)
	return value


static func returned(before: Dictionary) -> Dictionary:
	var after: Dictionary = before.duplicate(true)
	after.day = int(before.day) + 1
	after.settled_sorties = int(before.settled_sorties) + 1
	after.last_settlement_id = "%s:%d" % [PROFILE, int(after.settled_sorties)]
	after.last_day = CampEconomy.post_battle_food(int(before.day), before.crew, int(before.food), 8, 1, true)
	after.food = after.last_day.food_after
	after.camp_spending = 0
	after.last_day.merge({"day":before.day, "settlement_id":after.last_settlement_id, "evacuated":true,
		"cash_before":before.cash, "cash_after":before.cash, "cash_gained":0})
	return after


static func view_camp(count: int = 8) -> Dictionary:
	# Current action/view capabilities over the directed natural roster fixture.
	var base: Dictionary = camp(count)
	base.schema_version = EnemyState.SCHEMA
	base.journey.format = EnemyState.FORMAT
	base.journey.campaign = CampaignRules.initial(PROFILE)
	base.journey.build = PersonaState.initial_build(String(base.journey.seed))
	for index: int in range(base.weapons.size()):
		base.weapons[index] = WeaponModifiers.baseline(base.weapons[index])
	return base


func _run() -> void:
	var fresh: Dictionary = camp(2)
	_check(fresh.crew.size() == 2 and fresh.journey.active_member_ids == [1, 2], "new game still has only Gu and Xia")
	_check(RosterState.MAX_LIVING == 8 and RosterState.MAX_HISTORY == 10, "capacity separates living slots from permanent history")
	for count: int in range(2, 9):
		var value: Dictionary = camp(count)
		_check(RosterState.problem(value).is_empty(), "%d-person natural history validates: %s" % [count, RosterState.problem(value)])
		_check(SurvivalContracts.participants(value.crew, WeaponInventory.snapshot(value), true, true).size() == count, "every living member departs")
		if count < 8:
			var identity: String = "%s:%d" % [PROFILE, int(value.settled_sorties) + 1]
			_check(FieldJoinRules.problem([FieldJoinRules.event(value, identity, 10000)], value, identity).is_empty(), "next recruit can join beyond four")
	var full: Dictionary = camp()
	_check(RescuePoolState.available(full).is_empty() and "存活编制已满（8人）" in RosterState.unavailable_reason(full), "full squad exposes Chinese refusal")
	var identity: String = "%s:%d" % [PROFILE, int(full.settled_sorties) + 1]
	_check(not FieldJoinRules.problem([{"at_ms":10000}], full, identity).is_empty(), "full roster rejects field admission")
	_check(not TaskActions.offers(full).any(func(offer: Dictionary) -> bool: return offer.type == "rescue"), "full squad is not offered an impossible rescue")
	var reduced: Dictionary = returned(full)
	var fallen: Dictionary = SurvivorRoster.member(reduced.crew, 3)
	var death: Dictionary = DeathRules.propose(fallen, 0.0, "BATTLE", reduced.last_settlement_id, {}, true)
	fallen.health = 0.0
	reduced.journey.deaths.append(death.death)
	reduced.loadout = reduced.loadout.filter(func(row: Dictionary) -> bool: return row.member_id != 3)
	reduced = RosterState.snapshot(reduced, reduced.journey, reduced.recruits, reduced.training)
	_check(RosterState.problem(reduced).is_empty() and RosterState.living_count(reduced) == 7, "permanent death vacates a living slot")
	_check(RescuePoolState.available(reduced) == [9, 10] and 3 not in RescuePoolState.available(reduced), "replacement candidates are different people; dead Lin cannot return")
	identity = "%s:%d" % [PROFILE, int(reduced.settled_sorties) + 1]
	var replacement_event: Dictionary = FieldJoinRules.event(reduced, identity, 10000)
	_check(FieldJoinRules.problem([replacement_event], reduced, identity).is_empty(), "replacement uses the same admission authority")
	var replacement: Dictionary = FieldJoinRules.action_base(reduced, [replacement_event])
	_check(RosterState.living_count(replacement) == 8 and replacement.crew.size() == 9 and SurvivorRoster.member(replacement.crew, 3).health == 0.0, "replacement restores eight living without resurrecting the dead")
	var replacement_camp: Dictionary = returned(reduced)
	replacement_camp.crew = replacement.crew
	replacement_camp.weapons = replacement.weapons
	replacement_camp.loadout = replacement.loadout
	replacement_camp.recruits = replacement.recruits
	replacement_camp = RosterState.snapshot(replacement_camp, replacement_camp.journey, replacement_camp.recruits, replacement_camp.training)
	_check(RosterState.problem(replacement_camp).is_empty(), "replacement return persists both eight living and permanent death history")
	var nine: Dictionary = camp()
	var ninth_identity: String = "%s:%d" % [PROFILE, int(nine.settled_sorties) + 1]
	RescuePoolState.grant(nine, 9)
	nine.recruits.append({"rescue_id":RescueState.TARGET,"member_id":9,"recruit_id":PROFILE+":recruit:9", "settlement_id":ninth_identity,"joined_at_ms":10000,"field_status":"RETURNED"})
	nine.settled_sorties += 1
	nine.day += 1
	nine.last_day = {}
	nine.last_settlement_id = ninth_identity
	nine = RosterState.snapshot(nine, nine.journey, nine.recruits, nine.training)
	_check(RosterState.problem(nine) == "ROSTER_LIVING_LIMIT", "ninth living member is rejected at persistence boundary")
	await _field_admission()
	await _capacity_and_replacement(full, reduced)
	await _views(full)
	await _menus(full)
	_persistence(full)
	print("BH_SQUAD_RECRUIT " + JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures == 0 else 1)


func _persistence(full: Dictionary) -> void:
	var value: Dictionary = full.duplicate(true)
	var facts: Dictionary = SurvivorPersona.generate(String(value.journey.seed))
	for id: int in [6, 7, 8]:
		var member: Dictionary = SurvivorRoster.member(value.crew, id)
		member.health = 150.0 + id
		member.service = {"sorties":1, "kills":3, "damage_received":200.0 - member.health, "last_settlement_id":value.last_settlement_id}
		member.growth.xp_total = 30
		member.growth.level = GrowthRules.level_for(30)
		_check(not SurvivorPersona.member(facts, id).is_empty() and TraitRules.role(member) > 0, "new identity has real traits and seeded persona")
		var preview: Dictionary = TrainingRules.preview(value, id)
		_check(preview.error.is_empty(), "member %d can train after confirmed return" % id)
		if preview.error.is_empty():
			value = preview.after
	var issue: String = RosterState.problem(value)
	_check(issue.is_empty(), "eight-person injuries, XP and training validate: " + issue)
	var folder: String = ProjectSettings.globalize_path("res://.local/squad-recruit/" + RunSave.new_profile_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var save: RunSave = RunSave.new(folder.path_join("run.roster-v1.json"), false, false, false, false, false, false, false, false, true)
	var writer: ProgressWriter = ProgressWriter.new(save.path)
	_check(writer.acquire() == OK, "isolated test owns the same writer capability as transactions")
	_check(save.save(value, false, writer) == OK, "eight-person camp is written only in isolated .local")
	writer.release()
	var reader: RunSave = RunSave.new(save.path, false, false, false, false, false, false, false, false, true)
	var restored: Dictionary = reader.read_transaction_exact()
	_check(restored.error == OK and TransactionReceipt.same(restored.data, value), "disk round trip retains health, weapons, XP, traits and recruit history")
	_check(WeaponInventory.snapshot_problem(value.crew, WeaponInventory.snapshot(value), true).is_empty(), "all eight have distinct valid weapon ownership")
	var swapped: Dictionary = WeaponInventory.equip(value, 8, WeaponInventory.for_member(value, 6).instance_id)
	_check(swapped.has("data") and RosterState.problem(swapped.data).is_empty(), "sixth and eighth members can swap loadouts")


func _field_admission() -> void:
	var base: Dictionary = camp(7)
	var world: Expedition = Expedition.new()
	world.supply = preload("res://src/features/camp/rescue.tres").duplicate(true)
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.field_departure = base
	world.day = int(base.day)
	world.sortie_id = "%s:%d" % [PROFILE, int(base.settled_sorties) + 1]
	world.ui_theme = preload("res://assets/ui/c1/hud_theme.tres")
	world.field_join_gate = func(at_ms: int) -> Dictionary:
		return {"error":OK, "receipt":{"joins":[FieldJoinRules.event(base, world.sortie_id, at_ms)]}}
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	_check(world.setup_problem.is_empty() and world.survivors.size() == 7, "seven-person departure builds without overlap or missing weapons")
	var target: RescueTarget = world.rescue_target
	if target == null:
		_check(false, "rescue mission creates positioned target")
		world.free()
		return
	var original: FieldActor = target.npc
	_check(original.visual.visible and target.candidate_name() in target.label.text, "named rescue target is visible before admission")
	target.request()
	var worker: FieldActor = world.search_member(target.worker)
	_check(worker != null, "rescue assigns a living worker")
	if worker != null:
		worker.position = original.position + Vector2(-40, 0)
		world.elapsed = 10.0
		target.step(9.9)
		_check(world.survivors.size() == 7, "candidate is not admitted early")
		target.step(0.1)
		_check(world.survivors.size() == 8 and world.search_member(world.candidate_id()) == original and target.status == "IN_FIELD_JOINED", "ten-second assistance promotes same eighth actor into real combat squad")
		_check(world.participants_snapshot.size() == 8 and original.weapon_definition != null, "new member has participant, weapon and growth inputs")
		if not world.field_joins.is_empty():
			world.promote_target(world.field_joins[0])
		_check(world.survivors.size() == 8, "repeated admission cannot duplicate a recruit")
		for actor: FieldActor in world.survivors:
			_check(world._group_offset(actor).length() <= world.tuning.boarding_radius, "eight-person formation remains within boarding radius")
	world.free()
	await process_frame


func _views(full: Dictionary) -> void:
	var camp_world: CampSceneWorld = CampSceneWorld.new()
	root.add_child(camp_world)
	camp_world.refresh(full.crew)
	_check(camp_world.visible_member_ids.size() == 8, "camp walks all eight living residents")
	for id: int in [6, 7, 8]:
		var definition: SurvivorDefinition = SurvivorRoster.definition(id)
		var resident: CampSceneResident = camp_world.residents[id]
		var body: AtlasTexture = resident.body.texture as AtlasTexture
		var portrait: AtlasTexture = definition.portrait as AtlasTexture
		var region: Rect2 = CampPixelArt.REGIONS[CampPixelArt.variant(String(definition.id))]
		_check(resident.visible and resident.get_meta("definition_id") == definition.id
			and body != null and body.atlas == CampPixelArt.SHEET and body.region == region.grow(2)
			and portrait != null and portrait.atlas == CampPixelArt.SHEET and portrait.region.position == region.position,
			"new resident uses the correct independent pixel body and portrait identity")
	camp_world.free()
	var actual: Dictionary = view_camp(8)
	var models: Array[Dictionary] = []
	for member: Dictionary in actual.crew:
		models.append({"id":int(member.id), "persona":PersonaViewModel.camp(actual, int(member.id))})
	models.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640), Vector2i(1024, 576)]:
		var viewport: SubViewport = SubViewport.new()
		viewport.size = dimensions
		viewport.world_2d = World2D.new()
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var hud: C1ExpeditionHud = C1ExpeditionHud.new()
		hud.theme = preload("res://assets/ui/c1/hud_theme.tres")
		hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(hud)
		hud.refresh({"survivors":models})
		await process_frame
		await process_frame
		_check(hud._persona_cards.size() == 8 and hud._member_scroll.size.y <= dimensions.y - 88.0, "eight portraits stay in bounded scrolling HUD")
		for index: int in range(8):
			var card: PersonaCard = hud._persona_cards[index]
			_hover_fields(card.portrait_button.tooltip_text, actual, int(models[index].id), "field HUD")
			_check(card.visible, "all admitted identities have a visible card")
		if DisplayServer.get_name() != "headless":
			await _render_hover(viewport, hud, actual, dimensions)
		viewport.free()
		await process_frame


func _menus(full: Dictionary) -> void:
	var roster: RosterPanel = RosterPanel.new()
	root.add_child(roster)
	var actual: Dictionary = view_camp(8)
	roster.refresh(actual)
	_check(roster.buttons_by_id.size() == 8, "camp roster includes all eight profiles")
	for id: int in roster.buttons_by_id:
		_hover_fields(roster.buttons_by_id[id].tooltip_text, actual, id, "roster")
	roster.free()
	var menu: MissionSelect = MissionSelect.new()
	menu.review_enabled = true
	root.add_child(menu)
	var base: Dictionary = view_camp(7)
	var offers: Array[Dictionary] = DailyActions.offers(base)
	var signed: String = RecordEncoding.fingerprint({"offers":offers})
	menu.refresh_daily(base)
	_check(RecordEncoding.fingerprint({"offers":menu.daily_offers}) == signed, "selection preserves offer fingerprints")
	for index: int in range(menu.daily_offers.size()):
		var offer: Dictionary = menu.daily_offers[index]
		if offer.type == "rescue":
			_check(SurvivorRoster.definition(int(offer.recruit)).default_display_name in menu._descriptions[index].text, "mission card names its actual frozen candidate")
	menu.refresh_daily(view_camp(8))
	_check("存活编制已满" in menu._subtitle.text, "full-squad reason remains visible even with no rescue card")
	var camp_view: CampSceneView = CampSceneView.new()
	root.add_child(camp_view)
	camp_view.refresh(actual, CampEconomy.rations(actual.day, actual.crew, actual.food, CampRules.new()), true, "")
	for id: int in camp_view.member_buttons:
		if camp_view.member_buttons[id].visible:
			_hover_fields(camp_view.member_buttons[id].tooltip_text, actual, id, "camp portrait")
	camp_view.free()
	var named: String = ""
	for node: Node in menu._review_details.get_children():
		if node is Label:
			named += node.text + "\n"
			for member: Dictionary in actual.crew:
				if node.text.begins_with(SurvivorRoster.display_label(member)):
					_hover_fields(node.tooltip_text, actual, int(member.id), "departure review")
					_check(node.mouse_filter == Control.MOUSE_FILTER_PASS, "departure review label actually receives tooltip hover")
	for id: int in [6, 7, 8]:
		_check(SurvivorRoster.definition(id).default_display_name in named, "departure review includes new member")
	menu.free()
	await process_frame


func _hover_fields(hover: String, base: Dictionary, id: int, context: String) -> void:
	var member: Dictionary = SurvivorRoster.member(base.crew, id)
	var weapon: Dictionary = WeaponInventory.for_member(base, id)
	var model: Dictionary = PersonaViewModel.camp(base, id)
	_check(SurvivorRoster.definition(id).default_display_name in hover and "HP %d/%d" % [ceili(member.health), ceili(GrowthRules.maximum(member))] in hover
		and "Lv%d" % int(member.growth.level) in hover and WeaponInventory.definition(weapon.weapon_id).display_name in hover
		and model.primary in hover and model.positive.name in hover and model.negative.name in hover,
		"%s hover contains actual identity, HP, level, equipped weapon and traits for %d" % [context, id])


func _capacity_and_replacement(full: Dictionary, reduced: Dictionary) -> void:
	var world: Expedition = _rescue_world(full)
	var calls: Array[int] = [0]
	world.field_join_gate = func(_at_ms: int) -> Dictionary:
		calls[0] += 1
		return {"error":ERR_UNAVAILABLE}
	_check(world.rescue_target == null and world.survivors.size() == 8, "stale full-squad rescue cannot construct an invalid ninth candidate")
	_check(not world.join_target(10000) and calls[0] == 0 and world.survivors.size() == 8,
		"runtime refuses full-squad admission before requesting persistence")
	world.free()
	await process_frame
	world = _rescue_world(reduced)
	var target: RescueTarget = world.rescue_target
	_check(target != null and world.candidate_id() in [9,10], "only a vacancy unlocks an existing reserve identity")
	if target != null:
		var original: FieldActor = target.npc
		target.request()
		var worker: FieldActor = world.search_member(target.worker)
		var start: Vector2 = worker.position if worker != null else Vector2.ZERO
		for tick: int in range(5400):
			world.step(1.0 / 30.0)
			if target.status == "IN_FIELD_JOINED" or world.is_paused: break
			if tick % 30 == 0: await process_frame
		_check(worker != null and worker.position.distance_to(start) > 80.0 and world.elapsed >= 10.0,
			"reserve assistance uses real navigation and simulation time without teleporting a worker")
		_check(target.status == "IN_FIELD_JOINED" and world.survivors.size() == 8
			and world.search_member(world.candidate_id()) == original and world.search_member(3) == null,
			"completed help promotes the same reserve actor and never revives the fallen")
		var reports: Array[Dictionary] = []
		world.finished.connect(func(report: Dictionary) -> void: reports.append(report))
		world.request_bus_gather()
		for tick: int in range(2700):
			world.step(1.0 / 30.0)
			if world.phase == Expedition.Phase.FINISHED: break
			if world.phase == Expedition.Phase.ACTIVE and world.elapsed >= world.tuning.bus_ready_seconds: world.request_bus_action()
			if tick % 30 == 0: await process_frame
		_check(reports.size() == 1 and reports[0].evacuated and reports[0].field_joins.size() == 1,
			"reserve follows real gather and evacuation into the final report")
		if not reports.is_empty():
			var computed: Dictionary = FrozenSettlement.compute({"before":reduced,"token":world.growth_binding,
				"participants":SurvivalContracts.participants(reduced.crew, WeaponInventory.snapshot(reduced), true, true),
				"rules":FrozenSettlement.pool_rules(reduced, world.supply),"report":reports[0],
				"carried":{"loot":world.loot,"food":world.food_loot,"weapons":world.weapon_loot.duplicate(true)},
				"prior_deaths":reduced.journey.deaths,"completion":"COMPLETED","searching_member_ids":[]})
			_check(computed.error.is_empty(), "formal reserve settlement accepts real rescue and evacuation: " + String(computed.get("reason",computed.error)))
			if computed.error.is_empty():
				var after: Dictionary = computed.packet.envelope.result.camp
				_check(SurvivorRoster.member(after.crew, world.candidate_id()).health > 0.0 and after.recruits.back().field_status == "RETURNED",
					"reserve is registered in camp with confirmed return and first-meal exemption")
		print("BH_RESCUE_PATH " + JSON.stringify({"elapsed":world.elapsed,"candidate":world.candidate_id(),
			"status":target.status,"living":world.living_count(),"rescue":str(world.layout.rescue_point),"bus":str(world.layout.bus_door)}))
	world.free()
	await process_frame


func _rescue_world(base: Dictionary) -> Expedition:
	var world: Expedition = Expedition.new()
	world.supply = preload("res://src/features/camp/rescue.tres").duplicate(true)
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.field_departure = base
	world.day = int(base.day)
	world.sortie_id = "%s:%d" % [PROFILE, int(base.settled_sorties) + 1]
	world.ui_theme = preload("res://assets/ui/c1/hud_theme.tres")
	world.field_join_gate = func(at_ms: int) -> Dictionary:
		var event: Dictionary = FieldJoinRules.event(base, world.sortie_id, at_ms)
		var issue: String = FieldJoinRules.problem([event], base, world.sortie_id)
		return {"error":OK, "receipt":{"joins":[event]}} if issue.is_empty() else {"error":ERR_INVALID_DATA,"reason":issue}
	var rules: Dictionary = FrozenSettlement.pool_rules(base, world.supply)
	world.growth_binding = {"run_id":base.profile_id,"root_id":base.journey.root_id,"transaction_id":world.sortie_id,
		"base_hash":SurvivalContracts.fingerprint(base),"rules_hash":SurvivalContracts.fingerprint(rules)}
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	return world


func _render_hover(viewport: SubViewport, hud: C1ExpeditionHud, base: Dictionary, dimensions: Vector2i) -> void:
	var card: PersonaCard = hud._persona_cards[7]
	hud._member_scroll.ensure_control_visible(card)
	for frame: int in range(4): await process_frame
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = card.portrait_button.get_global_rect().get_center()
	viewport.notify_mouse_entered()
	viewport.push_input(motion, true)
	await create_timer(0.8).timeout
	var popup: Window
	for window: Window in viewport.get_embedded_subwindows():
		if window.visible: popup = window
	_check(popup != null, "real pointer hover opens native tooltip for eighth card")
	if popup == null: return
	_check(Rect2i(Vector2i.ZERO, dimensions).encloses(Rect2i(popup.position, popup.size)),
		"complete native hover popup stays inside %s" % str(dimensions))
	var label: Label
	for child: Node in popup.find_children("*", "Label", true, false):
		if child is Label and not child.text.is_empty(): label = child
	_check(label != null and label.get_visible_line_count() == label.get_line_count(), "native tooltip displays every line")
	if label != null: _hover_fields(label.text, base, 8, "native tooltip")
	RenderingServer.force_draw()
	var path: String = "res://.local/squad-recruit/hover-%dx%d.png" % [dimensions.x,dimensions.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var rendered: Image = viewport.get_texture().get_image()
	var area: Rect2i = Rect2i(popup.position, popup.size)
	var glyphs: int = _bright_pixels(rendered, area)
	popup.hide()
	RenderingServer.force_draw()
	var blank: int = _bright_pixels(viewport.get_texture().get_image(), area)
	_check(glyphs > blank + 80, "native tooltip contributes real visible text pixels over the no-popup control")
	_check(rendered.save_png(path) == OK, "native tooltip renders to isolated test evidence")


func _bright_pixels(image: Image, area: Rect2i) -> int:
	var count: int = 0
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var colour: Color = image.get_pixel(x,y)
			if colour.r > 0.6 and colour.g > 0.6 and colour.b > 0.5: count += 1
	return count
