class_name ExpeditionOrders
extends RefCounted

var expedition: Expedition


func _init(owner: Expedition) -> void:
	expedition = owner


func _unhandled_input(event: InputEvent) -> void:
	if expedition.phase == Expedition.Phase.FINISHED:
		return
	if expedition._support_input(event):
		expedition.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_sortie"):
		expedition.toggle_pause()
		expedition.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("squad_command"):
		var point: Vector2 = IsoSpace.to_map(expedition.get_global_mouse_position())
		if event is InputEventMouseButton:
			# Use the click's coordinates, not a later position of the desktop cursor.
			point = IsoSpace.to_map(expedition.get_global_transform_with_canvas().affine_inverse() * event.position)
		if expedition.rescue_target != null and expedition.rescue_target.contains(point):
			expedition.rescue_target.request()
		elif not expedition.layout.world_data.is_empty() and expedition._clicked_site(point):
			pass
		elif expedition.layout.world_data.is_empty() and expedition.supply.supports(&"cash") and expedition.layout.hit_area(&"cash").has_point(point):
			if expedition.searched:
				expedition.command_move(point)
			else:
				expedition.request_search()
		elif expedition.layout.world_data.is_empty() and expedition.supply.supports(&"food") and expedition.layout.hit_area(&"food").has_point(point):
			if expedition._food_site.searched:
				expedition.command_move(point)
			else:
				expedition.request_search(&"food")
		elif expedition.layout.bus_block.grow(18.0).has_point(point):
			expedition.request_extraction()
		elif expedition.layout.world_bounds.has_point(point):
			expedition.command_move(point)
		expedition.get_viewport().set_input_as_handled()


func _clicked_site(point: Vector2) -> bool:
	if expedition.billboard_site != null and expedition.billboard_site.hit.has_point(point):
		if expedition.billboard_site.searched:
			expedition._show_notice(BillboardFieldView.DONE)
		else:
			expedition.request_search(expedition.billboard_site.id)
		return true
	if expedition.recon_site != null and expedition.recon_site.door.distance_squared_to(point) <= 32.0 * 32.0:
		if expedition.recon_site.searched:
			expedition.locate_objective("recon")
		else:
			expedition.request_search(expedition.recon_site.id)
		return true
	if expedition.supply.generated.get("mission_policy") == 1:
		# The marked work entrance is a precise target even where two facade hit areas overlap.
		for site: Expedition.SearchSite in expedition.sites:
			if expedition.site_discovered(site) and (site.prop.primary_target or expedition._is_recon_target(site.id) or (expedition.supply.generated.has("rare_policy") and not site.prop.loot_landmark.is_empty())) \
					and site.door.distance_squared_to(point) <= 24.0 * 24.0:
				if not site.searched:
					expedition.request_search(site.id)
				else:
					expedition.command_move(site.door)
				return true
	# Foreground object art takes precedence over the broad building facade hit.
	var candidates: Array[Expedition.SearchSite]=[]
	if expedition.exploration_mode():
		for site: Expedition.SearchSite in expedition.sites:
			if site.prop is ExplorationProp: candidates.append(site)
	for site: Expedition.SearchSite in expedition.sites:
		if not candidates.has(site): candidates.append(site)
	if expedition.layout.world_data.get("version")==5:
		candidates.sort_custom(func(a:Expedition.SearchSite,b:Expedition.SearchSite)->bool:return a.prop.position.y>b.prop.position.y if a.prop.position.y!=b.prop.position.y else String(a.id)<String(b.id))
	for site: Expedition.SearchSite in candidates:
		if expedition.site_discovered(site) and site.hit.has_point(point):
			if expedition.layout.world_data.get("version")==5 and site.prop.world_asset and not site.prop.scaled_hit_contains(point):continue
			if not site.searched: expedition.request_search(site.id)
			else: expedition.command_move(site.door)
			return true
	return false


func command_move(point: Vector2) -> void:
	if expedition.bus_view != null and expedition.bus_view.running(): return
	if not expedition.field_join_error.is_empty():
		return
	if expedition.rescue_target != null: expedition.rescue_target.cancel()
	if expedition.phase == Expedition.Phase.FINISHED:
		return
	if expedition.event_sortie_panel != null:
		expedition.event_sortie_panel.hide()
	expedition.goal = point
	for index: int in range(expedition.survivors.size()):
		var actor: FieldActor = expedition.survivors[index]
		if expedition.has_search_job(actor.member_id) or actor.activity == FieldActor.Activity.DOWN:
			continue
		expedition._move_to_group_goal(actor)
	expedition.queue_redraw()


