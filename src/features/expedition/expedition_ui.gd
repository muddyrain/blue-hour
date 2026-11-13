class_name ExpeditionUi
extends RefCounted

var x: Expedition


func _init(owner: Expedition) -> void:
	x = owner


func site_label(site: Expedition.SearchSite) -> String:
	if site == x.recon_site:
		return "侦察点"
	if site == x.billboard_site:
		return "广告牌"
	if x._is_event_site(site):
		return EventSortieV1.TITLE
	return "工具回收点" if x._tools_at(String(site.id)) > 0 \
		else SearchWorkView.short_site(site.prop.title,x.sites.find(site)+1)


func _make_ui() -> void:
	x._hud = ExpeditionHud.new()
	x._hud.ui_theme = x.ui_theme
	x._hud.pause_requested.connect(x.toggle_pause)
	x._hud.extraction_requested.connect(x.request_bus_action)
	x._hud.help_changed.connect(func(expanded: bool) -> void: x.help_changed.emit(expanded))
	x.add_child(x._hud)
	x._hud.view.objective_locate_requested.connect(x.locate_objective)
	if not EventSortieV1.site_id(x.supply.generated).is_empty():
		x.event_sortie_panel = EventSortiePanel.new()
		x.event_sortie_panel.generated = x.supply.generated
		x.event_sortie_panel.choice_confirmed.connect(x.confirm_event_choice)
		x._hud.view.add_child(x.event_sortie_panel)
	if x.layout.world_data.get("version")==5:
		x._hud.view.place_help_above_lane()
	if x.battle_survival:
		x.drill_panel = BattleDrillPanel.new()
		x.drill_panel.expedition = x
		x.drill_panel.theme = x.ui_theme
		x._hud.view.add_child(x.drill_panel)
		x.drill_panel.visible = false
	if x.build_mode():
		x.support_panel=BasicSupportPanel.new()
		x.support_panel.position=Vector2(16,160)
		x.support_panel.heal_requested.connect(x.request_heal)
		x.support_panel.airstrike_requested.connect(x.toggle_support_aim)
		x._hud.view.add_child(x.support_panel)
		x.support_aim=BasicSupportAim.new()
		x._effects.add_child(x.support_aim)
	if x.power_mode():
		x.power_panel=PowerSlotPanel.new()
		x.power_panel.position=Vector2(16,300)
		x.power_panel.activation_requested.connect(x.request_power)
		x._hud.view.add_child(x.power_panel)
		if SpecialPowers.progression_version(x.powers.get("version")) and x.powers.loadout.slots.size() >= 2:
			x.second_power_panel = PowerSlotPanel.new()
			x.second_power_panel.slot_index = 1
			x.second_power_panel.position = Vector2(16, 378)
			x.second_power_panel.activation_requested.connect(x.request_power.bind(1))
			x._hud.view.add_child(x.second_power_panel)
		if SpecialPowers.progression_version(x.powers.get("version")) and x.powers.loadout.slots.size() >= 3:
			x.third_power_panel = PowerSlotPanel.new()
			x.third_power_panel.slot_index = 2
			x.third_power_panel.position = Vector2(16, 456)
			x.third_power_panel.activation_requested.connect(x.request_power.bind(2))
			x._hud.view.add_child(x.third_power_panel)
		x.power_view=PowerEffectView.new()
		x._effects.add_child(x.power_view)
	if BuildItems.specialty_pool(int(x.supply.generated.get("build", {}).get("version", 0))):
		var names: PackedStringArray = []
		for id: String in x.supply.generated.build.slots:
			if id in [BuildItems.AID_KIT, BuildItems.STRIDE_HARNESS, BuildItems.GUIDED_MAG]:
				var item: Dictionary = SpecialtyPresentation.definition(id)
				var enhanced: bool = id in x.supply.generated.build.get("enhanced", [])
				names.append("%s\n%s" % [item.name, BuildItems.effect_text(id, enhanced, int(x.supply.generated.build.version))])
		if not names.is_empty():
			var kit: PanelContainer = PanelContainer.new()
			kit.position = Vector2(16, 540 if x.third_power_panel != null else 460)
			kit.mouse_filter = Control.MOUSE_FILTER_IGNORE
			kit.add_theme_stylebox_override("panel", CampStyle.box(Color(0.045, 0.10, 0.14, 0.90), Color("48646d"), 8))
			var label: Label = CampStyle.label("\n".join(names), 13, CampStyle.TEAL)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if x.get_viewport_rect().size.y - kit.position.y < 80.0:
				label.text = "专精道具 · %d 件" % names.size()
				label.tooltip_text = "\n".join(names)
				label.mouse_filter = Control.MOUSE_FILTER_STOP
				label.focus_mode = Control.FOCUS_ALL
				label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				var detail: PanelContainer = PanelContainer.new()
				detail.name = "SpecialtyDetails"
				detail.position = Vector2(16, kit.position.y - 150)
				detail.add_theme_stylebox_override("panel", CampStyle.box(Color("10252f"), Color("48646d"), 8))
				detail.add_child(CampStyle.label("\n".join(names), 13, CampStyle.TEAL))
				detail.hide()
				x._hud.view.add_child(detail)
				label.gui_input.connect(func(event: InputEvent) -> void:
					if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) \
							or (event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]):
						detail.visible = not detail.visible
						label.grab_focus()
						label.accept_event())
			kit.add_child(label)
			x._hud.view.add_child(kit)
	x._update_ui()


