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
var search_actor: FieldActor
var goal: Vector2 = Vector2.ZERO
var initial_cash: int = 53
var initial_food: int = 2
var camp_rules: CampRules = preload("res://src/features/camp/camp_rules.tres")
var supply: MissionSupply = preload("res://src/features/camp/supermarket.tres")
var day: int = 2
var mission_title: String = "旧街补给点"
var starting_health: Array[float] = [200.0, 200.0]
var crew_snapshot: Array[Dictionary] = []
var participants_snapshot: Array[Dictionary] = []
var setup_problem: String = ""
var _setup_crew: Array[Dictionary] = []
var ui_theme: Theme
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
var _active_site: SearchSite


func _ready() -> void:
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
	if trait_mode:
		trait_inputs.configure(growth_binding)
	if is_practice and participants_snapshot.size() != 2:
		setup_problem = "当前独立练习仅支持原双人配置"
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	layout = supply.layout
	_cash_site.door = layout.cash_door
	_food_site.door = layout.food_door
	navigation.configure(layout.blockers())
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
	add_child(camera)
	camera.pan_by(layout.camera_start-camera.position)
	_sort = Node2D.new()
	_sort.name = "ActorsAndProps"
	_sort.y_sort_enabled = true
	add_child(_sort)
	_effects = Node2D.new()
	add_child(_effects)
	var bus: Sprite2D = Sprite2D.new()
	bus.texture = BusTexture
	bus.offset = Vector2(0, -128)
	bus.scale = Vector2.ONE * (240.0 / 448.0)
	bus.position = layout.bus_foot()
	_sort.add_child(bus)
	_shop = _make_building(layout.cash_block,layout.cash_title,FieldProp.ShopTexture,false,false)
	_shop.searchable = supply.supports(&"cash")
	_shop.reward_hint = "货币 +%d / 武器" % supply.cash_reward
	_cash_site.prop = _shop
	var second: FieldProp = _make_building(layout.food_block,layout.food_title,
		preload("res://assets/m401/market.png") if supply.supports(&"food") else preload("res://assets/m402/rowhouse.png"),supply.supports(&"food"),not supply.supports(&"food"))
	second.searchable = supply.supports(&"food")
	second.reward_hint = "食物 +%d" % supply.food_reward
	_food_site.prop = second
	for block: Rect2 in layout.residences:
		_make_building(block,"柳巷住宅",preload("res://assets/m402/rowhouse.png"),false,true)
	for block: Rect2 in layout.fences:
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
		survivors.append(actor)
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
	print("BH_SORTIE build=%s start day=%d members=%d" % [BUILD_ID, day, survivors.size()])


func _physics_process(delta: float) -> void:
	step(delta)