func request_search(kind: StringName = &"cash") -> void:
	if (expedition.bus_view != null and expedition.bus_view.running()) or not expedition.field_join_error.is_empty():
		return
	var site: Expedition.SearchSite = expedition.search_site(kind)
	if expedition.phase == Expedition.Phase.FINISHED or site == null or site.searched or not expedition.site_discovered(site):
		return
	var event_site: bool = expedition._is_event_site(site)
	if site != expedition.recon_site and site != expedition.billboard_site and not event_site and not expedition.pump_station_mode() and not expedition.supply.supports(site.kind):
		return
	var previous: int = expedition.search_assignments.member_for(String(site.id))
	if previous > 0:
		expedition._release_searcher(previous)
		expedition._show_notice(SearchWorkView.notice("cancelled",expedition.site_label(site)))
		expedition._update_ui()
		return
	if event_site and expedition.task_event.branch == "" and expedition._near_event_worker(site) != null:
		expedition.event_sortie_panel.present()
		return
	if not expedition.parallel_search:
		if expedition.rescue_target != null:
			expedition.rescue_target.cancel()
		expedition._release_searcher()
	var candidates: Array[Dictionary] = []
	var paths: Dictionary = {}
	var free_count: int = 0
	for actor: FieldActor in expedition.survivors:
		if actor.health <= 0 or not actor.visible or expedition.has_search_job(actor.member_id) or actor.activity not in [FieldActor.Activity.IDLE,FieldActor.Activity.MOVING]:
			continue
		if expedition.rescue_target != null and expedition.rescue_target.status == "IN_PROGRESS" and expedition.rescue_target.worker == actor.member_id:
			continue
		free_count += 1
		var path: PackedVector2Array = expedition.navigation.path_between(actor.position,site.door)
		var reachable: bool = not path.is_empty() and path[-1].distance_to(site.door) <= 14.0
		if actor.position.distance_to(site.door) <= 14.0:
			path = PackedVector2Array([actor.position])
			reachable = true
		paths[actor.member_id] = path
		candidates.append({"member_id":actor.member_id,"distance":actor.position.distance_to(site.door),"reachable":reachable,"available":true})
	var chosen: int = SearchAssignments.pick(candidates)
	if chosen == 0:
		expedition._show_notice(SearchWorkView.notice("no_idle" if free_count == 0 else "unreachable",expedition.site_label(site)))
		return
	if expedition._assign_search(site, expedition.search_member(chosen), paths[chosen]):
		expedition._update_ui()


func _assign_search(site: Expedition.SearchSite, actor: FieldActor, path: PackedVector2Array) -> bool:
	if not expedition.search_assignments.assign(actor.member_id, String(site.id)):
		return false
	actor.command_path(path)
	expedition._show_notice(SearchWorkView.notice("assigned",expedition.site_label(site),actor.call_sign))
	expedition.queue_redraw()
	return true


func candidate_id() -> int:
	return RescuePoolState.choice(expedition.field_departure,expedition.sortie_id)


func join_target(at_ms: int) -> bool:
	if not expedition.field_join_gate.is_valid():
		return false
	var confirmed: Dictionary = expedition.field_join_gate.call(at_ms)
	if confirmed.error != OK:
		expedition.field_join_error = confirmed.get("reason","FIELD_JOIN_ACK_FAILED")
		expedition._show_notice("接纳尚未保存成功，已暂停；请点击重试完成援救。")
		if not expedition.is_paused:
			expedition.toggle_pause()
		return false
	expedition.field_join_error = ""
	expedition.promote_target(confirmed.receipt.joins[0])
	return true


