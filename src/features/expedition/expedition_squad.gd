class_name ExpeditionSquad
extends RefCounted

var expedition: Expedition


func _init(owner: Expedition) -> void:
	expedition = owner


func _update_search(delta: float) -> void:
	expedition._clear_dead_worker()
	for job: Dictionary in expedition.search_assignments.ordered():
		if expedition.is_paused:
			return
		var actor: FieldActor = expedition.search_member(int(job.member_id))
		var site: Expedition.SearchSite = expedition.search_site(StringName(job.site_id))
		var outdoor: bool = TaskActions.outdoor_site(expedition.supply.generated,site.id)
		if job.phase == "approach":
			if actor.position.distance_to(site.door) > 14.0:
				if actor._path_index >= actor.path.size():
					var route: PackedVector2Array = expedition.navigation.path_between(actor.position,site.door)
					if route.is_empty() or route[-1].distance_to(site.door)>14.0:
						expedition._release_searcher(actor.member_id)
						expedition._show_notice(SearchWorkView.notice("unreachable",expedition.site_label(site)))
					else:
						actor.command_path(route)
				continue
			if expedition._is_event_site(site) and expedition.task_event.branch == "":
				expedition.search_assignments.release_member(actor.member_id)
				actor.clear_order()
				expedition.event_sortie_panel.present()
				continue
			actor.clear_order()
			actor.activity = FieldActor.Activity.RECOVERING if outdoor else FieldActor.Activity.SEARCHING
			actor.visible = outdoor
			expedition.search_assignments.begin(actor.member_id)
			if expedition.combat_mode():
				expedition.combat.cancel_unavailable(expedition)
			if outdoor and (not expedition.exploration_mode() or (site.id==&"cash" and expedition.supply.generated.type=="airdrop")):
				expedition._trigger_airdrop()
			# A movement step ending in range cannot also count as billboard work.
			if site == expedition.billboard_site:
				continue
		if not expedition.work_state_matches(actor,site):
			expedition._release_searcher(actor.member_id)
			continue
		var prior_progress: float = site.progress
		if site == expedition.recon_site:
			site.progress += delta
			if is_equal_approx(site.progress, site.seconds):
				site.progress = site.seconds
			var worked: float = minf(site.progress, site.seconds) - prior_progress
			if worked > 0.0:
				var start: float = expedition.elapsed - delta
				expedition.recon_knowledge.record_work(actor.member_id, actor.position, start, minf(expedition.elapsed, start + worked))
		elif site == expedition.billboard_site:
			site.progress = minf(site.seconds, prior_progress + delta)
			if site.seconds - site.progress <= 0.000000001:
				site.progress = site.seconds
			var worked: float = site.progress - prior_progress
			if worked > 0.0:
				var start: float = expedition.elapsed - delta
				expedition.billboard_work.record(actor.member_id, actor.position, start, minf(expedition.elapsed, start + worked))
		else:
			site.progress += delta / (actor.trait_search_factor * actor.persona_work_factor * (BuildItems.frozen_factors(expedition.supply.generated.build).work if expedition.build_mode() else 1.0))
		if site.progress > prior_progress and expedition._is_event_site(site) and expedition.task_event.work_at < 0.0:
			expedition.task_event.work_at = maxf(0.0, expedition.elapsed - delta)
			if expedition.task_event.branch == EventSortieV1.FORCE:
				expedition.task_event.first_enemy_id = expedition._spawn_count
				expedition.task_event.first_attempt = expedition._spawn_attempts
				expedition._request_task_wave(site, int(expedition.supply.generated.event_sortie.requests), {"source":"event_sortie"})
				expedition._show_notice("强开物资柜 · 警报已触发，留意来袭。")
		if site.progress >= expedition._site_seconds(site):
			if not expedition._complete_search(actor,site):
				site.progress = prior_progress
				return


