class_name ExpeditionWorld
extends RefCounted

var expedition: Expedition


func _init(owner: Expedition) -> void:
	expedition = owner


func setup() -> void:
	expedition.task_event = TaskActions.empty_event(expedition.supply.generated)
	expedition.parallel_search = expedition.combat_mode()
	expedition._setup_crew.assign(expedition.crew_snapshot.duplicate(true) if not expedition.crew_snapshot.is_empty() else SurvivorRoster.new_crew())
	if expedition.crew_snapshot.is_empty():
		for index: int in range(expedition._setup_crew.size()):
			if index < expedition.starting_health.size():
				expedition._setup_crew[index].health = expedition.starting_health[index]
	expedition.setup_problem = SurvivalContracts.identity_problem(expedition._setup_crew,true)
	if expedition.setup_problem.is_empty() and not expedition.loadout_snapshot.is_empty():
		expedition.setup_problem = WeaponInventory.snapshot_problem(expedition._setup_crew, expedition.loadout_snapshot, true,WeaponState.is_family(expedition.field_departure))
	if expedition.setup_problem.is_empty() and not expedition.crew_snapshot.is_empty() and expedition.loadout_snapshot.is_empty():
		expedition.setup_problem = "正式名册缺少出击配装快照"
	expedition.participants_snapshot = SurvivalContracts.participants(expedition._setup_crew, expedition.loadout_snapshot, true,true) if expedition.setup_problem.is_empty() else []
	if expedition.participants_snapshot.is_empty():
		expedition.setup_problem = expedition.setup_problem if not expedition.setup_problem.is_empty() else "没有可行动的参与者"
		expedition.set_physics_process(false)
		expedition.set_process_unhandled_input(false)
		return
	expedition.growth_inputs.configure(expedition.participants_snapshot)
	expedition.xp_inputs.configure(expedition.growth_binding)
	if expedition.build_mode():
		expedition.basic_support.configure(expedition.growth_binding, FirstAidV1.enabled(expedition.supply.generated),
			BuildAuthority.radio_equipped(expedition.supply.generated))
	if expedition.power_mode(): expedition.powers=SpecialPowers.initial(expedition.growth_binding,PowerState.loadout(expedition.supply.generated.powers))
	if expedition.combat_mode(): expedition.combat.setup(expedition)
	expedition.trait_inputs.configure(expedition.growth_binding)
	if SurvivalContracts.integer(expedition.supply.generated.get("version"), 6, 9):
		expedition.tuning.spawn_seconds *= CampaignPressureV1.spawn_factor(expedition.supply.generated)
	expedition.layout = expedition.supply.layout
	expedition._supply_entrances = expedition._world._street_supply_entrances()
	expedition._cash_site.door = expedition.layout.cash_door
	expedition._food_site.door = expedition.layout.food_door
	if expedition.supply.generated.has("barricade"):
		expedition.navigation = BarricadeV1.navigation(expedition.supply.generated, false)
	elif expedition.exploration_mode() and not expedition.pump_station_mode():
		expedition.navigation = ExplorationLayout._routing(expedition.layout.world_data).nav
	else:
		expedition.navigation.configure(expedition.layout.blockers(), expedition.layout.world_bounds)
	expedition.shot_obstacles = expedition.layout.shot_obstacles()
	if expedition.pump_station_mode():
		var station_ground: PumpStationGround = PumpStationGround.new()
		station_ground.layout = expedition.layout
		station_ground.z_index = -10
		expedition.add_child(station_ground)
	else:
		var ground: StreetBlock = StreetBlock.new()
		ground.layout = expedition.layout
		ground.supply_entrances = expedition._supply_entrances
		ground.food_source_visible = expedition.supply.supports(&"food")
		ground.z_index = -10
		expedition.add_child(ground)
	expedition._feedback._make_camera()
	expedition._sort = Node2D.new()
	expedition._sort.name = "ActorsAndProps"
	expedition._sort.y_sort_enabled = true
	expedition.add_child(expedition._sort)
	expedition._effects = Node2D.new()
	expedition.add_child(expedition._effects)
	if expedition.supply.generated.has("barricade"):
		expedition._barricade_view = BarricadeView.new()
		expedition._barricade_view.footprint = BarricadeV1.rect(expedition.supply.generated)
		expedition._barricade_view.landing = WorldLayout.point(expedition.supply.generated.barricade.landing)
		expedition._barricade_view.label_font = expedition.ui_theme.default_font if expedition.ui_theme != null else null
		expedition._barricade_view.z_index = 1
		expedition.add_child(expedition._barricade_view)
	if ReconActionV1.enabled(expedition.supply.generated):
		expedition.recon_site = Expedition.SearchSite.new(StringName(ReconActionV1.SITE_ID), ReconActionV1.point(expedition.supply.generated))
		expedition.recon_site.seconds = ReconActionV1.SECONDS
		expedition.recon_knowledge = ReconKnowledge.new(expedition.supply.generated)
		expedition._recon_view = ReconFieldView.new()
		expedition._recon_view.world = expedition
		expedition._recon_view.z_index = 1
		expedition._effects.z_index = 2
		expedition.add_child(expedition._recon_view)
	if BillboardActionV1.enabled(expedition.supply.generated):
		expedition.billboard_site = Expedition.SearchSite.new(StringName(BillboardActionV1.SITE_ID), BillboardActionV1.point(expedition.supply.generated))
		expedition.billboard_site.seconds = BillboardActionV1.SECONDS
		expedition.billboard_site.hit = BillboardActionV1.hit_rect(expedition.billboard_site.door)
		expedition.billboard_work = BillboardWorkV1.new()
		expedition._billboard_view = BillboardFieldView.new()
		expedition._billboard_view.position = expedition.billboard_site.door
		expedition._billboard_view.label_font = expedition.ui_theme.default_font if expedition.ui_theme != null else null
		expedition._sort.add_child(expedition._billboard_view)
	var bus: Sprite2D = Sprite2D.new()
	expedition._bus_sprite = bus
	bus.texture = Expedition.BusTexture
	bus.offset = Vector2(0, -128)
	bus.scale = Vector2.ONE * (240.0 / 448.0)
	bus.position = expedition.layout.bus_foot()
	expedition._sort.add_child(bus)
	if expedition.pump_station_mode():
		expedition._world._make_pump_station()
	elif not expedition.layout.world_data.is_empty():
		expedition._world._make_world_buildings()
	else:
		expedition._shop = expedition._world._make_building(expedition.layout.cash_block,expedition.layout.cash_title,FieldProp.ShopTexture,false,false)
		expedition._shop.searchable = expedition.supply.supports(&"cash")
		expedition._shop.reward_hint = ("货币 +%d" % expedition.supply.cash_reward)+(" / 武器" if expedition.supply.has_weapon_sample else "")
		expedition._cash_site.prop = expedition._shop
		var second: FieldProp = expedition._world._make_building(expedition.layout.food_block,expedition.layout.food_title,
			preload("res://assets/m401/market.png") if expedition.supply.supports(&"food") else preload("res://assets/m402/rowhouse.png"),expedition.supply.supports(&"food"),not expedition.supply.supports(&"food"))
		second.searchable = expedition.supply.supports(&"food")
		second.reward_hint = "食物 +%d" % expedition.supply.food_reward
		expedition._food_site.prop = second
		for block: Rect2 in expedition.layout.residences:
			expedition._world._make_building(block,"柳巷住宅",preload("res://assets/m402/rowhouse.png"),false,true)
		expedition.sites.assign([expedition._cash_site,expedition._food_site])
	for block: Rect2 in ([] if expedition.layout.world_data.get("version")==5 else expedition.layout.fences):
		var fence: StreetFence = StreetFence.new()
		fence.footprint = block
		fence.position = Vector2(block.position.x,block.end.y)
		expedition._sort.add_child(fence)
	for index: int in range(expedition.participants_snapshot.size()):
		var participant: Dictionary = expedition.participants_snapshot[index]
		var profile: Dictionary = SurvivorRoster.member(expedition._setup_crew, int(participant.id))
		var start: Vector2 = expedition._arrival(index)
		if not expedition.setup_problem.is_empty():
			expedition.set_physics_process(false)
			expedition.set_process_unhandled_input(false)
			return
		var actor: FieldActor = expedition._make_actor(false, index, start, profile)
		actor.health = float(participant.health_before)
		actor.call_sign = profile.call_sign
		var item: Dictionary = {}
		for entry: Dictionary in expedition.loadout_snapshot:
			if int(entry.member_id) == actor.member_id:
				item = entry.instance
		if item.is_empty():
			# Standalone scenes have no campaign inventory; retain their old views.
			actor.weapon_definition = WeaponInventory.Definitions[1 if actor.definition_id == &"crew_2" else 0].duplicate() as WeaponDefinition
		else:
			actor.weapon_instance_id = item.instance_id
			actor.weapon_definition = WeaponModifiers.combat_definition(item)
		actor.visual.set_weapon(actor.weapon_definition.presentation)
		if expedition.combat_mode() and CombatRuntime.patterned(String(actor.weapon_definition.id)): expedition.combat.action(actor)
		if (expedition.supply.generated.get("version")==5 or (expedition.supply.generated.get("version")==6 or (expedition.supply.generated.get("version")==7 or (expedition.supply.generated.get("version")==8 or expedition.supply.generated.get("version")==9)))):
			if not CombatEquipment.melee(String(actor.weapon_definition.id)):
				actor.magazine = WeaponMagazine.new(actor.weapon_instance_id, String(actor.weapon_definition.id),
					WorkshopV1.mod_for(expedition.field_departure, actor.weapon_instance_id))
		if expedition.build_mode(): expedition.apply_build(actor)
		expedition.survivors.append(actor)
	if expedition.recon_knowledge != null and not expedition.restoring_world:
		expedition.recon_knowledge.reveal(expedition.layout.bus_door)
		expedition._support._update_recon_knowledge()
	if (expedition.supply.generated.get("version")==6 or (expedition.supply.generated.get("version")==7 or (expedition.supply.generated.get("version")==8 or expedition.supply.generated.get("version")==9))):
		expedition.encounter=EncounterRuntime.new();expedition.encounter.setup(expedition,expedition.restoring_world)
	expedition._make_ui()
	var readout_layer: CanvasLayer = CanvasLayer.new()
	readout_layer.layer = 5
	expedition.add_child(readout_layer)
	if expedition.supply.id == &"rescue" and not expedition.rescue_completed:
		expedition.rescue_target = RescueTarget.new()
		expedition.rescue_target.world = expedition
		expedition.add_child(expedition.rescue_target)
	if not expedition.field_joins.is_empty() and expedition.rescue_target != null:
		expedition.promote_target(expedition.field_joins[0],true)
	expedition._readouts = SquadReadouts.new()
	readout_layer.add_child(expedition._readouts)
	expedition._spawn_clock = expedition.tuning.spawn_seconds
	expedition.threat.update(expedition.elapsed, expedition.tuning.daylight_seconds, expedition.tuning.spawn_seconds)
	if expedition.recon_site != null:
		expedition._show_notice("主装备点待发现 · 可沿街探索或先到侦察点。")
	else:
		expedition._show_notice(expedition.layout.route_hint if expedition._supply_entrances.is_empty() else
			"先搜近点食品 · 可回巴士撤离，也可沿街追加第二处。")
	if not expedition.layout.world_data.is_empty():
		expedition.bus_view = BusJourney.new()
		expedition.bus_view.configure(expedition,expedition._bus_sprite,expedition.layout.world_data.bus)
		expedition.add_child(expedition.bus_view)
	expedition._night_lighting = NightLighting.new()
	expedition.add_child(expedition._night_lighting)
	print("BH_SORTIE start day=%d members=%d" % [expedition.day, expedition.survivors.size()])


