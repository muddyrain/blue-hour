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

const BUILD_ID: String = "M5-UX-01"
const BusTexture: Texture2D = preload("res://assets/candidates/bus_02.png")

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
var player_mode: bool = false
var is_practice: bool = false
var battle_survival: bool = false
var battle_drill: bool = false
var battle_seed: String = "NONE"
var drill_panel: BattleDrillPanel
var hunger_trial: bool = false
var rescue_mode: bool = false
var growth_mode: bool = false
var trait_mode: bool = false
var training_mode: bool = false
var pool_mode: bool = false
var enemy_mode: bool = false
var trait_inputs: TraitInputs = TraitInputs.new()
var field_join_mode: bool = false
var field_join_gate: Callable
var field_departure: Dictionary = {}
var field_joins: Array[Dictionary] = []
var field_join_error: String = ""
var growth_binding: Dictionary = {}
var xp_inputs: XpInputs = XpInputs.new()
var rescue_completed: bool = false
var rescue_target: RescueTarget
var los_practice: bool = false
var los_range_case: bool = false
var los_setup: LosPracticeSetup
var threat: ThreatDirector = ThreatDirector.new()
var threat_rehearsal: bool = false
var combat: CombatRuntime=CombatRuntime.new()
var combat_delta: float=0.0
var powers: Dictionary = {}
var power_commit: Callable
var pending_power: Dictionary = {}
var power_frozen: bool = false
var _power_effect_visible: bool = false
var power_panel: PowerSlotPanel
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
var _practice_manual_waves: bool = false
var _readouts: SquadReadouts
var _cash_site: SearchSite = SearchSite.new(&"cash", Vector2.ZERO)
var _food_site: SearchSite = SearchSite.new(&"food", Vector2.ZERO)
var sites: Array[SearchSite] = []
var task_event: Dictionary = TaskActions.empty_event()
var _bus_sprite: Sprite2D
var bus_view: BusJourney
var restoring_world: bool=false
var encounter: EncounterRuntime
var _active_site: SearchSite:
	get:
		return member_site(search_actor.member_id) if search_actor != null else null


func _ready() -> void:
	parallel_search = combat_mode()
	_setup_crew.assign(crew_snapshot.duplicate(true) if not crew_snapshot.is_empty() else SurvivorRoster.new_crew())
	if crew_snapshot.is_empty() or is_practice:
		for index: int in range(_setup_crew.size()):
			if index < starting_health.size():
				_setup_crew[index].health = starting_health[index]
	setup_problem = SurvivalContracts.identity_problem(_setup_crew,growth_mode)
	if setup_problem.is_empty() and not loadout_snapshot.is_empty():
		setup_problem = WeaponInventory.snapshot_problem(_setup_crew, loadout_snapshot, not is_practice,WeaponState.is_family(field_departure))
	if setup_problem.is_empty() and not is_practice and not crew_snapshot.is_empty() and loadout_snapshot.is_empty():
		setup_problem = "正式名册缺少出击配装快照"
	participants_snapshot = SurvivalContracts.participants(_setup_crew, loadout_snapshot, not is_practice,growth_mode) if setup_problem.is_empty() else []
	if participants_snapshot.is_empty():
		setup_problem = setup_problem if not setup_problem.is_empty() else "没有可行动的参与者"
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	growth_inputs.configure(participants_snapshot)
	if growth_mode:
		xp_inputs.configure(growth_binding)
	if build_mode(): basic_support.configure(growth_binding)
	if power_mode(): powers=SpecialPowers.initial(growth_binding,supply.generated.powers.slot)
	if combat_mode(): combat.setup(self)
	if trait_mode:
		trait_inputs.configure(growth_binding)
	if is_practice and participants_snapshot.size() != 2:
		setup_problem = "当前独立练习仅支持原双人配置"
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	if (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9))): tuning.spawn_seconds*=float(supply.generated.campaign.pressure)
	layout = supply.layout
	_cash_site.door = layout.cash_door
	_food_site.door = layout.food_door
	if exploration_mode(): navigation=ExplorationLayout._routing(layout.world_data).nav
	else: navigation.configure(layout.blockers(),layout.world_bounds)
	shot_obstacles = layout.shot_obstacles()
	if is_practice and los_practice:
		los_setup = LosPracticeSetup.for_layout(layout, los_range_case)
	var ground: StreetBlock = StreetBlock.new()
	ground.layout = layout
	ground.food_source_visible = supply.supports(&"food")
	ground.z_index = -10
	add_child(ground)
	camera = FieldCamera.new()
	camera.pan_speed = tuning.camera_pan_speed
	camera.min_zoom = tuning.camera_min_zoom
	camera.max_zoom = tuning.camera_max_zoom
	camera.zoom_step = tuning.camera_zoom_step
	camera.bounds = layout.world_bounds
	add_child(camera)
	camera.pan_by(layout.camera_start-camera.position)
	_sort = Node2D.new()
	_sort.name = "ActorsAndProps"
	_sort.y_sort_enabled = true
	add_child(_sort)
	_effects = Node2D.new()
	add_child(_effects)
	var bus: Sprite2D = Sprite2D.new()
	_bus_sprite = bus
	bus.texture = BusTexture
	bus.offset = Vector2(0, -128)
	bus.scale = Vector2.ONE * (240.0 / 448.0)
	bus.position = layout.bus_foot()
	_sort.add_child(bus)
	if not layout.world_data.is_empty():
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
	for block: Rect2 in ([] if (layout.world_data.get("version")==3 or layout.world_data.get("version")==4 or layout.world_data.get("version")==5) else layout.fences):
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
		if los_setup != null:
			start = los_setup.starts[index]
		var actor: FieldActor = _make_actor(false, index, start, profile)
		actor.health = float(participant.health_before)
		actor.call_sign = profile.call_sign
		var item: Dictionary = {}
		for entry: Dictionary in loadout_snapshot:
			if int(entry.member_id) == actor.member_id:
				item = entry.instance
		if item.is_empty():
			# Standalone/practice scenes have no campaign inventory; retain their old views.
			actor.weapon_definition = WeaponInventory.Definitions[1 if not is_practice and actor.definition_id == &"crew_2" else 0].duplicate() as WeaponDefinition
		else:
			actor.weapon_instance_id = item.instance_id
			actor.weapon_definition = WeaponModifiers.combat_definition(item)
		actor.visual.set_weapon(actor.weapon_definition.presentation)
		if combat_mode() and String(actor.weapon_definition.id) in ["fire_axe_v1","shotgun_v1"]: combat.action(actor)
		if (supply.generated.get("version")==5 or (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9)))):
			if not CombatEquipment.melee(String(actor.weapon_definition.id)): actor.magazine=WeaponMagazine.new(actor.weapon_instance_id,String(actor.weapon_definition.id))
		if build_mode(): apply_build(actor)
		survivors.append(actor)
	if (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9))):
		encounter=EncounterRuntime.new();encounter.setup(self,restoring_world)
	_make_ui()
	var readout_layer: CanvasLayer = CanvasLayer.new()
	readout_layer.layer = 5
	add_child(readout_layer)
	if rescue_mode and supply.id == &"rescue" and not rescue_completed:
		rescue_target = RescueTarget.new()
		rescue_target.world = self
		add_child(rescue_target)
	if field_join_mode and not field_joins.is_empty() and rescue_target != null:
		promote_target(field_joins[0],true)
	_readouts = SquadReadouts.new()
	readout_layer.add_child(_readouts)
	_spawn_clock = tuning.spawn_seconds
	threat.update(elapsed, tuning.daylight_seconds, tuning.spawn_seconds)
	if is_practice:
		_spawn_clock = 1.4
		camera.zoom_at(Vector2(640, 360), 1.10 / camera.zoom.x)
		camera.pan_by(Vector2(1040, 744) - camera.position)
		_show_notice("交火练习 · 先观察生命200；即将近身来袭。I/J/K/L：指定来袭方位")
		if los_setup != null:
			camera.pan_by(los_setup.camera_center - camera.position)
			_show_notice("项目验收演练 · 实墙挡枪，左键绕角后自动恢复；正式进度不改变。")
	if not is_practice:
		_show_notice(layout.route_hint)
		if threat_rehearsal:
			_show_notice("短时压力演练 · 21秒夜间候选；正常出击105秒，规则均待校准。")
	if not layout.world_data.is_empty():
		bus_view = BusJourney.new()
		bus_view.configure(self,_bus_sprite,layout.world_data.bus)
		add_child(bus_view)
	print("BH_SORTIE build=%s start day=%d members=%d" % [BUILD_ID, day, survivors.size()])


func _process(delta: float) -> void:
	if phase == Phase.FINISHED and bus_view != null and bus_view.running(): bus_view.advance(delta)


func _physics_process(delta: float) -> void:
	step(delta)


