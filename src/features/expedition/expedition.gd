class_name Expedition
extends Node2D
## Owns one sortie; observed behavior IDs and differences live in the reference table.

signal membership_committed()

signal finished(report: Dictionary)
signal combat_feedback(event: Dictionary)
signal search_completed(reward: int)
signal engine_started
signal pause_changed(paused: bool)
signal help_changed(expanded: bool)
signal threat_changed(state: Dictionary)
signal spawn_resolved(event: Dictionary)
signal growth_input_recorded(event: Dictionary)
signal bus_gather_ordered(state: Dictionary)

enum Phase {
	ACTIVE,
	ENGINE,
	BOARDING,
	FINISHED,
}

const BusTexture: Texture2D = preload("res://assets/candidates/bus_02.png")

var _feedback: ExpeditionFeedback
var _ui: ExpeditionUi
var _orders: ExpeditionOrders = ExpeditionOrders.new(self)
var _squad: ExpeditionSquad = ExpeditionSquad.new(self)

var tuning: ExpeditionTuning = ExpeditionTuning.new()
var navigation: FieldNavigation = FieldNavigation.new()
var shot_obstacles: Array[ShotObstacle] = []
var survivors: Array[FieldActor] = []
var enemies: Array[FieldActor] = []
var phase: Phase = Phase.ACTIVE
var is_paused: bool = false
var suspend_sealed: bool = false
var elapsed: float = 0.0
var loot: int = 0
var food_loot: int = 0
var weapon_loot: Array[Dictionary] = []
var sortie_id: String = "00000000000000000000000000000000:1"
var loadout_snapshot: Array[Dictionary] = []
var kills: int = 0
# The original cash-point API remains available to existing callers.
var searched: bool:
	get:
		return _cash_site.searched
	set(value):
		_cash_site.searched = value
var search_progress: float:
	get:
		return _cash_site.progress
	set(value):
		_cash_site.progress = value
var search_assignments: SearchAssignments = SearchAssignments.new()
var parallel_search: bool = false
# Legacy readers see the first stable task; runtime ownership stays in the registry.
var search_actor: FieldActor:
	get:
		var jobs: Array[Dictionary] = search_assignments.ordered()
		return search_member(int(jobs[0].member_id)) if not jobs.is_empty() else null
var goal: Vector2 = Vector2.ZERO
var initial_cash: int = 53
var initial_food: int = 2
var camp_rules: CampRules = preload("res://src/features/camp/camp_rules.tres")
var supply: MissionSupply = preload("res://src/features/camp/supermarket.tres")
var day: int = 2
var mission_title: String = "旧街补给点"
var starting_health: Array[float] = [200.0, 200.0]
var crew_snapshot: Array[Dictionary] = []
var exploration_props: Dictionary = {}
var _supply_entrances: Array[Vector2] = []
var _objective_cursors: Dictionary = {}
var _locate_marker: Node2D
var _locate_ring: Line2D
var _locate_label: Label
var _locate_tween: Tween
var persona_views: Dictionary = {} # Derived immutable presentation cache; never serialized.
var participants_snapshot: Array[Dictionary] = []
var setup_problem: String = ""
var _setup_crew: Array[Dictionary] = []
var ui_theme: Theme
var battle_survival: bool = false
var battle_seed: String = "NONE"
var drill_panel: BattleDrillPanel
var trait_inputs: TraitInputs = TraitInputs.new()
var field_join_gate: Callable
var field_departure: Dictionary = {}
var field_joins: Array[Dictionary] = []
var field_join_error: String = ""
var growth_binding: Dictionary = {}
var xp_inputs: XpInputs = XpInputs.new()
var rescue_completed: bool = false
var rescue_target: RescueTarget
var threat: ThreatDirector = ThreatDirector.new()
var combat: CombatRuntime=CombatRuntime.new()
var combat_delta: float=0.0
var powers: Dictionary = {}
var power_commit: Callable
var pending_power: Dictionary = {}
var burst_commit: Callable
var pending_burst: Dictionary = {}
var power_frozen: bool = false
var power_panel: PowerSlotPanel
var second_power_panel: PowerSlotPanel
var third_power_panel: PowerSlotPanel
var power_view: PowerEffectView
var basic_support: BasicSupport = BasicSupport.new()
var support_commit: Callable
var support_aiming: bool = false
var pending_support: Dictionary = {}
var support_panel: BasicSupportPanel
var support_aim: BasicSupportAim
var growth_inputs: GrowthInputs = GrowthInputs.new()
var layout: StreetLayout
var _buildings: Array[FieldProp] = []
var camera: FieldCamera
var _sort: Node2D
var _effects: Node2D
var _shop: FieldProp
var _hud: ExpeditionHud
var _night_lighting: NightLighting
var _notice_text: String = ""
var _spawn_clock: float = 0.0
var _ai_clock: float = 0.0
var _engine_clock: float = 0.0
var _spawn_count: int = 0
var _spawn_attempts: int = 0
var last_simulation_usec: int = 0
# Read-only last-step diagnostics, not solver state or a saved decision input.
var last_contact_metrics: Dictionary = {}
var _notice_clock: float = 0.0
var _corpses: Array[FieldActor] = []
var _corpse_times: Array[float] = []
var _readouts: SquadReadouts
var _cash_site: SearchSite = SearchSite.new(&"cash", Vector2.ZERO)
var _food_site: SearchSite = SearchSite.new(&"food", Vector2.ZERO)
var sites: Array[SearchSite] = []
var task_event: Dictionary = TaskActions.empty_event()
var event_sortie_panel: EventSortiePanel
var recon_site: SearchSite
var recon_knowledge: ReconKnowledge
var _recon_view: ReconFieldView
var billboard_site: SearchSite
var billboard_work: BillboardWorkV1
var _billboard_view: BillboardFieldView
var barricade_open: bool = false
var _barricade_view: BarricadeView
var _bus_sprite: Sprite2D
var bus_view: BusJourney
var restoring_world: bool=false
var encounter: EncounterRuntime
var station_art: PumpStationArt
var _active_site: SearchSite:
	get:
		return member_site(search_actor.member_id) if search_actor != null else null


