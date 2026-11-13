class_name ExpeditionExtraction
extends RefCounted

var expedition: Expedition


func _init(owner: Expedition) -> void:
	expedition = owner


func request_extraction() -> void:
	if expedition.bus_view != null and expedition.bus_view.running(): return
	if not expedition.field_join_error.is_empty():
		return
	if expedition.phase != Expedition.Phase.ACTIVE:
		return
	if expedition.elapsed < expedition.tuning.bus_ready_seconds:
		expedition._show_notice("巴士仍在准备，请稍候。")
		return
	expedition.phase = Expedition.Phase.ENGINE
	expedition._engine_clock = expedition.tuning.engine_seconds
	expedition.engine_started.emit()
	expedition._show_notice("引擎发动中 · 队伍仍可移动，请前往巴士旁集合。")


func request_bus_action() -> void:
	if expedition.phase == Expedition.Phase.BOARDING:
		expedition.request_bus_gather()
	else:
		expedition.request_extraction()


func boarding_status(with_feedback: bool = false) -> Dictionary:
	var required: int = 0
	var arrived: int = 0
	var working: int = 0
	var ordered: bool = expedition.goal == expedition.layout.bus_door
	var waiting: Array[Dictionary] = []
	for actor: FieldActor in expedition.survivors:
		if actor.activity == FieldActor.Activity.DOWN:
			continue
		required += 1
		var search_phase: String = expedition.search_assignments.phase_for(actor.member_id)
		if not search_phase.is_empty():
			working += 1
		elif actor.position.distance_to(expedition.layout.bus_door) <= expedition.tuning.boarding_radius:
			arrived += 1
			continue
		if with_feedback:
			var activity: String = "pending"
			if search_phase == "approach":
				activity = "approaching_search"
			elif search_phase == "working":
				activity = "recovering" if actor.activity == FieldActor.Activity.RECOVERING else "searching"
			elif ordered and actor.activity == FieldActor.Activity.MOVING and not actor.path.is_empty():
				if actor.path[-1].distance_to(expedition.layout.bus_door) <= expedition.tuning.boarding_radius:
					activity = "gathering"
			waiting.append({"id":actor.member_id, "call_sign":actor.call_sign, "activity":activity})
	var status: Dictionary = {"arrived":arrived, "required":required, "working":working, "ordered":ordered}
	if with_feedback:
		status["waiting"] = waiting
		status["rescue_waiting"] = expedition._extraction._rescue_waiting_for_bus()
	return status


func _rescue_waiting_for_bus() -> bool:
	return expedition.rescue_target != null and expedition.rescue_target.status == "RESCUED" and not expedition.rescue_target.delivered()


func request_bus_gather() -> void:
	if not expedition.field_join_error.is_empty():
		return
	if expedition.phase != Expedition.Phase.BOARDING or expedition.living_count() == 0:
		return
	# Validate the same formation destinations before acknowledging the whole order.
	# Hidden workers will use their entrance and the latest goal when work completes.
	for actor: FieldActor in expedition.survivors:
		if actor.activity == FieldActor.Activity.DOWN:
			continue
		var start: Vector2 = expedition.member_site(actor.member_id).door if expedition.has_search_job(actor.member_id) else actor.position
		var path: PackedVector2Array = expedition.navigation.path_between(start, expedition.layout.bus_door + expedition._group_offset(actor))
		if path.is_empty() or path[-1].distance_to(expedition.layout.bus_door) > expedition.tuning.boarding_radius:
			expedition._show_notice("无法到达巴士集合区 · 请检查当前路线。")
			return
	# An unconfirmed visit must not hold a worker back from gathering.
	if expedition.event_sortie_panel != null:
		expedition.event_sortie_panel.hide()
		if expedition.task_event.branch == "":
			var approaching: int = expedition.search_assignments.member_for(EventSortieV1.site_id(expedition.supply.generated))
			if approaching > 0:
				expedition._release_searcher(approaching)
	# Gathering also releases assistance when the previous group goal was already the bus.
	if expedition.rescue_target != null: expedition.rescue_target.cancel()
	if expedition.goal != expedition.layout.bus_door:
		expedition.command_move(expedition.layout.bus_door)
	var boarding: Dictionary = expedition.boarding_status()
	expedition._show_notice("已下令集合 · 搜集中的队员完成后归队。" if boarding.working > 0 else "已下令集合 · 队员正前往巴士。")
	expedition._update_ui()
	expedition.bus_gather_ordered.emit(boarding)