func _draw() -> void:
	for job: Dictionary in search_assignments.ordered():
		var actor: FieldActor = search_member(int(job.member_id))
		if actor != null and actor.activity == FieldActor.Activity.MOVING:
			draw_dashed_line(actor.position, search_site(StringName(job.site_id)).door, Color("e3c879"), 1.5, 8.0)
	if phase == Phase.BOARDING:
		draw_circle(layout.bus_door, tuning.boarding_radius, Color(0.9, 0.75, 0.3, 0.2))
		draw_arc(layout.bus_door, tuning.boarding_radius, 0.0, TAU, 48, Color("e3c879"), 2.0)
	if goal != Vector2.ZERO and phase != Phase.FINISHED:
		draw_arc(goal, 13.0, 0.0, TAU, 24, Color("b3e8d9"), 2.0, true)
		draw_line(goal - Vector2(6, 0), goal + Vector2(6, 0), Color("b3e8d9"), 2.0)
		for actor: FieldActor in survivors:
			if actor.activity == FieldActor.Activity.MOVING and not has_search_job(actor.member_id):
				draw_dashed_line(actor.position, goal, Color(0.8, 0.95, 0.91, 0.4), 1.0, 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.FINISHED:
		return
	if _support_input(event):
		get_viewport().set_input_as_handled()
		return
	if is_practice and event.is_action_pressed("practice_far_target"):
		practice_far_target()
	elif is_practice and event.is_action_pressed("practice_cross"):
		practice_cross()
	elif is_practice and event.is_action_pressed("practice_long_rifle"):
		practice_weapon(ActorVisual.LongRifleView)
	elif is_practice and event.is_action_pressed("practice_carbine"):
		practice_weapon(ActorVisual.CarbineView)
	elif is_practice and event.is_action_pressed("practice_north"):
		practice_incoming(Vector2.UP)
	elif is_practice and event.is_action_pressed("practice_south"):
		practice_incoming(Vector2.DOWN)
	elif is_practice and event.is_action_pressed("practice_west"):
		practice_incoming(Vector2.LEFT)
	elif is_practice and event.is_action_pressed("practice_east"):
		practice_incoming(Vector2.RIGHT)
	elif event.is_action_pressed("pause_sortie"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("squad_command"):
		var point: Vector2 = get_global_mouse_position()
		if event is InputEventMouseButton:
			# Use the click's coordinates, not a later position of the desktop cursor.
			point = get_global_transform_with_canvas().affine_inverse() * event.position
		if rescue_target != null and rescue_target.contains(point):
			rescue_target.request()
		elif not layout.world_data.is_empty() and _clicked_site(point):
			pass
		elif layout.world_data.is_empty() and supply.supports(&"cash") and layout.hit_area(&"cash").has_point(point):
			if searched:
				command_move(point)
			else:
				request_search()
		elif layout.world_data.is_empty() and supply.supports(&"food") and layout.hit_area(&"food").has_point(point):
			if _food_site.searched:
				command_move(point)
			else:
				request_search(&"food")
		elif layout.bus_block.grow(18.0).has_point(point):
			request_extraction()
		elif layout.world_bounds.has_point(point):
			command_move(point)
		get_viewport().set_input_as_handled()


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
	if combat_mode() and not combat.toxic.pending.is_empty():
		combat.advance_toxic(self,0.0)
		if is_paused: return
	var started_usec: int = Time.get_ticks_usec()
	elapsed += delta
	if build_mode():
		basic_support.advance(delta,true)
		if support_aim!=null: support_aim.advance(delta,true)
	_notice_clock = maxf(0.0, _notice_clock - delta)
	if not is_practice and threat.update(elapsed, tuning.daylight_seconds, tuning.spawn_seconds):
		# Tighten the next deadline, without owing any historical spawns.
		if is_finite(_spawn_clock):
			_spawn_clock = minf(_spawn_clock, threat.interval)
		var state: Dictionary = threat_status()
		threat_changed.emit(state)
		_show_notice("%s · 增援更密集；仍可发动巴士集合撤离。" % state.label)
		print("BH_THREAT " + JSON.stringify(state))
	_spawn_clock -= delta
	_ai_clock -= delta
	if _spawn_clock <= 0.0 and not _practice_manual_waves:
		if enemies.size() < threat.rules.enemy_cap:
			_spawn_enemy()
		elif not is_practice:
			_record_spawn(&"capacity", Vector2.INF)
		# No while-loop or accumulated debt, including when full or all points are visible.
		_spawn_clock = tuning.spawn_seconds if is_practice else threat.interval
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
	_update_enemy_behaviors(delta)
	_update_enemy_paths(true)
	for enemy: FieldActor in enemies:
		enemy.advance(0.0 if power_frozen else delta,false,false)
	var enemy_motion: Dictionary = FieldContacts.move(enemies,occupants,navigation,0.0 if power_frozen else delta,false,_hold_enemy_approach)
	last_contact_metrics.enemy_substeps = enemy_motion.substeps
	last_contact_metrics.motion_deviation_max = maxf(last_contact_metrics.motion_deviation_max,enemy_motion.motion_deviation_max)
	for actor: FieldActor in occupants: actor.present_motion(delta,previous[actor])
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
	if combat_mode():
		for actor: FieldActor in survivors: combat.present(actor)
	if encounter!=null and not is_paused:
		if power_frozen: encounter.observe_frozen_health()
		else: encounter.advance(delta)
	if is_paused:
		_update_ui()
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
	return RescuePoolState.choice(field_departure,sortie_id) if pool_mode else 3


func join_target(at_ms: int) -> bool:
	if not field_join_mode or not field_join_gate.is_valid():
		return false
	var confirmed: Dictionary = field_join_gate.call(at_ms)
	if confirmed.error != OK:
		field_join_error = confirmed.get("reason","FIELD_JOIN_ACK_FAILED")
		_show_notice("接纳尚未保存成功，已暂停；请点击重试完成援救。")
		if not is_paused:
			toggle_pause()
		return false
	field_join_error = ""
	promote_target(confirmed.receipt.joins[0])
	return true


func promote_target(event: Dictionary, restoring: bool = false) -> void:
	var id: int = int(event.member_id)
	if survivors.any(func(actor: FieldActor) -> bool: return actor.member_id == id):
		return
	var action: Dictionary = FieldJoinRules.action_base(field_departure,[event])
	var profile: Dictionary = SurvivorRoster.member(action.crew,id)
	var gun: Dictionary = WeaponInventory.for_member(action,id)
	var actor: FieldActor = rescue_target.npc
	actor.actor_id = survivors.size()
	actor.call_sign = profile.call_sign
	actor.weapon_instance_id = gun.instance_id
	actor.weapon_definition = WeaponModifiers.combat_definition(gun)
	actor.visual.set_weapon(actor.weapon_definition.presentation)
	if (supply.generated.get("version")==5 or (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9)))) and not CombatEquipment.melee(String(actor.weapon_definition.id)):actor.magazine=WeaponMagazine.new(actor.weapon_instance_id,String(actor.weapon_definition.id))
	actor.clear_order()
	if trait_mode:
		TraitRules.apply(actor,profile,tuning.survivor_speed)
	if build_mode(): apply_build(actor,profile,gun)
	survivors.append(actor)
	if pool_mode:
		# Match the existing participant/snapshot execution order, including 5 then 3/4.
		survivors.sort_custom(func(a: FieldActor,b: FieldActor) -> bool: return a.member_id<b.member_id)
		for index: int in range(survivors.size()):
			survivors[index].actor_id = index
	_setup_crew.append(profile.duplicate(true))
	loadout_snapshot.append({"member_id":id,"instance":gun.duplicate(true)})
	participants_snapshot = SurvivalContracts.participants(_setup_crew,loadout_snapshot,true,true)
	growth_inputs.register_member(id)
	field_joins.assign([event.duplicate(true)])
	rescue_target.status = "IN_FIELD_JOINED"
	rescue_target.progress = RescueTarget.SECONDS
	rescue_target.worker = 0
	if not restoring and goal != Vector2.ZERO:
		_move_to_group_goal(actor)
	rescue_target.refresh()
	membership_committed.emit()
	_update_ui()
	print("BH_FIELD_JOIN member=%d at_ms=%d same_npc=true" % [id,int(event.at_ms)])


func toggle_pause() -> void:
	if not pending_power.is_empty():
		_accept_power(pending_power.before,pending_power.request)
		return
	if combat_mode(): combat.cancel_unavailable(self)
	support_aiming=false
	if not pending_support.is_empty():
		_accept_support(pending_support.before,pending_support.request)
		return
	if is_paused and not field_join_error.is_empty():
		return
	if suspend_sealed:
		return
	if phase == Phase.FINISHED:
		return
	is_paused = not is_paused
	pause_changed.emit(is_paused)
	_effects.process_mode = Node.PROCESS_MODE_DISABLED if is_paused else Node.PROCESS_MODE_INHERIT
	_update_ui()
	print("BH_SORTIE paused=%s" % is_paused)


func command_move(point: Vector2) -> void:
	if bus_view != null and bus_view.running(): return
	if not field_join_error.is_empty():
		return
	if rescue_target != null: rescue_target.cancel()
	if phase == Phase.FINISHED:
		return
	goal = point
	for index: int in range(survivors.size()):
		var actor: FieldActor = survivors[index]
		if has_search_job(actor.member_id) or actor.activity == FieldActor.Activity.DOWN:
			continue
		_move_to_group_goal(actor)
	queue_redraw()
	print("BH_ORDER move %s" % point)