func _make_actor(enemy: bool, index: int, point: Vector2, profile: Dictionary = {}, kind: String = "") -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.actor_id = index
	if not enemy:
		var identity: Dictionary = profile
		if identity.is_empty() and index < 2:
			identity = SurvivorRoster.new_crew()[index]
		actor.member_id = int(identity.get("id", 0))
		actor.definition_id = StringName(identity.get("definition_id", ""))
	actor.is_enemy = enemy
	if enemy:
		actor.visual_contact = expedition._visual_contact.bind(actor)
	actor.speed = expedition.tuning.enemy_speed if enemy else expedition.tuning.survivor_speed
	actor.motion_locked=expedition.power_frozen if enemy else false
	actor.max_health = expedition.tuning.enemy_health if enemy else expedition.tuning.survivor_health
	if not enemy and not profile.is_empty():
		actor.max_health = GrowthRules.maximum(profile)
	actor.health = actor.max_health
	if enemy:
		actor.enemy_behavior = EnemyBehavior.new()
		actor.enemy_behavior.kind = kind if not kind.is_empty() else EnemyRules.NORMAL if index>=10000 else expedition.combat.pick_spawn(expedition,index) if expedition.combat_mode() else EnemyRules.pick(expedition.sortie_id,index,int(expedition.threat.stage))
		actor.enemy_behavior.spawn_stage = int(expedition.threat.stage)
		if expedition.combat_mode() and actor.enemy_behavior.kind==CombatEnemyRules.TOXIC: expedition.combat.toxic.casters[str(index)]=ToxicV1._caster(index)
		actor.enemy_theme = expedition.ui_theme
		actor.max_health = EnemyRules.health(actor.enemy_behavior.kind,expedition.tuning.enemy_health)
		actor.health = actor.max_health
		actor.speed = EnemyRules.speed(actor.enemy_behavior.kind,false,expedition.tuning.enemy_speed)
	if not enemy and not profile.is_empty():
		TraitRules.apply(actor,profile,expedition.tuning.survivor_speed)
	actor.position = point
	expedition._sort.add_child(actor)
	return actor