func _update_ui() -> void:
	x._feedback._refresh_night_lighting()
	x._present_support()
	x._present_power()
	if x._hud == null:
		return
	if x.billboard_site != null:
		var worker: FieldActor = x.search_member(x.search_assignments.member_for(String(x.billboard_site.id)))
		var work_phase: String = x.search_assignments.phase_for(worker.member_id) if worker != null else ""
		x._billboard_view.present(x.billboard_site.progress, work_phase,
			SearchWorkView.short_call_sign(worker.call_sign) if worker != null else "")
	if x.event_sortie_panel != null and x.event_sortie_panel.visible:
		var site: Expedition.SearchSite = x.search_site(StringName(EventSortieV1.site_id(x.supply.generated)))
		if x.phase == Expedition.Phase.FINISHED or x.task_event.branch != "" or x._near_event_worker(site) == null:
			x.event_sortie_panel.hide()
	if x._readouts != null:
		if x.phase == Expedition.Phase.FINISHED:
			x._readouts.hide()
		else:
			_update_member_display()
			x._readouts.update_members(x.survivors, x.get_global_transform_with_canvas(), x.get_viewport_rect().size)
	var timing: Dictionary = x.time_status()
	var boarding: Dictionary = x.boarding_status(x.phase == Expedition.Phase.BOARDING)
	var engine_text: String = "发动引擎 →"
	if x.phase == Expedition.Phase.ENGINE:
		engine_text = "发动引擎 %d" % timing["engine_seconds"]
	elif x.phase == Expedition.Phase.BOARDING:
		engine_text = "等待幸存者"
	elif x.elapsed < x.tuning.bus_ready_seconds:
		engine_text = "巴士准备 %d 秒" % timing["bus_seconds"]
	var members: Array[Dictionary] = []
	var activities: Array[String] = ["警戒", "移动", "搜集中", "倒地", "回收中"]
	for actor: FieldActor in x.survivors:
		var assigned_site: Expedition.SearchSite = x.member_site(actor.member_id)
		var status: String = activities[actor.activity]
		if assigned_site != null:
			var work_phase: String = x.search_assignments.phase_for(actor.member_id)
			if assigned_site == x.billboard_site:
				status = "调查·广告牌" if work_phase == "working" else "前往·广告牌"
			else:
				status = SearchWorkView.actor_status(work_phase,site_label(assigned_site),TaskActions.outdoor_site(x.supply.generated,assigned_site.id))
		members.append({"id":actor.member_id,"label":"%s · %s" % [actor.call_sign, "阵亡" if actor.permanent_death else status],
			"call_sign":actor.call_sign,"status":_weapon_status(actor,status),"ammo":_ammo_text(actor),"detail":("%s · %s"%[status,site_label(assigned_site) if assigned_site.prop == null else assigned_site.prop.title] if assigned_site!=null else status),
			"colour":SurvivorRoster.definition_by_id(String(actor.definition_id)).colour,
			"hp":actor.health,"max_hp":actor.max_health})
	for member: Dictionary in members:
		member.level = SurvivorRoster.member(x._setup_crew,int(member.id)).growth.level
	if x.persona_mode():
		for member: Dictionary in members:
			member.persona=PersonaViewModel.field(x,x.search_member(int(member.id)),String(member.status))
	var pending: PackedStringArray = []
	for actor: FieldActor in x.survivors:
		pending.append("%02d +%d" % [actor.member_id,0 if actor.health <= 0 else x.xp_inputs.pending(actor.member_id)])
	var xp_text: String = "本次经验（归航后生效）："+" / ".join(pending)
	if not x.weapon_loot.is_empty():xp_text+="\n携带："+WeaponInventory.loot_description(x.weapon_loot[0])
	var objective: String = TaskActions.hud(x)
	if x.pump_station_mode():
		if not x.station_stopped():
			var worker: int = x.search_assignments.member_for(String(PumpStationAction.CONSOLE))
			objective = "前往控制柜 · 点击派工停机"
			if worker > 0:
				objective = "正在停机 · 再点控制柜可取消" if x.search_assignments.phase_for(worker) == "working" else "操作员正前往控制柜"
		elif x.encounter.defeat.is_empty():
			objective = "破阵者蓄力 · 横移避开冲锋道" if not x.encounter.pump.state.lane.is_empty() else "停机完成 · 击败破阵者"
		else:
			objective = "破阵者已倒地 · 集合回车"
		if x.phase in [Expedition.Phase.ENGINE, Expedition.Phase.BOARDING] and x.encounter.defeat.is_empty():
			objective = "提前撤离 · 未达成胜利，可回营再战"
	elif x.encounter != null and not x.encounter.defeat.is_empty() and CampFacilities.enabled(x.field_departure):
		objective = "破阵者已倒地 · 集合回车"
	var toolbox: Expedition.SearchSite = x._toolbox_site()
	x._hud.refresh({
		"toolbox":x._carried_tools() if x.supply.generated.has("economy_source") else int(toolbox.searched) if toolbox != null else -1,
		"exploration_objectives":_exploration_objective_rows() if x.exploration_mode() else [],
		"objective":objective,
		"mission_title":x.mission_title, "members":members,
		"can_extract":x.phase == Expedition.Phase.ACTIVE and x.elapsed >= x.tuning.bus_ready_seconds,
		"boarding":boarding,
		"engine_running":x.phase == Expedition.Phase.ENGINE,
		"can_gather":x.phase == Expedition.Phase.BOARDING and boarding.required > 0,
		"day": x.day, "seconds": timing["sortie_seconds"], "time_fraction": timing["sortie_fraction"],
		"paused": x.is_paused, "cash": x.initial_cash, "loot": x.loot,
		"food":x.initial_food,"food_loot":x.food_loot,"sites_searched":x._searched_count(),
		"sites_total":1 if x.pump_station_mode() else x.sites.filter(func(site: Expedition.SearchSite) -> bool: return x.supply.supports(site.kind)).size(),
		"has_food_source":x.supply.supports(&"food"),
		"route_hint":"可定位侦察点。走近站点后可搜集，侦察完成可提前标记两处。" if x.recon_site != null else x.layout.route_hint,
		"weapon_loot":x.weapon_loot.size(),
		"searched": x.searched, "kills": x.kills, "engine": engine_text,
		"notice": x._notice_text, "notice_visible": x._notice_clock > 0.0,
		"threat":x.threat_status(),
		"burst_warning":x.combat.burst.warning_text() if x.combat.burst != null and x.phase != Expedition.Phase.FINISHED else "",
	})
	if x.drill_panel != null:
		x.drill_panel.refresh()
	if x.station_art != null:
		x.station_art.set_stopped(x.station_stopped())
	for site: Expedition.SearchSite in x.sites:
		if x.recon_knowledge != null:
			var known: bool = x.site_discovered(site)
			if site.prop.searchable != known or (site.prop is AirdropProp and site.prop.visible != known):
				site.prop.searchable = known
				site.prop.primary_target = known and x.supply.generated.objective.site_ids.has(String(site.id))
				if site.prop is AirdropProp:
					site.prop.visible = known
				site.prop.queue_redraw()
		var worker: FieldActor = x.search_member(x.search_assignments.member_for(String(site.id)))
		if site.prop is ExplorationProp:
			var faded: bool=x.survivors.any(func(actor: FieldActor) -> bool: return actor.visible and actor.health>0 and actor.position.y<site.prop.position.y and actor.position.distance_to(site.prop.position)<105.0)
			(site.prop as ExplorationProp).present({"searched":site.searched,"progress":site.progress},worker.member_id if worker!=null else 0,worker.call_sign if worker!=null else "",faded)
		site.prop.searched = site.searched
		var work_phase: String = x.search_assignments.phase_for(worker.member_id) if worker != null else ""
		var fraction: float = site.progress / x._site_seconds(site)
		if not site.prop.loot_category.is_empty():
			site.prop.present_loot(worker.member_id if worker != null else 0, worker.call_sign if worker != null else "", work_phase, fraction)
		else:
			var text: String = SearchWorkView.building_text(worker.member_id, worker.call_sign, work_phase, TaskActions.outdoor_site(x.supply.generated,site.id)) if worker != null else ""
			site.prop.update_work(worker.actor_id if worker != null else -1,
				fraction, worker != null and x.work_state_matches(worker,site), worker.call_sign if worker != null else "", text)