func request_search(kind: StringName = &"cash") -> void:
	if (bus_view != null and bus_view.running()) or not field_join_error.is_empty():
		return
	var site: SearchSite = search_site(kind)
	if phase == Phase.FINISHED or site == null or site.searched or not supply.supports(site.kind):
		return
	var previous: int = search_assignments.member_for(String(site.id))
	if previous > 0:
		_release_searcher(previous)
		_show_notice(SearchWorkView.notice("cancelled",site_label(site)))
		_search_log("cancelled",site)
		_update_ui()
		return
	if not parallel_search:
		if rescue_target != null:
			rescue_target.cancel()
		_release_searcher()
	var candidates: Array[Dictionary] = []
	var paths: Dictionary = {}
	var free_count: int = 0
	for actor: FieldActor in survivors:
		if actor.health <= 0 or not actor.visible or has_search_job(actor.member_id) or actor.activity not in [FieldActor.Activity.IDLE,FieldActor.Activity.MOVING]:
			continue
		if rescue_target != null and rescue_target.status == "IN_PROGRESS" and rescue_target.worker == actor.member_id:
			continue
		free_count += 1
		var path: PackedVector2Array = navigation.path_between(actor.position,site.door)
		var reachable: bool = not path.is_empty() and path[-1].distance_to(site.door) <= 14.0
		if actor.position.distance_to(site.door) <= 14.0:
			path = PackedVector2Array([actor.position])
			reachable = true
		paths[actor.member_id] = path
		candidates.append({"member_id":actor.member_id,"distance":actor.position.distance_to(site.door),"reachable":reachable,"available":true})
	var chosen: int = SearchAssignments.pick(candidates)
	if chosen == 0:
		_show_notice(SearchWorkView.notice("no_idle" if free_count == 0 else "unreachable",site_label(site)))
		return
	if not search_assignments.assign(chosen,String(site.id)):
		return
	var actor: FieldActor = search_member(chosen)
	actor.command_path(paths[chosen])
	_show_notice(SearchWorkView.notice("assigned",site_label(site),actor.call_sign))
	_search_log("assigned",site)
	_update_ui()
	queue_redraw()


func has_search_job(member_id: int) -> bool:
	return not search_assignments.site_for(member_id).is_empty()


func search_member(member_id: int) -> FieldActor:
	for actor: FieldActor in survivors:
		if actor.member_id == member_id:
			return actor
	return null


func member_site(member_id: int) -> SearchSite:
	var id: String = search_assignments.site_for(member_id)
	return search_site(StringName(id)) if not id.is_empty() else null


func site_label(site: SearchSite) -> String:
	return SearchWorkView.short_site(site.prop.title,sites.find(site)+1)


func _search_log(stage: String, site: SearchSite) -> void:
	var rows: Array[Dictionary] = []
	for job: Dictionary in search_assignments.ordered():
		var entry: Dictionary = job.duplicate()
		entry.progress = search_site(StringName(job.site_id)).progress
		rows.append(entry)
	print("BH_SEARCH "+JSON.stringify({"stage":stage,"site_id":String(site.id),"jobs":rows,"elapsed":elapsed,"loot":loot,"food":food_loot}))


func search_site(kind: StringName) -> SearchSite:
	for site: SearchSite in sites:
		if site.id == kind: return site
	if kind == &"cash":
		return _cash_site
	if kind == &"food":
		return _food_site
	return null


func request_extraction() -> void:
	if bus_view != null and bus_view.running(): return
	if not field_join_error.is_empty():
		return
	if is_practice and phase != Phase.FINISHED:
		_finish(true)
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
	print("BH_EXTRACTION engine")


func request_bus_action() -> void:
	if phase == Phase.BOARDING and not is_practice:
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
	if phase != Phase.BOARDING or is_practice or living_count() == 0:
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
	# Gathering also releases assistance when the previous group goal was already the bus.
	if rescue_target != null: rescue_target.cancel()
	if goal != layout.bus_door:
		command_move(layout.bus_door)
	var boarding: Dictionary = boarding_status()
	_show_notice("已下令集合 · 搜集中的队员完成后归队。" if boarding.working > 0 else "已下令集合 · 队员正前往巴士。")
	_update_ui()
	bus_gather_ordered.emit(boarding)
	print("BH_BUS_GATHER " + JSON.stringify({"goal":goal,"paused":is_paused,"boarding":boarding,"elapsed":elapsed}))


func practice_incoming(direction: Vector2, distance: float = 175.0, target_health: float = 0.0) -> void:
	if not is_practice or phase == Phase.FINISHED:
		return
	_practice_manual_waves = true
	var point: Vector2 = survivors[0].position + direction.normalized() * distance
	var enemy: FieldActor = _make_actor(true, _spawn_count, point)
	if target_health > 0.0:
		enemy.max_health = target_health
		enemy.health = target_health
	enemies.append(enemy)
	_spawn_count += 1
	_show_notice("项目验收演练 · 实墙影响合法目标，左键绕角后自动开火。" if los_setup != null else "交火练习 · 1/2：卡宾枪/长管步枪 · I/J/K/L：来袭方位 · H：交错")
	print("BH_PRACTICE incoming=%s" % direction)


func practice_far_target() -> void:
	if not is_practice or phase == Phase.FINISHED:
		return
	# TMP-112: durable practice fixture allows retreat/re-entry before it dies; combat is shared.
	practice_incoming(Vector2.RIGHT, 350.0, 540.0)
	_show_notice("远距耐久靶 · 540生命 · 左键接近/退离，观察开火与停止")


func time_status() -> Dictionary:
	return {
		"sortie_seconds": maxi(0, ceili(tuning.daylight_seconds - elapsed)),
		"sortie_fraction": clampf(1.0 - elapsed / maxf(tuning.daylight_seconds, 0.001), 0.0, 1.0),
		"bus_seconds": maxi(0, ceili(tuning.bus_ready_seconds - elapsed)),
		"engine_seconds": maxi(0, ceili(_engine_clock)),
	}


func practice_weapon(view: WeaponPresentation) -> void:
	if not is_practice or phase == Phase.FINISHED:
		return
	for actor: FieldActor in survivors:
		actor.visual.set_weapon(view)
	_show_notice("交火练习 · %s · I/J/K/L：来袭方位 · H：交错" % view.display_name)


func practice_cross() -> void:
	if not is_practice or phase == Phase.FINISHED:
		return
	var first: Vector2 = survivors[0].position
	var second: Vector2 = survivors[1].position
	survivors[0].command_path(navigation.path_between(first, second))
	survivors[1].command_path(navigation.path_between(second, first))
	goal = Vector2.ZERO
	_show_notice("交错演练 · 青色1 / 琥珀2 · 地面脚底与路径保持不变")


func living_count() -> int:
	var count: int = 0
	for actor: FieldActor in survivors:
		if actor.activity != FieldActor.Activity.DOWN:
			count += 1
	return count


func _move_to_group_goal(actor: FieldActor) -> void:
	actor.command_path(navigation.path_between(actor.position, goal + _group_offset(actor)))


func _group_offset(actor: FieldActor) -> Vector2:
	var gap: float = minf(tuning.squad_spacing, tuning.boarding_radius * 1.2 / maxi(1, survivors.size() - 1))
	return Vector2.ONE * ((float(actor.actor_id) - float(survivors.size() - 1) * 0.5) * gap)


func _arrival(index: int) -> Vector2:
	if is_practice:
		return Vector2(1008 + index * 48, 720 + index * 48)
	if index < layout.arrivals.size():
		return layout.arrivals[index]
	var anchor: Vector2 = layout.arrivals[0]
	for ring: int in range(1, 17):
		for x: int in range(-ring, ring + 1):
			for y: int in range(-ring, ring + 1):
				var point: Vector2 = anchor + Vector2(x,y) * 48.0
				if not navigation.is_clear(point) or survivors.any(func(actor: FieldActor) -> bool: return actor.position.distance_to(point) < 32.0):
					continue
				if not navigation.path_between(anchor, point).is_empty():
					return point
	# Explicit construction error; never drop members from the participant set.
	setup_problem = "本图没有足够的合法出生位置"
	return anchor


func _release_searcher(member_id: int = 0) -> void:
	if member_id == 0:
		if search_actor == null:
			return
		member_id = search_actor.member_id
	search_assignments.release_member(member_id)
	var released: FieldActor = search_member(member_id)
	if released != null:
		released.clear_order()
		if released.health > 0 and goal != Vector2.ZERO:
			_move_to_group_goal(released)
	queue_redraw()


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
	if growth_mode and not enemy and not profile.is_empty():
		actor.max_health = GrowthRules.maximum(profile)
	actor.health = actor.max_health
	if enemy and enemy_mode:
		actor.enemy_behavior = EnemyBehavior.new()
		actor.enemy_behavior.kind = kind if not kind.is_empty() else EnemyRules.NORMAL if index>=10000 or is_practice else combat.pick_spawn(self,index) if combat_mode() else EnemyRules.pick(sortie_id,index,int(threat.stage))
		actor.enemy_behavior.spawn_stage = int(threat.stage)
		if combat_mode() and actor.enemy_behavior.kind==CombatEnemyRules.TOXIC: combat.toxic.casters[str(index)]=ToxicV1._caster(index)
		actor.enemy_theme = ui_theme
		actor.max_health = EnemyRules.health(actor.enemy_behavior.kind,tuning.enemy_health)
		actor.health = actor.max_health
		actor.speed = EnemyRules.speed(actor.enemy_behavior.kind,false,tuning.enemy_speed)
	if trait_mode and not enemy and not profile.is_empty():
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


