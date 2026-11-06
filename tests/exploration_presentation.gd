extends SceneTree
## Controlled read-only components, not a generated map, journey or physical-input proof.
## Headless-compatible: no screenshots, player profiles or owner-side state mutations.

const HUD_SCENE: PackedScene = preload("res://src/features/expedition_hud/expedition_hud.tscn")
const HUD_THEME: Theme = preload("res://assets/ui/c1/hud_theme.tres")
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1024, 576)]

var failures: int = 0
var checks: Array[Dictionary] = []
var hud_cases: Array[Dictionary] = []
var prop_cases: Array[Dictionary] = []
var base: Dictionary


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("run")


func run() -> void:
	base = camp_fixture()
	var original: String = SurvivalContracts.fingerprint(base)
	check(TransactionReceipt.camp_problem(base).is_empty(), "controlled persona DTO source is a legal pure initial camp")
	for size: Vector2i in SIZES:
		for count: int in [2, 4]:
			await hud_case(size, count)
	await props_case()
	check(hud_cases.size() == 4 and prop_cases.size() == 3, "every requested HUD and prop scenario reached completion")
	check(SurvivalContracts.fingerprint(base) == original, "all components preserve their legal camp source")
	print("EXPLORATION_PRESENTATION " + JSON.stringify({"scope":"controlled read-only presentation; extra persona identities use candidate DTOs; no map generation, recruitment, rewards, combat or physical-input proof", "input_level":"GUI signals, focus and STOP properties only", "renderer":DisplayServer.get_name(), "checks":checks, "hud_cases":hud_cases, "prop_cases":prop_cases, "failures":failures}))
	quit(1 if failures else 0)


