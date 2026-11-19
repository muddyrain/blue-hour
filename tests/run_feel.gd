extends "res://tests/persona_rules.gd"
## Run pacing and the production StatusHint layout, including rendered glyphs.


func run() -> void:
	var camp: Dictionary = _feel_camp()
	var offers: Array[Dictionary] = DailyActions.offers(camp)
	var digest: String = RecordEncoding.fingerprint({"offers":offers})
	print("BH_RUN_FEEL_OFFERS " + digest)
	expect(digest == "33486051927307aeb441f05498ef1333061d57e3df164815e0712329c5ee896f",
		"fixed pre-change offers SHA and frozen daylight evidence stay exact")
	expect(ExpeditionTuning.new().daylight_seconds == 105.0 and ExpeditionTuning.new().spawn_seconds == 10.0,
		"opening reinforcement changes without extending the frozen 105-second day")
	expect(CampRules.new().initial_food == 4 and RunSave.DefaultRules.initial_food == 4, "all opening food defaults are four")
	_food_forecasts(camp)
	_result_wording(camp)
	var opening: Dictionary = camp.duplicate(true)
	opening.food = 4
	expect(RecordEncoding.fingerprint({"offers":DailyActions.offers(opening)}) == digest,
		"opening food buffer does not change the same three signed task cards")
	await _first_food_sortie(opening, DailyActions.supply(offers[0]))
	for size: Vector2i in [Vector2i(1024, 576), Vector2i(1280, 720)]:
		await _hint_layout(size)
	print(JSON.stringify({"suite":"run_feel", "checks":checks, "failures":failures}))
	quit(1 if failures else 0)


func _feel_camp() -> Dictionary:
	var camp: Dictionary = _camp_fixture()
	# Fixed pre-change input: opening stock must not alter task-card evidence.
	camp.food = 2
	camp.journey.build = WorldgenState.initial_build(camp.journey.seed, true, true)
	camp.journey.campaign = CampaignRules.initial_mission(camp.profile_id,
		true, true, true, false, false, false, false, false, true)
	return camp


func _hint_layout(size: Vector2i) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: Expedition = Expedition.new()
	world.supply = preload("res://src/features/camp/supermarket.tres")
	viewport.add_child(world)
	world.set_physics_process(false)
	expect(world.initial_food == 4, "standalone expedition opening stock is four")
	var hud: C1ExpeditionHud = world._hud.view
	for mode: String in ["notice", "persistent", "night"]:
		if mode == "notice":
			world._show_notice("引擎发动中 · 不会自动召回；发动后再按 B 集合。\n若归航：本餐需 2 粮 · 缺 0 粮 · 餐后余 5 粮")
		else:
			world._notice_clock = 0.0
			if mode == "night":
				world.elapsed = 140.0
				world.threat.update(world.elapsed, world.tuning.daylight_seconds, world.tuning.spawn_seconds)
		world._update_ui()
		for frame: int in range(6):
			await process_frame
		var hint: Label = hud._hint
		var panel: PanelContainer = hud._hint_panel
		var tag: String = "%s/%s" % [size, mode]
		print("BH_RUN_FEEL_LAYOUT " + JSON.stringify({"viewport":[size.x,size.y],"mode":mode,
			"label_size":str(hint.size),"minimum":str(hint.get_minimum_size()),"combined_minimum":str(hint.get_combined_minimum_size()),
			"panel":str(panel.get_global_rect()),"label":str(hint.get_global_rect()),
			"lines":hint.get_line_count(),"visible_lines":hint.get_visible_line_count()}))
		expect(hint.size.x > 100.0 and hint.size.y > 1.0 and hint.get_combined_minimum_size().y >= hint.get_line_height() * 2,
			"StatusHint receives a real text minimum and bounds at " + tag)
		expect(panel.size.y > 28.0 and panel.get_global_rect().encloses(hint.get_global_rect())
			and Rect2(Vector2.ZERO, Vector2(size)).encloses(panel.get_global_rect())
			and hint.get_line_count() == 2 and hint.get_visible_line_count() == 2
			and hint.clip_text, "StatusHint contains two uncropped lines with production clipping at " + tag)
		if mode != "notice":
			expect(hint.text.contains("若归航：") and hint.text.contains("本餐需 2 粮"),
				"persistent meal estimate remains on the visible second line at " + tag)
		if mode == "night":
			expect(hint.text.contains("入夜仍可撤离") and hud._threat_content.text.contains("4.50 秒")
				and hud._threat_content.text.contains("天黑不会强制发车")
				and hud._threat_content.text.contains("存活者全登车才归航"),
				"night route and top explanation follow the actual director at " + tag)
		if DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			var image: Image = viewport.get_texture().get_image()
			var area: Rect2i = Rect2i(hint.get_global_rect())
			var counts: Array[int] = _glyph_counts(image, area, hint.get_line_height())
			# Hide only glyph opacity: identical production panel geometry gives a
			# negative control, so a bright world pixel cannot masquerade as text.
			hint.self_modulate.a = 0.0
			RenderingServer.force_draw()
			var blank: Array[int] = _glyph_counts(viewport.get_texture().get_image(), area, hint.get_line_height())
			hint.self_modulate.a = 1.0
			print("BH_RUN_FEEL_GLYPHS " + JSON.stringify({"case":tag,"text_pixels":counts,"blank_pixels":blank}))
			expect(counts[0] > blank[0] + 80 and counts[1] > blank[1] + 80,
				"both lines render real cream glyphs inside the production panel at " + tag)
		else:
			print("BH_RUN_FEEL_RENDER skipped: headless Dummy; native renderer required for " + tag)
	# Casualty notifications are keyed by identity, including non-combat UI refreshes.
	world.survivors[0].take_damage(world.survivors[0].health)
	world._update_ui()
	expect(world._notice_clock > 0.0 and world._notice_text.contains("顾予安"), "first down notice names its member")
	world._notice_clock = 0.0
	world._update_ui()
	expect(world._notice_clock == 0.0 and hud._hint.text.contains("本餐需 1 粮"),
		"repeated down refresh does not replay notice and forecast follows living headcount")
	viewport.queue_free()
	await process_frame


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BH_RUN_FEEL_FAIL " + label)