func _make_building(block: Rect2, title: String, texture: Texture2D, market: bool, residence: bool) -> FieldProp:
	var building: FieldProp = FieldProp.new()
	building.facade = texture
	building.is_market = market
	building.is_residence = residence
	building.searchable = expedition.supply.supports(&"food") if market else (not residence and expedition.supply.supports(&"cash"))
	building.title = title
	building.front_width = block.size.x
	building.position = Vector2(block.get_center().x,block.end.y)
	building.ui_theme = expedition.ui_theme
	expedition._sort.add_child(building)
	expedition._buildings.append(building)
	return building


func _make_pump_station() -> void:
	var station: Dictionary = expedition.layout.world_data.pump_station
	expedition.station_art = PumpStationArt.new()
	expedition.station_art.configure(WorldLayout.rect(station.power_house), WorldLayout.point(station.console))
	expedition._sort.add_child(expedition.station_art)
	for block: Rect2 in expedition.layout.fences:
		var wall: IndustrialYardWall = IndustrialYardWall.new()
		wall.footprint = block
		wall.position = Vector2(block.get_center().x, block.end.y)
		expedition._sort.add_child(wall)
	var def: Dictionary = expedition.supply.generated.sites[0]
	var site: Expedition.SearchSite = Expedition.SearchSite.new(&"cash", WorldLayout.point(def.point))
	site.seconds = float(def.seconds)
	site.hit = Rect2(site.door - Vector2(45, 72), Vector2(90, 96))
	var cabinet: PumpConsoleProp = PumpConsoleProp.new()
	cabinet.position = site.door
	cabinet.title = "泵站控制柜"
	cabinet.primary_target = true
	cabinet.ui_theme = expedition.ui_theme
	expedition._sort.add_child(cabinet)
	site.prop = cabinet
	expedition._cash_site = site
	expedition.sites.assign([site])