func hud_case(size: Vector2i, count: int) -> void:
	var tag: String = "%dx%d/%dp" % [size.x, size.y, count]
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	var layer: CanvasLayer = CanvasLayer.new()
	viewport.add_child(layer)
	var hud: C1ExpeditionHud = HUD_SCENE.instantiate() as C1ExpeditionHud
	hud.theme = HUD_THEME
	layer.add_child(hud)
	var objectives: Array[Dictionary] = [
		{"id":"primary_food", "title":"食品主站点", "optional":false, "done":0, "total":2, "complete":false, "site_ids":["food", "cash"], "hint":"受控主要目标，计数仅来自传入DTO。"},
		{"id":"optional_vehicles", "title":"搜完车辆", "optional":true, "done":1, "total":3, "complete":false, "site_ids":["vehicle_01", "vehicle_02", "vehicle_03"], "hint":"可选站点本身给收益，不额外发整组奖金。"},
		{"id":"optional_fruit", "title":"采完果树", "optional":true, "done":1, "total":1, "complete":true, "site_ids":["tree_01"], "hint":"已完成的受控目标，定位不更改任何工作。"},
	]
	var objective_hash: String = SurvivalContracts.fingerprint({"rows":objectives})
	var ids: Array[int] = [1, 2]
	if count == 4:
		ids.append(4)
		ids.append(5)
	var members: Array[Dictionary] = []
	for id: int in ids:
		var model: Dictionary = PersonaViewModel.camp(base, id, "camp" if id <= 2 else "candidate")
		model.scope = "field"
		model.editable = false
		model.status = "受控待命"
		members.append({"id":id, "persona":model})
	var located: Array[String] = []
	hud.objective_locate_requested.connect(func(id: String) -> void: located.append(id))
	hud.refresh({"mission_title":"受控探索界面", "objective":"", "day_text":"第 2 天", "search_progress_text":"2 / 9", "defeated_text":"0", "currency_text":"53", "resource_text":"货币53 · 食物2\n携带：钱1 · 粮1 · 武器0", "survivors":members, "exploration_objectives":objectives, "time":{"label":"受控界面", "text":"01:36", "hint":"威胁 · 平稳"}, "bus_status_text":"巴士准备 20 秒", "bus_action_label":"巴士准备 20 秒", "bus_action_enabled":false})
	await settle()
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(size)).grow(0.5)
	var list: ExplorationObjectives = hud._exploration_objectives
	var mission: Control = hud.get_node("MissionPanel") as Control
	var expanded_height: float = mission.size.y
	var row_sizes: Array = []
	var compact: bool = list.size.y <= 76.5 and list.size.x <= 272.5
	var text_matches: bool = true
	for index: int in range(3):
		var row: Control = list.get_child(index) as Control
		row_sizes.append([row.size.x, row.size.y])
		compact = compact and row.size.y <= 24.5
		text_matches = text_matches and list.labels[index].text.contains("%d/%d" % [objectives[index].done, objectives[index].total]) and list.labels[index].tooltip_text.contains(objectives[index].title) and list.labels[index].tooltip_text.contains(objectives[index].hint)
	check(compact and text_matches and list.labels[0].text.contains("主") and list.labels[1].text.contains("可选") and list.labels[2].text.contains("✓"), tag + " three factual objective rows stay within 24px/76px and retain full explanations")
	var skills: Array[Rect2] = [Rect2(16, 164, 184, 68), Rect2(16, 240, 184, 68), Rect2(16, 316, 184, 74)]
	var no_overlap: bool = bounds.encloses(mission.get_global_rect())
	for rect: Rect2 in skills:
		no_overlap = no_overlap and not mission.get_global_rect().intersects(rect)
	check(no_overlap, tag + " expanded MissionPanel clears the existing Q/E/3 rectangles")
	hud._objective_toggle.pressed.emit()
	await settle()
	var folded: bool = not list.visible and mission.size.y < expanded_height
	hud._objective_toggle.pressed.emit()
	await settle()
	check(folded and list.visible and mission.size.y == expanded_height, tag + " original fold control hides and restores the objective list")
	for button: Button in list.locate_buttons:
		button.pressed.emit()
	var expected_ids: Array[String] = ["primary_food", "optional_vehicles", "optional_fruit"]
	check(located == expected_ids and SurvivalContracts.fingerprint({"rows":objectives}) == objective_hash and not hud._paused, tag + " locate controls emit only the stable IDs and preserve supplied objective DTOs")
	var panel: Control = hud.get_node("MembersPanel") as Control
	var reachable: bool = bounds.encloses(panel.get_global_rect())
	var cards: Array[Dictionary] = []
	for card: PersonaCard in hud._persona_cards:
		if not card.visible:
			continue
		hud._member_scroll.ensure_control_visible(card)
		await settle()
		var client: Rect2 = scroll_client(hud._member_scroll).grow(0.5)
		reachable = reachable and client.encloses(card.get_global_rect())
		cards.append({"rect":rect_values(card.get_global_rect()), "client":rect_values(client)})
	check(cards.size() == count and reachable, tag + " every persona card is reachable through the real bounded member scroll")
	if count == 2:
		var last: PersonaCard = hud._persona_cards[1]
		check(panel.get_global_rect().end.y < float(size.y) - 80.0 and panel.get_global_rect().end.y - last.get_global_rect().end.y <= 24.5, tag + " two-person member background contracts to the actual content")
	hud._persona_cards[0].info_button.pressed.emit()
	await settle()
	var details: PersonaDetails = hud.persona_details
	check(details.visible and details.mouse_filter == Control.MOUSE_FILTER_STOP and not details.mouse_force_pass_scroll_events and details.scroll.mouse_filter == Control.MOUSE_FILTER_STOP and not details.scroll.mouse_force_pass_scroll_events and bounds.encloses(details.get_global_rect()), tag + " original details keep bounded STOP ownership of clicks and scrolling")
	details.close()
	var result: Dictionary = {"size":[size.x, size.y], "count":count, "objective_size":[list.size.x, list.size.y], "row_sizes":row_sizes, "mission":rect_values(mission.get_global_rect()), "member_panel":rect_values(panel.get_global_rect()), "cards":cards, "located":located, "scope":"controlled UI only"}
	viewport.queue_free()
	await process_frame
	hud_cases.append(result)