func _spawn_enemy(forced_kind: String = "", pressure_point: Vector2 = Vector2.INF) -> Dictionary:
	if is_practice:
		_spawn_practice_enemy()
		return {"reason":"practice","enemy_id":-1}
	var point: Vector2 = _safe_spawn_point(pressure_point)
	if not point.is_finite():
		_record_spawn(&"no_safe_point", point)
		return {"reason":"no_safe_point","enemy_id":-1}
	var enemy: FieldActor = _make_actor(true, _spawn_count, point,{},forced_kind)
	enemies.append(enemy)
	_spawn_count += 1
	_record_spawn(&"spawned", point, enemy.actor_id)

	return {"reason":"spawned","enemy_id":enemy.actor_id}


func visible_world_rect() -> Rect2:
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var corner: Vector2 = inverse * Vector2.ZERO
	return Rect2(corner, inverse * get_viewport_rect().size - corner)


func threat_status() -> Dictionary:
	var state: Dictionary = threat.snapshot()
	state.merge({"enabled":not is_practice, "elapsed":elapsed, "spawned":_spawn_count,
		"attempts":_spawn_attempts, "next_spawn":_spawn_clock, "active_enemies":enemies.size(),
		"cap":threat.rules.enemy_cap, "rehearsal":threat_rehearsal,
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
	for point: Vector2 in candidates:
		if visible.has_point(point) or not navigation.is_clear(point):
			continue
		if pressure_point.is_finite() and point.distance_to(pressure_point)<threat.rules.party_distance:
			continue
		var nearest: FieldActor = _nearest_target_from_point(point)
		if nearest == null or point.distance_to(nearest.position) < threat.rules.party_distance:
			continue
		var occupied: bool = false
		for enemy: FieldActor in enemies:
			if point.distance_to(enemy.position) < threat.rules.enemy_separation:
				occupied = true
				break
		if occupied or navigation.path_between(point, nearest.position).size() < 2:
			continue
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


func _record_spawn(reason: StringName, point: Vector2, enemy_id: int = -1) -> void:
	_spawn_attempts += 1
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
	if enemy_mode and enemy_id>=0:
		for actor: FieldActor in enemies:
			if actor.actor_id==enemy_id:
				event.enemy_type = actor.enemy_behavior.kind
				event.enemy_health = actor.health
				event.enemy_speed = actor.speed
	spawn_resolved.emit(event)
	print("BH_SPAWN " + JSON.stringify(event))


func _spawn_practice_enemy() -> void:
	# An explicit practice fixture uses the normal attacks, health and cooldowns.
	var offset: Vector2 = Vector2(24, 0) if _spawn_count == 0 else Vector2(220, -40)
	var point: Vector2 = survivors[0].position + offset
	if los_setup != null:
		point = los_setup.blocked_spawn
		_practice_manual_waves = true
	var enemy: FieldActor = _make_actor(true, _spawn_count, point)
	enemies.append(enemy)
	_spawn_count += 1
	if los_setup != null:
		_show_notice("项目验收演练 · 射程进退，不改变正式进度。" if los_range_case else "项目验收演练 · 实墙挡枪，绕开后恢复；不改变正式进度。")
	else:
		_show_notice("交火练习 · 近身来袭可受伤；移动和自动开火规则与出击相同。")


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
		if combat_mode() and String(actor.weapon_definition.id) in ["fire_axe_v1","shotgun_v1"]:
			combat.attack(self,actor,combat_delta)
			if is_paused: return
			continue
		if actor.activity in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING, FieldActor.Activity.RECOVERING]:
			continue
		if actor.magazine!=null and not actor.magazine.can_fire():continue
		var weapon: WeaponDefinition = actor.weapon_definition
		var target: FieldActor = _attack_target(actor)
		if target != null:
			actor.aim = target.position - actor.position
			var decision: AttackRules.Decision = evaluate_attack(actor, target)
			if decision.can_fire:
				if growth_mode and not xp_inputs.has_capacity():
					_reap_defeated_enemies()
					_show_notice("成长账本达到安全容量，已暂停；不能丢弃事件或虚报保存成功。")
					toggle_pause()
					return
				if target.health<=weapon.damage and growth_mode and not is_practice and (not growth_inputs.can_record(actor,target,elapsed) or not xp_inputs.can_record(self,actor,target)):
					_show_notice("成长来源不可提交，已暂停；生命、弹量与开火均未应用。")
					toggle_pause();return
				var recorded: Dictionary={}
				var cooldown_before: float = actor.cooldown
				var health_before: float = target.health
				if not target.take_damage(weapon.damage, (target.position - actor.position).normalized()):continue
				if target.activity == FieldActor.Activity.DOWN:
					kills += 1
					actor.confirmed_kills += 1
					if not is_practice and not loadout_snapshot.is_empty():
						var receipt: Dictionary = growth_inputs.accept_defeat(actor,target,elapsed)
						if not receipt.is_empty():
							if growth_mode and not xp_inputs.accept(self,actor,target,receipt):
								_show_notice("成长来源校验失败，已暂停；本次不会伪造经验。")
								toggle_pause()
								return
							recorded=receipt
						if encounter!=null: encounter.record_defeat(target,receipt)
				actor.cooldown = weapon.shot_interval(actor.trait_shot_factor)
				if actor.magazine!=null:actor.magazine.commit_shot()
				if not recorded.is_empty():growth_input_recorded.emit(recorded)
				actor.visual.show_fire(actor.aim)
				var muzzle: Vector2 = actor.position + actor.visual.muzzle_offset(actor.aim)
				_shot_effect(muzzle, target.position, weapon.damage)
				combat_feedback.emit({"kind": "shot", "actor": actor.actor_id,
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
					"facing": actor.visual.presentation_state()["facing"]})
		else:
			actor.aim = Vector2.ZERO
	for enemy: FieldActor in enemies:
		if power_frozen or enemy.activity == FieldActor.Activity.DOWN or (encounter!=null and encounter.is_boss(enemy)):
			continue
		if combat_mode() and combat.holds(enemy): continue
		var target: FieldActor = _nearest_target(enemy, survivors, 28.0)
		var damage: float = tuning.enemy_damage
		var behavior: EnemyBehavior = enemy.enemy_behavior
		if behavior!=null and behavior.kind==EnemyRules.RUSH and target!=null and not behavior.legal(self,enemy,target,EnemyRules.POLICY.melee_range):
			target = null
		if behavior!=null and behavior.kind==EnemyRules.HEAVY:
			if behavior.state=="windup":
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
			damage = EnemyRules.POLICY.heavy_damage
		if target != null and enemy.cooldown <= 0.0:
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
			enemy.cooldown = tuning.enemy_interval
			if behavior!=null and behavior.kind==EnemyRules.HEAVY:
				behavior.reset(enemy,tuning.enemy_speed)
			enemy.visual.show_attack(direction)
			_hit_effect(target.position, damage, true)
			var feedback: Dictionary = {"kind": "hit", "actor": target.actor_id, "member_id":target.member_id, "health": target.health,
				"applied_damage": health_before - target.health, "elapsed": elapsed}
			if enemy_mode:
				feedback.merge({"enemy_id":enemy.actor_id,"enemy_type":behavior.kind})
			combat_feedback.emit(feedback)
			print("BH_HIT member=%d health=%.0f source=enemy_attack" % [target.member_id, target.health])
	_update_enemy_behaviors(0.0)
	_reap_defeated_enemies()


func _update_enemy_behaviors(delta: float) -> void:
	if not enemy_mode or power_frozen:
		return
	for enemy: FieldActor in enemies:
		if enemy.enemy_behavior!=null and not (encounter!=null and encounter.is_boss(enemy)):
			enemy.enemy_behavior.update(self,enemy,delta)
			enemy.sync_enemy_visual()


func _reap_defeated_enemies() -> void:
	for index: int in range(enemies.size() - 1, -1, -1):
		if enemies[index].activity == FieldActor.Activity.DOWN:
			if enemies[index].enemy_behavior!=null:
				enemies[index].enemy_behavior.cancel(self,enemies[index])
			_corpses.append(enemies[index])
			_corpse_times.append(0.95)
			print("BH_DEFEAT enemy=%d" % enemies[index].actor_id)
			combat_feedback.emit({"kind": "defeat", "actor": enemies[index].actor_id, "elapsed": elapsed})
			enemies.remove_at(index)


func evaluate_attack(actor: FieldActor, target: FieldActor) -> AttackRules.Decision:
	return AttackRules.evaluate(_combatant(actor), _combatant(target),
		actor.position + actor.visual.aimed_shot_offset(target.position - actor.position),
		actor.weapon_definition.shot_range, actor.cooldown, shot_obstacles)


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
	if site == null: return false
	var outdoor: bool = TaskActions.outdoor_site(supply.generated,site.id)
	return actor.health>0 and actor.activity == (FieldActor.Activity.RECOVERING if outdoor else FieldActor.Activity.SEARCHING) and actor.visible == outdoor and (not outdoor or actor.position.distance_to(site.door)<=14.0)


func _clear_dead_worker() -> void:
	for job: Dictionary in search_assignments.ordered():
		var actor: FieldActor = search_member(int(job.member_id))
		if actor != null and (actor.health <= 0 or actor.activity == FieldActor.Activity.DOWN):
			var site: SearchSite = search_site(StringName(job.site_id))
			site.progress = 0.0
			_release_searcher(actor.member_id)
			_search_log("worker_dead",site)


func _update_search(delta: float) -> void:
	_clear_dead_worker()
	for job: Dictionary in search_assignments.ordered():
		if is_paused:
			return
		var actor: FieldActor = search_member(int(job.member_id))
		var site: SearchSite = search_site(StringName(job.site_id))
		var outdoor: bool = TaskActions.outdoor_site(supply.generated,site.id)
		if job.phase == "approach":
			if actor.position.distance_to(site.door) > 14.0:
				if actor._path_index >= actor.path.size():
					var route: PackedVector2Array = navigation.path_between(actor.position,site.door)
					if route.is_empty() or route[-1].distance_to(site.door)>14.0:
						_release_searcher(actor.member_id)
						_show_notice(SearchWorkView.notice("unreachable",site_label(site)))
					else:
						actor.command_path(route)
				continue
			actor.clear_order()
			actor.activity = FieldActor.Activity.RECOVERING if outdoor else FieldActor.Activity.SEARCHING
			actor.visible = outdoor
			search_assignments.begin(actor.member_id)
			if combat_mode():
				combat.cancel_unavailable(self)
			if outdoor and (not exploration_mode() or (site.id==&"cash" and supply.generated.type=="airdrop")):
				_trigger_airdrop()
			_search_log("entered",site)
		if not work_state_matches(actor,site):
			_release_searcher(actor.member_id)
			_search_log("interrupted",site)
			continue
		var prior_progress: float = site.progress
		site.progress += delta / (actor.trait_search_factor * actor.persona_work_factor * (BuildItems.factors(supply.generated.build.slots).work if build_mode() else 1.0))
		if site.progress >= _site_seconds(site):
			if not _complete_search(actor,site):
				site.progress = prior_progress
				return


func _complete_search(actor: FieldActor, site: SearchSite) -> bool:
	if exploration_mode() and site.searched: return false
	if trait_mode and not trait_inputs.events.any(func(e: Dictionary) -> bool: return e.site == String(site.kind)) and not trait_inputs.accept_search(self,actor,site.kind,site.id):
		_show_notice("特性搜集来源未确认，已暂停；不会重复发放收益。")
		toggle_pause()
		return false
	site.searched = true
	if exploration_mode(): site.progress=_site_seconds(site)
	var reward: int = site.reward if not layout.world_data.is_empty() else supply.reward(site.kind)
	if site.kind == &"cash":
		loot += reward
		if not is_practice and (site.weapon if not layout.world_data.is_empty() else supply.has_weapon_sample):
			weapon_loot.append(_site_weapon(site))
	else:
		food_loot += reward
	_release_searcher(actor.member_id)
	site.prop.searched = true
	site.prop.queue_redraw()
	_show_notice("搜集完成 · 携带%s +%d（撤离后带回）" % ["货币" if site.kind == &"cash" else "食物",reward])
	if site.kind == &"cash" and not is_practice and (site.weapon if not layout.world_data.is_empty() else supply.has_weapon_sample):
		_show_notice("获得损坏%s · 回营后入库维修"%WeaponInventory.definition(weapon_loot.back().weapon_id).display_name)
		print("BH_WEAPON_FOUND %s" % JSON.stringify(weapon_loot.back()))
	if power_mode() and site.id==&"cash" and supply.generated.type=="equipment":
		_show_notice("已携带能力样本：%s · 归航确认后入库"%SpecialPowers.POLICY[supply.generated.powers.sample].name if not supply.generated.powers.sample.is_empty() else "特殊能力已集齐。")
	if build_mode() and site.id==&"cash" and not supply.generated.build.drops.is_empty():
		var names: PackedStringArray=[]
		for item: String in supply.generated.build.drops: names.append(BuildItems.definitions()[item].name)
		_show_notice("携带道具："+"、".join(names)+" · 归航确认后入库")
	print("BH_SEARCH completed kind=%s reward=%d cash=%d food=%d" % [site.kind,reward,loot,food_loot])
	search_completed.emit(reward)
	_search_log("completed",site)
	return true


func _finish(evacuated: bool, boarding: Vector2i = Vector2i.ZERO) -> void:
	if phase == Phase.FINISHED:
		return
	FreezeProfile.start({"day":day,"size":layout.world_data.get("size","legacy"),"buildings":_buildings.size(),"sites":sites.size(),"survivors":survivors.size(),"enemies":enemies.size(),"elapsed":elapsed})
	var profile_report: int = FreezeProfile.enter("report.build")
	phase = Phase.FINISHED
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
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
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
		"weapons":weapon_loot.duplicate(true) if evacuated and not is_practice else [],
		"food":food_loot if evacuated else 0,"food_searched":_kind_searched(&"food"),
		"sites_searched":_searched_count(),
		"kills": kills, "searched": _kind_searched(&"cash"), "health": remaining_health, "elapsed": elapsed}
	if not layout.world_data.is_empty(): report.site_facts = WorldSites.facts(self)
	if supply.generated.get("version")==4 or (supply.generated.get("version")==5 or (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9)))): report.task_event=task_event.duplicate(true)
	if build_mode(): report.support=basic_support.snapshot()
	if power_mode(): report.powers=powers.duplicate(true)
	if not is_practice and not loadout_snapshot.is_empty():
		report.growth_inputs = growth_inputs.snapshot(sortie_id,layout.id,elapsed)
	if rescue_mode:
		report.rescue = rescue_target.fact(evacuated) if rescue_target != null else {"rescue_id":RescueState.TARGET,"status":"UNAVAILABLE"}
	if growth_mode:
		report.xp_inputs = xp_inputs.snapshot(self)
	if trait_mode:
		report.trait_inputs = trait_inputs.snapshot(self)
	if field_join_mode:
		report.field_joins = field_joins.duplicate(true)
	if encounter!=null: report.encounter=encounter.snapshot()
	FreezeProfile.leave("report.build", profile_report)
	print("BH_RESULT %s" % JSON.stringify(report))
	finished.emit(report)
	FreezeProfile.finish()