func _update_member_display() -> void:
	var both_visible: bool = x.survivors.size() == 2 and x.survivors[0].visible and x.survivors[1].visible and x.living_count() == 2
	var separation: float = x.survivors[0].position.distance_to(x.survivors[1].position) if x.survivors.size() == 2 else 0.0
	var shift: float = clampf(1.0 - separation / 56.0, 0.0, 1.0) * 12.0 if both_visible else 0.0
	for index: int in range(x.survivors.size()):
		x.survivors[index].visual.position.x = shift * (-1.0 if index == 0 else 1.0)

	for building: FieldProp in x._buildings:
		var hidden_friend: bool = false
		for actor: FieldActor in x.survivors:
			if actor.visible and building.obscures(actor.position):
				hidden_friend = true
		building.show_behind_roof(hidden_friend)


func _ammo_text(actor: FieldActor) -> String:
	if CombatEquipment.melee(String(actor.weapon_definition.id)): return actor.weapon_definition.display_name + " · 近战"
	if actor.magazine==null:return "%s · 旧规则"%actor.weapon_definition.display_name if actor.weapon_definition!=null else ""
	# Keep the task destination readable; reload feedback uses the ammunition line.
	if x.has_search_job(actor.member_id) and actor.magazine.reloading:
		return "换弹暂停" if actor.activity in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING] else "换弹 %.1fs"%actor.magazine.remaining
	return "%s %d/%d · ∞"%[actor.weapon_definition.display_name,actor.magazine.rounds,actor.magazine.capacity()]