func _ready() -> void:
	_feedback = ExpeditionFeedback.new(self)
	_ui = ExpeditionUi.new(self)
	task_event = TaskActions.empty_event(supply.generated)
	parallel_search = combat_mode()
	_setup_crew.assign(crew_snapshot.duplicate(true) if not crew_snapshot.is_empty() else SurvivorRoster.new_crew())
	if crew_snapshot.is_empty():
		for index: int in range(_setup_crew.size()):
			if index < starting_health.size():
				_setup_crew[index].health = starting_health[index]
	setup_problem = SurvivalContracts.identity_problem(_setup_crew,true)
	if setup_problem.is_empty() and not loadout_snapshot.is_empty():
		setup_problem = WeaponInventory.snapshot_problem(_setup_crew, loadout_snapshot, true,WeaponState.is_family(field_departure))
	if setup_problem.is_empty() and not crew_snapshot.is_empty() and loadout_snapshot.is_empty():
		setup_problem = "正式名册缺少出击配装快照"
	participants_snapshot = SurvivalContracts.participants(_setup_crew, loadout_snapshot, true,true) if setup_problem.is_empty() else []
	if participants_snapshot.is_empty():
		setup_problem = setup_problem if not setup_problem.is_empty() else "没有可行动的参与者"
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	growth_inputs.configure(participants_snapshot)
	xp_inputs.configure(growth_binding)
	if build_mode():
		basic_support.configure(growth_binding, FirstAidV1.enabled(supply.generated),
			BuildAuthority.radio_equipped(supply.generated))
	if power_mode(): powers=SpecialPowers.initial(growth_binding,PowerState.loadout(supply.generated.powers))
	if combat_mode(): combat.setup(self)
	trait_inputs.configure(growth_binding)
	if SurvivalContracts.integer(supply.generated.get("version"), 6, 9):
		tuning.spawn_seconds *= CampaignPressureV1.spawn_factor(supply.generated)
	layout = supply.layout
	_supply_entrances = _street_supply_entrances()
	_cash_site.door = layout.cash_door
	_food_site.door = layout.food_door
	if supply.generated.has("barricade"):
		navigation = BarricadeV1.navigation(supply.generated, false)
	elif exploration_mode() and not pump_station_mode():
		navigation = ExplorationLayout._routing(layout.world_data).nav
	else:
		navigation.configure(layout.blockers(), layout.world_bounds)
	shot_obstacles = layout.shot_obstacles()
	if pump_station_mode():
		var station_ground: PumpStationGround = PumpStationGround.new()
		station_ground.layout = layout
		station_ground.z_index = -10
		add_child(station_ground)
	else:
		var ground: StreetBlock = StreetBlock.new()
		ground.layout = layout
		ground.supply_entrances = _supply_entrances
		ground.food_source_visible = supply.supports(&"food")
		ground.z_index = -10
		add_child(ground)
	_feedback._make_camera()
	_sort = Node2D.new()
	_sort.name = "ActorsAndProps"
	_sort.y_sort_enabled = true
	add_child(_sort)
	_effects = Node2D.new()
	add_child(_effects)
	if supply.generated.has("barricade"):
		_barricade_view = BarricadeView.new()
		_barricade_view.footprint = BarricadeV1.rect(supply.generated)
		_barricade_view.landing = WorldLayout.point(supply.generated.barricade.landing)
		_barricade_view.label_font = ui_theme.default_font if ui_theme != null else null
		_barricade_view.z_index = 1
		add_child(_barricade_view)
	if ReconActionV1.enabled(supply.generated):
		recon_site = SearchSite.new(StringName(ReconActionV1.SITE_ID), ReconActionV1.point(supply.generated))
		recon_site.seconds = ReconActionV1.SECONDS
		recon_knowledge = ReconKnowledge.new(supply.generated)
		_recon_view = ReconFieldView.new()
		_recon_view.world = self
		_recon_view.z_index = 1
		_effects.z_index = 2
		add_child(_recon_view)
	if BillboardActionV1.enabled(supply.generated):
		billboard_site = SearchSite.new(StringName(BillboardActionV1.SITE_ID), BillboardActionV1.point(supply.generated))
		billboard_site.seconds = BillboardActionV1.SECONDS
		billboard_site.hit = BillboardActionV1.hit_rect(billboard_site.door)
		billboard_work = BillboardWorkV1.new()
		_billboard_view = BillboardFieldView.new()
		_billboard_view.position = billboard_site.door
		_billboard_view.label_font = ui_theme.default_font if ui_theme != null else null
		_sort.add_child(_billboard_view)
	var bus: Sprite2D = Sprite2D.new()
	_bus_sprite = bus
	bus.texture = BusTexture
	bus.offset = Vector2(0, -128)
	bus.scale = Vector2.ONE * (240.0 / 448.0)
	bus.position = layout.bus_foot()
	_sort.add_child(bus)
	if pump_station_mode():
		_make_pump_station()
	elif not layout.world_data.is_empty():
		_make_world_buildings()
	else:
		_shop = _make_building(layout.cash_block,layout.cash_title,FieldProp.ShopTexture,false,false)
		_shop.searchable = supply.supports(&"cash")
		_shop.reward_hint = ("货币 +%d" % supply.cash_reward)+(" / 武器" if supply.has_weapon_sample else "")
		_cash_site.prop = _shop
		var second: FieldProp = _make_building(layout.food_block,layout.food_title,
			preload("res://assets/m401/market.png") if supply.supports(&"food") else preload("res://assets/m402/rowhouse.png"),supply.supports(&"food"),not supply.supports(&"food"))
		second.searchable = supply.supports(&"food")
		second.reward_hint = "食物 +%d" % supply.food_reward
		_food_site.prop = second
		for block: Rect2 in layout.residences:
			_make_building(block,"柳巷住宅",preload("res://assets/m402/rowhouse.png"),false,true)
		sites.assign([_cash_site,_food_site])
	for block: Rect2 in ([] if layout.world_data.get("version")==5 else layout.fences):
		var fence: StreetFence = StreetFence.new()
		fence.footprint = block
		fence.position = Vector2(block.position.x,block.end.y)
		_sort.add_child(fence)
	for index: int in range(participants_snapshot.size()):
		var participant: Dictionary = participants_snapshot[index]
		var profile: Dictionary = SurvivorRoster.member(_setup_crew, int(participant.id))
		var start: Vector2 = _arrival(index)
		if not setup_problem.is_empty():
			set_physics_process(false)
			set_process_unhandled_input(false)
			return
		var actor: FieldActor = _make_actor(false, index, start, profile)
		actor.health = float(participant.health_before)
		actor.call_sign = profile.call_sign
		var item: Dictionary = {}
		for entry: Dictionary in loadout_snapshot:
			if int(entry.member_id) == actor.member_id:
				item = entry.instance
		if item.is_empty():
			# Standalone scenes have no campaign inventory; retain their old views.
			actor.weapon_definition = WeaponInventory.Definitions[1 if actor.definition_id == &"crew_2" else 0].duplicate() as WeaponDefinition
		else:
			actor.weapon_instance_id = item.instance_id
			actor.weapon_definition = WeaponModifiers.combat_definition(item)
		actor.visual.set_weapon(actor.weapon_definition.presentation)
		if combat_mode() and CombatRuntime.patterned(String(actor.weapon_definition.id)): combat.action(actor)
		if (supply.generated.get("version")==5 or (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9)))):
			if not CombatEquipment.melee(String(actor.weapon_definition.id)):
				actor.magazine = WeaponMagazine.new(actor.weapon_instance_id, String(actor.weapon_definition.id),
					WorkshopV1.mod_for(field_departure, actor.weapon_instance_id))
		if build_mode(): apply_build(actor)
		survivors.append(actor)
	if recon_knowledge != null and not restoring_world:
		recon_knowledge.reveal(layout.bus_door)
		_update_recon_knowledge()
	if (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9))):
		encounter=EncounterRuntime.new();encounter.setup(self,restoring_world)
	_make_ui()
	var readout_layer: CanvasLayer = CanvasLayer.new()
	readout_layer.layer = 5
	add_child(readout_layer)
	if supply.id == &"rescue" and not rescue_completed:
		rescue_target = RescueTarget.new()
		rescue_target.world = self
		add_child(rescue_target)
	if not field_joins.is_empty() and rescue_target != null:
		promote_target(field_joins[0],true)
	_readouts = SquadReadouts.new()
	readout_layer.add_child(_readouts)
	_spawn_clock = tuning.spawn_seconds
	threat.update(elapsed, tuning.daylight_seconds, tuning.spawn_seconds)
	if recon_site != null:
		_show_notice("主装备点待发现 · 可沿街探索或先到侦察点。")
	else:
		_show_notice(layout.route_hint if _supply_entrances.is_empty() else
			"先搜近点食品 · 可回巴士撤离，也可沿街追加第二处。")
	if not layout.world_data.is_empty():
		bus_view = BusJourney.new()
		bus_view.configure(self,_bus_sprite,layout.world_data.bus)
		add_child(bus_view)
	_night_lighting = NightLighting.new()
	add_child(_night_lighting)
	print("BH_SORTIE start day=%d members=%d" % [day, survivors.size()])


func _process(delta: float) -> void:
	if phase == Phase.FINISHED and bus_view != null and bus_view.running():
		bus_view.advance(delta)
		_feedback._refresh_night_lighting()


func _physics_process(delta: float) -> void:
	step(delta)


func _draw() -> void:
	_feedback._draw()


func _unhandled_input(event: InputEvent) -> void:
	_orders._unhandled_input(event)


func step(delta: float) -> void:
	if power_mode() and not is_paused and not suspend_sealed and phase!=Phase.FINISHED and not (bus_view!=null and bus_view.running()):
		var remaining: float=SpecialPowers.remaining(powers,elapsed)
		if remaining>0.0 and delta>remaining:
			step(remaining)
			step(delta-remaining)
			return
	refresh_power_factors()
	combat_delta=delta
	if bus_view != null and bus_view.running():
		if not is_paused: bus_view.advance(delta)
		_update_ui()
		return
	if phase == Phase.FINISHED or is_paused or suspend_sealed:
		_update_ui()
		return
	if combat.burst != null and combat.burst.state.phase == "confirming":
		accept_burst(support_world())
		return
	if combat_mode() and not combat.toxic.pending.is_empty():
		combat.advance_toxic(self,0.0)
		if is_paused: return
	var started_usec: int = Time.get_ticks_usec()
	elapsed += delta
	if build_mode():
		basic_support.advance(delta,true)
		if support_aim!=null: support_aim.advance(delta,true)
	_notice_clock = maxf(0.0, _notice_clock - delta)
	if threat.update(elapsed, tuning.daylight_seconds, tuning.spawn_seconds):
		# Tighten the next deadline, without owing any historical spawns.
		if is_finite(_spawn_clock):
			_spawn_clock = minf(_spawn_clock, threat.interval)
		var state: Dictionary = threat_status()
		threat_changed.emit(state)
		_show_notice("%s · 增援更密集；仍可发动巴士集合撤离。" % state.label)
	_spawn_clock -= delta
	_ai_clock -= delta
	if _spawn_clock <= 0.0:
		if enemies.size() < threat.rules.enemy_cap:
			_spawn_enemy()
		else:
			_record_spawn(&"capacity", Vector2.INF)
		# No while-loop or accumulated debt, including when full or all points are visible.
		_spawn_clock = threat.interval
	if _ai_clock <= 0.0:
		if not power_frozen: _update_enemy_paths()
		_ai_clock = 0.7
	var working_before: Dictionary={}
	for actor: FieldActor in survivors:working_before[actor.member_id]=actor.activity in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]
	var occupants: Array[FieldActor] = survivors + enemies
	var previous: Dictionary = {}
	for actor: FieldActor in occupants: previous[actor] = actor.position
	for actor: FieldActor in survivors:
		actor.advance(delta,false,false)
	last_contact_metrics = FieldContacts.move(survivors,occupants,navigation,delta,true)
	if recon_knowledge != null:
		_update_recon_knowledge()
	_update_enemy_behaviors(delta)
	_update_enemy_paths(true)
	for enemy: FieldActor in enemies:
		enemy.advance(0.0 if power_frozen else delta,false,false)
	var enemy_motion: Dictionary = FieldContacts.move(enemies,occupants,navigation,0.0 if power_frozen else delta,false,_hold_enemy_approach)
	last_contact_metrics.enemy_substeps = enemy_motion.substeps
	last_contact_metrics.motion_deviation_max = maxf(last_contact_metrics.motion_deviation_max,enemy_motion.motion_deviation_max)
	for actor: FieldActor in occupants:
		if power_frozen and actor.enemy_behavior != null and actor.enemy_behavior.kind == NightHoundV1.KIND:
			continue
		actor.present_motion(delta,previous[actor])
	for index: int in range(_corpses.size() - 1, -1, -1):
		_corpses[index].advance(delta)
		_corpse_times[index] -= delta
		if _corpse_times[index] <= 0.0:
			_corpses[index].queue_free()
			_corpses.remove_at(index)
			_corpse_times.remove_at(index)
	if rescue_target != null:
		rescue_target.step(delta)
		if is_paused:
			_update_ui()
			return
	_update_search(delta)
	if is_paused:
		_update_ui()
		return
	# Neither entry into nor completion of work consumes a whole reload delta.
	for actor: FieldActor in survivors:
		if actor.magazine!=null and not working_before.get(actor.member_id,false) and actor.activity not in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]:actor.magazine.advance(delta)
	_update_enemy_behaviors(0.0)
	_update_combat()
	if combat_mode(): combat.cancel_unavailable(self)
	if combat_mode() and not is_paused: combat.advance_toxic(self,delta)
	# Resolve after the original attacks so a lethal hit on the last windup frame wins.
	if combat.screamer != null and not is_paused and living_count() > 0:
		combat.screamer.advance(self, delta)
	if combat.burst != null and not is_paused and living_count() > 0:
		combat.burst.advance(self, delta)
	if combat_mode():
		for actor: FieldActor in survivors: combat.present(actor)
	if encounter!=null and not is_paused:
		if power_frozen: encounter.observe_frozen_health()
		else: encounter.advance(delta)
	if is_paused:
		_update_ui()
		return
	request_first_aid()
	if is_paused:
		return
	if living_count() == 0:
		_finish(false)
	elif phase == Phase.BOARDING:
		var boarding: Dictionary = boarding_status()
		if boarding.arrived == boarding.required and not _rescue_waiting_for_bus():
			_finish(true, Vector2i(boarding.arrived, boarding.required))
	elif phase == Phase.ENGINE:
		_engine_clock -= delta
		if _engine_clock <= 0.0:
			phase = Phase.BOARDING
			_show_notice("引擎已发动 · 点击「集合至巴士」，或左键黄色区域。")
	refresh_power_factors()
	_update_ui()
	queue_redraw()
	last_simulation_usec = Time.get_ticks_usec() - started_usec