func _draw() -> void:
	if search_actor != null and search_actor.activity == FieldActor.Activity.MOVING:
		draw_dashed_line(search_actor.position, _active_site.door, Color("e3c879"), 1.5, 8.0)
	if phase == Phase.BOARDING:
		draw_circle(layout.bus_door, tuning.boarding_radius, Color(0.9, 0.75, 0.3, 0.2))
		draw_arc(layout.bus_door, tuning.boarding_radius, 0.0, TAU, 48, Color("e3c879"), 2.0)
	if goal != Vector2.ZERO and phase != Phase.FINISHED:
		draw_arc(goal, 13.0, 0.0, TAU, 24, Color("b3e8d9"), 2.0, true)
		draw_line(goal - Vector2(6, 0), goal + Vector2(6, 0), Color("b3e8d9"), 2.0)
		for actor: FieldActor in survivors:
			if actor.activity == FieldActor.Activity.MOVING and actor != search_actor:
				draw_dashed_line(actor.position, goal, Color(0.8, 0.95, 0.91, 0.4), 1.0, 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.FINISHED:
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
		elif supply.supports(&"cash") and layout.hit_area(&"cash").has_point(point):
			if searched:
				command_move(point)
			else:
				request_search()
		elif supply.supports(&"food") and layout.hit_area(&"food").has_point(point):
			if _food_site.searched:
				command_move(point)
			else:
				request_search(&"food")
		elif layout.bus_block.grow(18.0).has_point(point):
			request_extraction()
		elif FieldNavigation.BOUNDS.has_point(point):
			command_move(point)
		get_viewport().set_input_as_handled()


func step(delta: float) -> void:
	if phase == Phase.FINISHED or is_paused or suspend_sealed:
		_update_ui()
		return
	var started_usec: int = Time.get_ticks_usec()
	elapsed += delta
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
		_update_enemy_paths()
		_ai_clock = 0.7
	var occupants: Array[FieldActor] = survivors + enemies
	var previous: Dictionary = {}
	for actor: FieldActor in occupants: previous[actor] = actor.position
	for actor: FieldActor in survivors:
		actor.advance(delta,false,false)
	last_contact_metrics = FieldContacts.move(survivors,occupants,navigation,delta,true)
	_update_enemy_behaviors(delta)
	_update_enemy_paths(true)
	for enemy: FieldActor in enemies:
		enemy.advance(delta,false,false)
	var enemy_motion: Dictionary = FieldContacts.move(enemies,occupants,navigation,delta,false,_hold_enemy_approach)
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
	_update_enemy_behaviors(0.0)
	_update_combat()
	if is_paused:
		_update_ui()
		return
	if living_count() == 0:
		_finish(false)
	elif phase == Phase.BOARDING:
		var boarding: Dictionary = boarding_status()
		if boarding.arrived == boarding.required and (rescue_target == null or rescue_target.status != "RESCUED" or rescue_target.delivered()):
			_finish(true)
	elif phase == Phase.ENGINE:
		_engine_clock -= delta
		if _engine_clock <= 0.0:
			phase = Phase.BOARDING
			_show_notice("引擎已发动 · 点击「集合至巴士」，或左键黄色区域。")
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
	actor.clear_order()
	if trait_mode:
		TraitRules.apply(actor,profile,tuning.survivor_speed)
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
	if not field_join_error.is_empty():
		return
	if rescue_target != null: rescue_target.cancel()
	if phase == Phase.FINISHED:
		return
	goal = point
	for index: int in range(survivors.size()):
		var actor: FieldActor = survivors[index]
		if actor == search_actor or actor.activity == FieldActor.Activity.DOWN:
			continue
		_move_to_group_goal(actor)
	queue_redraw()
	print("BH_ORDER move %s" % point)


func request_search(kind: StringName = &"cash") -> void:
	if not field_join_error.is_empty():
		return
	if rescue_target != null: rescue_target.cancel()
	var site: SearchSite = search_site(kind)
	if phase == Phase.FINISHED or site == null or site.searched or not supply.supports(kind):
		return
	if search_actor != null:
		var cancelling_same: bool = site == _active_site
		_release_searcher()
		if cancelling_same:
			_show_notice("搜集已取消 · 队员返回当前队伍目标。")
			print("BH_SEARCH cancelled kind=%s progress=%.2f" % [kind, site.progress])
			return
	var closest: float = INF
	for actor: FieldActor in survivors:
		if actor.activity == FieldActor.Activity.DOWN:
			continue
		var distance: float = actor.position.distance_squared_to(site.door)
		if distance < closest:
			closest = distance
			search_actor = actor
	if search_actor != null:
		_active_site = site
		search_actor.command_path(navigation.path_between(search_actor.position, site.door))
		_show_notice("队员 %d 前往搜集，其余队员留守。" % search_actor.member_id)
		queue_redraw()
		print("BH_SEARCH assigned=%d kind=%s" % [search_actor.actor_id,kind])


func search_site(kind: StringName) -> SearchSite:
	if kind == &"cash":
		return _cash_site
	if kind == &"food":
		return _food_site
	return null


func request_extraction() -> void:
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


func boarding_status() -> Dictionary:
	var required: int = 0
	var arrived: int = 0
	var working: int = 0
	for actor: FieldActor in survivors:
		if actor.activity == FieldActor.Activity.DOWN:
			continue
		required += 1
		if actor == search_actor:
			working += 1
		elif actor.position.distance_to(layout.bus_door) <= tuning.boarding_radius:
			arrived += 1
	return {"arrived":arrived, "required":required, "working":working,
		"ordered":goal == layout.bus_door}


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
		var start: Vector2 = _active_site.door if actor == search_actor else actor.position
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


func _release_searcher() -> void:
	var released: FieldActor = search_actor
	search_actor = null
	_active_site = null
	released.clear_order()
	if goal != Vector2.ZERO:
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
	actor.max_health = tuning.enemy_health if enemy else tuning.survivor_health
	if growth_mode and not enemy and not profile.is_empty():
		actor.max_health = GrowthRules.maximum(profile)
	actor.health = actor.max_health
	if enemy and enemy_mode:
		actor.enemy_behavior = EnemyBehavior.new()
		actor.enemy_behavior.kind = kind if not kind.is_empty() else EnemyRules.NORMAL if index>=10000 or is_practice else EnemyRules.pick(sortie_id,index,int(threat.stage))
		actor.enemy_behavior.spawn_stage = int(threat.stage)
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


func _spawn_enemy() -> void:
	if is_practice:
		_spawn_practice_enemy()
		return
	var point: Vector2 = _safe_spawn_point()
	if not point.is_finite():
		_record_spawn(&"no_safe_point", point)
		return
	var enemy: FieldActor = _make_actor(true, _spawn_count, point)
	enemies.append(enemy)
	_spawn_count += 1
	_record_spawn(&"spawned", point, enemy.actor_id)


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


func _safe_spawn_point() -> Vector2:
	var candidates: Array[Vector2] = []
	for index: int in range(layout.enemy_points.size()):
		candidates.append(layout.enemy_points[(_spawn_attempts + index) % layout.enemy_points.size()])
	var bounds: Rect2 = FieldNavigation.BOUNDS.grow(-ThreatRules.EDGE_MARGIN)
	for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		candidates.append(Vector2(lerpf(bounds.position.x, bounds.end.x, fraction), bounds.position.y))
		candidates.append(Vector2(lerpf(bounds.position.x, bounds.end.x, fraction), bounds.end.y))
		candidates.append(Vector2(bounds.position.x, lerpf(bounds.position.y, bounds.end.y, fraction)))
		candidates.append(Vector2(bounds.end.x, lerpf(bounds.position.y, bounds.end.y, fraction)))
	var visible: Rect2 = visible_world_rect().grow(threat.rules.screen_margin)
	for point: Vector2 in candidates:
		if visible.has_point(point) or not navigation.is_clear(point):
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
	for enemy: FieldActor in enemies:
		if enemy.enemy_behavior!=null and enemy.enemy_behavior.state=="windup":
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
		if actor.activity == FieldActor.Activity.DOWN or actor.activity == FieldActor.Activity.SEARCHING:
			continue
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
				var cooldown_before: float = actor.cooldown
				actor.cooldown = weapon.shot_interval(actor.trait_shot_factor)
				var health_before: float = target.health
				target.take_damage(weapon.damage, (target.position - actor.position).normalized())
				actor.visual.show_fire(actor.aim)
				var muzzle: Vector2 = actor.position + actor.visual.muzzle_offset(actor.aim)
				_shot_effect(muzzle, target.position, weapon.damage)
				combat_feedback.emit({"kind": "shot", "actor": actor.actor_id,
					"target": target.actor_id, "target_health": target.health,
					"damage": weapon.damage, "from": actor.position, "to": target.position,
					"instance_id":actor.weapon_instance_id, "weapon_id":String(weapon.id), "interval":actor.cooldown,
					"applied_damage": health_before - target.health,
					"member_id":actor.member_id,"shot_from":muzzle,"hit_to":decision.hit_to,
					"foot_distance":decision.distance,"shot_range":weapon.shot_range,
					"blocker_id":String(decision.blocker_id),"attack_reason":String(decision.reason),
					"predicted_muzzle_error":muzzle.distance_to(decision.shot_from),
					"cooldown_before":cooldown_before,"cooldown_after":actor.cooldown,
					"moving": actor.activity == FieldActor.Activity.MOVING, "elapsed": elapsed,
					"weapon": String(actor.visual.weapon_view.id), "row": actor.visual.direction_row,
					"facing": actor.visual.presentation_state()["facing"]})
				if target.activity == FieldActor.Activity.DOWN:
					kills += 1
					actor.confirmed_kills += 1
					if not is_practice and not loadout_snapshot.is_empty():
						var receipt: Dictionary = growth_inputs.accept_defeat(actor,target,elapsed)
						if not receipt.is_empty():
							if growth_mode and not xp_inputs.accept(self,actor,target,receipt):
								_show_notice("成长来源校验失败，已暂停；本次不会伪造经验。")
								toggle_pause()
							growth_input_recorded.emit(receipt)
		else:
			actor.aim = Vector2.ZERO
	for enemy: FieldActor in enemies:
		if enemy.activity == FieldActor.Activity.DOWN:
			continue
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
	if not enemy_mode:
		return
	for enemy: FieldActor in enemies:
		if enemy.enemy_behavior!=null:
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


func _update_search(delta: float) -> void:
	if search_actor == null:
		return
	if search_actor.activity == FieldActor.Activity.DOWN:
		search_actor = null
		_active_site.progress = 0.0
		_active_site = null
		return
	if search_actor.activity != FieldActor.Activity.SEARCHING:
		if search_actor.position.distance_to(_active_site.door) > 14.0:
			return
		search_actor.activity = FieldActor.Activity.SEARCHING
		search_actor.hide()
		print("BH_SEARCH entered")
	_active_site.progress += delta / search_actor.trait_search_factor
	if _active_site.progress >= tuning.search_seconds:
		var site: SearchSite = _active_site
		if trait_mode and not trait_inputs.accept_search(self,search_actor,site.kind):
			_show_notice("特性搜集来源未确认，已暂停；不会重复发放收益。")
			toggle_pause()
			return
		site.searched = true
		var reward: int = supply.reward(site.kind)
		if site.kind == &"cash":
			loot += reward
			if not is_practice and supply.has_weapon_sample:
				weapon_loot.append(WeaponInventory.reward(sortie_id,WeaponState.is_family(field_departure)))
		else:
			food_loot += reward
		_release_searcher()
		site.prop.searched = true
		site.prop.queue_redraw()
		_show_notice("搜集完成 · 携带%s +%d（撤离后带回）" % ["货币" if site.kind == &"cash" else "食物",reward])
		if site.kind == &"cash" and not is_practice and supply.has_weapon_sample:
			_show_notice("获得损坏长管步枪 · 回营后入库维修")
			print("BH_WEAPON_FOUND %s" % JSON.stringify(weapon_loot.back()))
		print("BH_SEARCH completed kind=%s reward=%d cash=%d food=%d" % [site.kind,reward,loot,food_loot])
		search_completed.emit(reward)


func _finish(evacuated: bool) -> void:
	if phase == Phase.FINISHED:
		return
	phase = Phase.FINISHED
	for enemy: FieldActor in enemies:
		if enemy.enemy_behavior!=null:
			enemy.enemy_behavior.cancel(self,enemy)
			enemy.sync_enemy_visual()
	set_physics_process(false)
	set_process_unhandled_input(false)
	_effects.process_mode = Node.PROCESS_MODE_DISABLED
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
		"food":food_loot if evacuated else 0,"food_searched":_food_site.searched,
		"sites_searched":int(searched) + int(_food_site.searched),
		"kills": kills, "searched": searched, "health": remaining_health, "elapsed": elapsed}
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
	print("BH_RESULT %s" % JSON.stringify(report))
	finished.emit(report)


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
	_hud.ui_theme = ui_theme
	_hud.pause_requested.connect(toggle_pause)
	_hud.extraction_requested.connect(request_bus_action)
	_hud.help_changed.connect(func(expanded: bool) -> void: help_changed.emit(expanded))
	add_child(_hud)
	if battle_survival:
		drill_panel = BattleDrillPanel.new()
		drill_panel.expedition = self
		drill_panel.theme = ui_theme
		_hud.view.add_child(drill_panel)
	_update_ui()


