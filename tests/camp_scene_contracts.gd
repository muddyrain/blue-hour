extends SceneTree
## Real opening constructors; later facility tiers are read-only display fixtures.
## No player save is opened. Exercise the actual scene and GUI intent adapter.

const SCENE: PackedScene = preload("res://src/features/camp_scene/camp_scene.tscn")
var _checks: int = 0
var _failures: int = 0
var _actions: Array[Dictionary] = []
var _investments: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var view: CampSceneView = SCENE.instantiate() as CampSceneView
	view.player_mode = true
	root.add_child(view)
	# This fixture owns its extent; production fills its parent with anchors.
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1280, 720)
	view.world.set_process(false)
	view.action_requested.connect(func(action: StringName, id: int) -> void:
		_actions.append({"action":action, "member_id":id}))
	view.facility_requested.connect(func(id: String) -> void: _investments.append(id))
	var camp: Dictionary = _fixture()
	_check(TransactionReceipt.camp_problem(camp).is_empty(), "fixture is a valid real opening snapshot before display-only changes")
	_check(camp.journey.state == "ACTIVE" and camp.crew.size() == 2 and not camp.weapons.is_empty(), "opening includes real journey state, roster and equipment")
	var daily: Dictionary = CampEconomy.rations(camp.day, camp.crew, camp.food, RunSave.DefaultRules)
	_check_ground_and_dressing(view)
	var level_one_art: Dictionary[String, String] = {}
	for tier: int in [0, 1, 2]:
		for id: String in EconomyBuildV1.FACILITIES:
			camp.journey.campaign.economy.facilities[id].level = tier
		var before: String = JSON.stringify(camp)
		view.refresh(camp, daily, true, "可以选择行动")
		_check(view.world.visible and view.world.stage.y_sort_enabled, "player entry shows depth-sorted world")
		for id: String in EconomyBuildV1.FACILITIES:
			var site: CampSceneScenery = view.world.facilities[id]
			_check(site.tier == tier, "independent facility tier " + id + str(tier))
			var art: Sprite2D = site.get_node_or_null("IsoSprite") as Sprite2D
			_check((art == null) if tier == 0 else (art != null and art.texture != null), "empty site or closed-roof art " + id)
			if tier == 1:
				level_one_art[id] = String(site.get_meta("iso_art"))
			if tier == 2:
				_check(level_one_art[id] != String(site.get_meta("iso_art")), "upgrade changes building silhouette " + id)
		if tier == 0:
			_actions.clear()
			view.facility_buttons["supply"].pressed.emit()
			_check(_actions == [{"action":&"supplies", "member_id":0}] and _investments.is_empty(), "opening site routes to supplies until return and tool requirements are met")
			_actions.clear()
		view.world.advance(0.1)
		_check(before == JSON.stringify(camp), "refresh and ambient time never mutate camp")
	_check(view.world.visible_member_ids == [1, 2], "real opening displays its two living members")
	_check_identity_templates(camp.crew[0])
	for id: int in view.world.visible_member_ids:
		var resident: CampSceneResident = view.world.residents[id]
		_check(resident.body.scale == Vector2.ONE * ActorVisual.BODY_SCALE, "official body scale")
		_check(resident.body.texture == SurvivorVisualV1.SHEETS[id - 1] and not resident.body.flip_h, "official unmirrored eight-way sheet")
	var initial: Vector2 = view.world.residents[1].map_position
	for tick: int in range(90):
		view.world.advance(0.1)
	_check(not initial.is_equal_approx(view.world.residents[1].map_position), "resident actually walks between safe yard stops")
	for id: int in view.world.visible_member_ids:
		var resident: CampSceneResident = view.world.residents[id]
		_check(resident.position.is_equal_approx(IsoSpace.to_view(resident.map_position)), "walking stays in shared iso projection")
		_check(not CampSceneLayout.FACILITIES.values().any(func(rect: Rect2) -> bool: return rect.has_point(resident.map_position)), "route never enters a closed building")
		_actions.clear()
		view.activate_at(resident.position + Vector2(0, -22))
		_check(_actions == [{"action":&"crew", "member_id":id}], "click moving person retains stable member identity")
	_actions.clear()
	for id: String in ["supply", "workshop", "planning"]:
		view.facility_buttons[id].pressed.emit()
	_check(_actions == [{"action":&"supplies", "member_id":0}, {"action":&"workshop", "member_id":0}, {"action":&"planning", "member_id":0}], "built facility pins use original panels")
	_actions.clear()
	for id: String in ["supply", "workshop", "planning"]:
		view.activate_at(IsoSpace.to_view(CampSceneLayout.FACILITIES[id].get_center()))
	_check(_actions == [{"action":&"supplies", "member_id":0}, {"action":&"workshop", "member_id":0}, {"action":&"planning", "member_id":0}], "physical buildings use the same panel routes as their pins")
	_actions.clear()
	view.input_allowed = func() -> bool: return false
	view.hotspots[&"bus"].pressed.emit()
	view.facility_buttons["supply"].pressed.emit()
	view.activate_at(view.world.residents[1].position)
	_check(_actions.is_empty() and _investments.is_empty(), "busy/modal guard blocks every input path")
	view.input_allowed = Callable()
	view.refresh(camp, daily, false, "暂不能出发")
	view.hotspots[&"bus"].pressed.emit()
	view.scene_buttons[&"bus"].pressed.emit()
	view.activate_at(IsoSpace.to_view(IsoSpace.foot(CampSceneLayout.AREAS[&"bus"])))
	_check(_actions.is_empty(), "departure eligibility also protects physical bus")
	view.refresh(camp, daily, true, "可以选择行动")
	view.hotspots[&"bus"].pressed.emit()
	_check(_actions == [{"action":&"bus", "member_id":0}], "departure remains the mission-selection intent")
	_check_geometry(view)
	var header: PanelContainer = view.get_node("CampHud") as PanelContainer
	var header_style: StyleBoxFlat = header.get_theme_stylebox("panel") as StyleBoxFlat
	var header_colour: Color = header_style.bg_color
	var caption: Label = view.find_child("AtmosphereCaption", true, false) as Label
	for amount: float in [0.0, 0.46, 0.72, 0.9]:
		view.world.set_dusk(amount)
		var expected: String = "白昼" if amount == 0.0 else "暖暮" if amount == 0.46 else "蓝时" if amount == 0.72 else "夜色"
		_check(caption.text == "旧渔协院落 · " + expected, "header follows live atmosphere " + expected)
	view.refresh(camp, daily, true, "可以选择行动")
	_check(caption.text.ends_with("夜色"), "camp refresh preserves the selected atmosphere")
	_check(header_colour == header_style.bg_color and view.modulate == Color.WHITE, "dusk is isolated from HUD")
	camp.crew[1].health = 0.0
	view.refresh(camp, daily, true, "可以选择行动")
	_check(2 not in view.world.visible_member_ids and not view.member_buttons[2].visible, "absent/down members do not wander or receive hit targets")
	view.clear()
	_check(view.world.visible_member_ids.is_empty(), "leaving camp clears resident hit targets")
	view.queue_free()
	await process_frame
	print("BH_CAMP_SCENE checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_geometry(view: CampSceneView) -> void:
	for extent: Vector2 in [Vector2(1280, 720), Vector2(1024, 640), Vector2(1600, 900)]:
		view.size = extent
		view._resize_world()
		var origin: Vector2 = view.world.to_global(Vector2.ZERO)
		var edge: Vector2 = view.world.to_global(IsoSpace.to_view(Vector2(64, 0))) - origin
		_check(is_equal_approx(absf(edge.x / edge.y), 2.0), "viewport keeps strict 2:1 axes")
		for id: String in view.facility_buttons:
			var expected: Vector2 = view.world.to_global(IsoSpace.to_view(CampSceneLayout.facility_door(id)))
			var button: Button = view.facility_buttons[id]
			var actual: Vector2 = button.global_position + Vector2(button.size.x * 0.5, 0)
			_check(actual.distance_to(expected) < 0.1, "facility pin follows uniform projection when resized")
			_check(button.size.x <= 112 * minf(extent.x / 1280.0, extent.y / 720.0) + 0.1 and button.get_theme_font_size("font_size") == 12, "facility pins stay compact")
	_check(CampSceneLayout.AREAS[&"bus"].size == Vector2(108, 32), "bus dimensions remain locked")
	_check(view.world.tiles.cells[Vector2i(10, 15)] == "road" and view.world.tiles.cells[Vector2i(10, 17)] == "road" and view.world.tiles.cells[Vector2i(10, 18)] == "sidewalk", "96-unit asphalt and 32-unit sidewalk")
	view.size = Vector2(1280, 720)
	var summary: PanelContainer = view.get_node("ReturnSummary") as PanelContainer
	for top: float in [542.0, 516.0]:
		summary.show()
		CampStyle.place(summary, Rect2(24, top, 916, 598 - top))
		view._resize_world()
		for corner: Vector2 in [Vector2(64, 32), Vector2(704, 32), Vector2(64, 448), Vector2(704, 448)]:
			var point: Vector2 = view.world.to_global(IsoSpace.to_view(corner))
			_check(Rect2(24, 104, 932, top - 108).has_point(point), "summary leaves the complete yard fence visible")
	summary.hide()
	view._resize_world()
	var pin: Button = view.facility_buttons["supply"]
	_check(pin.get_theme_color("font_color") != pin.get_theme_color("font_focus_color") and pin.get_theme_color("font_hover_color") == CampSceneStyle.AMBER, "quiet labels emphasize hover and keyboard focus")


func _fixture() -> Dictionary:
	# Match AppSession._new_game and camp_snapshot, without opening any save session.
	var crew: Array[Dictionary] = SurvivorRoster.new_crew()
	GrowthRules.initialize(crew)
	TraitRules.initialize(crew)
	TrainingState.initialize(crew)
	var profile: String = "0123456789abcdef0123456789abcdef"
	var camp: Dictionary = {"schema_version":RunSave.SCHEMA_VERSION, "profile_id":profile,
		"day":2, "cash":CampRules.INITIAL_CASH, "food":RunSave.DefaultRules.initial_food,
		"crew":crew, "last_day":{}, "settled_sorties":0, "last_settlement_id":"", "camp_spending":0}
	WeaponInventory.initialize(camp, "initial")
	for index: int in range(camp.weapons.size()):
		camp.weapons[index] = WeaponModifiers.baseline(camp.weapons[index])
	var journey: Dictionary = EnemyState.initial("camp-scene-contracts")
	var campaign: Dictionary = CampaignRules.initial_mission(profile, true, true, true, true,
		true, true, true, true, true, true)
	CampFacilities.enable_tier_two(campaign)
	campaign.night_hound_policy = NightHoundV1.VERSION
	campaign.workshop = WorkshopV1.initial()
	campaign.event_sortie_policy = EventSortieV1.VERSION
	campaign.recon_policy = ReconActionV1.SOURCE_VERSION
	campaign.barricade_policy = BarricadeV1.VERSION
	campaign.billboard_policy = BillboardActionV1.VERSION
	campaign.open_streets_policy = OpenStreetsV1.VERSION
	campaign.economy = EconomyBuildV1.initial()
	journey.campaign = campaign
	journey.build = WorldgenState.initial_build(journey.seed, true, true)
	journey.build.powers = PowerState.initial_progression(SpecialPowers.M48_VERSION)
	BuildState.enable_m48(journey.build)
	var starter: Dictionary = OpeningBuild.source("scavenge", profile, journey.root_id, journey.seed,
		{"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	journey.build.opening = starter
	journey.build.owned.append(starter.item_id)
	journey.build.slots[0] = starter.item_id
	journey.build.catalog = {"version":CatalogProgress.VERSION, "unlock":""}
	return EnemyState.snapshot(camp, journey, [], [])


func _check_identity_templates(opening_member: Dictionary) -> void:
	# Check all identity templates, including distinct reserve people sharing artwork.
	for definition: SurvivorDefinition in SurvivorRoster.Definitions:
		var member: Dictionary = opening_member.duplicate(true)
		member.definition_id = String(definition.id)
		member.call_sign = definition.default_display_name
		var resident: CampSceneResident = CampSceneResident.new()
		root.add_child(resident)
		resident.configure(member)
		var index: int = SurvivorVisualV1.variant_for(String(definition.id))
		_check(resident.body.texture == SurvivorVisualV1.SHEETS[index] and not resident.body.flip_h, "existing identity sheet " + String(definition.id))
		resident.free()


func _check_ground_and_dressing(view: CampSceneView) -> void:
	view._resize_world()
	var backdrop: CanvasItem = view.get_node("CampBackdrop") as CanvasItem
	_check(_canvas_z(backdrop) < _canvas_z(view.world.tiles) and _canvas_z(view.world.tiles) < _canvas_z(view.world.stage), "full-screen backing cannot cover ground; ground stays below depth-sorted props")
	_check(view.world.tiles.is_visible_in_tree() and view.world.tiles.cells[Vector2i(7, 6)] == "concrete", "yard has a visible continuous path layer")
	_check(view.world.scale.x > 0.80, "empty return-summary slot is available to the enlarged yard")
	for furnishing: Dictionary in CampSceneLayout.DRESSING:
		var extent: Vector2 = furnishing.size
		var at: Vector2 = furnishing.at
		var area: Rect2 = Rect2(at - Vector2(extent.x * 0.5, extent.y), extent)
		for id: String in CampSceneLayout.FACILITIES:
			_check(not area.intersects(CampSceneLayout.FACILITIES[id].grow(12)), "dressing clears facility " + id + "/" + String(furnishing.kind))
			_check(not area.grow(20).has_point(CampSceneLayout.facility_door(id)), "dressing clears door " + id)
		for index: int in range(CampSceneLayout.LOOP.size()):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(at, CampSceneLayout.LOOP[index], CampSceneLayout.LOOP[(index + 1) % CampSceneLayout.LOOP.size()])
			_check(not area.grow(16).has_point(closest), "dressing leaves a walking corridor " + String(furnishing.kind))
		var matches: Array[Node] = view.world.stage.get_children().filter(func(node: Node) -> bool:
			return node is CampSceneScenery and node.kind == furnishing.kind and IsoSpace.map_of(node) == at)
		_check(matches.size() == 1, "authored furnishing is on the real depth-sort stage " + String(furnishing.kind))


func _canvas_z(item: CanvasItem) -> int:
	var depth: int = item.z_index
	var current: CanvasItem = item
	while current.z_as_relative:
		# The yard uses direct CanvasItem parents. get_parent_item is not a
		# script API in the pinned engine; use the actual scene hierarchy.
		current = current.get_parent() as CanvasItem
		if current == null:
			break
		depth += current.z_index
	return depth


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("BH_CAMP_SCENE_FAIL " + label)
