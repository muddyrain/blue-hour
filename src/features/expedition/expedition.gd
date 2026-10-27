class_name Expedition
extends Node2D
## Owns one sortie; observed behavior IDs and differences live in the reference table.

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
var ui_theme: Theme
var is_practice: bool = false
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
var _notice_clock: float = 0.0
var _corpses: Array[FieldActor] = []
var _corpse_times: Array[float] = []
var _practice_manual_waves: bool = false
var _readouts: SquadReadouts
var _cash_site: SearchSite = SearchSite.new(&"cash", Vector2.ZERO)
var _food_site: SearchSite = SearchSite.new(&"food", Vector2.ZERO)
var _active_site: SearchSite


func _ready() -> void:
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
	for index: int in range(2):
		var start: Vector2 = Vector2(1008 + index * 48, 720 + index * 48) if is_practice else layout.arrivals[index]
		if los_setup != null:
			start = los_setup.starts[index]
		var actor: FieldActor = _make_actor(false, index, start)
		actor.health = starting_health[index]
		var profile: Dictionary = SurvivorRoster.member(crew_snapshot, index + 1)
		actor.call_sign = profile.call_sign if not profile.is_empty() else SurvivorRoster.definition(index + 1).default_display_name
		var item: Dictionary = {}
		for entry: Dictionary in loadout_snapshot:
			if int(entry.member_id) == index + 1:
				item = entry.instance
		if item.is_empty():
			# Standalone/practice scenes have no campaign inventory; retain their old views.
			actor.weapon_definition = WeaponInventory.Definitions[1 if not is_practice and index == 1 else 0].duplicate() as WeaponDefinition
		else:
			actor.weapon_instance_id = item.instance_id
			actor.weapon_definition = WeaponInventory.definition(item.weapon_id).duplicate() as WeaponDefinition
		actor.visual.set_weapon(actor.weapon_definition.presentation)
		survivors.append(actor)
	_make_ui()
	var readout_layer: CanvasLayer = CanvasLayer.new()
	readout_layer.layer = 5
	add_child(readout_layer)
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
		if supply.supports(&"cash") and layout.hit_area(&"cash").has_point(point):
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
	if phase == Phase.FINISHED or is_paused:
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
	for actor: FieldActor in survivors:
		actor.advance(delta)
	for enemy: FieldActor in enemies:
		enemy.advance(delta)
	for index: int in range(_corpses.size() - 1, -1, -1):
		_corpses[index].advance(delta)
		_corpse_times[index] -= delta
		if _corpse_times[index] <= 0.0:
			_corpses[index].queue_free()
			_corpses.remove_at(index)
			_corpse_times.remove_at(index)
	_update_search(delta)
	_update_combat()
	if living_count() == 0:
		_finish(false)
	elif phase == Phase.BOARDING:
		var boarding: Dictionary = boarding_status()
		if boarding.arrived == boarding.required:
			_finish(true)
	elif phase == Phase.ENGINE:
		_engine_clock -= delta
		if _engine_clock <= 0.0:
			phase = Phase.BOARDING
			_show_notice("引擎已发动 · 点击「集合至巴士」，或左键黄色区域。")
	_update_ui()
	queue_redraw()
	last_simulation_usec = Time.get_ticks_usec() - started_usec


func toggle_pause() -> void:
	if phase == Phase.FINISHED:
		return
	is_paused = not is_paused
	pause_changed.emit(is_paused)
	_effects.process_mode = Node.PROCESS_MODE_DISABLED if is_paused else Node.PROCESS_MODE_INHERIT
	_update_ui()
	print("BH_SORTIE paused=%s" % is_paused)


func command_move(point: Vector2) -> void:
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
		_show_notice("队员 %d 前往搜集，其余队员留守。" % (search_actor.actor_id + 1))
		queue_redraw()
		print("BH_SEARCH assigned=%d kind=%s" % [search_actor.actor_id,kind])


func search_site(kind: StringName) -> SearchSite:
	if kind == &"cash":
		return _cash_site
	if kind == &"food":
		return _food_site
	return null


func request_extraction() -> void:
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
	return Vector2.ONE * ((float(actor.actor_id) - 0.5) * tuning.squad_spacing)


func _release_searcher() -> void:
	var released: FieldActor = search_actor
	search_actor = null
	_active_site = null
	released.clear_order()
	if goal != Vector2.ZERO:
		_move_to_group_goal(released)
	queue_redraw()


func _make_actor(enemy: bool, index: int, point: Vector2) -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.actor_id = index
	actor.is_enemy = enemy
	actor.speed = tuning.enemy_speed if enemy else tuning.survivor_speed
	actor.max_health = tuning.enemy_health if enemy else tuning.survivor_health
	actor.health = actor.max_health
	actor.position = point
	_sort.add_child(actor)
	return actor


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


func _update_enemy_paths() -> void:
	for enemy: FieldActor in enemies:
		var target: FieldActor = _nearest_target(enemy, survivors, INF)
		if target != null and enemy.position.distance_to(target.position) > 23.0:
			enemy.command_path(navigation.path_between(enemy.position, target.position))