func _show_notice(message: String) -> void:
	_notice_text = message
	_notice_clock = 7.0


func _update_ui() -> void:
	if _hud == null:
		return
	if _readouts != null:
		if phase == Phase.FINISHED:
			_readouts.hide()
		else:
			_update_member_display()
			_readouts.update_members(survivors, get_global_transform_with_canvas(), get_viewport_rect().size)
	var timing: Dictionary = time_status()
	var boarding: Dictionary = boarding_status()
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
	var activities: Array[String] = ["警戒", "移动", "搜集中", "倒地"]
	for actor: FieldActor in survivors:
		members.append({"id":actor.member_id,"label":"%s · %s" % [actor.call_sign, "阵亡" if actor.permanent_death else activities[actor.activity]],
			"call_sign":actor.call_sign,"status":"阵亡" if actor.permanent_death else activities[actor.activity],
			"colour":SurvivorRoster.definition_by_id(String(actor.definition_id)).colour,
			"hp":actor.health,"max_hp":actor.max_health})
	if growth_mode:
		for member: Dictionary in members:
			member.level = SurvivorRoster.member(_setup_crew,int(member.id)).growth.level
	var pending: PackedStringArray = []
	if growth_mode:
		for actor: FieldActor in survivors:
			pending.append("%02d +%d" % [actor.member_id,0 if battle_drill or actor.health <= 0 else xp_inputs.pending(actor.member_id)])
	var xp_text: String = "本次经验（归航后生效）："+" / ".join(pending) if growth_mode else ""
	_hud.refresh({
		"mission_title":("交火练习" if is_practice else mission_title) if los_setup == null else mission_title, "members":members,
		"can_extract":phase != Phase.FINISHED if is_practice else phase == Phase.ACTIVE and elapsed >= tuning.bus_ready_seconds,
		"boarding":boarding,
		"can_gather":not is_practice and phase == Phase.BOARDING and boarding.required > 0,
		"day": day, "seconds": timing["sortie_seconds"], "time_fraction": timing["sortie_fraction"],
		"paused": is_paused, "cash": initial_cash, "loot": loot,
		"food":initial_food,"food_loot":food_loot,"sites_searched":int(searched)+int(_food_site.searched),
		"sites_total":int(supply.supports(&"cash"))+int(supply.supports(&"food")),
		"has_food_source":supply.supports(&"food"),
		"route_hint":layout.route_hint,
		"enemy_mode":enemy_mode,
		"weapon_loot":weapon_loot.size(),
		"searched": searched, "kills": kills, "engine": engine_text,
		"notice": (xp_text+"\n"+_notice_text if _notice_clock > 0 else xp_text) if growth_mode else _notice_text, "notice_visible": growth_mode or _notice_clock > 0.0,
		"practice": is_practice,
		"threat":threat_status(),
	})
	if drill_panel != null:
		drill_panel.refresh()
	for site: SearchSite in [_cash_site, _food_site]:
		site.prop.searched = site.searched
		site.prop.update_work(search_actor.actor_id if search_actor != null and _active_site == site else -1,
			site.progress / tuning.search_seconds,
			search_actor != null and _active_site == site and search_actor.activity == FieldActor.Activity.SEARCHING,
			search_actor.call_sign if search_actor != null and _active_site == site else "")


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
	var kind: StringName
	var door: Vector2
	var progress: float = 0.0
	var searched: bool = false
	var prop: FieldProp


	func _init(resource_kind: StringName, entrance: Vector2) -> void:
		kind = resource_kind
		door = entrance