func _food_forecasts(base: Dictionary) -> void:
	var before_hash: String = RecordEncoding.fingerprint(base)
	var crew: Array = base.crew.duplicate(true)
	var ledger: Dictionary = ReturnFeedback.forecast(2, crew, base, 4, 3, 1)
	expect(ledger.food_required == 2 and ledger.food_shortage == 0 and ledger.food_after == 5,
		"ordinary forecast spends one food per living departure member")
	crew[1].health = 0.0
	ledger = ReturnFeedback.forecast(2, crew, base, 0, 0, 1)
	expect(ledger.food_required == 1 and ledger.food_shortage == 1 and ledger.food_after == 0,
		"fallen members do not eat and shortage is visible")
	var joined: Dictionary = base.crew[0].duplicate(true)
	joined.id = 3
	joined.definition_id = "crew_3"
	joined.call_sign = "林知秋"
	crew.append(joined)
	ledger = ReturnFeedback.forecast(2, crew, base, 4, 0, 1)
	expect(ledger.food_required == 1 and ledger.food_after == 3,
		"new field recruit remains exempt from the first meal")
	crew[1].health = base.crew[1].health
	ledger = ReturnFeedback.forecast(2, crew, base, 0, 2, 1)
	expect(ledger.ration_member_ids == [1, 2] and ledger.food_shortage == 0 and ledger.food_after == 0,
		"two returning rations feed the original pair on the rescue night")
	var recruited: Dictionary = base.duplicate(true)
	recruited.crew.append(joined)
	ledger = ReturnFeedback.forecast(3, crew, recruited, ledger.food_after, 2, 1)
	expect(ledger.ration_member_ids == [1, 2, 3] and ledger.food_shortage == 1,
		"the same three survivors need a third ration on their next return")
	var facility: Dictionary = base.duplicate(true)
	facility.journey.campaign.economy = EconomyBuildV1.initial()
	EconomyBuildV1.state(facility).edits.append({"sortie":1,"target":"supply","op":"build"})
	ledger = ReturnFeedback.forecast(3, base.crew, facility, 0, 0, 1)
	expect(ledger.get("facility_food", 0) == 0 and ledger.food_shortage == 2,
		"empty returns earn no processing bonus even with a supply facility")
	ledger = ReturnFeedback.forecast(3, base.crew, facility, 0, 1, 1)
	expect(ledger.get("facility_food", 0) == 0 and ledger.food_shortage == 1,
		"one field ration leaves the pair one short")
	ledger = ReturnFeedback.forecast(3, base.crew, facility, 0, 2, 1)
	expect(ledger.facility_food == 1 and ledger.food_shortage == 0 and ledger.food_after == 1,
		"two field rations feed the pair and leave one processed ration")
	ledger = ReturnFeedback.forecast(2, base.crew, facility, 0, 2, 1)
	expect(ledger.get("facility_food", 0) == 0 and ledger.food_after == 0,
		"same-sortie construction cannot process a prior day's harvest")
	ledger = ReturnFeedback.forecast(3, base.crew, facility, CampRules.FOOD_LIMIT - 1, 3, 1)
	expect(ledger.food_stored == 1 and ledger.food_overflow == 2 and ledger.facility_stored == 0
		and ledger.food_after == CampRules.FOOD_LIMIT - 2, "forecast respects shared inventory capacity and deposit order")
	expect(RecordEncoding.fingerprint(base) == before_hash, "forecast never mutates departure or awards food")