func props_case() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var textures: Array[Texture2D] = [ExplorationProp.SEDAN, ExplorationProp.VAN, ExplorationProp.TREE, ExplorationProp.EMPTY_TREE, ExplorationProp.TRUNK]
	check(textures.all(func(texture: Texture2D) -> bool: return texture != null and texture.get_width() > 0 and texture.get_height() > 0), "all five actual object textures load with nonzero dimensions")
	var definitions: Array[Dictionary] = [
		{"id":"vehicle_01", "kind":"vehicle", "variant":"sedan", "point":[300.0, 300.0], "collision":[236.0, 272.0, 128.0, 32.0], "work_point":[412.0, 300.0]},
		{"id":"vehicle_02", "kind":"vehicle", "variant":"van", "point":[650.0, 300.0], "collision":[580.0, 264.0, 140.0, 40.0], "work_point":[762.0, 300.0]},
		{"id":"tree_01", "kind":"fruit_tree", "variant":"apple_tree", "point":[930.0, 300.0], "collision":[923.0, 290.0, 14.0, 14.0], "work_point":[970.0, 300.0]},
	]
	for definition: Dictionary in definitions:
		var tag: String = String(definition.variant)
		var definition_hash: String = SurvivalContracts.fingerprint(definition)
		var seconds: float = 6.0 if definition.kind == "fruit_tree" else 8.0
		var fresh: Dictionary = {"searched":false, "progress":0.0}
		var working: Dictionary = {"searched":false, "progress":seconds * 0.5}
		var empty: Dictionary = {"searched":true, "progress":seconds}
		var facts_hash: String = SurvivalContracts.fingerprint({"fresh":fresh, "working":working, "empty":empty})
		var prop: ExplorationProp = ExplorationProp.new()
		prop.ui_theme = HUD_THEME
		prop.configure(definition)
		prop.reward_hint = "食物+1" if definition.kind == "fruit_tree" else "货币+1"
		viewport.add_child(prop)
		prop.present(fresh)
		prop.update_work(-1, 0.0, false)
		await settle()
		var available_texture: Texture2D = prop._roof.texture
		check(prop is FieldProp and not prop.searched and prop._work.text.contains(prop.reward_hint) and not prop._bar.visible, tag + " original FieldProp-compatible skin shows the actual available resource")
		prop.present(working, 1, "顾予安")
		prop.update_work(0, 0.5, true, "顾予安", "受控工作界面")
		await settle()
		check(not prop.searched and prop._work.text.contains("顾予安") and prop._work.text.contains("50%") and prop._bar.visible and prop._bar.value == 50.0, tag + " owner-supplied worker and fraction drive visible work feedback")
		prop.update_work(-1, 0.5, false)
		check(not prop.searched and prop._bar.visible and prop._bar.value == 50.0, tag + " cancellation presentation preserves supplied partial progress")
		prop.present(empty)
		prop.update_work(-1, 1.0, false)
		await settle()
		check(prop.searched and not prop._bar.visible and prop._work.text.contains("已采空" if definition.kind == "fruit_tree" else "已清空"), tag + " completed facts produce a clearly empty state without a second reward owner")
		if definition.kind == "fruit_tree":
			prop.present(empty, 0, "", true)
			check(prop._roof.texture != available_texture and prop._roof.modulate.a < 1.0 and prop._wall.modulate.a == 1.0 and prop._wall.visible, "tree canopy changes after harvest and fades independently of the trunk")
			prop.show_behind_roof(false)
			check(prop._roof.modulate.a == 1.0, "tree canopy restores opacity when the supplied occlusion ends")
		else:
			check(prop._roof.modulate != Color.WHITE and not prop.obscures(prop.global_position), tag + " empty parked car stays visible and creates no roof-occlusion policy")
		check(SurvivalContracts.fingerprint(definition) == definition_hash and SurvivalContracts.fingerprint({"fresh":fresh, "working":working, "empty":empty}) == facts_hash, tag + " display updates preserve the exact object definition and facts")
		prop_cases.append({"variant":tag, "available_texture":available_texture.resource_path, "empty_texture":prop._roof.texture.resource_path, "empty_label":prop._work.text, "scope":"controlled component states, not actual work or rewards"})
		prop.queue_free()
		await process_frame
	viewport.queue_free()
	await process_frame


func camp_fixture() -> Dictionary:
	var crew: Array[Dictionary] = SurvivorRoster.new_crew()
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	var camp: Dictionary = {"schema_version":5, "profile_id":"0123456789abcdef0123456789abcdef", "day":2, "cash":53, "food":RunSave.DefaultRules.initial_food, "last_day":{}, "settled_sorties":0, "last_settlement_id":"", "crew":crew}
	WeaponInventory.initialize(camp, "initial")
	for index: int in range(camp.weapons.size()):
		camp.weapons[index] = WeaponModifiers.baseline(camp.weapons[index])
	var journey: Dictionary = EnemyState.initial("exploration-presentation-fixture")
	journey.campaign = CampaignRules.initial(camp.profile_id)
	journey.build = PersonaState.initial_build(journey.seed)
	return EnemyState.snapshot(camp, journey, [], [])


func scroll_client(scroll: ScrollContainer) -> Rect2:
	var rect: Rect2 = scroll.get_global_rect()
	if scroll.get_v_scroll_bar().visible:
		rect.size.x -= scroll.get_v_scroll_bar().size.x
	return rect


func rect_values(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func settle() -> void:
	for tick: int in range(4):
		await process_frame


func check(value: bool, label: String) -> void:
	checks.append({"pass":value, "label":label})
	if not value:
		failures += 1
		printerr("EXPLORATION_PRESENTATION_FAIL " + label)