func time_status() -> Dictionary:
	return {
		"sortie_seconds": maxi(0, ceili(expedition.tuning.daylight_seconds - expedition.elapsed)),
		"sortie_fraction": clampf(1.0 - expedition.elapsed / maxf(expedition.tuning.daylight_seconds, 0.001), 0.0, 1.0),
		"bus_seconds": maxi(0, ceili(expedition.tuning.bus_ready_seconds - expedition.elapsed)),
		"engine_seconds": maxi(0, ceili(expedition._engine_clock)),
	}


func _finish(evacuated: bool, boarding: Vector2i = Vector2i.ZERO) -> void:
	if expedition.phase == Expedition.Phase.FINISHED:
		return
	FreezeProfile.start({"day":expedition.day,"size":expedition.layout.world_data.get("size","legacy"),"buildings":expedition._buildings.size(),"sites":expedition.sites.size(),"survivors":expedition.survivors.size(),"enemies":expedition.enemies.size(),"elapsed":expedition.elapsed})
	var profile_report: int = FreezeProfile.enter("report.build")
	expedition.phase = Expedition.Phase.FINISHED
	if expedition.combat.screamer != null and expedition.combat.screamer.state.phase == "windup":
		ScreamerRuntimeV1.cancel(expedition.combat.screamer.state, int(expedition.combat.screamer.state.actor_id))
		expedition.combat.screamer.present(expedition)
	for enemy: FieldActor in expedition.enemies:
		if enemy.enemy_behavior!=null:
			enemy.enemy_behavior.cancel(expedition,enemy)
			enemy.sync_enemy_visual()
	expedition.set_physics_process(false)
	expedition.set_process_unhandled_input(false)
	expedition._effects.process_mode = Node.PROCESS_MODE_DISABLED
	if expedition.bus_view != null:
		expedition.bus_view.final_boarding = boarding
	expedition._hud.hide_screen()
	expedition._readouts.hide()
	expedition._feedback._stop_camera()
	var remaining_health: Array[float] = []
	var member_records: Array[Dictionary] = []
	var member_results: Array[Dictionary] = []
	for actor: FieldActor in expedition.survivors:
		remaining_health.append(actor.health)
		member_records.append({"id":actor.member_id,"kills":actor.confirmed_kills,"damage_received":actor.damage_received})
		member_results.append({"id":actor.member_id,"health":actor.health,"kills":actor.confirmed_kills,"damage_received":actor.damage_received})
	var report: Dictionary = {"evacuated": evacuated, "loot": expedition.loot if evacuated else 0,
		"member_records":member_records,
		"contract_version":SurvivalContracts.VERSION,"sortie_id":expedition.sortie_id,
		"participants":expedition.participants_snapshot.duplicate(true),"member_results":member_results,
		"mission_outcome":"EXTRACTED" if evacuated else "FAILED",
		"weapons":expedition.weapon_loot.duplicate(true) if evacuated else [],
		"food":expedition.food_loot if evacuated else 0,"food_searched":expedition._kind_searched(&"food"),
		"sites_searched":expedition._searched_count(),
		"kills": expedition.kills, "searched": expedition._kind_searched(&"cash"), "health": remaining_health, "elapsed": expedition.elapsed}
	if not expedition.layout.world_data.is_empty(): report.site_facts = WorldSites.facts(expedition)
	if expedition.billboard_site != null:
		report.billboard = expedition.billboard_work.snapshot(expedition.billboard_site.progress)
	if expedition.supply.generated.get("version")==4 or (expedition.supply.generated.get("version")==5 or (expedition.supply.generated.get("version")==6 or (expedition.supply.generated.get("version")==7 or (expedition.supply.generated.get("version")==8 or expedition.supply.generated.get("version")==9)))): report.task_event=expedition.task_event.duplicate(true)
	if expedition.build_mode(): report.support=expedition.basic_support.snapshot()
	if expedition.power_mode(): report.powers=expedition.powers.duplicate(true)
	if not expedition.loadout_snapshot.is_empty():
		report.growth_inputs = expedition.growth_inputs.snapshot(expedition.sortie_id,expedition.layout.id,expedition.elapsed)
	report.rescue = expedition.rescue_target.fact(evacuated) if expedition.rescue_target != null else {"rescue_id":RescueState.TARGET,"status":"UNAVAILABLE"}
	report.xp_inputs = expedition.xp_inputs.snapshot(expedition)
	report.trait_inputs = expedition.trait_inputs.snapshot(expedition)
	report.field_joins = expedition.field_joins.duplicate(true)
	if expedition.encounter!=null: report.encounter=expedition.encounter.snapshot()
	FreezeProfile.leave("report.build", profile_report)
	print("BH_RESULT %s" % JSON.stringify(report))
	expedition.finished.emit(report)
	FreezeProfile.finish()