func _weapon_status(actor: FieldActor, action: String) -> String:
	if actor.activity==FieldActor.Activity.DOWN:return "阵亡" if actor.permanent_death else "倒地"
	if x.has_search_job(actor.member_id): return action
	if actor.magazine!=null and actor.magazine.reloading:
		return "%s · 换弹暂停"%action if actor.activity in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING] else "%s · 换弹%.1fs"%[action,actor.magazine.remaining]
	return action

func first_aid_status() -> String:
	if not FirstAidV1.enabled(x.supply.generated):
		return ""
	if not x.basic_support.ready(FirstAidV1.KIND):
		return "已用"
	var medic: FieldActor = x.search_member(FirstAidV1.SOURCE_ID)
	var present: bool = medic != null and FirstAidV1.available({"health":medic.health,
		"visible":medic.visible, "activity":medic.activity})
	return "可用" if present else "暂不可用"

func _exploration_objective_rows() -> Array[Dictionary]:
	var generated: Dictionary = x.supply.generated
	var rescue_revealed: bool = x.rescue_target != null and x.rescue_target.revealed()
	var rows: Array[Dictionary] = ExplorationSites.objective_rows(
		{"type":generated.type,"objective":generated.objective,"optional_objectives":generated.exploration.optional_objectives},
		WorldSites.facts(x),rescue_revealed and x.rescue_target.npc.health > 0.0,
		x.rescue_target.candidate_name() if rescue_revealed else "")
	var investigation: Dictionary = generated.get("investigation", {})
	if x.pump_station_mode():
		var stopped: bool = x.station_stopped()
		rows[0].title = "停机完成 · 击败破阵者" if stopped else "控制柜 · 派工停机"
		rows[0].complete = stopped and x.encounter != null and not x.encounter.defeat.is_empty()
		if rows[0].complete:
			rows[0].title = "破阵者已倒地 · 集合回车"
		rows[0].done = int(rows[0].complete)
		rows[0].hint = "右装卸道较近，左检修道有实墙。冲锋锁线后横移。"
	elif x.event_sortie_panel != null:
		var site: Expedition.SearchSite = x.search_site(StringName(EventSortieV1.site_id(generated)))
		var branch: String = x.task_event.branch
		if branch.is_empty():
			rows[0].hint = "左键前往站点，抵达后选取方案。"
		else:
			var title: String = EventSortieV1.QUIET_TITLE if branch == EventSortieV1.QUIET else "强开 · 警报" if x.task_event.started else EventSortieV1.FORCE_TITLE
			rows[0].title = "%s %.1f/%.0f秒" % [title, site.progress, site.seconds]
			if site.searched:
				rows[0].title = "已携带 %s · %s" % [_event_reward_text(EventSortieV1.reward(generated, branch)), "强开警报" if x.task_event.started else "待归航"]
			rows[0].hint = "无事件增援" if branch == EventSortieV1.QUIET else "警报已触发" if x.task_event.started else "选择已锁定 · 待开工"
	elif not investigation.is_empty():
		rows[0].title = "%s · %s" % ["已携带" if rows[0].complete else "调查", CampaignRules.CLUE_NAMES[investigation.clue_id]]
		rows[0].hint = "搜索标记建筑取得线索，生还撤离并确认归航后登记。"
	elif generated.has("rare_policy"):
		if generated.type == "supply":
			rows[0].title = "近处配货间 · %d 粮" % RareSortie.NEAR_FOOD
			rows[0].hint = "取粮后可直接归航。"
			rows[1].title = "后装卸区 · %d 粮" % RareSortie.DEEP_FOOD
			rows[1].hint = "深入作业会压缩天黑前回车时间。"
		else:
			rows[0].title = "露天武器箱 · 武器 1 件"
			rows[0].hint = "增援已触发，可集合归航。" if x.task_event.started else "首次开工引来增援。"
			rows[1].title = "器材库 · %d 币" % RareSortie.EQUIPMENT_CASH
			rows[1].hint = "可选，带回用于维修或建设。"
	elif generated.get("mission_policy") == 1 and generated.type == "airdrop":
		rows[0].title = "装备 · 露天回收"
		if generated.has("gear_build_policy") and not generated.build.drops.is_empty():
			rows[0].title += " · 道具 %d 件" % generated.build.drops.size()
		rows[0].hint = "一次性增援已触发。" if x.task_event.started else "首次开工触发一次增援，工作中可受击。"
	var toolbox: Expedition.SearchSite = x._toolbox_site()
	if generated.has("economy_source"):
		for source: Dictionary in EconomyActions.tool_sources(generated):
			var tool_site: Expedition.SearchSite = x.search_site(StringName(source.site_id))
			rows.insert(1, {"id":"tools:" + String(source.site_id), "title":"工具 ×%d" % int(source.count),
				"optional":source.site_id not in generated.objective.site_ids, "done":int(tool_site.searched),
				"total":1,"complete":tool_site.searched,"site_ids":[source.site_id],
				"hint":"完成此点即可携带，归航确认后入库。"})
	elif toolbox != null:
		rows.insert(1, {"id":"toolbox", "title":"工具箱 ×1", "optional":true, "done":int(toolbox.searched),
			"total":1, "complete":toolbox.searched, "site_ids":[String(toolbox.id)],
			"hint":"完成此点原搜集即可携带，归航确认后入库。"})
	if x.recon_site != null:
		x._feedback._present_recon_objectives(rows)
	if x.billboard_site != null:
		rows.insert(1, {"id":BillboardActionV1.SITE_ID,
			"title":"超市广告牌 · 已调查" if x.billboard_site.searched else "超市广告牌 · %.1f/4 秒" % x.billboard_site.progress,
			"optional":true, "complete":x.billboard_site.searched, "done":int(x.billboard_site.searched), "total":1,
			"site_ids":[BillboardActionV1.SITE_ID],
			"hint":BillboardFieldView.DONE if x.billboard_site.searched else BillboardFieldView.HINT.replace("\n", " · ")})
	return rows


func _event_reward_text(reward: Dictionary) -> String:
	return "%d 粮" % reward.food if reward.food > 0 else "%d 币" % reward.cash