func candidate_id() -> int:
	return _orders.candidate_id()


func join_target(at_ms: int) -> bool:
	return _orders.join_target(at_ms)


func promote_target(event: Dictionary, restoring: bool = false) -> void:
	_orders.promote_target(event, restoring)


func toggle_pause() -> void:
	_orders.toggle_pause()


func command_move(point: Vector2) -> void:
	_orders.command_move(point)


func request_search(kind: StringName = &"cash") -> void:
	_orders.request_search(kind)


func _assign_search(site: SearchSite, actor: FieldActor, path: PackedVector2Array) -> bool:
	return _orders._assign_search(site, actor, path)


func _is_event_site(site: SearchSite) -> bool:
	return _squad._is_event_site(site)


func _near_event_worker(site: SearchSite) -> FieldActor:
	return _squad._near_event_worker(site)


func confirm_event_choice(branch: String) -> bool:
	return _squad.confirm_event_choice(branch)


func has_search_job(member_id: int) -> bool:
	return _squad.has_search_job(member_id)


func search_member(member_id: int) -> FieldActor:
	return _squad.search_member(member_id)


func member_site(member_id: int) -> SearchSite:
	return _squad.member_site(member_id)


func site_label(site: SearchSite) -> String:
	return _squad.site_label(site)


func _toolbox_site() -> SearchSite:
	return _squad._toolbox_site()


func search_site(kind: StringName) -> SearchSite:
	return _squad.search_site(kind)


func request_extraction() -> void:
	if bus_view != null and bus_view.running(): return
	if not field_join_error.is_empty():
		return
	if phase != Phase.ACTIVE:
		return
	if elapsed < tuning.bus_ready_seconds:
		_show_notice("巴士仍在准备，请稍候。")
		return
	phase = Phase.ENGINE
	_engine_clock = tuning.engine_seconds
	engine_started.emit()
	_show_notice("引擎发动中 · 队伍仍可移动，请前往巴士旁集合。")


func request_bus_action() -> void:
	if phase == Phase.BOARDING:
		request_bus_gather()
	else:
		request_extraction()


func boarding_status(with_feedback: bool = false) -> Dictionary:
	var required: int = 0
	var arrived: int = 0
	var working: int = 0
	var ordered: bool = goal == layout.bus_door
	var waiting: Array[Dictionary] = []
	for actor: FieldActor in survivors:
		if actor.activity == FieldActor.Activity.DOWN:
			continue
		required += 1
		var search_phase: String = search_assignments.phase_for(actor.member_id)
		if not search_phase.is_empty():
			working += 1
		elif actor.position.distance_to(layout.bus_door) <= tuning.boarding_radius:
			arrived += 1
			continue
		if with_feedback:
			var activity: String = "pending"
			if search_phase == "approach":
				activity = "approaching_search"
			elif search_phase == "working":
				activity = "recovering" if actor.activity == FieldActor.Activity.RECOVERING else "searching"
			elif ordered and actor.activity == FieldActor.Activity.MOVING and not actor.path.is_empty():
				if actor.path[-1].distance_to(layout.bus_door) <= tuning.boarding_radius:
					activity = "gathering"
			waiting.append({"id":actor.member_id, "call_sign":actor.call_sign, "activity":activity})
	var status: Dictionary = {"arrived":arrived, "required":required, "working":working, "ordered":ordered}
	if with_feedback:
		status["waiting"] = waiting
		status["rescue_waiting"] = _rescue_waiting_for_bus()
	return status


func _rescue_waiting_for_bus() -> bool:
	return rescue_target != null and rescue_target.status == "RESCUED" and not rescue_target.delivered()


func request_bus_gather() -> void:
	if not field_join_error.is_empty():
		return
	if phase != Phase.BOARDING or living_count() == 0:
		return
	# Validate the same formation destinations before acknowledging the whole order.
	# Hidden workers will use their entrance and the latest goal when work completes.
	for actor: FieldActor in survivors:
		if actor.activity == FieldActor.Activity.DOWN:
			continue
		var start: Vector2 = member_site(actor.member_id).door if has_search_job(actor.member_id) else actor.position
		var path: PackedVector2Array = navigation.path_between(start, layout.bus_door + _group_offset(actor))
		if path.is_empty() or path[-1].distance_to(layout.bus_door) > tuning.boarding_radius:
			_show_notice("无法到达巴士集合区 · 请检查当前路线。")
			return
	# An unconfirmed visit must not hold a worker back from gathering.
	if event_sortie_panel != null:
		event_sortie_panel.hide()
		if task_event.branch == "":
			var approaching: int = search_assignments.member_for(EventSortieV1.site_id(supply.generated))
			if approaching > 0:
				_release_searcher(approaching)
	# Gathering also releases assistance when the previous group goal was already the bus.
	if rescue_target != null: rescue_target.cancel()
	if goal != layout.bus_door:
		command_move(layout.bus_door)
	var boarding: Dictionary = boarding_status()
	_show_notice("已下令集合 · 搜集中的队员完成后归队。" if boarding.working > 0 else "已下令集合 · 队员正前往巴士。")
	_update_ui()
	bus_gather_ordered.emit(boarding)


func time_status() -> Dictionary:
	return {
		"sortie_seconds": maxi(0, ceili(tuning.daylight_seconds - elapsed)),
		"sortie_fraction": clampf(1.0 - elapsed / maxf(tuning.daylight_seconds, 0.001), 0.0, 1.0),
		"bus_seconds": maxi(0, ceili(tuning.bus_ready_seconds - elapsed)),
		"engine_seconds": maxi(0, ceili(_engine_clock)),
	}


func living_count() -> int:
	var count: int = 0
	for actor: FieldActor in survivors:
		if actor.activity != FieldActor.Activity.DOWN:
			count += 1
	return count


func _move_to_group_goal(actor: FieldActor) -> void:
	_orders._move_to_group_goal(actor)


func _group_offset(actor: FieldActor) -> Vector2:
	return _orders._group_offset(actor)


func _arrival(index: int) -> Vector2:
	return _squad._arrival(index)


func _release_searcher(member_id: int = 0) -> void:
	_squad._release_searcher(member_id)


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
		actor.visual_contact = _visual_contact.bind(actor)
	actor.speed = tuning.enemy_speed if enemy else tuning.survivor_speed
	actor.motion_locked=power_frozen if enemy else false
	actor.max_health = tuning.enemy_health if enemy else tuning.survivor_health
	if not enemy and not profile.is_empty():
		actor.max_health = GrowthRules.maximum(profile)
	actor.health = actor.max_health
	if enemy:
		actor.enemy_behavior = EnemyBehavior.new()
		actor.enemy_behavior.kind = kind if not kind.is_empty() else EnemyRules.NORMAL if index>=10000 else combat.pick_spawn(self,index) if combat_mode() else EnemyRules.pick(sortie_id,index,int(threat.stage))
		actor.enemy_behavior.spawn_stage = int(threat.stage)
		if combat_mode() and actor.enemy_behavior.kind==CombatEnemyRules.TOXIC: combat.toxic.casters[str(index)]=ToxicV1._caster(index)
		actor.enemy_theme = ui_theme
		actor.max_health = EnemyRules.health(actor.enemy_behavior.kind,tuning.enemy_health)
		actor.health = actor.max_health
		actor.speed = EnemyRules.speed(actor.enemy_behavior.kind,false,tuning.enemy_speed)
	if not enemy and not profile.is_empty():
		TraitRules.apply(actor,profile,tuning.survivor_speed)
	actor.position = point
	_sort.add_child(actor)
	return actor


func _visual_contact(enemy: FieldActor) -> Vector2:
	# Read-only display query; never chooses or changes the combat target/path.
	var nearest: Vector2 = Vector2.INF
	var distance: float = 50.0
	for actor: FieldActor in survivors:
		if actor.health <= 0.0 or not actor.visible or actor.activity == FieldActor.Activity.SEARCHING:
			continue
		var offset: Vector2 = actor.position - enemy.position
		if offset.length() < distance:
			distance = offset.length()
			nearest = offset
	return nearest