func _nearest_target(actor: FieldActor, candidates: Array[FieldActor], limit: float) -> FieldActor:
	var closest: float = limit * limit
	var result: FieldActor
	for candidate: FieldActor in candidates:
		if candidate.activity == FieldActor.Activity.DOWN or candidate.activity == FieldActor.Activity.SEARCHING:
			continue
		var distance: float = actor.position.distance_squared_to(candidate.position)
		if distance < closest:
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
				var cooldown_before: float = actor.cooldown
				actor.cooldown = weapon.interval
				var health_before: float = target.health
				target.take_damage(weapon.damage, (target.position - actor.position).normalized())
				actor.visual.show_fire(actor.aim)
				var muzzle: Vector2 = actor.position + actor.visual.muzzle_offset(actor.aim)
				_shot_effect(muzzle, target.position, weapon.damage)
				combat_feedback.emit({"kind": "shot", "actor": actor.actor_id,
					"target": target.actor_id, "target_health": target.health,
					"damage": weapon.damage, "from": actor.position, "to": target.position,
					"instance_id":actor.weapon_instance_id, "weapon_id":String(weapon.id), "interval":weapon.interval,
					"applied_damage": health_before - target.health,
					"member_id":actor.actor_id + 1,"shot_from":muzzle,"hit_to":decision.hit_to,
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
							growth_input_recorded.emit(receipt)
		else:
			actor.aim = Vector2.ZERO
	for enemy: FieldActor in enemies:
		if enemy.activity == FieldActor.Activity.DOWN:
			continue
		var target: FieldActor = _nearest_target(enemy, survivors, 28.0)
		if target != null and enemy.cooldown <= 0.0:
			enemy.cooldown = tuning.enemy_interval
			var direction: Vector2 = (target.position - enemy.position).normalized()
			enemy.visual.show_attack(direction)
			var health_before: float = target.health
			target.take_damage(tuning.enemy_damage, direction)
			_hit_effect(target.position, tuning.enemy_damage, true)
			combat_feedback.emit({"kind": "hit", "actor": target.actor_id, "health": target.health,
				"applied_damage": health_before - target.health, "elapsed": elapsed})
			print("BH_HIT member=%d health=%.0f source=enemy_attack" % [target.actor_id + 1, target.health])
	for index: int in range(enemies.size() - 1, -1, -1):
		if enemies[index].activity == FieldActor.Activity.DOWN:
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
	_active_site.progress += delta
	if _active_site.progress >= tuning.search_seconds:
		var site: SearchSite = _active_site
		site.searched = true
		var reward: int = supply.reward(site.kind)
		if site.kind == &"cash":
			loot += reward
			if not is_practice and supply.has_weapon_sample:
				weapon_loot.append(WeaponInventory.reward(sortie_id))
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
	set_physics_process(false)
	set_process_unhandled_input(false)
	_effects.process_mode = Node.PROCESS_MODE_DISABLED
	_hud.hide_screen()
	_readouts.hide()
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	var remaining_health: Array[float] = []
	var member_records: Array[Dictionary] = []
	for actor: FieldActor in survivors:
		remaining_health.append(actor.health)
		member_records.append({"id":actor.actor_id + 1,"kills":actor.confirmed_kills,"damage_received":actor.damage_received})
	var report: Dictionary = {"evacuated": evacuated, "loot": loot if evacuated else 0,
		"member_records":member_records,
		"weapons":weapon_loot.duplicate(true) if evacuated and not is_practice else [],
		"food":food_loot if evacuated else 0,"food_searched":_food_site.searched,
		"sites_searched":int(searched) + int(_food_site.searched),
		"kills": kills, "searched": searched, "health": remaining_health, "elapsed": elapsed}
	if not is_practice and not loadout_snapshot.is_empty():
		report.growth_inputs = growth_inputs.snapshot(sortie_id,layout.id,elapsed)
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
	label.text = ("−" if survivor_hit else "") + str(int(damage))
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
		members.append({"id":actor.actor_id + 1,"label":"%s · %s" % [actor.call_sign, activities[actor.activity]],
			"hp":actor.health,"max_hp":actor.max_health})
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
		"weapon_loot":weapon_loot.size(),
		"searched": searched, "kills": kills, "health1": ceili(survivors[0].health),
		"health2": ceili(survivors[1].health), "engine": engine_text,
		"notice": _notice_text, "notice_visible": _notice_clock > 0.0,
		"practice": is_practice,
		"threat":threat_status(),
	})
	for site: SearchSite in [_cash_site, _food_site]:
		site.prop.searched = site.searched
		site.prop.update_work(search_actor.actor_id if search_actor != null and _active_site == site else -1,
			site.progress / tuning.search_seconds,
			search_actor != null and _active_site == site and search_actor.activity == FieldActor.Activity.SEARCHING,
			search_actor.call_sign if search_actor != null and _active_site == site else "")


func _update_member_display() -> void:
	var both_visible: bool = survivors[0].visible and survivors[1].visible and living_count() == 2
	var separation: float = survivors[0].position.distance_to(survivors[1].position)
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