func _result_wording(base: Dictionary) -> void:
	var rows: Array = [{"id":1,"health":200.0},{"id":2,"health":0.0}]
	var text: String = ReturnFeedback.return_text({"evacuated":false,"member_results":rows}, base.crew, [], "test:1")
	expect(text.contains("归航 0 人") and text.contains("未登车：顾予安")
		and text.contains("场内阵亡：夏之遥") and not text.contains("全员阵亡"),
		"unboarded living members and named field deaths are distinct")
	var snapshot: Dictionary = {"journey":{"state":"FAILED","deaths":[]},"last_settlement_id":"test:1"}
	expect(not ReturnFeedback.result_heading(snapshot, {"member_results":rows}).contains("全员阵亡"),
		"unboarded survivor cannot receive a full-wipe heading")
	snapshot.journey.deaths.append({"transaction_id":"test:1","member_id":1,"cause":"STARVATION"})
	text = ReturnFeedback.return_text({"evacuated":true,"member_results":rows}, base.crew,
		snapshot.journey.deaths, "test:1")
	expect(ReturnFeedback.result_heading(snapshot, {"member_results":rows}) == "旅程结束 · 口粮耗尽"
		and text.contains("归航 1 人：顾予安") and text.contains("餐后饥饿死亡：顾予安"),
		"hunger terminal distinguishes returning alive from meal deaths")


func _first_food_sortie(base: Dictionary, supply: MissionSupply) -> void:
	var world: Expedition = Expedition.new()
	world.supply = supply
	world.field_departure = base
	world.initial_food = 4
	world.sortie_id = base.profile_id + ":1"
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.growth_binding = {"run_id":base.profile_id,"root_id":base.journey.root_id,
		"transaction_id":world.sortie_id,"base_hash":SurvivalContracts.fingerprint(base),
		"rules_hash":SurvivalContracts.fingerprint(FrozenSettlement.pool_rules(base, supply))}
	root.add_child(world)
	world.set_physics_process(false)
	world.bus_view.skip()
	var food: Expedition.SearchSite = world.search_site(&"food")
	expect(world.setup_problem.is_empty() and world.day == 2 and SeasideTown.is_layout(world.layout)
		and food != null, "signed day-two offer opens the real seaside food point")
	if not world.setup_problem.is_empty() or food == null:
		world.queue_free()
		await process_frame
		return
	print("BH_RUN_FEEL_ROUTE " + JSON.stringify({"bus_door":str(world.layout.bus_door),"food_door":str(food.door)}))
	world.command_move(food.door)
	world.request_search(food.id)
	var engine_started: bool = false
	var gathered: bool = false
	var searching_at_start: int = 0
	for tick: int in range(2700):
		world.step(1.0 / 30.0)
		if not engine_started and world.elapsed >= world.tuning.bus_ready_seconds:
			searching_at_start = world.search_assignments.ordered().size()
			world.request_bus_action()
			engine_started = true
			expect(world.phase == Expedition.Phase.ENGINE
				and world.search_assignments.ordered().size() == searching_at_start and world.goal == food.door,
				"first B starts the engine without cancelling work or calling anyone back")
		if not gathered and world.phase == Expedition.Phase.BOARDING:
			world.request_bus_action()
			gathered = true
			world._notice_clock = 0.0
			world._update_ui()
			expect(world._hud.view._hint.text.contains("等待")
				and world._hud.view._hint.text.contains("再点搜集点可取消"),
				"boarding advice names waiting workers and explains how to cancel ongoing search")
		if world.phase == Expedition.Phase.FINISHED:
			break
		if tick % 30 == 0:
			await process_frame
	print("BH_RUN_FEEL_FIRST_RETURN " + JSON.stringify({"elapsed":world.elapsed,"food":world.food_loot,
		"living":world.living_count(),"phase":world.phase}))
	expect(world.phase == Expedition.Phase.FINISHED and world.elapsed >= 20.0 and world.elapsed <= 65.0
		and world.tuning.daylight_seconds - world.elapsed >= 20.0 and world.food_loot > 0
		and world.living_count() == 2, "first food return stays in tens of seconds, with daylight, loot and original pair alive")
	world.queue_free()
	await process_frame


func _glyph_counts(image: Image, area: Rect2i, line_height: int) -> Array[int]:
	var result: Array[int] = [0, 0]
	for y: int in range(area.position.y, area.end.y):
		for px: int in range(area.position.x, area.end.x):
			var colour: Color = image.get_pixel(px, y)
			if colour.r > 0.65 and colour.g > 0.60 and colour.b > 0.45:
				result[mini(1, (y - area.position.y) / line_height)] += 1
	return result