func _spawn_enemy(forced_kind: String = "", pressure_point: Vector2 = Vector2.INF, provenance: Dictionary = {}) -> Dictionary:
	var point: Vector2 = _safe_spawn_point(pressure_point)
	if not point.is_finite():
		_record_spawn(&"no_safe_point", point, -1, provenance)
		return {"reason":"no_safe_point","enemy_id":-1}
	var enemy: FieldActor = _make_actor(true, _spawn_count, point,{},forced_kind)
	enemies.append(enemy)
	_spawn_count += 1
	if combat.screamer != null and enemy.enemy_behavior.kind == ScreamerPolicyV1.KIND:
		combat.screamer.spawned(self, enemy)
	if combat.burst != null and enemy.enemy_behavior.kind == BurstRuntimeV1.KIND:
		combat.burst.spawned(self, enemy)
	_record_spawn(&"spawned", point, enemy.actor_id, provenance)

	return {"reason":"spawned","enemy_id":enemy.actor_id}


func _spawn_screamer_batch(event: Dictionary) -> void:
	# Insert the whole batch before notifying listeners. It never modifies the ambient clock.
	for row: Dictionary in event.spawned:
		var point: Vector2 = SortieSnapshot._vec(row.point)
		var enemy: FieldActor = _make_actor(true, int(row.enemy_id), point, {}, EnemyRules.NORMAL)
		enemies.append(enemy)
	_spawn_count += event.spawned.size()
	_spawn_attempts += event.spawned.size()
	for row: Dictionary in event.spawned:
		_record_spawn(&"spawned", SortieSnapshot._vec(row.point), int(row.enemy_id),
			{"source":"screamer", "source_id":event.source_id, "event_id":event.event_id, "entrance":row.entrance}, false)


func visible_world_rect() -> Rect2:
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var corner: Vector2 = inverse * Vector2.ZERO
	return Rect2(corner, inverse * get_viewport_rect().size - corner)


func threat_status() -> Dictionary:
	var state: Dictionary = threat.snapshot()
	state.merge({"enabled":true, "elapsed":elapsed, "spawned":_spawn_count,
		"attempts":_spawn_attempts, "next_spawn":_spawn_clock, "active_enemies":enemies.size(),
		"cap":threat.rules.enemy_cap,
		"overtime":maxf(0.0,elapsed - tuning.daylight_seconds)})
	return state


func _safe_spawn_point(pressure_point: Vector2 = Vector2.INF) -> Vector2:
	var candidates: Array[Vector2] = []
	for index: int in range(layout.enemy_points.size()):
		candidates.append(layout.enemy_points[(_spawn_attempts + index) % layout.enemy_points.size()])
	var bounds: Rect2 = layout.world_bounds.grow(-ThreatRules.EDGE_MARGIN)
	for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		candidates.append(Vector2(lerpf(bounds.position.x, bounds.end.x, fraction), bounds.position.y))
		candidates.append(Vector2(lerpf(bounds.position.x, bounds.end.x, fraction), bounds.end.y))
		candidates.append(Vector2(bounds.position.x, lerpf(bounds.position.y, bounds.end.y, fraction)))
		candidates.append(Vector2(bounds.end.x, lerpf(bounds.position.y, bounds.end.y, fraction)))
	if pressure_point.is_finite():
		candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool:return a.distance_squared_to(pressure_point)<b.distance_squared_to(pressure_point))
	var visible: Rect2 = visible_world_rect().grow(threat.rules.screen_margin)
	var occupied: Array[Vector2] = []
	for enemy: FieldActor in enemies:
		occupied.append(enemy.position)
	for point: Vector2 in candidates:
		if pressure_point.is_finite() and point.distance_to(pressure_point)<threat.rules.party_distance:
			continue
		var nearest: FieldActor = _nearest_target_from_point(point)
		if nearest != null and threat.rules.spawn_point_legal(point, visible, navigation, nearest.position, occupied):
			return point
	return Vector2.INF


func _nearest_target_from_point(point: Vector2) -> FieldActor:
	var nearest: FieldActor
	var distance: float = INF
	for actor: FieldActor in survivors:
		if actor.activity in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING]:
			continue
		var candidate: float = point.distance_squared_to(actor.position)
		if candidate < distance:
			distance = candidate
			nearest = actor
	return nearest


func _record_spawn(reason: StringName, point: Vector2, enemy_id: int = -1,
		provenance: Dictionary = {}, count_attempt: bool = true) -> void:
	_spawn_attempts += int(count_attempt)
	var event: Dictionary = threat_status()
	var party_points: Array[Vector2] = []
	var enemy_points: Array[Vector2] = []
	for actor: FieldActor in survivors:
		if actor.activity not in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING]:
			party_points.append(actor.position)
	for enemy: FieldActor in enemies:
		if enemy.actor_id != enemy_id:
			enemy_points.append(enemy.position)
	event.merge({"reason":String(reason), "enemy_id":enemy_id,
		"point":[point.x, point.y] if point.is_finite() else [],
		"visible_rect":visible_world_rect(), "party_points":party_points, "enemy_points":enemy_points,
		"legal":navigation.is_clear(point) if point.is_finite() else false})
	if enemy_id>=0:
		for actor: FieldActor in enemies:
			if actor.actor_id==enemy_id:
				event.enemy_type = actor.enemy_behavior.kind
				event.enemy_health = actor.health
				event.enemy_speed = actor.speed
	event.merge(provenance, true)
	spawn_resolved.emit(event)


func _update_enemy_paths(idle_only: bool = false) -> void:
	if power_frozen: return
	for enemy: FieldActor in enemies:
		if (combat_mode() and combat.holds(enemy)) or (encounter!=null and encounter.holds(enemy)) or (enemy.enemy_behavior!=null and enemy.enemy_behavior.state=="windup"):
			continue
		var target: FieldActor = _nearest_target(enemy, survivors, INF)
		if target == null or _hold_enemy_approach(enemy):
			enemy.clear_order()
		elif not idle_only or (enemy.activity == FieldActor.Activity.IDLE and enemy.position.distance_to(target.position)>FieldContacts.RECHASE):
			enemy.command_path(navigation.path_between(enemy.position, target.position))


func _hold_enemy_approach(enemy: FieldActor) -> bool:
	var target: FieldActor = _nearest_target(enemy,survivors,FieldContacts.APPROACH)
	if target != null and navigation._segment_is_clear(enemy.position,target.position):
		enemy.clear_order()
		return true
	return false


func _nearest_target(actor: FieldActor, candidates: Array[FieldActor], limit: float) -> FieldActor:
	var closest: float = limit * limit
	var result: FieldActor
	for candidate: FieldActor in candidates:
		if candidate.health <= 0.0 or not candidate.visible or candidate.activity in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING]:
			continue
		var distance: float = actor.position.distance_squared_to(candidate.position)
		if distance < closest or (result != null and distance == closest and FieldContacts.identity(candidate)<FieldContacts.identity(result)):
			closest = distance
			result = candidate
	return result


func _update_combat() -> void:
	for actor: FieldActor in survivors:
		if combat_mode() and CombatRuntime.patterned(String(actor.weapon_definition.id)):
			combat.attack(self,actor,combat_delta)
			if is_paused: return
			continue
		if actor.activity in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING, FieldActor.Activity.RECOVERING]:
			continue
		if actor.magazine!=null and not actor.magazine.can_fire():continue
		var target: FieldActor = _attack_target(actor)
		if target != null:
			actor.aim = target.position - actor.position
			var decision: AttackRules.Decision = evaluate_attack(actor, target)
			if decision.can_fire:
				_fire_ranged(actor, target, decision)
				if is_paused:
					return
		else:
			actor.aim = Vector2.ZERO
	for enemy: FieldActor in enemies:
		if power_frozen or enemy.activity == FieldActor.Activity.DOWN or (encounter!=null and encounter.is_boss(enemy)):
			continue
		if combat_mode() and combat.holds(enemy): continue
		var target: FieldActor = _nearest_target(enemy, survivors, 28.0)
		var damage: float = tuning.enemy_damage
		var behavior: EnemyBehavior = enemy.enemy_behavior
		if behavior != null and behavior.kind == BurstRuntimeV1.KIND and combat.burst != null and combat.burst.state.phase != "released":
			continue
		if behavior!=null and behavior.kind==EnemyRules.RUSH and target!=null and not behavior.legal(self,enemy,target,EnemyRules.POLICY.melee_range):
			target = null
		var hound: bool = behavior != null and behavior.kind == NightHoundV1.KIND
		var timed_attack: bool = hound or (behavior != null and behavior.kind == EnemyRules.HEAVY)
		if timed_attack:
			if behavior.state=="windup":
				if hound and behavior.windup_remaining > 0.0:
					continue
				target = behavior.locked_target(self)
				if target==null or not behavior.legal(self,enemy,target,EnemyRules.POLICY.melee_range):
					behavior.cancel(self,enemy,true)
					continue
				if behavior.windup_remaining>0.0:
					continue
			elif target!=null and enemy.cooldown<=0.0 and behavior.legal(self,enemy,target,EnemyRules.POLICY.melee_range):
				behavior.arm(self,enemy,target)
				continue
			else:
				continue
			damage = NightHoundV1.DAMAGE if hound else EnemyRules.POLICY.heavy_damage
		if target != null and enemy.cooldown <= 0.0:
			if behavior != null:
				damage = CombatRuntime.direct_melee_damage(behavior.kind, damage, powers, elapsed)
			var direction: Vector2 = (target.position - enemy.position).normalized()
			var health_before: float = target.health
			if not target.take_damage(damage, direction):
				if target.damage_gate.is_valid() and not is_paused:
					_show_notice("保存确认未完成：已暂停，生命与攻击未应用。排除写入故障后继续重试。")
					toggle_pause()
				return
			if battle_survival and target.health == 0:
				_show_notice("%02d %s 已阵亡 · 战斗死亡已持久确认" % [target.member_id,target.call_sign])
			_clear_dead_worker()
			enemy.cooldown = behavior.attack_interval(tuning.enemy_interval) if hound else tuning.enemy_interval
			if timed_attack:
				behavior.reset(enemy,tuning.enemy_speed)
			enemy.visual.show_attack(direction)
			_hit_effect(target.position, damage, true)
			var feedback: Dictionary = {"kind": "hit", "actor": target.actor_id, "member_id":target.member_id, "health": target.health,
				"applied_damage": health_before - target.health, "elapsed": elapsed}
			feedback.merge({"enemy_id":enemy.actor_id,"enemy_type":behavior.kind})
			combat_feedback.emit(feedback)
	_update_enemy_behaviors(0.0)
	_reap_defeated_enemies()