func promote_target(event: Dictionary, restoring: bool = false) -> void:
	var id: int = int(event.member_id)
	if expedition.survivors.any(func(actor: FieldActor) -> bool: return actor.member_id == id):
		return
	var action: Dictionary = FieldJoinRules.action_base(expedition.field_departure,[event])
	var profile: Dictionary = SurvivorRoster.member(action.crew,id)
	var gun: Dictionary = WeaponInventory.for_member(action,id)
	var actor: FieldActor = expedition.rescue_target.npc
	actor.actor_id = expedition.survivors.size()
	actor.call_sign = profile.call_sign
	actor.weapon_instance_id = gun.instance_id
	actor.weapon_definition = WeaponModifiers.combat_definition(gun)
	actor.visual.set_weapon(actor.weapon_definition.presentation)
	if int(expedition.supply.generated.get("version", 0)) in [5, 6, 7, 8, 9] and not CombatEquipment.melee(String(actor.weapon_definition.id)):
		actor.magazine = WeaponMagazine.new(actor.weapon_instance_id, String(actor.weapon_definition.id),
			WorkshopV1.mod_for(action, actor.weapon_instance_id))
	actor.clear_order()
	TraitRules.apply(actor,profile,expedition.tuning.survivor_speed)
	if expedition.build_mode(): expedition.apply_build(actor,profile,gun)
	expedition.survivors.append(actor)
	# Match the existing participant/snapshot execution order, including 5 then 3/4.
	expedition.survivors.sort_custom(func(a: FieldActor,b: FieldActor) -> bool: return a.member_id<b.member_id)
	for index: int in range(expedition.survivors.size()):
		expedition.survivors[index].actor_id = index
	expedition._setup_crew.append(profile.duplicate(true))
	expedition.loadout_snapshot.append({"member_id":id,"instance":gun.duplicate(true)})
	expedition.participants_snapshot = SurvivalContracts.participants(expedition._setup_crew,expedition.loadout_snapshot,true,true)
	expedition.growth_inputs.register_member(id)
	expedition.field_joins.assign([event.duplicate(true)])
	expedition.rescue_target.status = "IN_FIELD_JOINED"
	expedition.rescue_target.progress = RescueTarget.SECONDS
	expedition.rescue_target.worker = 0
	if not restoring and expedition.goal != Vector2.ZERO:
		expedition._move_to_group_goal(actor)
	expedition.rescue_target.refresh()
	expedition.membership_committed.emit()
	expedition._update_ui()


func toggle_pause() -> void:
	if not expedition.pending_burst.is_empty():
		expedition.accept_burst(expedition.pending_burst)
		return
	if not expedition.pending_power.is_empty():
		expedition._accept_power(expedition.pending_power.before,expedition.pending_power.request)
		return
	if expedition.combat_mode(): expedition.combat.cancel_unavailable(expedition)
	clear_command_aims()
	if not expedition.pending_support.is_empty():
		expedition._accept_support(expedition.pending_support.before,expedition.pending_support.request)
		return
	if expedition.is_paused and not expedition.field_join_error.is_empty():
		return
	if expedition.suspend_sealed:
		return
	if expedition.phase == Expedition.Phase.FINISHED:
		return
	expedition.is_paused = not expedition.is_paused
	expedition.pause_changed.emit(expedition.is_paused)
	expedition._effects.process_mode = Node.PROCESS_MODE_DISABLED if expedition.is_paused else Node.PROCESS_MODE_INHERIT
	expedition._update_ui()
	print("BH_SORTIE paused=%s" % expedition.is_paused)


func toggle_support_aim() -> void:
	if expedition.support_available() and expedition.basic_support.snapshot().cooldowns.airstrike==0.0:
		var was: bool = expedition.support_aiming
		clear_command_aims()
		expedition.support_aiming = not was


func toggle_rally_aim() -> void:
	if expedition.phase == Expedition.Phase.FINISHED:
		return
	var was: bool = expedition.rally_aiming
	clear_command_aims()
	if was:
		return
	if _commandable().is_empty() and not _has_living_searchers():
		expedition._show_notice("没有可集合的队员")
		expedition._update_ui()
		return
	expedition.rally_aiming = true
	expedition._show_notice("选择集合地点 · 左键确认，右键 / Esc 取消")
	expedition._update_ui()


func request_rally(point: Vector2) -> bool:
	if expedition.phase == Expedition.Phase.FINISHED:
		return false
	if not expedition.layout.world_bounds.has_point(point):
		expedition._show_notice("请选择集合地点")
		return false
	var movers: Array[FieldActor] = _commandable()
	expedition.rally_aiming = false
	expedition.command_move(point)
	if movers.is_empty():
		expedition._show_notice("已记下集合点 · 搜集中的队员完成后归队。" if _has_living_searchers() else "没有可集合的队员")
	else:
		expedition._show_notice("已下令集合" if not _has_living_searchers() else "已下令集合 · 搜集中的队员完成后归队。")
	expedition._update_ui()
	return true


func toggle_focus_aim() -> void:
	if expedition.phase == Expedition.Phase.FINISHED:
		return
	var was: bool = expedition.focus_aiming
	var keep: FieldActor = expedition.focus_target
	clear_command_aims()
	expedition.focus_target = keep
	if was:
		expedition._update_ui()
		return
	if not expedition.survivors.any(func(actor: FieldActor) -> bool: return actor.health > 0.0) \
			or not expedition.enemies.any(func(enemy: FieldActor) -> bool: return enemy.health > 0.0):
		expedition._show_notice("没有可集火的目标")
		expedition._update_ui()
		return
	expedition.focus_aiming = true
	expedition._show_notice("选择集火目标 · 左键确认，右键 / Esc 取消")
	expedition._update_ui()