func _shot_effect(from: Vector2, to: Vector2, damage: float) -> void:
	var line: Line2D = Line2D.new()
	line.points = PackedVector2Array([from, to + Vector2.UP * AttackRules.HIT_HEIGHT])
	line.width = 1.5
	line.default_color = Color("f1d5a1")
	_effects.add_child(line)
	var tween: Tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.09)
	tween.tween_callback(line.queue_free)
	_hit_effect(to, damage, false)


func _hit_effect(to: Vector2, damage: float, survivor_hit: bool) -> void:
	var impact: Node2D = Node2D.new()
	impact.position = to + Vector2(0, -30)
	_effects.add_child(impact)
	for index: int in range(4):
		var spark: Line2D = Line2D.new()
		var direction: Vector2 = Vector2.RIGHT.rotated(float(index) * TAU / 4.0 + 0.4)
		spark.points = PackedVector2Array([direction * 4.0, direction * 9.0])
		spark.width = 2.0
		spark.default_color = Color("f1ac80") if survivor_hit else Color("f5dda0")
		impact.add_child(spark)
	var fade: Tween = impact.create_tween()
	fade.tween_property(impact, "modulate:a", 0.0, 0.18)
	fade.tween_callback(impact.queue_free)
	var label: Label = Label.new()
	var amount_text: String = str(int(damage)) if is_equal_approx(damage,roundf(damage)) else "%.2f" % damage
	label.text = ("−" if survivor_hit else "") + amount_text
	label.add_theme_color_override("font_color", Color("f8b491") if survivor_hit else Color("f1dfbd"))
	label.add_theme_color_override("font_outline_color", Color("142d36"))
	label.add_theme_constant_override("outline_size", 3)
	label.position = to + Vector2(-38 if survivor_hit else 8, -108)
	_effects.add_child(label)
	var popup: Tween = label.create_tween()
	popup.tween_property(label, "position:y", label.position.y - 18.0, 0.5)
	popup.tween_callback(label.queue_free)