func _update_enemy_behaviors(delta: float) -> void:
	if power_frozen:
		return
	for enemy: FieldActor in enemies:
		if enemy.enemy_behavior!=null and not (encounter!=null and encounter.is_boss(enemy)):
			enemy.enemy_behavior.update(self,enemy,delta)
			enemy.sync_enemy_visual()


func _reap_defeated_enemies() -> void:
	for index: int in range(enemies.size() - 1, -1, -1):
		if enemies[index].activity == FieldActor.Activity.DOWN:
			if combat.screamer != null:
				combat.screamer.removed(self, enemies[index].actor_id)
			if combat.burst != null:
				combat.burst.removed(self, enemies[index].actor_id)
			if enemies[index].enemy_behavior!=null:
				enemies[index].enemy_behavior.cancel(self,enemies[index])
			_corpses.append(enemies[index])
			_corpse_times.append(0.95)
			combat_feedback.emit({"kind": "defeat", "actor": enemies[index].actor_id, "elapsed": elapsed})
			enemies.remove_at(index)


func evaluate_attack(actor: FieldActor, target: FieldActor) -> AttackRules.Decision:
	return AttackRules.evaluate(_combatant(actor), _combatant(target),
		actor.position + actor.visual.aimed_shot_offset(target.position - actor.position),
		actor.weapon_definition.shot_range, actor.cooldown, shot_obstacles)


func _fire_ranged(actor: FieldActor, target: FieldActor, decision: AttackRules.Decision) -> void:
	var weapon: WeaponDefinition = actor.weapon_definition
	var secondary: FieldActor
	var impact: Vector2 = Vector2.INF
	var closest: float = INF
	if weapon.combat_affix == WeaponModifiers.PIERCE:
		for candidate: FieldActor in enemies:
			if candidate.actor_id == target.actor_id:
				continue
			var hit: Vector2 = AttackRules.pierce_hit(decision, actor.position, _combatant(candidate),
				weapon.shot_range, shot_obstacles)
			if not hit.is_finite():
				continue
			var distance: float = decision.hit_to.distance_squared_to(hit)
			if distance < closest or (distance == closest and secondary != null and candidate.actor_id < secondary.actor_id):
				secondary = candidate
				impact = hit
				closest = distance
	var secondary_damage: float = weapon.damage * AttackRules.PIERCE_DAMAGE_FACTOR
	var fatal: int = int(target.health <= weapon.damage)
	if secondary != null and secondary.health <= secondary_damage:
		fatal += 1
	# Reserve room for both defeat facts before the first hit can change HP.
	if not xp_inputs.has_capacity() or xp_inputs.events.size() + fatal > GrowthRules.MAX_EVENTS:
		_reap_defeated_enemies()
		_show_notice("成长账本达到安全容量，已暂停；不能丢弃事件或虚报保存成功。")
		toggle_pause()
		return
	if (not _ranged_hit_recordable(actor, target, weapon.damage)
			or (secondary != null and not _ranged_hit_recordable(actor, secondary, secondary_damage))):
		_show_notice("成长来源不可提交，已暂停；生命、弹量与开火均未应用。")
		toggle_pause()
		return
	var recorded: Array[Dictionary] = []
	var cooldown_before: float = actor.cooldown
	var health_before: float = target.health
	if not _commit_ranged_hit(actor, target, weapon.damage, recorded):
		return
	var extra: Dictionary = {}
	if secondary != null:
		var secondary_before: float = secondary.health
		if _commit_ranged_hit(actor, secondary, secondary_damage, recorded):
			extra = {"target": secondary.actor_id, "target_health": secondary.health,
				"damage": secondary_damage, "applied_damage": secondary_before - secondary.health,
				"to": secondary.position, "hit_to": impact}
		elif is_paused:
			return
	actor.cooldown = weapon.shot_interval(actor.trait_shot_factor)
	var refunded: int = 0
	if actor.magazine != null:
		refunded = actor.magazine.commit_shot(weapon.combat_affix == WeaponModifiers.REFUND
			and target.activity == FieldActor.Activity.DOWN)
	for receipt: Dictionary in recorded:
		growth_input_recorded.emit(receipt)
	actor.visual.show_fire(actor.aim)
	var muzzle: Vector2 = actor.position + actor.visual.muzzle_offset(actor.aim)
	_feedback._shot_effect(muzzle, target.position, weapon.damage)
	if not extra.is_empty():
		_shot_trace(decision.hit_to, impact, Color("a5dfce"))
		_feedback._draw_hit_effect(secondary.position, float(extra.applied_damage), false, "穿透 ")
	if refunded > 0:
		_combat_popup(actor.position + Vector2(12, -136), "击倒补弹 +%d" % refunded, Color("a5dfce"))
	var feedback: Dictionary = {"kind": "shot", "actor": actor.actor_id,
		"target": target.actor_id, "target_health": target.health,
		"damage": weapon.damage, "from": actor.position, "to": target.position,
		"instance_id":actor.weapon_instance_id, "weapon_id":String(weapon.id), "interval":actor.cooldown,
		"applied_damage": health_before - target.health,
		"magazine":actor.magazine.snapshot() if actor.magazine!=null else {},"member_id":actor.member_id,"shot_from":muzzle,"hit_to":decision.hit_to,
		"foot_distance":decision.distance,"shot_range":weapon.shot_range,
		"blocker_id":String(decision.blocker_id),"attack_reason":String(decision.reason),
		"predicted_muzzle_error":muzzle.distance_to(decision.shot_from),
		"cooldown_before":cooldown_before,"cooldown_after":actor.cooldown,
		"moving": actor.activity == FieldActor.Activity.MOVING, "elapsed": elapsed,
		"weapon": String(actor.visual.weapon_view.id), "row": actor.visual.direction_row,
		"facing": actor.visual.presentation_state()["facing"]}
	if not weapon.combat_affix.is_empty():
		feedback.merge({"affix": weapon.combat_affix, "secondary": extra, "rounds_refunded": refunded})
	combat_feedback.emit(feedback)


func _ranged_hit_recordable(actor: FieldActor, target: FieldActor, damage: float) -> bool:
	return target.health > damage or (growth_inputs.can_record(actor, target, elapsed)
		and xp_inputs.can_record(self, actor, target))


func _commit_ranged_hit(actor: FieldActor, target: FieldActor, damage: float, recorded: Array[Dictionary]) -> bool:
	if not target.take_damage(damage, actor.position.direction_to(target.position)):
		return false
	if target.activity == FieldActor.Activity.DOWN:
		kills += 1
		actor.confirmed_kills += 1
		if not loadout_snapshot.is_empty():
			var receipt: Dictionary = growth_inputs.accept_defeat(actor, target, elapsed)
			if not receipt.is_empty():
				if not xp_inputs.accept(self, actor, target, receipt):
					_show_notice("成长来源校验失败，已暂停；本次不会伪造经验。")
					toggle_pause()
					return false
				recorded.append(receipt)
			if encounter != null:
				encounter.record_defeat(target, receipt)
	return true


func _combatant(actor: FieldActor) -> AttackRules.Combatant:
	return AttackRules.Combatant.new(actor.position, actor.health > 0.0,
		actor.visible and actor.activity not in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING], actor.is_enemy)


func _attack_target(actor: FieldActor) -> FieldActor:
	var closest: float = INF
	var result: FieldActor
	for candidate: FieldActor in enemies:
		var decision: AttackRules.Decision = evaluate_attack(actor, candidate)
		if decision.targetable and decision.distance < closest:
			closest = decision.distance
			result = candidate
	return result


func work_state_matches(actor: FieldActor, site: SearchSite) -> bool:
	return _squad.work_state_matches(actor, site)


func _clear_dead_worker() -> void:
	_squad._clear_dead_worker()


func _update_search(delta: float) -> void:
	_squad._update_search(delta)


func _complete_search(actor: FieldActor, site: SearchSite) -> bool:
	return _squad._complete_search(actor, site)