func request_focus_fire(point: Vector2) -> bool:
	if expedition.phase == Expedition.Phase.FINISHED:
		return false
	var target: FieldActor = _enemy_near(point)
	if target == null:
		expedition._show_notice("请选择集火目标")
		return false
	expedition.focus_aiming = false
	expedition.focus_target = target
	var label: String = EnemyRules.name_for(target.enemy_behavior.kind) if target.enemy_behavior != null else "目标"
	for actor: FieldActor in _commandable():
		var decision: AttackRules.Decision = expedition.evaluate_attack(actor, target)
		if not decision.targetable:
			var path: PackedVector2Array = expedition.navigation.path_between(actor.position, target.position)
			if not path.is_empty():
				actor.command_path(path)
	expedition._show_notice("集火 · %s" % label)
	expedition._update_ui()
	expedition.queue_redraw()
	return true


func clear_command_aims() -> void:
	expedition.support_aiming = false
	expedition.rally_aiming = false
	expedition.focus_aiming = false


func _commandable() -> Array[FieldActor]:
	var members: Array[FieldActor] = []
	for actor: FieldActor in expedition.survivors:
		if actor.health <= 0.0 or not actor.visible or actor.activity == FieldActor.Activity.DOWN or expedition.has_search_job(actor.member_id):
			continue
		members.append(actor)
	return members


func _has_living_searchers() -> bool:
	for actor: FieldActor in expedition.survivors:
		if actor.health > 0.0 and expedition.has_search_job(actor.member_id):
			return true
	return false


func _enemy_near(point: Vector2) -> FieldActor:
	var click: Vector2 = IsoSpace.to_view(point)
	var closest: float = 40.0 * 40.0
	var result: FieldActor
	for enemy: FieldActor in expedition.enemies:
		if enemy.health <= 0.0 or not is_instance_valid(enemy):
			continue
		var distance: float = IsoSpace.to_view(enemy.position).distance_squared_to(click)
		if distance <= closest:
			closest = distance
			result = enemy
	return result


func _support_input(event: InputEvent) -> bool:
	var details_open: bool = expedition._hud != null and expedition._hud.view != null and expedition._hud.view.persona_details.visible
	if details_open and event is InputEventKey and event.keycode in [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_3, KEY_4, KEY_5]:
		return true
	if event is InputEventKey and event.pressed and not event.echo and expedition.power_mode() \
			and (event.keycode == KEY_3 or (event.keycode == KEY_4 and expedition.second_power_panel != null) or (event.keycode == KEY_5 and expedition.third_power_panel != null)):
		if expedition.get_viewport().gui_get_focus_owner()==null: expedition.request_power(0 if event.keycode == KEY_3 else 1 if event.keycode == KEY_4 else 2)
		return true
	if event is InputEventKey and event.pressed and not event.echo and expedition.get_viewport().gui_get_focus_owner()==null:
		if event.keycode==KEY_ESCAPE and (expedition.rally_aiming or expedition.focus_aiming or expedition.support_aiming):
			clear_command_aims()
			expedition._update_ui()
			return true
		if event.keycode==KEY_Q: expedition.toggle_rally_aim(); return true
		if event.keycode==KEY_W: expedition.toggle_focus_aim(); return true
		if event.keycode==KEY_E: expedition.request_heal(); return true
		if event.keycode==KEY_R: expedition.request_special(); return true
	if (expedition.rally_aiming or expedition.focus_aiming or expedition.support_aiming) and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:
			clear_command_aims()
			expedition._update_ui()
			return true
		if event.button_index==MOUSE_BUTTON_LEFT:
			FreezeProfile.mark("left_received")
			var point: Vector2 = IsoSpace.to_map(expedition.get_global_transform_with_canvas().affine_inverse()*event.position)
			if expedition.rally_aiming:
				expedition.request_rally(point)
				return true
			if expedition.focus_aiming:
				expedition.request_focus_fire(point)
				return true
			expedition.request_airstrike(point)
			return true
	return false


func _move_to_group_goal(actor: FieldActor) -> void:
	actor.command_path(expedition.navigation.path_between(actor.position, expedition.goal + expedition._group_offset(actor)))


func _group_offset(actor: FieldActor) -> Vector2:
	var gap: float = minf(expedition.tuning.squad_spacing, expedition.tuning.boarding_radius * 1.2 / maxi(1, expedition.survivors.size() - 1))
	return Vector2.ONE * ((float(actor.actor_id) - float(expedition.survivors.size() - 1) * 0.5) * gap)