func _make_ui() -> void:
	_hud = ExpeditionHud.new()
	_hud.player_mode = player_mode
	_hud.ui_theme = ui_theme
	_hud.pause_requested.connect(toggle_pause)
	_hud.extraction_requested.connect(request_bus_action)
	_hud.help_changed.connect(func(expanded: bool) -> void: help_changed.emit(expanded))
	add_child(_hud)
	_hud.view.objective_locate_requested.connect(locate_objective)
	if (layout.world_data.get("version")==3 or layout.world_data.get("version")==4 or layout.world_data.get("version")==5):
		_hud.view.place_help_above_lane()
	if battle_survival:
		drill_panel = BattleDrillPanel.new()
		drill_panel.expedition = self
		drill_panel.theme = ui_theme
		_hud.view.add_child(drill_panel)
		drill_panel.visible = not player_mode
	if build_mode():
		support_panel=BasicSupportPanel.new()
		support_panel.position=Vector2(16,160)
		support_panel.heal_requested.connect(request_heal)
		support_panel.airstrike_requested.connect(toggle_support_aim)
		_hud.view.add_child(support_panel)
		support_aim=BasicSupportAim.new()
		_effects.add_child(support_aim)
	if power_mode():
		power_panel=PowerSlotPanel.new()
		power_panel.position=Vector2(16,300)
		power_panel.activation_requested.connect(request_power)
		_hud.view.add_child(power_panel)
		power_view=PowerEffectView.new()
		_effects.add_child(power_view)
	_update_ui()


func _show_notice(message: String) -> void:
	_notice_text = message
	_notice_clock = 7.0


func _update_ui() -> void:
	_present_support()
	_present_power()
	if _hud == null:
		return
	if _readouts != null:
		if phase == Phase.FINISHED:
			_readouts.hide()
		else:
			_update_member_display()
			_readouts.update_members(survivors, get_global_transform_with_canvas(), get_viewport_rect().size)
	var timing: Dictionary = time_status()
	var boarding: Dictionary = boarding_status(phase == Phase.BOARDING)
	var engine_text: String = "发动引擎 →"
	if phase == Phase.ENGINE:
		engine_text = "发动引擎 %d" % timing["engine_seconds"]
	elif phase == Phase.BOARDING:
		engine_text = "等待幸存者"
	elif elapsed < tuning.bus_ready_seconds:
		engine_text = "巴士准备 %d 秒" % timing["bus_seconds"]
	if is_practice:
		engine_text = "结束交火练习 →"
	var members: Array[Dictionary] = []
	var activities: Array[String] = ["警戒", "移动", "搜集中", "倒地", "回收中"]
	for actor: FieldActor in survivors:
		var assigned_site: SearchSite = member_site(actor.member_id)
		var status: String = activities[actor.activity]
		if assigned_site != null:
			status = SearchWorkView.actor_status(search_assignments.phase_for(actor.member_id),site_label(assigned_site),TaskActions.outdoor_site(supply.generated,assigned_site.id))
		members.append({"id":actor.member_id,"label":"%s · %s" % [actor.call_sign, "阵亡" if actor.permanent_death else status],
			"call_sign":actor.call_sign,"status":_weapon_status(actor,status),"ammo":_ammo_text(actor),"detail":("%s · %s"%[status,assigned_site.prop.title] if assigned_site!=null else status),
			"colour":SurvivorRoster.definition_by_id(String(actor.definition_id)).colour,
			"hp":actor.health,"max_hp":actor.max_health})
	if growth_mode:
		for member: Dictionary in members:
			member.level = SurvivorRoster.member(_setup_crew,int(member.id)).growth.level
	if persona_mode():
		for member: Dictionary in members:
			member.persona=PersonaViewModel.field(self,search_member(int(member.id)),String(member.status))
	var pending: PackedStringArray = []
	if growth_mode:
		for actor: FieldActor in survivors:
			pending.append("%02d +%d" % [actor.member_id,0 if battle_drill or actor.health <= 0 else xp_inputs.pending(actor.member_id)])
	var xp_text: String = "本次经验（归航后生效）："+" / ".join(pending) if growth_mode else ""
	if not weapon_loot.is_empty():xp_text+="\n携带："+WeaponInventory.loot_description(weapon_loot[0])
	_hud.refresh({
		"exploration_objectives":ExplorationSites.objective_rows({"type":supply.generated.type,"objective":supply.generated.objective,"optional_objectives":supply.generated.exploration.optional_objectives},WorldSites.facts(self),rescue_target!=null and rescue_target.status=="IN_FIELD_JOINED" and rescue_target.npc.health>0) if exploration_mode() else [],
		"objective":TaskActions.hud(self),
		"mission_title":("交火练习" if is_practice else mission_title) if los_setup == null else mission_title, "members":members,
		"can_extract":phase != Phase.FINISHED if is_practice else phase == Phase.ACTIVE and elapsed >= tuning.bus_ready_seconds,
		"boarding":boarding,
		"engine_running":not is_practice and phase == Phase.ENGINE,
		"can_gather":not is_practice and phase == Phase.BOARDING and boarding.required > 0,
		"day": day, "seconds": timing["sortie_seconds"], "time_fraction": timing["sortie_fraction"],
		"paused": is_paused, "cash": initial_cash, "loot": loot,
		"food":initial_food,"food_loot":food_loot,"sites_searched":_searched_count(),
		"sites_total":sites.filter(func(site: SearchSite) -> bool: return supply.supports(site.kind)).size(),
		"has_food_source":supply.supports(&"food"),
		"route_hint":layout.route_hint,
		"enemy_mode":enemy_mode,
		"weapon_loot":weapon_loot.size(),
		"searched": searched, "kills": kills, "engine": engine_text,
		"notice": _notice_text, "notice_visible": _notice_clock > 0.0,
		"practice": is_practice,
		"threat":threat_status(),
	})
	if drill_panel != null:
		drill_panel.refresh()
	for site: SearchSite in sites:
		var worker: FieldActor = search_member(search_assignments.member_for(String(site.id)))
		if site.prop is ExplorationProp:
			var faded: bool=survivors.any(func(actor: FieldActor) -> bool: return actor.visible and actor.health>0 and actor.position.y<site.prop.position.y and actor.position.distance_to(site.prop.position)<105.0)
			(site.prop as ExplorationProp).present({"searched":site.searched,"progress":site.progress},worker.member_id if worker!=null else 0,worker.call_sign if worker!=null else "",faded)
		site.prop.searched = site.searched
		var work_phase: String = search_assignments.phase_for(worker.member_id) if worker != null else ""
		var fraction: float = site.progress / _site_seconds(site)
		if not site.prop.loot_category.is_empty():
			site.prop.present_loot(worker.member_id if worker != null else 0, worker.call_sign if worker != null else "", work_phase, fraction)
		else:
			var text: String = SearchWorkView.building_text(worker.member_id, worker.call_sign, work_phase, TaskActions.outdoor_site(supply.generated,site.id)) if worker != null else ""
			site.prop.update_work(worker.actor_id if worker != null else -1,
				fraction, worker != null and work_state_matches(worker,site), worker.call_sign if worker != null else "", text)


func _update_member_display() -> void:
	var both_visible: bool = survivors.size() == 2 and survivors[0].visible and survivors[1].visible and living_count() == 2
	var separation: float = survivors[0].position.distance_to(survivors[1].position) if survivors.size() == 2 else 0.0
	var shift: float = clampf(1.0 - separation / 56.0, 0.0, 1.0) * 12.0 if both_visible else 0.0
	for index: int in range(survivors.size()):
		survivors[index].visual.position.x = shift * (-1.0 if index == 0 else 1.0)

	for building: FieldProp in _buildings:
		var hidden_friend: bool = false
		for actor: FieldActor in survivors:
			if actor.visible and building.obscures(actor.position):
				hidden_friend = true
		building.show_behind_roof(hidden_friend)


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
	return sites.any(func(site: SearchSite) -> bool: return site.kind==kind and site.searched)

func _searched_count() -> int:
	return sites.filter(func(site: SearchSite) -> bool: return site.searched).size()

func _clicked_site(point: Vector2) -> bool:
	# Foreground object art takes precedence over the broad building facade hit.
	var candidates: Array[SearchSite]=[]
	if exploration_mode():
		for site: SearchSite in sites:
			if site.prop is ExplorationProp: candidates.append(site)
	for site: SearchSite in sites:
		if not candidates.has(site): candidates.append(site)
	if layout.world_data.get("version")==5:
		candidates.sort_custom(func(a:SearchSite,b:SearchSite)->bool:return a.prop.position.y>b.prop.position.y if a.prop.position.y!=b.prop.position.y else String(a.id)<String(b.id))
	for site: SearchSite in candidates:
		if site.hit.has_point(point):
			if layout.world_data.get("version")==5 and site.prop.world_asset and not site.prop.scaled_hit_contains(point):continue
			if not site.searched: request_search(site.id)
			else: command_move(site.door)
			return true
	return false