func _finish(evacuated: bool, boarding: Vector2i = Vector2i.ZERO) -> void:
	if phase == Phase.FINISHED:
		return
	FreezeProfile.start({"day":day,"size":layout.world_data.get("size","legacy"),"buildings":_buildings.size(),"sites":sites.size(),"survivors":survivors.size(),"enemies":enemies.size(),"elapsed":elapsed})
	var profile_report: int = FreezeProfile.enter("report.build")
	phase = Phase.FINISHED
	if combat.screamer != null and combat.screamer.state.phase == "windup":
		ScreamerRuntimeV1.cancel(combat.screamer.state, int(combat.screamer.state.actor_id))
		combat.screamer.present(self)
	for enemy: FieldActor in enemies:
		if enemy.enemy_behavior!=null:
			enemy.enemy_behavior.cancel(self,enemy)
			enemy.sync_enemy_visual()
	set_physics_process(false)
	set_process_unhandled_input(false)
	_effects.process_mode = Node.PROCESS_MODE_DISABLED
	if bus_view != null:
		bus_view.final_boarding = boarding
	_hud.hide_screen()
	_readouts.hide()
	_feedback._stop_camera()
	var remaining_health: Array[float] = []
	var member_records: Array[Dictionary] = []
	var member_results: Array[Dictionary] = []
	for actor: FieldActor in survivors:
		remaining_health.append(actor.health)
		member_records.append({"id":actor.member_id,"kills":actor.confirmed_kills,"damage_received":actor.damage_received})
		member_results.append({"id":actor.member_id,"health":actor.health,"kills":actor.confirmed_kills,"damage_received":actor.damage_received})
	var report: Dictionary = {"evacuated": evacuated, "loot": loot if evacuated else 0,
		"member_records":member_records,
		"contract_version":SurvivalContracts.VERSION,"sortie_id":sortie_id,
		"participants":participants_snapshot.duplicate(true),"member_results":member_results,
		"mission_outcome":"EXTRACTED" if evacuated else "FAILED",
		"weapons":weapon_loot.duplicate(true) if evacuated else [],
		"food":food_loot if evacuated else 0,"food_searched":_kind_searched(&"food"),
		"sites_searched":_searched_count(),
		"kills": kills, "searched": _kind_searched(&"cash"), "health": remaining_health, "elapsed": elapsed}
	if not layout.world_data.is_empty(): report.site_facts = WorldSites.facts(self)
	if billboard_site != null:
		report.billboard = billboard_work.snapshot(billboard_site.progress)
	if supply.generated.get("version")==4 or (supply.generated.get("version")==5 or (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9)))): report.task_event=task_event.duplicate(true)
	if build_mode(): report.support=basic_support.snapshot()
	if power_mode(): report.powers=powers.duplicate(true)
	if not loadout_snapshot.is_empty():
		report.growth_inputs = growth_inputs.snapshot(sortie_id,layout.id,elapsed)
	report.rescue = rescue_target.fact(evacuated) if rescue_target != null else {"rescue_id":RescueState.TARGET,"status":"UNAVAILABLE"}
	report.xp_inputs = xp_inputs.snapshot(self)
	report.trait_inputs = trait_inputs.snapshot(self)
	report.field_joins = field_joins.duplicate(true)
	if encounter!=null: report.encounter=encounter.snapshot()
	FreezeProfile.leave("report.build", profile_report)
	print("BH_RESULT %s" % JSON.stringify(report))
	finished.emit(report)
	FreezeProfile.finish()


func _shot_trace(from: Vector2, to: Vector2, colour: Color) -> void:
	_feedback._shot_trace(from, to, colour)


func _hit_effect(to: Vector2, damage: float, survivor_hit: bool) -> void:
	_feedback._hit_effect(to, damage, survivor_hit)


func _combat_popup(at: Vector2, text: String, colour: Color) -> void:
	_feedback._combat_popup(at, text, colour)


func _make_ui() -> void:
	_ui._make_ui()


func _show_notice(message: String) -> void:
	_feedback._show_notice(message)


func _update_ui() -> void:
	_ui._update_ui()


func _make_building(block: Rect2, title: String, texture: Texture2D, market: bool, residence: bool) -> FieldProp:
	var building: FieldProp = FieldProp.new()
	building.facade = texture
	building.is_market = market
	building.is_residence = residence
	building.searchable = supply.supports(&"food") if market else (not residence and supply.supports(&"cash"))
	building.title = title
	building.front_width = block.size.x
	building.position = Vector2(block.get_center().x,block.end.y)
	building.ui_theme = ui_theme
	_sort.add_child(building)
	_buildings.append(building)
	return building


class SearchSite:
	extends RefCounted
	var id: StringName
	var reward: int = 0
	var seconds: float = WorldSites.WORK_SECONDS
	var weapon: bool = false
	var hit: Rect2
	var kind: StringName
	var door: Vector2
	var progress: float = 0.0
	var searched: bool = false
	var prop: FieldProp


	func _init(resource_kind: StringName, entrance: Vector2) -> void:
		id = resource_kind
		kind = resource_kind
		door = entrance


func _kind_searched(kind: StringName) -> bool:
	return _squad._kind_searched(kind)


func _street_supply_entrances() -> Array[Vector2]:
	var doors: Array[Vector2] = []
	var generated: Dictionary = supply.generated
	var cold_store: bool = generated.has("rare_policy") and generated.type == "supply"
	if pump_station_mode() or generated.get("mission_policy") != 1 or generated.get("type") != "supply" \
			or (not cold_store and layout.world_data.get("size") != "medium") or layout.world_data.get("art_revision") != 3:
		return doors
	var ids: Array = ["food", "food_2"] if cold_store else generated.objective.site_ids
	for identity: String in ids:
		for site: Dictionary in generated.sites:
			if site.id == identity:
				doors.append(TaskActions.site_point(generated, site))
				break
	return doors if doors.size() == 2 and doors[0].is_finite() and doors[1].is_finite() else []


func _searched_count() -> int:
	return _squad._searched_count()


func _clicked_site(point: Vector2) -> bool:
	return _orders._clicked_site(point)


func _make_pump_station() -> void:
	var station: Dictionary = layout.world_data.pump_station
	station_art = PumpStationArt.new()
	station_art.configure(WorldLayout.rect(station.power_house), WorldLayout.point(station.console))
	_sort.add_child(station_art)
	for block: Rect2 in layout.fences:
		var wall: IndustrialYardWall = IndustrialYardWall.new()
		wall.footprint = block
		wall.position = Vector2(block.get_center().x, block.end.y)
		_sort.add_child(wall)
	var def: Dictionary = supply.generated.sites[0]
	var site: SearchSite = SearchSite.new(&"cash", WorldLayout.point(def.point))
	site.seconds = float(def.seconds)
	site.hit = Rect2(site.door - Vector2(45, 72), Vector2(90, 96))
	var cabinet: PumpConsoleProp = PumpConsoleProp.new()
	cabinet.position = site.door
	cabinet.title = "泵站控制柜"
	cabinet.primary_target = true
	cabinet.ui_theme = ui_theme
	_sort.add_child(cabinet)
	site.prop = cabinet
	_cash_site = site
	sites.assign([site])


func _make_world_buildings() -> void:
	if layout.world_data.get("version")==5:
		var yard: Dictionary = layout.world_data.get("loading_yard", layout.world_data.get("rescue_court", {}))
		var yard_bounds: Rect2 = WorldLayout.rect(yard.bounds) if not yard.is_empty() else Rect2()
		for wall: Rect2 in layout.fences:
			if layout.world_data.has("warehouse_district") or layout.world_data.has("themed_district") \
					or (not yard.is_empty() and yard_bounds.encloses(wall)):
				var masonry: IndustrialYardWall = IndustrialYardWall.new()
				masonry.footprint = wall
				masonry.position = Vector2(wall.get_center().x, wall.end.y)
				_sort.add_child(masonry)
				continue
			var stone: WorldgenFurniture=WorldgenFurniture.new()
			stone.detail={"kind":"wall","width":wall.size.x};stone.position=Vector2(wall.get_center().x,wall.end.y);_sort.add_child(stone)
	if layout.world_data.get("version")==5:
		for detail: Dictionary in NeighborhoodDecor.placements(layout):
			var prop: WorldFurniture = WorldFurniture.new()
			prop.kind = detail.kind
			prop.position = detail.position
			prop.variant = int(detail.variant)
			prop.refined = true
			_sort.add_child(prop)
	else:
		for row: Dictionary in layout.world_data.entities:
			for kind: String in ["lamp","planter","crate","fence"]:
				var prop: WorldFurniture = WorldFurniture.new()
				prop.kind=kind
				var offset: Vector2 = {"lamp":Vector2(-24,48),"planter":Vector2(44,52),"crate":Vector2(-32,-16),"fence":Vector2(100,-30)}[kind]
				prop.position=Vector2(row.rect[0],row.rect[1]+row.rect[3])+offset
				_sort.add_child(prop)
	if layout.world_data.get("version")==5:
		for parcel: Dictionary in layout.world_data.parcels:
			for detail: Dictionary in parcel.get("dressing",[]):
				if detail.has("surface"):
					continue
				var scenery: WorldgenFurniture=WorldgenFurniture.new()
				scenery.detail=detail;scenery.position=WorldLayout.point(detail.point);_sort.add_child(scenery)
	var props: Dictionary = {}
	for entity: Dictionary in layout.world_data.entities:
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
		building.soft_contact=layout.world_data.get("art_revision")==3
		if layout.world_data.get("version")==5:
			building.modulate=[Color.WHITE,Color(0.92,0.97,1.0),Color(1.0,0.97,0.9),Color.WHITE][int(entity.variant)]
		if layout.world_data.has("warehouse_district"):
			building.roof_tint = [Color.WHITE, Color(0.88, 1.12, 1.08), Color(1.14, 0.98, 0.83)][int(entity.variant)]
		if not _supply_entrances.is_empty():
			building.roof_tint *= Color(0.69, 0.81, 1.0)
			building.facade_tint = Color(0.87, 0.91, 0.98)
		building.world_asset = true
		if layout.world_data.get("version")==5:
			building.calibrated=true;building.roof_cut=int(definition.roof_split);building.body_depth=block.size.y
			building.door_offset=WorldLayout.point(entity.door).x-block.get_center().x
		building.title = definition.title
		building.front_width = block.size.x
		building.position = Vector2(block.get_center().x,block.end.y)
		building.ui_theme = ui_theme
		building.searchable = supply.generated.sites.any(func(d: Dictionary) -> bool: return d.building==entity.id)
		_sort.add_child(building)
		_buildings.append(building)
		props[entity.id] = building
	if exploration_mode():
		for definition: Dictionary in layout.world_data.objects:
			var prop: ExplorationProp=ExplorationProp.new()
			prop.ui_theme=ui_theme
			prop.refined_art=layout.world_data.get("version")==5
			_sort.add_child(prop)
			prop.configure(definition)
			props[definition.id]=prop
			exploration_props[definition.id]=prop
	for def: Dictionary in supply.generated.sites:
		var entity: Dictionary = {}
		for row: Dictionary in layout.world_data.entities:
			if row.id==def.building: entity=row
		var object_site: bool=exploration_mode() and def.source in ["vehicle","fruit_tree"]
		var crate: bool = def.has("point") and not object_site
		var site: SearchSite = SearchSite.new(StringName(def.kind),TaskActions.site_point(supply.generated,def) if exploration_mode() else WorldLayout.point(def.point) if crate else WorldLayout.point(entity.door))
		site.id=StringName(def.id); site.reward=int(def.amount); site.weapon=def.weapon; site.seconds=float(def.seconds)
		if object_site:
			site.door=TaskActions.site_point(supply.generated,def)
			site.prop=props[def.object_id]
			site.hit=Rect2(site.prop.position+Vector2(-80,-180 if def.source=="fruit_tree" else -96),Vector2(160,192 if def.source=="fruit_tree" else 108))
		elif crate:
			site.prop=AirdropProp.new(); site.prop.position=site.door; site.prop.front_width=80; site.prop.ui_theme=ui_theme
			_sort.add_child(site.prop)
			site.hit=Rect2(site.door-Vector2(48,100),Vector2(96,150))
		else:
			site.prop=props[def.building]
			site.hit=Rect2(site.prop.position-Vector2(site.prop.front_width/2,280),Vector2(site.prop.front_width,340)) if layout.world_data.get("version")==5 else Rect2(WorldLayout.rect(entity.rect).position-Vector2(0,160),WorldLayout.rect(entity.rect).size+Vector2(0,220))
			if layout.world_data.get("version")==5: site.hit=site.prop.scaled_hit_bounds()
			site.prop.primary_target=supply.generated.get("objective",{}).get("site_ids",[]).has(def.id)
		site.prop.reward_hint=("货币" if site.kind==&"cash" else "食物")+" +%d"%site.reward+(" / 武器" if site.weapon else "")
		if exploration_mode():
			site.prop.primary_target=supply.generated.objective.site_ids.has(def.id)
			site.prop.reward_hint=("货币" if site.kind==&"cash" else "食物")+" +%d"%site.reward
		if _is_event_site(site):
			site.prop.loot_landmark = EventSortieV1.TITLE
			site.prop.reward_hint = "现场二选一"
		if supply.generated.has("rare_policy"):
			site.prop.loot_landmark = RareSortie.landmark(supply.generated.type, def.id)
			if site.weapon:
				site.prop.reward_hint = "武器 +1"
		if build_mode() and site.id==&"cash" and supply.generated.type=="equipment": site.prop.reward_hint+=" / 道具%d件"%supply.generated.build.drops.size() if not supply.generated.build.drops.is_empty() else " / 道具已集齐"
		if exploration_mode() and not crate:
			var category: String = "果树" if def.source == "fruit_tree" else "车辆" if object_site else "建筑"
			var anchor: Vector2 = Vector2(0, 5) if object_site else Vector2(site.prop.door_offset, 28)
			if not _supply_entrances.is_empty() and site.prop.loot_landmark.is_empty() and site.prop.primary_target and site.kind == &"food":
				site.prop.loot_landmark = "近点食品" if def.id == supply.generated.objective.site_ids[0] else "追加食品"
			var tool_count: int = _tools_at(String(site.id))
			if tool_count > 0:
				site.prop.loot_landmark = "工具 ×%d" % tool_count
				site.prop.reward_hint += " · 工具 ×%d" % tool_count
			site.prop.configure_loot_badge(category, anchor)
		sites.append(site)
		if site.id==&"cash": _cash_site=site; _shop=site.prop
		if site.id==&"food": _food_site=site