func _complete_search(actor: FieldActor, site: Expedition.SearchSite) -> bool:
	if site == expedition.billboard_site:
		site.searched = true
		expedition._release_searcher(actor.member_id)
		expedition._show_notice("已调查 · 生还归航并确认后，下次选卡保证有超市补给")
		return true
	if site == expedition.recon_site:
		site.progress = site.seconds
		site.searched = true
		expedition._release_searcher(actor.member_id)
		expedition._show_notice("侦察完成 · 已标记 2 处")
		expedition.refresh_recon_view()
		return true
	if expedition.exploration_mode() and site.searched: return false
	if not expedition.trait_inputs.events.any(func(e: Dictionary) -> bool: return e.site == String(site.kind)) and not expedition.trait_inputs.accept_search(expedition,actor,site.kind,site.id):
		expedition._show_notice("特性搜集来源未确认，已暂停；不会重复发放收益。")
		expedition.toggle_pause()
		return false
	site.searched = true
	if expedition.exploration_mode(): site.progress=expedition._site_seconds(site)
	var reward: int = site.reward if not expedition.layout.world_data.is_empty() else expedition.supply.reward(site.kind)
	if expedition._is_event_site(site):
		var carried: Dictionary = EventSortieV1.reward(expedition.supply.generated, expedition.task_event.branch)
		expedition.loot += int(carried.cash)
		expedition.food_loot += int(carried.food)
		expedition._release_searcher(actor.member_id)
		site.prop.searched = true
		site.prop.queue_redraw()
		expedition._show_notice("应急补给站 · 已携带%s，归航后入库。" % expedition._ui._event_reward_text(carried))
		expedition.search_completed.emit(int(carried.cash) + int(carried.food))
		return true
	if site.kind == &"cash":
		expedition.loot += reward
		if (site.weapon if not expedition.layout.world_data.is_empty() else expedition.supply.has_weapon_sample):
			expedition.weapon_loot.append(expedition._site_weapon(site))
	else:
		expedition.food_loot += reward
	expedition._release_searcher(actor.member_id)
	site.prop.searched = true
	site.prop.queue_redraw()
	if expedition.pump_station_mode():
		expedition.station_art.set_stopped(true)
		expedition.encounter.activate_pump()
		expedition._show_notice("停机完成 · 破阵者出现，留意地面冲锋预警")
		expedition.search_completed.emit(0)
		return true
	expedition._show_notice("搜集完成 · 携带%s +%d（撤离后带回）" % ["货币" if site.kind == &"cash" else "食物",reward])
	if site.kind == &"cash" and (site.weapon if not expedition.layout.world_data.is_empty() else expedition.supply.has_weapon_sample):
		expedition._show_notice("获得损坏%s · 回营后入库维修"%WeaponInventory.definition(expedition.weapon_loot.back().weapon_id).display_name)
	if expedition.power_mode() and site.id == &"cash" and (expedition.supply.generated.type == "equipment" or not expedition.supply.generated.powers.sample.is_empty()):
		expedition._show_notice("已携带能力样本：%s · 归航确认后入库"%SpecialPowers.definition(expedition.supply.generated.powers.sample).name if not expedition.supply.generated.powers.sample.is_empty() else "特殊能力已集齐。")
	if expedition.build_mode() and site.id==&"cash" and not expedition.supply.generated.build.drops.is_empty():
		var names: PackedStringArray=[]
		for item: String in expedition.supply.generated.build.drops: names.append(expedition.supply.generated.build.policy.items[item].name)
		if expedition.supply.generated.get("powers", {}).get("sample") == SpecialPowers.RADIO:
			names.append(SpecialPowers.RADIO_DEFINITION.name)
		expedition._show_notice("携带道具："+"、".join(names)+" · 归航确认后入库")
	var investigation: Dictionary = expedition.supply.generated.get("investigation", {})
	if expedition.supply.generated.get("mission_policy") == 1 and investigation.get("site_id") == String(site.id):
		expedition._show_notice("已携带线索：%s · 生还归航并确认后登记" % CampaignRules.CLUE_NAMES[investigation.clue_id])
	var tool_count: int = expedition._tools_at(String(site.id))
	if tool_count > 0:
		expedition._show_notice("已携带工具 ×%d · 归航确认后入库" % tool_count)
	expedition.search_completed.emit(reward)
	return true


func _release_searcher(member_id: int = 0) -> void:
	if member_id == 0:
		if expedition.search_actor == null:
			return
		member_id = expedition.search_actor.member_id
	expedition.search_assignments.release_member(member_id)
	var released: FieldActor = expedition.search_member(member_id)
	if released != null:
		released.clear_order()
		if released.health > 0 and expedition.goal != Vector2.ZERO:
			expedition._move_to_group_goal(released)
	expedition.queue_redraw()


func _arrival(index: int) -> Vector2:
	if index < expedition.layout.arrivals.size():
		return expedition.layout.arrivals[index]
	var anchor: Vector2 = expedition.layout.arrivals[0]
	for ring: int in range(1, 17):
		for x: int in range(-ring, ring + 1):
			for y: int in range(-ring, ring + 1):
				var point: Vector2 = anchor + Vector2(x,y) * 48.0
				if not expedition.navigation.is_clear(point) or expedition.survivors.any(func(actor: FieldActor) -> bool: return actor.position.distance_to(point) < 32.0):
					continue
				if not expedition.navigation.path_between(anchor, point).is_empty():
					return point
	# Explicit construction error; never drop members from the participant set.
	expedition.setup_problem = "本图没有足够的合法出生位置"
	return anchor


func _clear_dead_worker() -> void:
	for job: Dictionary in expedition.search_assignments.ordered():
		var actor: FieldActor = expedition.search_member(int(job.member_id))
		if actor != null and (actor.health <= 0 or actor.activity == FieldActor.Activity.DOWN):
			var site: Expedition.SearchSite = expedition.search_site(StringName(job.site_id))
			if site != expedition.recon_site and site != expedition.billboard_site:
				site.progress = 0.0
			expedition._release_searcher(actor.member_id)
			if expedition.pump_station_mode():
				expedition._show_notice("操作员已阵亡 · 控制柜停机中断，可派其他存活者")


