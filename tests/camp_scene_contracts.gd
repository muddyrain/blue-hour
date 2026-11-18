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

	for tier: int in [0, 1, 2]:
		for id: String in EconomyBuildV1.FACILITIES:
			camp.journey.campaign.economy.facilities[id].level = tier
		var before: String = JSON.stringify(camp)
		view.refresh(camp, daily, true, "可以选择行动")
		_check(view.world.visible and view.world.stage.y_sort_enabled, "player entry shows depth-sorted world")
		for id: String in EconomyBuildV1.FACILITIES:
			_check(view.world.facilities[id] == tier, "independent facility tier " + id + str(tier))
			_check(view.facility_buttons[id].text.contains("待建" if tier == 0 else "%d 级" % tier), "visible on focus and hover: actual facility state " + id)
			_check(view.facility_buttons[id].tooltip_text.begins_with(view.facility_buttons[id].text), "facility tooltip retains level and effect " + id)
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
		_check(is_equal_approx(resident.body.texture.get_height() * resident.body.scale.y, CampSceneResident.HEIGHT), "pixel resident has a stable screen-space height")
		_check(resident.body.texture is AtlasTexture and resident.body.texture.atlas == CampPixelArt.SHEET, "resident uses the matched pixel family")
	var initial: Vector2 = view.world.residents[1].map_position
	for tick: int in range(140):
		view.world.advance(0.1)
	_check(not initial.is_equal_approx(view.world.residents[1].map_position), "resident actually walks between safe yard stops")
	for id: int in view.world.visible_member_ids:
		var resident: CampSceneResident = view.world.residents[id]
		_check(resident.position.is_equal_approx(resident.map_position.round()), "ambient walking stays on pixel-aligned camp coordinates")
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
		view.activate_at(CampSceneLayout.FACILITIES[id].get_center())
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
	view.activate_at(CampSceneLayout.AREAS[&"bus"].get_center())
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
	_check_reserve_positions(view.world)
	view.clear()
	_check(view.world.visible_member_ids.is_empty(), "leaving camp clears resident hit targets")
	view.queue_free()
	await process_frame
	print("BH_CAMP_SCENE checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_reserve_positions(world: CampSceneWorld) -> void:
	# Eight living members with both reserves and both of their shared-art identities.
	var members: Array[Dictionary] = []
	for id: int in range(3, 11):
		members.append({"id":id, "health":200.0})
	_check(SurvivorRoster.initialize(members).is_empty(), "reserve display fixture has official identities")
	var before: String = JSON.stringify(members)
	world.refresh(members)
	for tick: int in range(200):
		world.advance(0.1)
		if tick % 20 != 0:
			continue
		for id: int in world.visible_member_ids:
			var resident: CampSceneResident = world.residents[id]
			_check(world.pick(resident.position + Vector2(0, -30)).get("member_id") == id, "reserve roster retains a distinct clickable body")
	var positions: Array[Vector2] = []
	for id: int in world.visible_member_ids:
		positions.append(world.residents[id].position)
	world.refresh(members)
	for index: int in range(world.visible_member_ids.size()):
		_check(world.residents[world.visible_member_ids[index]].position == positions[index], "unchanged roster refresh does not reset ambient walks")
	_check(JSON.stringify(members) == before, "reserve layout never edits roster data")


func _check_geometry(view: CampSceneView) -> void:
	for extent: Vector2 in [Vector2(1280, 720), Vector2(1024, 640), Vector2(1600, 900)]:
		view.size = extent
		view._resize_world()
		_check(is_equal_approx(view.world.scale.x, view.world.scale.y), "scene resizing preserves authored perspective")
		for id: String in view.facility_buttons:
			var expected: Vector2 = view.world.to_global(CampSceneLayout.facility_door(id))
			var button: Button = view.facility_buttons[id]
			var actual: Vector2 = button.global_position + Vector2(button.size.x * 0.5, 0)
			_check(actual.distance_to(expected) < 0.1, "facility control stays attached to the visible door")
			_check(Rect2(Vector2.ZERO, extent).encloses(button.get_global_rect()), "door controls remain on screen")
	view.size = Vector2(1280, 720)
	view._resize_world()
	var original_position: Vector2 = view.world.position
	var original_scale: Vector2 = view.world.scale
	var summary: PanelContainer = view.get_node("ReturnSummary") as PanelContainer
	summary.show()
	view._resize_world()
	_check(view.world.position == original_position and view.world.scale == original_scale, "return receipt does not shrink or displace the scene's click targets")
	summary.hide()
	var pin: Button = view.facility_buttons["supply"]
	_check(pin.get_theme_color("font_color").a == 0.0 and pin.get_theme_color("font_hover_color") == CampSceneStyle.AMBER, "scene labels reveal on hover or keyboard focus")


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
		var atlas: AtlasTexture = resident.body.texture as AtlasTexture
		_check(atlas != null and atlas.atlas == CampPixelArt.SHEET and atlas.region == CampPixelArt.REGIONS[CampPixelArt.variant(String(definition.id))].grow(2), "correct stable identity region " + String(definition.id))
		_check(resident.get_meta("definition_id") == definition.id, "art replacement preserves identity " + String(definition.id))
		resident.free()


func _check_ground_and_dressing(view: CampSceneView) -> void:
	view._resize_world()
	var surface: Control = view.get_node("CampSceneSurface") as Control
	_check(surface.clip_contents and view.world.plate.texture == CampSceneWorld.PLATE, "real pixel scene plate is clipped to the scene region")
	_check(view.world.plate.z_index < view.world.stage.z_index and view.world.stage.y_sort_enabled, "independent residents render over the plate in foot-depth order")
	_check(view.world.plate.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "pixel scene uses nearest texture filtering")
	for id: int in range(1, RosterState.MAX_HISTORY + 1):
		var route: Array[Vector2] = CampSceneLayout.resident_route(id)
		for step: int in range(21):
			var point: Vector2 = route[0].lerp(route[1], step / 20.0)
			_check(CampSceneLayout.BOUNDS.has_point(point), "ambient route stays inside the scene")
			_check(not CampSceneLayout.FACILITIES.values().any(func(rect: Rect2) -> bool: return rect.has_point(point)), "ambient route avoids closed buildings and map table")
			_check(point.distance_to(CampSceneLayout.FIRE) > 36.0, "ambient route avoids the campfire")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("BH_CAMP_SCENE_FAIL " + label)