func _site_seconds(site: SearchSite) -> float:
	return _squad._site_seconds(site)


func _trigger_airdrop() -> void:
	if task_event.started:
		return
	_request_task_wave(search_site(&"cash"), int(TaskActions.PARAMETERS.reinforcements))
	_show_notice("武器箱开工 · 增援接近；拿到武器即可集合归航。" if supply.generated.has("rare_policy")
		else "空投信标已启动 · 留意来袭；回收后可直接集合归航。")


func _request_task_wave(site: SearchSite, requests: int, provenance: Dictionary = {}) -> void:
	task_event.started = true
	for index: int in range(requests):
		if enemies.size() >= threat.rules.enemy_cap:
			_record_spawn(&"capacity", Vector2.INF, -1, provenance)
			task_event.resolutions.append({"reason":"capacity","enemy_id":-1})
		else:
			task_event.resolutions.append(_spawn_enemy(EnemyRules.NORMAL, site.door, provenance))


func _site_weapon(site: SearchSite) -> Dictionary:
	return _squad._site_weapon(site)


func _ammo_text(actor: FieldActor) -> String:
	return _ui._ammo_text(actor)


func combat_mode() -> bool:
	return (supply.generated.get("version")==8 or supply.generated.get("version")==9)

func build_mode() -> bool:
	return (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9))

func apply_build(actor: FieldActor, profile: Dictionary = {}, item: Dictionary = {}) -> void:
	var factors: Dictionary=BuildItems.frozen_factors(supply.generated.build)
	if persona_mode():
		if profile.is_empty(): profile=SurvivorRoster.member(_setup_crew,actor.member_id)
		var recipe: Dictionary=PersonaState.recipe(supply.generated,actor.member_id,actor.definition_id)
		var personal: Dictionary=SurvivorPersona.factors(recipe)
		if profile.is_empty() or personal.is_empty():
			setup_problem="PERSONA_ACTOR_IDENTITY"
			return
		if item.is_empty(): item=WeaponInventory.for_member(field_departure,actor.member_id)
		actor.weapon_definition=WeaponModifiers.combat_definition(item)
		var melee: bool=CombatEquipment.melee(String(actor.weapon_definition.id))
		actor.weapon_definition.damage*=personal.melee if melee else personal.ranged*factors.damage
		actor.speed=125.0*TraitRules.factor(profile,"move")*personal.move*factors.move
		actor.trait_shot_factor=TraitRules.factor(profile,"shot")
		actor.trait_search_factor=TraitRules.factor(profile,"search")
		actor.persona_work_factor=personal.work
		actor.power_move_factor=SpecialPowers.move_factor(powers,elapsed)
		if actor.magazine!=null: actor.magazine.reload_factor=personal.reload*factors.reload
		return
	# Definitions are freshly derived from immutable inventory once per actor setup.
	if not CombatEquipment.melee(String(actor.weapon_definition.id)): actor.weapon_definition.damage*=factors.damage
	actor.speed*=factors.move
	actor.power_move_factor=SpecialPowers.move_factor(powers,elapsed) if power_mode() else 1.0
	if actor.magazine!=null: actor.magazine.reload_factor=factors.reload

func support_available() -> bool:
	return build_mode() and not is_paused and not suspend_sealed and phase!=Phase.FINISHED and not (bus_view!=null and bus_view.running()) and field_join_error.is_empty()

func support_world() -> Dictionary:
	var stamp: int = FreezeProfile.enter("support.capture")
	var paused: bool=is_paused
	is_paused=true
	_clear_dead_worker()
	# Toxic/boss damage happens after the combat phase's ordinary cancellation.
	if combat_mode(): combat.cancel_unavailable(self)
	_reap_defeated_enemies()
	var value: Dictionary=SortieSnapshot.capture(self)
	is_paused=paused
	FreezeProfile.leave("support.capture", stamp)
	return value

func accept_burst(before: Dictionary) -> bool:
	var result: Dictionary = burst_commit.call(before) if burst_commit.is_valid() else {"error":ERR_UNAVAILABLE}
	if result.get("error", ERR_UNAVAILABLE) != OK:
		pending_burst = before
		is_paused = true
		support_aiming = false
		_show_notice("爆囊冲击待确认 · 已暂停，继续后重试。")
		_update_ui()
		queue_redraw()
		return false
	pending_burst = {}
	# The damage and original death facts already share the same durable publication.
	for actor: FieldActor in enemies:
		actor.free()
	enemies.clear()
	var issue: String = SortieSnapshot.apply(self, result.world)
	assert(issue.is_empty(), issue)
	is_paused = false
	var event: Dictionary = combat.burst.state.event
	for hit: Dictionary in event.hits:
		var actor: FieldActor = search_member(int(hit.member_id))
		_hit_effect(actor.position, float(hit.before) - float(hit.after), true)
		combat_feedback.emit({"kind":"burst_hit", "member_id":int(hit.member_id), "actor":actor.actor_id,
			"enemy_id":event.source_id, "enemy_type":BurstRuntimeV1.KIND, "health":hit.after,
			"applied_damage":float(hit.before) - float(hit.after), "elapsed":elapsed})
	combat.burst.feedback(self, "burst_released")
	_show_notice("爆囊冲击 · 命中 %d 人。" % event.hits.size() if not event.hits.is_empty() else "爆囊冲击 · 全员避开。")
	_update_ui()
	return true


func request_heal() -> bool:
	if not support_available(): return false
	var before: Dictionary=support_world()
	var plan: Dictionary=BuildAuthority.plan_heal(before)
	if plan.is_empty(): return false
	return _accept_support(before,basic_support.request("heal",plan))

func first_aid_status() -> String:
	return _ui.first_aid_status()


func request_first_aid() -> bool:
	if not FirstAidV1.enabled(supply.generated) or not support_available() \
			or not support_commit.is_valid() or not basic_support.ready(FirstAidV1.KIND):
		return false
	var stamp: int = FreezeProfile.enter("support.first_aid_plan")
	var states: Array[Dictionary] = []
	for actor: FieldActor in survivors:
		states.append({"member_id":actor.member_id, "health":actor.health, "max_health":actor.max_health,
			"visible":actor.visible, "activity":actor.activity, "position":[actor.position.x, actor.position.y]})
	var plan: Dictionary = FirstAidV1.plan_on_map(states, layout.world_bounds, shot_obstacles)
	FreezeProfile.leave("support.first_aid_plan", stamp)
	if plan.is_empty():
		return false
	FreezeProfile.mark("aid_eligible", stamp)
	var before: Dictionary = support_world()
	return _accept_support(before, basic_support.request(FirstAidV1.KIND, plan))

