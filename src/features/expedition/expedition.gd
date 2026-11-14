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

var _feedback: ExpeditionFeedback = ExpeditionFeedback.new(self)
var _ui: ExpeditionUi = ExpeditionUi.new(self)
var _orders: ExpeditionOrders = ExpeditionOrders.new(self)
var _squad: ExpeditionSquad = ExpeditionSquad.new(self)
var _combat: ExpeditionCombat = ExpeditionCombat.new(self)
var _threat: ExpeditionThreat = ExpeditionThreat.new(self)
var _extraction: ExpeditionExtraction = ExpeditionExtraction.new(self)
var _support: ExpeditionSupport = ExpeditionSupport.new(self)
var _world: ExpeditionWorld = ExpeditionWorld.new(self)

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
	_world.setup()

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
			_threat._record_spawn(&"capacity", Vector2.INF)
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
		_support._update_recon_knowledge()
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
		if boarding.arrived == boarding.required and not _extraction._rescue_waiting_for_bus():
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
	_extraction.request_extraction()

func request_bus_action() -> void:
	_extraction.request_bus_action()

func boarding_status(with_feedback: bool = false) -> Dictionary:
	return _extraction.boarding_status(with_feedback)

func request_bus_gather() -> void:
	_extraction.request_bus_gather()

func time_status() -> Dictionary:
	return _extraction.time_status()

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
	return _world._make_actor(enemy, index, point, profile, kind)

func _visual_contact(enemy: FieldActor) -> Vector2:
	return _combat._visual_contact(enemy)

func _spawn_enemy(forced_kind: String = "", pressure_point: Vector2 = Vector2.INF, provenance: Dictionary = {}) -> Dictionary:
	return _threat._spawn_enemy(forced_kind, pressure_point, provenance)

func _spawn_screamer_batch(event: Dictionary) -> void:
	_threat._spawn_screamer_batch(event)

func visible_world_rect() -> Rect2:
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var corner: Vector2 = inverse * Vector2.ZERO
	var view_rect: Rect2 = Rect2(corner, inverse * get_viewport_rect().size - corner)
	return IsoSpace.map_bounds_from_view(view_rect)

func threat_status() -> Dictionary:
	return _threat.threat_status()

func _update_enemy_paths(idle_only: bool = false) -> void:
	_threat._update_enemy_paths(idle_only)

func _hold_enemy_approach(enemy: FieldActor) -> bool:
	return _threat._hold_enemy_approach(enemy)

func _nearest_target(actor: FieldActor, candidates: Array[FieldActor], limit: float) -> FieldActor:
	return _combat._nearest_target(actor, candidates, limit)

func _update_combat() -> void:
	_combat._update_combat()

func _update_enemy_behaviors(delta: float) -> void:
	_combat._update_enemy_behaviors(delta)

func evaluate_attack(actor: FieldActor, target: FieldActor) -> AttackRules.Decision:
	return _combat.evaluate_attack(actor, target)

func _fire_ranged(actor: FieldActor, target: FieldActor, decision: AttackRules.Decision) -> void:
	_combat._fire_ranged(actor, target, decision)

func _combatant(actor: FieldActor) -> AttackRules.Combatant:
	return _combat._combatant(actor)

func _attack_target(actor: FieldActor) -> FieldActor:
	return _combat._attack_target(actor)

func work_state_matches(actor: FieldActor, site: SearchSite) -> bool:
	return _squad.work_state_matches(actor, site)

func _clear_dead_worker() -> void:
	_squad._clear_dead_worker()

func _update_search(delta: float) -> void:
	_squad._update_search(delta)

func _complete_search(actor: FieldActor, site: SearchSite) -> bool:
	return _squad._complete_search(actor, site)

func _finish(evacuated: bool, boarding: Vector2i = Vector2i.ZERO) -> void:
	_extraction._finish(evacuated, boarding)

func _shot_effect(from: Vector2, to: Vector2, damage: float) -> void:
	_feedback._shot_effect(from, to, damage)

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
	if _sort != null:
		IsoOcclusion.update(self, combat_delta if combat_delta > 0.0 else 1.0 / 30.0)
	_ui._update_ui()


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

func _searched_count() -> int:
	return _squad._searched_count()

func _clicked_site(point: Vector2) -> bool:
	return _orders._clicked_site(point)

func _site_seconds(site: SearchSite) -> float:
	return _squad._site_seconds(site)

func _trigger_airdrop() -> void:
	_threat._trigger_airdrop()

func _request_task_wave(site: SearchSite, requests: int, provenance: Dictionary = {}) -> void:
	_threat._request_task_wave(site, requests, provenance)

func _site_weapon(site: SearchSite) -> Dictionary:
	return _squad._site_weapon(site)

func _ammo_text(actor: FieldActor) -> String:
	return _ui._ammo_text(actor)

func combat_mode() -> bool:
	return (supply.generated.get("version")==8 or supply.generated.get("version")==9)

func build_mode() -> bool:
	return (supply.generated.get("version")==7 or (supply.generated.get("version")==8 or supply.generated.get("version")==9))

func apply_build(actor: FieldActor, profile: Dictionary = {}, item: Dictionary = {}) -> void:
	_support.apply_build(actor, profile, item)

func support_available() -> bool:
	return _support.support_available()

func support_world() -> Dictionary:
	return _support.support_world()

func accept_burst(before: Dictionary) -> bool:
	return _support.accept_burst(before)

func request_heal() -> bool:
	return _support.request_heal()

func first_aid_status() -> String:
	return _ui.first_aid_status()

func request_first_aid() -> bool:
	return _support.request_first_aid()

func apply_barricade_history(accepted: Array) -> void:
	_support.apply_barricade_history(accepted)

func request_airstrike(point: Vector2) -> bool:
	return _support.request_airstrike(point)

func _accept_support(before: Dictionary, request: Dictionary) -> bool:
	return _support._accept_support(before, request)

func toggle_support_aim() -> void:
	_orders.toggle_support_aim()

func _support_input(event: InputEvent) -> bool:
	return _orders._support_input(event)

func _present_support() -> void:
	_feedback._present_support()

func support_plan_airstrike(point: Vector2) -> Dictionary:
	return _support.support_plan_airstrike(point)

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
	_support.refresh_power_factors()

func request_power(slot: int = 0) -> bool:
	return _support.request_power(slot)

func _accept_power(before: Dictionary, request: Dictionary) -> bool:
	return _support._accept_power(before, request)

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
	return _support.site_discovered(site)

func _is_recon_target(id: StringName) -> bool:
	return _support._is_recon_target(id)

func refresh_recon_view() -> void:
	_feedback.refresh_recon_view()

func recon_region() -> Rect2:
	return _support.recon_region()

func locate_objective(id: String) -> void:
	_feedback.locate_objective(id)