func _make_world_buildings() -> void:
	if (layout.world_data.get("version")==3 or layout.world_data.get("version")==4 or layout.world_data.get("version")==5):
		for wall: Rect2 in layout.fences:
			if layout.world_data.get("version")==5:
				var stone: WorldgenFurniture=WorldgenFurniture.new()
				stone.detail={"kind":"wall","width":wall.size.x};stone.position=Vector2(wall.get_center().x,wall.end.y);_sort.add_child(stone)
				continue
			var barrier: NeighborhoodWall=NeighborhoodWall.new()
			barrier.footprint=wall;barrier.position=wall.position+Vector2(0,wall.size.y);_sort.add_child(barrier)
	if (layout.world_data.get("version")==3 or layout.world_data.get("version")==4 or layout.world_data.get("version")==5):
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
				var scenery: WorldgenFurniture=WorldgenFurniture.new()
				scenery.detail=detail;scenery.position=WorldLayout.point(detail.point);_sort.add_child(scenery)
	var props: Dictionary = {}
	for entity: Dictionary in layout.world_data.entities:
		var block: Rect2 = WorldLayout.rect(entity.rect)
		var definition: Dictionary = WorldgenArt.definition(entity) if layout.world_data.get("version")==5 else NeighborhoodArt.definition(entity.archetype) if (layout.world_data.get("version")==3 or layout.world_data.get("version")==4) else BuildingLibrary.definition(entity.archetype)
		var building: FieldProp = FieldProp.new()
		building.facade = definition.texture
		if definition.has("native_size"):
			building.native_size=definition.native_size
			building.render_anchor=definition.origin
			building.reference_width=definition.reference_width
			building.street_sign=definition.get("street_sign","")
			building.sign_rect=definition.get("sign_rect",Rect2())
		building.soft_contact=layout.world_data.get("art_revision")==3
		if layout.world_data.get("version")==5:
			building.modulate=[Color.WHITE,Color(0.92,0.97,1.0),Color(1.0,0.97,0.9),Color.WHITE][int(entity.variant)]
		building.world_asset = true
		if (layout.world_data.get("version")==3 or layout.world_data.get("version")==4 or layout.world_data.get("version")==5):
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
			site.hit=Rect2(site.prop.position-Vector2(site.prop.front_width/2,280),Vector2(site.prop.front_width,340)) if (layout.world_data.get("version")==3 or layout.world_data.get("version")==4 or layout.world_data.get("version")==5) else Rect2(WorldLayout.rect(entity.rect).position-Vector2(0,160),WorldLayout.rect(entity.rect).size+Vector2(0,220))
			if layout.world_data.get("version")==5: site.hit=site.prop.scaled_hit_bounds()
			site.prop.primary_target=supply.generated.get("objective",{}).get("site_ids",[]).has(def.id)
		site.prop.reward_hint=("货币" if site.kind==&"cash" else "食物")+" +%d"%site.reward+(" / 武器" if site.weapon else "")
		if exploration_mode():
			site.prop.primary_target=supply.generated.objective.site_ids.has(def.id)
			site.prop.reward_hint=("货币" if site.kind==&"cash" else "食物")+" +%d"%site.reward
		if build_mode() and site.id==&"cash" and supply.generated.type=="equipment": site.prop.reward_hint+=" / 道具%d件"%supply.generated.build.drops.size() if not supply.generated.build.drops.is_empty() else " / 道具已集齐"
		if exploration_mode() and not crate:
			var category: String = "果树" if def.source == "fruit_tree" else "车辆" if object_site else "建筑"
			var anchor: Vector2 = Vector2(0, 5) if object_site else Vector2(site.prop.door_offset, 43)
			site.prop.configure_loot_badge(category, anchor)
		sites.append(site)
		if site.id==&"cash": _cash_site=site; _shop=site.prop
		if site.id==&"food": _food_site=site


func _site_seconds(site: SearchSite) -> float:
	return site.seconds if supply.generated.get("version")==4 or (supply.generated.get("version")==5 or (supply.generated.get("version")==6 or (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9)))) else tuning.search_seconds


func _trigger_airdrop() -> void:
	if task_event.started: return
	task_event.started=true
	for index: int in range(int(TaskActions.PARAMETERS.reinforcements)):
		if enemies.size()>=threat.rules.enemy_cap:
			_record_spawn(&"capacity",Vector2.INF)
			task_event.resolutions.append({"reason":"capacity","enemy_id":-1})
		else: task_event.resolutions.append(_spawn_enemy(EnemyRules.NORMAL,search_site(&"cash").door))
	print("BH_TASK_EVENT "+JSON.stringify(task_event))
	_show_notice("空投信标已启动 · 留意来袭；回收后可直接集合归航。")


func _site_weapon(site: SearchSite) -> Dictionary:
	for definition: Dictionary in supply.generated.get("sites",[]):
		if definition.id==String(site.id):return WeaponInventory.site_reward(sortie_id,supply.generated,definition,WeaponState.is_family(field_departure))
	return WeaponInventory.reward(sortie_id,WeaponState.is_family(field_departure))


func _ammo_text(actor: FieldActor) -> String:
	if CombatEquipment.melee(String(actor.weapon_definition.id)): return "消防斧 · 近战"
	if actor.magazine==null:return "%s · 旧规则"%actor.weapon_definition.display_name if actor.weapon_definition!=null else ""
	# Keep the task destination readable; reload feedback uses the ammunition line.
	if has_search_job(actor.member_id) and actor.magazine.reloading:
		return "换弹暂停" if actor.activity in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING] else "换弹 %.1fs"%actor.magazine.remaining
	return "%s %d/%d · ∞"%[actor.weapon_definition.display_name,actor.magazine.rounds,actor.magazine.capacity()]


func _weapon_status(actor: FieldActor, action: String) -> String:
	if actor.activity==FieldActor.Activity.DOWN:return "阵亡" if actor.permanent_death else "倒地"
	if has_search_job(actor.member_id): return action
	if actor.magazine!=null and actor.magazine.reloading:
		return "%s · 换弹暂停"%action if actor.activity in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING] else "%s · 换弹%.1fs"%[action,actor.magazine.remaining]
	return action

func combat_mode() -> bool:
	return (supply.generated.get("version")==8 or supply.generated.get("version")==9)

func build_mode() -> bool:
	return (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9))

func apply_build(actor: FieldActor, profile: Dictionary = {}, item: Dictionary = {}) -> void:
	var factors: Dictionary=BuildItems.factors(supply.generated.build.slots)
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
	var paused: bool=is_paused
	is_paused=true
	_clear_dead_worker()
	# Toxic/boss damage happens after the combat phase's ordinary cancellation.
	if combat_mode(): combat.cancel_unavailable(self)
	_reap_defeated_enemies()
	var value: Dictionary=SortieSnapshot.capture(self)
	is_paused=paused
	return value

func request_heal() -> bool:
	if not support_available(): return false
	var before: Dictionary=support_world()
	var plan: Dictionary=BuildAuthority.plan_heal(before)
	if plan.is_empty(): return false
	return _accept_support(before,basic_support.request("heal",plan))

func request_airstrike(point: Vector2) -> bool:
	if not support_available(): return false
	var before: Dictionary=support_world()
	var plan: Dictionary=BuildAuthority.plan_airstrike(before,point)
	if plan.is_empty(): return false
	var accepted: bool=_accept_support(before,basic_support.request("airstrike",plan))
	if accepted: support_aiming=false
	return accepted

func _accept_support(before: Dictionary, request: Dictionary) -> bool:
	if request.is_empty() or not support_commit.is_valid(): return false
	var result: Dictionary=support_commit.call(before,request)
	if result.get("error",ERR_UNAVAILABLE)!=OK:
		pending_support={"before":before,"request":request}
		print("BH_SUPPORT "+JSON.stringify({"kind":request.kind,"status":"PENDING","reason":result.get("reason",""),"sequence":before.support.sequence,"elapsed":before.sim.elapsed}))
		is_paused=true
		support_aiming=false
		_show_notice("支援尚未确认，已暂停；请重试或暂存继续。"+String(result.get("reason","")))
		_update_ui()
		return false
	pending_support={}
	var after: Dictionary=result.world
	print("BH_SUPPORT "+JSON.stringify({"kind":request.kind,"status":"ACCEPTED","sequence_before":before.support.sequence,"sequence":after.support.sequence,"cooldowns":after.support.cooldowns,"kills_before":before.sim.kills,"kills":after.sim.kills,"facts":after.support.accepted.back().facts,"elapsed":after.sim.elapsed}))
	# All fallible validation and I/O preceded this visible state replacement.
	for enemy: FieldActor in enemies: enemy.free()
	enemies.clear()
	var issue: String=SortieSnapshot.apply(self,after)
	assert(issue.is_empty(),issue)
	is_paused=false
	if request.kind=="airstrike": support_aim.impact(SortieSnapshot._vec(request.payload.point),request.payload.radius)
	_show_notice("治疗已确认" if request.kind=="heal" else "空袭已确认 · 本次击败来源已保存")
	_update_ui()
	return true

func toggle_support_aim() -> void:
	if support_available() and basic_support.snapshot().cooldowns.airstrike==0.0:
		support_aiming=not support_aiming