func apply_barricade_history(accepted: Array) -> void:
	var opened: bool = BarricadeState.opened(supply.generated, accepted, layout)
	if opened == barricade_open:
		return
	var stamp: int = FreezeProfile.enter("barricade.navigation")
	navigation = BarricadeV1.navigation(supply.generated, opened)
	barricade_open = opened
	_barricade_view.present(opened, support_aiming and not opened)
	FreezeProfile.leave("barricade.navigation", stamp)


func request_airstrike(point: Vector2) -> bool:
	if not support_available(): return false
	var before: Dictionary=support_world()
	var plan: Dictionary=BuildAuthority.plan_airstrike(before,point)
	if plan.is_empty():
		if support_aiming:
			_show_notice("空袭无法落在此处 · 请选择射程内无遮挡的地面")
			_update_ui()
		return false
	return _accept_support(before,basic_support.request("airstrike",plan))

func _accept_support(before: Dictionary, request: Dictionary) -> bool:
	if request.is_empty() or not support_commit.is_valid(): return false
	var confirmation: int = FreezeProfile.enter("support.confirm")
	var result: Dictionary=support_commit.call(before,request)
	FreezeProfile.leave("support.confirm", confirmation)
	if result.get("error",ERR_UNAVAILABLE)!=OK:
		pending_support={"before":before,"request":request}
		is_paused=true
		support_aiming=false
		_show_notice("支援尚未确认，已暂停；请重试或暂存继续。"+String(result.get("reason","")))
		_update_ui()
		return false
	pending_support={}
	var after: Dictionary=result.world
	var interrupted: bool = before.get("combat", {}).get("screamer", {}).get("phase") == "windup" \
		and after.get("combat", {}).get("screamer", {}).get("phase") == "cancelled"
	var burst_interrupted: bool = before.get("combat", {}).get("burst", {}).get("phase") == "windup" \
		and after.get("combat", {}).get("burst", {}).get("phase") == "cancelled"
	# All fallible validation and I/O preceded this visible state replacement.
	var preserve_aim: bool = request.kind in [FirstAidV1.KIND, SpecialPowers.RADIO] and support_aiming
	var was_open: bool = barricade_open
	var application: int = FreezeProfile.enter("support.apply")
	for enemy: FieldActor in enemies: enemy.free()
	enemies.clear()
	var issue: String=SortieSnapshot.apply(self,after)
	FreezeProfile.leave("support.apply", application)
	assert(issue.is_empty(),issue)
	is_paused=false
	if request.kind=="airstrike":
		support_aiming=false
		support_aim.impact(SortieSnapshot._vec(request.payload.point),request.payload.radius)
		var hits: int=request.payload.targets.size()
		var notice: String = "空袭命中 · %d 个目标" % hits if hits > 0 else "空袭已落地"
		if barricade_open and not was_open:
			notice += " · 路障已清除"
		if burst_interrupted:
			combat.burst.feedback(self, "burst_cancelled")
			notice += " · 爆囊冲击取消"
		if interrupted:
			combat.screamer.report_cancelled(self, notice)
		else:
			_show_notice(notice)
	elif request.kind in [FirstAidV1.KIND, SpecialPowers.RADIO]:
		var first_aid: bool = request.kind == FirstAidV1.KIND
		if first_aid:
			FreezeProfile.mark("aid_hp_applied")
		support_aiming = preserve_aim
		var facts: Dictionary = after.support.accepted.back().facts
		var patient: FieldActor = search_member(int(facts.member_id))
		var amount: String = str(snappedf(float(facts.amount), 0.01))
		var title: String = FirstAidV1.TITLE if first_aid else SpecialPowers.RADIO_DEFINITION.name
		_show_notice("%s · %s +%s HP" % [title, patient.call_sign, amount])
		_combat_popup(patient.position + Vector2(12, -136), "+%s HP" % amount, Color("a5dfce"))
		var feedback: Dictionary = {"kind":request.kind, "member_id":facts.member_id,
			"amount":facts.amount, "health":facts.health_after}
		if first_aid:
			feedback.source_id = facts.source_id
		combat_feedback.emit(feedback)
	else:
		_show_notice("治疗已确认")
	_update_ui()
	return true

func toggle_support_aim() -> void:
	_orders.toggle_support_aim()


func _support_input(event: InputEvent) -> bool:
	return _orders._support_input(event)


func _present_support() -> void:
	_feedback._present_support()


func support_plan_airstrike(point: Vector2) -> Dictionary:
	var view: Dictionary={"version":10,"generated":supply.generated,"survivors":[],"enemies":[]}
	for actor: FieldActor in survivors:
		view.survivors.append({"state":{"member_id":actor.member_id,"health":actor.health,"visible":actor.visible,"activity":actor.activity,"position":[actor.position.x,actor.position.y]}})
	for enemy: FieldActor in enemies:
		view.enemies.append({"state":{"actor_id":enemy.actor_id,"health":enemy.health,"visible":enemy.visible,"position":[enemy.position.x,enemy.position.y]}})
	return BuildAuthority.plan_airstrike_on_map(view,point,layout,navigation)

func exploration_mode() -> bool:
	return supply.generated.get("version")==9

func pump_station_mode() -> bool:
	return PumpStationAction.enabled(supply.generated)

func station_stopped() -> bool:
	return pump_station_mode() and _cash_site.searched

func persona_mode() -> bool:
	return supply.generated.has("persona")

func power_mode() -> bool:
	return supply.generated.has("powers")

func refresh_power_factors() -> void:
	var factor: float=SpecialPowers.move_factor(powers,elapsed) if power_mode() else 1.0
	power_frozen=SpecialPowers.frozen(powers,elapsed) if power_mode() else false
	for actor: FieldActor in survivors: actor.power_move_factor=factor
	for actor: FieldActor in enemies:
		actor.motion_locked = power_frozen or (combat.screamer != null and combat.screamer.holds(actor)) \
			or (combat.burst != null and combat.burst.holds(actor)) \
			or (actor.enemy_behavior != null and actor.enemy_behavior.kind == NightHoundV1.KIND and actor.enemy_behavior.state == "windup")

func request_power(slot: int = 0) -> bool:
	if not power_mode() or not support_available() or not pending_power.is_empty() or not survivors.any(func(actor:FieldActor)->bool:return actor.health>0): return false
	if SpecialPowers.equipped_at(powers, slot) == SpecialPowers.RADIO:
		return _request_aid_broadcast()
	var request: Dictionary=SpecialPowers.request(powers,slot)
	if request.is_empty(): return false
	return _accept_power(support_world(),request)

func _request_aid_broadcast() -> bool:
	if not support_commit.is_valid() or not basic_support.ready(SpecialPowers.RADIO):
		return false
	var before: Dictionary = support_world()
	var plan: Dictionary = BuildAuthority.plan_radio(before)
	if plan.is_empty():
		_show_notice("急救广播 · 户外没有可治疗的在场队员，次数保留")
		_update_ui()
		return false
	return _accept_support(before, basic_support.request(SpecialPowers.RADIO, plan))

func _accept_power(before: Dictionary, request: Dictionary) -> bool:
	if not power_commit.is_valid(): return false
	var result: Dictionary=power_commit.call(before,request)
	if result.get("error",ERR_UNAVAILABLE)!=OK:
		pending_power={"before":before,"request":request}
		is_paused=true
		support_aiming=false
		_show_notice("能力尚未确认，已暂停；解除故障后继续重试。"+String(result.get("reason","")))
		_update_ui()
		return false
	pending_power={}
	powers=result.world.powers.duplicate(true)
	is_paused=false
	refresh_power_factors()
	_show_notice("%s已生效 · 本次使用已保存"%SpecialPowers.definition(request.ability_id).name)
	_update_ui()
	return true

func _present_power() -> void:
	_feedback._present_power()


func _present_power_slot(panel: PowerSlotPanel, slot: int) -> void:
	_feedback._present_power_slot(panel, slot)


func _exploration_objective_rows() -> Array[Dictionary]:
	return _ui._exploration_objective_rows()


func _tools_at(site_id: String) -> int:
	return _squad._tools_at(site_id)


func _carried_tools() -> int:
	return _squad._carried_tools()


func site_discovered(site: SearchSite) -> bool:
	return recon_knowledge == null or site == recon_site or recon_knowledge.explored(site.door) \
		or (recon_site.searched and _is_recon_target(site.id))


func _is_recon_target(id: StringName) -> bool:
	if recon_site == null:
		return false
	var marker: Dictionary = supply.generated.recon
	return String(id) in [marker.primary_id, marker.optional_id]


func _update_recon_knowledge() -> void:
	var changed: bool = false
	for actor: FieldActor in survivors:
		if actor.health > 0.0 and actor.visible and actor.activity != FieldActor.Activity.SEARCHING:
			if recon_knowledge.observe(actor.member_id, actor.position, elapsed):
				changed = true
	if changed:
		refresh_recon_view()


func refresh_recon_view() -> void:
	_feedback.refresh_recon_view()


func recon_region() -> Rect2:
	var target: Vector2 = search_site(&"cash").door
	var origin: Vector2 = layout.world_bounds.position
	var size: Vector2 = Vector2.ONE * ReconActionV1.REGION
	var start: Vector2 = origin + ((target - origin) / size).floor() * size
	return Rect2(start, size).intersection(layout.world_bounds)


func locate_objective(id: String) -> void:
	_feedback.locate_objective(id)