func work_state_matches(actor: FieldActor, site: Expedition.SearchSite) -> bool:
	if site == null: return false
	var outdoor: bool = TaskActions.outdoor_site(expedition.supply.generated,site.id)
	return actor.health>0 and actor.activity == (FieldActor.Activity.RECOVERING if outdoor else FieldActor.Activity.SEARCHING) and actor.visible == outdoor and (not outdoor or actor.position.distance_to(site.door)<=14.0)


func has_search_job(member_id: int) -> bool:
	return not expedition.search_assignments.site_for(member_id).is_empty()


func search_member(member_id: int) -> FieldActor:
	for actor: FieldActor in expedition.survivors:
		if actor.member_id == member_id:
			return actor
	return null


func member_site(member_id: int) -> Expedition.SearchSite:
	var id: String = expedition.search_assignments.site_for(member_id)
	return expedition.search_site(StringName(id)) if not id.is_empty() else null


func site_label(site: Expedition.SearchSite) -> String:
	return expedition._ui.site_label(site)


func search_site(kind: StringName) -> Expedition.SearchSite:
	if expedition.recon_site != null and kind == expedition.recon_site.id:
		return expedition.recon_site
	if expedition.billboard_site != null and kind == expedition.billboard_site.id:
		return expedition.billboard_site
	for site: Expedition.SearchSite in expedition.sites:
		if site.id == kind: return site
	if kind == &"cash":
		return expedition._cash_site
	if kind == &"food":
		return expedition._food_site
	return null


func _toolbox_site() -> Expedition.SearchSite:
	return expedition.search_site(StringName(WorkshopSiteV1.site_id(expedition.supply.generated)))


func _is_event_site(site: Expedition.SearchSite) -> bool:
	return String(site.id) == EventSortieV1.site_id(expedition.supply.generated)


func _near_event_worker(site: Expedition.SearchSite) -> FieldActor:
	var nearest: FieldActor
	var limit: float = 14.0
	for actor: FieldActor in expedition.survivors:
		if actor.health <= 0.0 or not actor.visible or expedition.has_search_job(actor.member_id) \
				or actor.activity not in [FieldActor.Activity.IDLE, FieldActor.Activity.MOVING]:
			continue
		var distance: float = actor.position.distance_to(site.door)
		if distance <= limit:
			nearest = actor
			limit = distance
	return nearest


func confirm_event_choice(branch: String) -> bool:
	if expedition.event_sortie_panel == null or not expedition.event_sortie_panel.visible or expedition.task_event.branch != "" \
			or expedition.phase == Expedition.Phase.FINISHED or expedition.suspend_sealed or not expedition.field_join_error.is_empty() \
			or (expedition.bus_view != null and expedition.bus_view.running()) or branch not in [EventSortieV1.QUIET, EventSortieV1.FORCE]:
		return false
	var site: Expedition.SearchSite = expedition.search_site(StringName(EventSortieV1.site_id(expedition.supply.generated)))
	var worker: FieldActor = expedition._near_event_worker(site)
	if worker == null or not expedition._assign_search(site, worker, PackedVector2Array([worker.position])):
		return false
	expedition.task_event.branch = branch
	expedition.event_sortie_panel.hide()
	expedition._update_ui()
	return true


func _site_seconds(site: Expedition.SearchSite) -> float:
	return site.seconds if expedition.supply.generated.get("version")==4 or (expedition.supply.generated.get("version")==5 or (expedition.supply.generated.get("version")==6 or (expedition.supply.generated.get("version")==7 or (expedition.supply.generated.get("version")==8 or expedition.supply.generated.get("version")==9)))) else expedition.tuning.search_seconds


func _site_weapon(site: Expedition.SearchSite) -> Dictionary:
	for definition: Dictionary in expedition.supply.generated.get("sites",[]):
		if definition.id==String(site.id):return WeaponInventory.site_reward(expedition.sortie_id,expedition.supply.generated,definition,WeaponState.is_family(expedition.field_departure))
	return WeaponInventory.reward(expedition.sortie_id,WeaponState.is_family(expedition.field_departure))


func _tools_at(site_id: String) -> int:
	if expedition.supply.generated.has("economy_source"):
		for source: Dictionary in EconomyActions.tool_sources(expedition.supply.generated):
			if source.site_id == site_id:
				return int(source.count)
		return 0
	return int(site_id == WorkshopSiteV1.site_id(expedition.supply.generated))


func _carried_tools() -> int:
	var count: int = 0
	for source: Dictionary in EconomyActions.tool_sources(expedition.supply.generated):
		var site: Expedition.SearchSite = expedition.search_site(StringName(source.site_id))
		if site != null and site.searched:
			count += int(source.count)
	return count


func _searched_count() -> int:
	return expedition.sites.filter(func(site: Expedition.SearchSite) -> bool: return site.searched).size()


func _kind_searched(kind: StringName) -> bool:
	return expedition.sites.any(func(site: Expedition.SearchSite) -> bool: return site.kind==kind and site.searched)