func _make_world_buildings() -> void:
	if expedition.layout.world_data.get("version")==5:
		var yard: Dictionary = expedition.layout.world_data.get("loading_yard", expedition.layout.world_data.get("rescue_court", {}))
		var yard_bounds: Rect2 = WorldLayout.rect(yard.bounds) if not yard.is_empty() else Rect2()
		for wall: Rect2 in expedition.layout.fences:
			if expedition.layout.world_data.has("warehouse_district") or expedition.layout.world_data.has("themed_district") \
					or (not yard.is_empty() and yard_bounds.encloses(wall)):
				var masonry: IndustrialYardWall = IndustrialYardWall.new()
				masonry.footprint = wall
				masonry.position = Vector2(wall.get_center().x, wall.end.y)
				expedition._sort.add_child(masonry)
				continue
			var stone: WorldgenFurniture=WorldgenFurniture.new()
			stone.detail={"kind":"wall","width":wall.size.x};stone.position=Vector2(wall.get_center().x,wall.end.y);expedition._sort.add_child(stone)
	if expedition.layout.world_data.get("version")==5:
		for detail: Dictionary in NeighborhoodDecor.placements(expedition.layout):
			var prop: WorldFurniture = WorldFurniture.new()
			prop.kind = detail.kind
			prop.position = detail.position
			prop.variant = int(detail.variant)
			prop.refined = true
			expedition._sort.add_child(prop)
	else:
		for row: Dictionary in expedition.layout.world_data.entities:
			for kind: String in ["lamp","planter","crate","fence"]:
				var prop: WorldFurniture = WorldFurniture.new()
				prop.kind=kind
				var offset: Vector2 = {"lamp":Vector2(-24,48),"planter":Vector2(44,52),"crate":Vector2(-32,-16),"fence":Vector2(100,-30)}[kind]
				prop.position=Vector2(row.rect[0],row.rect[1]+row.rect[3])+offset
				expedition._sort.add_child(prop)
	if expedition.layout.world_data.get("version")==5:
		for parcel: Dictionary in expedition.layout.world_data.parcels:
			for detail: Dictionary in parcel.get("dressing",[]):
				if detail.has("surface"):
					continue
				var scenery: WorldgenFurniture=WorldgenFurniture.new()
				scenery.detail=detail;scenery.position=WorldLayout.point(detail.point);expedition._sort.add_child(scenery)
	var props: Dictionary = {}
	for entity: Dictionary in expedition.layout.world_data.entities:
		var block: Rect2 = WorldLayout.rect(entity.rect)
		var definition: Dictionary = WorldgenArt.definition(entity)
		var building: FieldProp = FieldProp.new()
		building.facade = definition.texture
		building.fixed_roof = definition.get("fixed_roof", false)
		if definition.has("native_size"):
			building.native_size=definition.native_size
			building.render_anchor=definition.origin
			building.reference_width=definition.reference_width
			building.street_sign=definition.get("street_sign","")
			building.sign_rect=definition.get("sign_rect",Rect2())
		building.soft_contact=expedition.layout.world_data.get("art_revision")==3
		if expedition.layout.world_data.get("version")==5:
			building.modulate=[Color.WHITE,Color(0.92,0.97,1.0),Color(1.0,0.97,0.9),Color.WHITE][int(entity.variant)]
		if expedition.layout.world_data.has("warehouse_district"):
			building.roof_tint = [Color.WHITE, Color(0.88, 1.12, 1.08), Color(1.14, 0.98, 0.83)][int(entity.variant)]
		if not expedition._supply_entrances.is_empty():
			building.roof_tint *= Color(0.69, 0.81, 1.0)
			building.facade_tint = Color(0.87, 0.91, 0.98)
		building.world_asset = true
		if expedition.layout.world_data.get("version")==5:
			building.calibrated=true;building.roof_cut=int(definition.roof_split);building.body_depth=block.size.y
			building.door_offset=WorldLayout.point(entity.door).x-block.get_center().x
		building.title = definition.title
		building.front_width = block.size.x
		building.position = Vector2(block.get_center().x,block.end.y)
		building.ui_theme = expedition.ui_theme
		building.searchable = expedition.supply.generated.sites.any(func(d: Dictionary) -> bool: return d.building==entity.id)
		expedition._sort.add_child(building)
		expedition._buildings.append(building)
		props[entity.id] = building
	if expedition.exploration_mode():
		for definition: Dictionary in expedition.layout.world_data.objects:
			var prop: ExplorationProp=ExplorationProp.new()
			prop.ui_theme=expedition.ui_theme
			prop.refined_art=expedition.layout.world_data.get("version")==5
			expedition._sort.add_child(prop)
			prop.configure(definition)
			props[definition.id]=prop
			expedition.exploration_props[definition.id]=prop
	for def: Dictionary in expedition.supply.generated.sites:
		var entity: Dictionary = {}
		for row: Dictionary in expedition.layout.world_data.entities:
			if row.id==def.building: entity=row
		var object_site: bool=expedition.exploration_mode() and def.source in ["vehicle","fruit_tree"]
		var crate: bool = def.has("point") and not object_site
		var site: Expedition.SearchSite = Expedition.SearchSite.new(StringName(def.kind),TaskActions.site_point(expedition.supply.generated,def) if expedition.exploration_mode() else WorldLayout.point(def.point) if crate else WorldLayout.point(entity.door))
		site.id=StringName(def.id); site.reward=int(def.amount); site.weapon=def.weapon; site.seconds=float(def.seconds)
		if object_site:
			site.door=TaskActions.site_point(expedition.supply.generated,def)
			site.prop=props[def.object_id]
			site.hit=Rect2(site.prop.position+Vector2(-80,-180 if def.source=="fruit_tree" else -96),Vector2(160,192 if def.source=="fruit_tree" else 108))
		elif crate:
			site.prop=AirdropProp.new(); site.prop.position=site.door; site.prop.front_width=80; site.prop.ui_theme=expedition.ui_theme
			expedition._sort.add_child(site.prop)
			site.hit=Rect2(site.door-Vector2(48,100),Vector2(96,150))
		else:
			site.prop=props[def.building]
			site.hit=Rect2(site.prop.position-Vector2(site.prop.front_width/2,280),Vector2(site.prop.front_width,340)) if expedition.layout.world_data.get("version")==5 else Rect2(WorldLayout.rect(entity.rect).position-Vector2(0,160),WorldLayout.rect(entity.rect).size+Vector2(0,220))
			if expedition.layout.world_data.get("version")==5: site.hit=site.prop.scaled_hit_bounds()
			site.prop.primary_target=expedition.supply.generated.get("objective",{}).get("site_ids",[]).has(def.id)
		site.prop.reward_hint=("货币" if site.kind==&"cash" else "食物")+" +%d"%site.reward+(" / 武器" if site.weapon else "")
		if expedition.exploration_mode():
			site.prop.primary_target=expedition.supply.generated.objective.site_ids.has(def.id)
			site.prop.reward_hint=("货币" if site.kind==&"cash" else "食物")+" +%d"%site.reward
		if expedition._is_event_site(site):
			site.prop.loot_landmark = EventSortieV1.TITLE
			site.prop.reward_hint = "现场二选一"
		if expedition.supply.generated.has("rare_policy"):
			site.prop.loot_landmark = RareSortie.landmark(expedition.supply.generated.type, def.id)
			if site.weapon:
				site.prop.reward_hint = "武器 +1"
		if expedition.build_mode() and site.id==&"cash" and expedition.supply.generated.type=="equipment": site.prop.reward_hint+=" / 道具%d件"%expedition.supply.generated.build.drops.size() if not expedition.supply.generated.build.drops.is_empty() else " / 道具已集齐"
		if expedition.exploration_mode() and not crate:
			var category: String = "果树" if def.source == "fruit_tree" else "车辆" if object_site else "建筑"
			var anchor: Vector2 = Vector2(0, 5) if object_site else Vector2(site.prop.door_offset, 28)
			if not expedition._supply_entrances.is_empty() and site.prop.loot_landmark.is_empty() and site.prop.primary_target and site.kind == &"food":
				site.prop.loot_landmark = "近点食品" if def.id == expedition.supply.generated.objective.site_ids[0] else "追加食品"
			var tool_count: int = expedition._tools_at(String(site.id))
			if tool_count > 0:
				site.prop.loot_landmark = "工具 ×%d" % tool_count
				site.prop.reward_hint += " · 工具 ×%d" % tool_count
			site.prop.configure_loot_badge(category, anchor)
		expedition.sites.append(site)
		if site.id==&"cash": expedition._cash_site=site; expedition._shop=site.prop
		if site.id==&"food": expedition._food_site=site


func _street_supply_entrances() -> Array[Vector2]:
	var doors: Array[Vector2] = []
	var generated: Dictionary = expedition.supply.generated
	var cold_store: bool = generated.has("rare_policy") and generated.type == "supply"
	if expedition.pump_station_mode() or generated.get("mission_policy") != 1 or generated.get("type") != "supply" \
			or (not cold_store and expedition.layout.world_data.get("size") != "medium") or expedition.layout.world_data.get("art_revision") != 3:
		return doors
	var ids: Array = ["food", "food_2"] if cold_store else generated.objective.site_ids
	for identity: String in ids:
		for site: Dictionary in generated.sites:
			if site.id == identity:
				doors.append(TaskActions.site_point(generated, site))
				break
	return doors if doors.size() == 2 and doors[0].is_finite() and doors[1].is_finite() else []