func _support_input(event: InputEvent) -> bool:
	if not build_mode(): return false
	if _hud.view.persona_details.visible and event is InputEventKey and event.keycode in [KEY_Q,KEY_E,KEY_3]: return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_3 and power_mode():
		if get_viewport().gui_get_focus_owner()==null: request_power()
		return true
	if event is InputEventKey and event.pressed and not event.echo and get_viewport().gui_get_focus_owner()==null:
		if support_aiming and event.keycode in [KEY_ESCAPE,KEY_E]: support_aiming=false; return true
		if event.keycode==KEY_Q: request_heal(); return true
		if event.keycode==KEY_E: toggle_support_aim(); return true
	if support_aiming and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT: support_aiming=false; return true
		if event.button_index==MOUSE_BUTTON_LEFT:
			request_airstrike(get_global_transform_with_canvas().affine_inverse()*event.position)
			return true
	return false

func _present_support() -> void:
	if not build_mode() or support_panel==null: return
	if not support_available(): support_aiming=false
	var state: Dictionary=basic_support.snapshot()
	var members: Array[Dictionary]=[]
	for actor: FieldActor in survivors: members.append({"member_id":actor.member_id,"health":actor.health,"max_health":actor.max_health,"present":actor.activity!=FieldActor.Activity.DOWN})
	var plan: Dictionary=basic_support.plan_heal(members,BuildItems.factors(supply.generated.build.slots).heal)
	var heal_text: String="Q 治疗 · %.1fs"%state.cooldowns.heal if state.cooldowns.heal>0 else "Q 治疗 · 队员%d +%.0fHP"%[plan.member_id,plan.amount] if not plan.is_empty() else "Q 治疗 · 无受伤存活者"
	var strike_text: String="E 空袭 · %.1fs"%state.cooldowns.airstrike if state.cooldowns.airstrike>0 else "左键确认 · 右键/Esc取消" if support_aiming else "E 空袭 · 就绪"
	if not support_available(): heal_text="治疗 · 当前阶段不可用"; strike_text="空袭 · 当前阶段不可用"
	support_panel.present(heal_text,strike_text,support_available() and state.cooldowns.heal==0 and not plan.is_empty(),support_available() and state.cooldowns.airstrike==0)
	var point: Vector2=get_global_mouse_position()
	var legal: bool=not support_plan_airstrike(point).is_empty() if support_aiming else false
	if support_aiming:
		var caller: FieldActor=null
		for actor: FieldActor in survivors:
			if actor.health>0 and actor.visible and actor.activity not in [2,3,4] and (caller==null or actor.position.distance_to(point)<caller.position.distance_to(point) or (actor.position.distance_to(point)==caller.position.distance_to(point) and actor.member_id<caller.member_id)): caller=actor
		if caller!=null: support_aim.present_caller(caller.position)
	support_aim.present(point,BasicSupport.POLICY.airstrike_radius*BuildItems.factors(supply.generated.build.slots).blast,legal,support_aiming)

func support_plan_airstrike(point: Vector2) -> Dictionary:
	var view: Dictionary={"version":10,"generated":supply.generated,"survivors":[],"enemies":[]}
	for actor: FieldActor in survivors:
		view.survivors.append({"state":{"member_id":actor.member_id,"health":actor.health,"visible":actor.visible,"activity":actor.activity,"position":[actor.position.x,actor.position.y]}})
	for enemy: FieldActor in enemies:
		view.enemies.append({"state":{"actor_id":enemy.actor_id,"health":enemy.health,"position":[enemy.position.x,enemy.position.y]}})
	return BuildAuthority.plan_airstrike(view,point,layout)

func exploration_mode() -> bool:
	return supply.generated.get("version")==9

func persona_mode() -> bool:
	return supply.generated.has("persona")

func power_mode() -> bool:
	return supply.generated.has("powers")

func refresh_power_factors() -> void:
	var factor: float=SpecialPowers.move_factor(powers,elapsed) if power_mode() else 1.0
	power_frozen=SpecialPowers.frozen(powers,elapsed) if power_mode() else false
	for actor: FieldActor in survivors: actor.power_move_factor=factor
	for actor: FieldActor in enemies: actor.motion_locked=power_frozen

func request_power() -> bool:
	if not power_mode() or not support_available() or not pending_power.is_empty() or not survivors.any(func(actor:FieldActor)->bool:return actor.health>0): return false
	var request: Dictionary=SpecialPowers.request(powers)
	if request.is_empty(): return false
	return _accept_power(support_world(),request)

func _accept_power(before: Dictionary, request: Dictionary) -> bool:
	if not power_commit.is_valid(): return false
	var result: Dictionary=power_commit.call(before,request)
	if result.get("error",ERR_UNAVAILABLE)!=OK:
		pending_power={"before":before,"request":request}
		print("BH_POWER "+JSON.stringify({"status":"PENDING","reason":result.get("reason",""),"at":elapsed}))
		is_paused=true
		support_aiming=false
		_show_notice("能力尚未确认，已暂停；解除故障后继续重试。"+String(result.get("reason","")))
		_update_ui()
		return false
	pending_power={}
	powers=result.world.powers.duplicate(true)
	is_paused=false
	refresh_power_factors()
	_show_notice("%s已生效 · 今日一次已保存"%SpecialPowers.POLICY[request.ability_id].name)
	print("BH_POWER "+JSON.stringify({"status":"ACCEPTED","event":powers.accepted[0],"elapsed":elapsed}))
	_update_ui()
	return true

func _present_power() -> void:
	if not power_mode() or power_panel==null: return
	var id: String=supply.generated.powers.slot
	var remaining: float=SpecialPowers.remaining(powers,elapsed)
	if _power_effect_visible and remaining==0.0: _show_notice("特殊能力效果结束 · 今日已用")
	_power_effect_visible=remaining>0.0
	var status: String="营地装配 · 每日一次" if id.is_empty() else "持续 %.1f 秒"%remaining if remaining>0 else "今日已用" if not powers.accepted.is_empty() else "就绪 · 每日一次"
	power_panel.present("特殊能力空槽" if id.is_empty() else SpecialPowers.POLICY[id].name,status,remaining,float(SpecialPowers.POLICY[id].duration) if not id.is_empty() else 1.0,support_available() and not SpecialPowers.request(powers).is_empty(),id)
	var members: Array[Dictionary]=[]
	var foes: Array[Dictionary]=[]
	for actor: FieldActor in survivors: members.append({"position":actor.position,"moving":actor.activity==FieldActor.Activity.MOVING,"alive":actor.health>0 and actor.visible})
	for actor: FieldActor in enemies: foes.append({"position":actor.position,"moving":actor.activity==FieldActor.Activity.MOVING,"alive":actor.health>0 and actor.visible})
	power_view.present(members,foes,id=="speed_boost_v1" and remaining>0,id=="map_freeze_v1" and remaining>0,elapsed)


func locate_objective(id: String) -> void:
	if not exploration_mode(): return
	var rows: Array[Dictionary]=ExplorationSites.objective_rows({"type":supply.generated.type,"objective":supply.generated.objective,"optional_objectives":supply.generated.exploration.optional_objectives},WorldSites.facts(self),rescue_target!=null and rescue_target.status=="IN_FIELD_JOINED" and rescue_target.npc.health>0)
	var target: Vector2=Vector2.INF
	var target_prop: FieldProp
	for row: Dictionary in rows:
		if row.id!=id: continue
		var pending: Array[String]=[]
		for site_id: String in row.site_ids:
			var site: SearchSite=search_site(StringName(site_id))
			if site!=null and not site.searched: pending.append(site_id)
		if pending.is_empty(): pending.assign(row.site_ids)
		if pending.is_empty():
			target=layout.rescue_point
		else:
			var index: int=int(_objective_cursors.get(id,0))%pending.size()
			var site: SearchSite = search_site(StringName(pending[index]))
			target = site.door
			target_prop = site.prop
			_objective_cursors[id]=index+1
		break
	if not target.is_finite(): return
	camera.position=target
	camera._clamp_position()
	camera.force_update_scroll()
	if _locate_marker==null:
		_locate_marker=Node2D.new()
		_effects.add_child(_locate_marker)
		_locate_ring = Line2D.new()
		_locate_ring.width=3.0; _locate_ring.default_color=Color("f2c47c")
		for i: int in range(33):_locate_ring.add_point(Vector2.from_angle(TAU*i/32.0)*34.0)
		_locate_marker.add_child(_locate_ring)
		_locate_label = Label.new()
		_locate_label.text="目标位置"; _locate_label.position=Vector2(-30,-60); _locate_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_locate_label.add_theme_font_size_override("font_size",16)
		_locate_label.add_theme_color_override("font_color",Color("ffe5a7"))
		_locate_marker.add_child(_locate_label)
	var has_badge: bool = target_prop != null and not target_prop.loot_category.is_empty()
	_locate_label.visible = not has_badge
	# Keep the pulse at the entrance without painting across its two-line badge.
	_locate_ring.position.y = 38.0 if has_badge and not target_prop is ExplorationProp else 0.0
	if _locate_tween!=null: _locate_tween.kill()
	_locate_marker.position=target
	_locate_marker.modulate.a=1.0
	_locate_tween=create_tween()
	_locate_tween.tween_interval(0.6)
	_locate_tween.tween_property(_locate_marker,"modulate:a",0.0,1.3)
