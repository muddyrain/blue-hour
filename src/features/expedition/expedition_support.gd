class_name ExpeditionSupport
extends RefCounted

var expedition: Expedition


func _init(owner: Expedition) -> void:
	expedition = owner


func apply_build(actor: FieldActor, profile: Dictionary = {}, item: Dictionary = {}) -> void:
	var factors: Dictionary=BuildItems.frozen_factors(expedition.supply.generated.build)
	if expedition.persona_mode():
		if profile.is_empty(): profile=SurvivorRoster.member(expedition._setup_crew,actor.member_id)
		var recipe: Dictionary=PersonaState.recipe(expedition.supply.generated,actor.member_id,actor.definition_id)
		var personal: Dictionary=SurvivorPersona.factors(recipe)
		if profile.is_empty() or personal.is_empty():
			expedition.setup_problem="PERSONA_ACTOR_IDENTITY"
			return
		if item.is_empty(): item=WeaponInventory.for_member(expedition.field_departure,actor.member_id)
		actor.weapon_definition=WeaponModifiers.combat_definition(item)
		var melee: bool=CombatEquipment.melee(String(actor.weapon_definition.id))
		actor.weapon_definition.damage*=personal.melee if melee else personal.ranged*factors.damage
		actor.speed=125.0*TraitRules.factor(profile,"move")*personal.move*factors.move
		actor.trait_shot_factor=TraitRules.factor(profile,"shot")
		actor.trait_search_factor=TraitRules.factor(profile,"search")
		actor.persona_work_factor=personal.work
		actor.power_move_factor=SpecialPowers.move_factor(expedition.powers,expedition.elapsed)
		if actor.magazine!=null: actor.magazine.reload_factor=personal.reload*factors.reload
		return
	# Definitions are freshly derived from immutable inventory once per actor setup.
	if not CombatEquipment.melee(String(actor.weapon_definition.id)): actor.weapon_definition.damage*=factors.damage
	actor.speed*=factors.move
	actor.power_move_factor=SpecialPowers.move_factor(expedition.powers,expedition.elapsed) if expedition.power_mode() else 1.0
	if actor.magazine!=null: actor.magazine.reload_factor=factors.reload


func support_available() -> bool:
	return expedition.build_mode() and not expedition.is_paused and not expedition.suspend_sealed and expedition.phase!=Expedition.Phase.FINISHED and not (expedition.bus_view!=null and expedition.bus_view.running()) and expedition.field_join_error.is_empty()


func support_world() -> Dictionary:
	var stamp: int = FreezeProfile.enter("support.capture")
	var paused: bool=expedition.is_paused
	expedition.is_paused=true
	expedition._clear_dead_worker()
	# Toxic/boss damage happens after the combat phase's ordinary cancellation.
	if expedition.combat_mode(): expedition.combat.cancel_unavailable(expedition)
	expedition._combat._reap_defeated_enemies()
	var value: Dictionary=SortieSnapshot.capture(expedition)
	expedition.is_paused=paused
	FreezeProfile.leave("support.capture", stamp)
	return value


func accept_burst(before: Dictionary) -> bool:
	var result: Dictionary = expedition.burst_commit.call(before) if expedition.burst_commit.is_valid() else {"error":ERR_UNAVAILABLE}
	if result.get("error", ERR_UNAVAILABLE) != OK:
		expedition.pending_burst = before
		expedition.is_paused = true
		expedition.support_aiming = false
		expedition._show_notice("爆囊冲击待确认 · 已暂停，继续后重试。")
		expedition._update_ui()
		expedition.queue_redraw()
		return false
	expedition.pending_burst = {}
	# The damage and original death facts already share the same durable publication.
	for actor: FieldActor in expedition.enemies:
		actor.free()
	expedition.enemies.clear()
	var issue: String = SortieSnapshot.apply(expedition, result.world)
	assert(issue.is_empty(), issue)
	expedition.is_paused = false
	var event: Dictionary = expedition.combat.burst.state.event
	for hit: Dictionary in event.hits:
		var actor: FieldActor = expedition.search_member(int(hit.member_id))
		expedition._hit_effect(actor.position, float(hit.before) - float(hit.after), true)
		expedition.combat_feedback.emit({"kind":"burst_hit", "member_id":int(hit.member_id), "actor":actor.actor_id,
			"enemy_id":event.source_id, "enemy_type":BurstRuntimeV1.KIND, "health":hit.after,
			"applied_damage":float(hit.before) - float(hit.after), "elapsed":expedition.elapsed})
	expedition.combat.burst.feedback(expedition, "burst_released")
	expedition._show_notice("爆囊冲击 · 命中 %d 人。" % event.hits.size() if not event.hits.is_empty() else "爆囊冲击 · 全员避开。")
	expedition._update_ui()
	return true


func request_heal() -> bool:
	if not expedition.support_available(): return false
	var before: Dictionary=expedition.support_world()
	var plan: Dictionary=BuildAuthority.plan_heal(before)
	if plan.is_empty(): return false
	return expedition._accept_support(before,expedition.basic_support.request("heal",plan))


func request_first_aid() -> bool:
	if not FirstAidV1.enabled(expedition.supply.generated) or not expedition.support_available() \
			or not expedition.support_commit.is_valid() or not expedition.basic_support.ready(FirstAidV1.KIND):
		return false
	var stamp: int = FreezeProfile.enter("support.first_aid_plan")
	var states: Array[Dictionary] = []
	for actor: FieldActor in expedition.survivors:
		states.append({"member_id":actor.member_id, "health":actor.health, "max_health":actor.max_health,
			"visible":actor.visible, "activity":actor.activity, "position":[actor.position.x, actor.position.y]})
	var plan: Dictionary = FirstAidV1.plan_on_map(states, expedition.layout.world_bounds, expedition.shot_obstacles)
	FreezeProfile.leave("support.first_aid_plan", stamp)
	if plan.is_empty():
		return false
	FreezeProfile.mark("aid_eligible", stamp)
	var before: Dictionary = expedition.support_world()
	return expedition._accept_support(before, expedition.basic_support.request(FirstAidV1.KIND, plan))


func apply_barricade_history(accepted: Array) -> void:
	var opened: bool = BarricadeState.opened(expedition.supply.generated, accepted, expedition.layout)
	if opened == expedition.barricade_open:
		return
	var stamp: int = FreezeProfile.enter("barricade.navigation")
	expedition.navigation = BarricadeV1.navigation(expedition.supply.generated, opened)
	expedition.barricade_open = opened
	expedition._barricade_view.present(opened, expedition.support_aiming and not opened)
	FreezeProfile.leave("barricade.navigation", stamp)


func request_airstrike(point: Vector2) -> bool:
	if not expedition.support_available(): return false
	var before: Dictionary=expedition.support_world()
	var plan: Dictionary=BuildAuthority.plan_airstrike(before,point)
	if plan.is_empty():
		if expedition.support_aiming:
			expedition._show_notice("空袭无法落在此处 · 请选择射程内无遮挡的地面")
			expedition._update_ui()
		return false
	return expedition._accept_support(before,expedition.basic_support.request("airstrike",plan))


func _accept_support(before: Dictionary, request: Dictionary) -> bool:
	if request.is_empty() or not expedition.support_commit.is_valid(): return false
	var confirmation: int = FreezeProfile.enter("support.confirm")
	var result: Dictionary=expedition.support_commit.call(before,request)
	FreezeProfile.leave("support.confirm", confirmation)
	if result.get("error",ERR_UNAVAILABLE)!=OK:
		expedition.pending_support={"before":before,"request":request}
		expedition.is_paused=true
		expedition.support_aiming=false
		expedition._show_notice("支援尚未确认，已暂停；请重试或暂存继续。"+String(result.get("reason","")))
		expedition._update_ui()
		return false
	expedition.pending_support={}
	var after: Dictionary=result.world
	var interrupted: bool = before.get("combat", {}).get("screamer", {}).get("phase") == "windup" \
		and after.get("combat", {}).get("screamer", {}).get("phase") == "cancelled"
	var burst_interrupted: bool = before.get("combat", {}).get("burst", {}).get("phase") == "windup" \
		and after.get("combat", {}).get("burst", {}).get("phase") == "cancelled"
	# All fallible validation and I/O preceded this visible state replacement.
	var preserve_aim: bool = request.kind in [FirstAidV1.KIND, SpecialPowers.RADIO] and expedition.support_aiming
	var was_open: bool = expedition.barricade_open
	var application: int = FreezeProfile.enter("support.apply")
	for enemy: FieldActor in expedition.enemies: enemy.free()
	expedition.enemies.clear()
	var issue: String=SortieSnapshot.apply(expedition,after)
	FreezeProfile.leave("support.apply", application)
	assert(issue.is_empty(),issue)
	expedition.is_paused=false
	if request.kind=="airstrike":
		expedition.support_aiming=false
		expedition.support_aim.impact(SortieSnapshot._vec(request.payload.point),request.payload.radius)
		var hits: int=request.payload.targets.size()
		var notice: String = "空袭命中 · %d 个目标" % hits if hits > 0 else "空袭已落地"
		if expedition.barricade_open and not was_open:
			notice += " · 路障已清除"
		if burst_interrupted:
			expedition.combat.burst.feedback(expedition, "burst_cancelled")
			notice += " · 爆囊冲击取消"
		if interrupted:
			expedition.combat.screamer.report_cancelled(expedition, notice)
		else:
			expedition._show_notice(notice)
	elif request.kind in [FirstAidV1.KIND, SpecialPowers.RADIO]:
		var first_aid: bool = request.kind == FirstAidV1.KIND
		if first_aid:
			FreezeProfile.mark("aid_hp_applied")
		expedition.support_aiming = preserve_aim
		var facts: Dictionary = after.support.accepted.back().facts
		var patient: FieldActor = expedition.search_member(int(facts.member_id))
		var amount: String = str(snappedf(float(facts.amount), 0.01))
		var title: String = FirstAidV1.TITLE if first_aid else SpecialPowers.RADIO_DEFINITION.name
		expedition._show_notice("%s · %s +%s HP" % [title, patient.call_sign, amount])
		expedition._combat_popup(patient.position + Vector2(12, -136), "+%s HP" % amount, Color("a5dfce"))
		var feedback: Dictionary = {"kind":request.kind, "member_id":facts.member_id,
			"amount":facts.amount, "health":facts.health_after}
		if first_aid:
			feedback.source_id = facts.source_id
		expedition.combat_feedback.emit(feedback)
	else:
		expedition._show_notice("治疗已确认")
	expedition._update_ui()
	return true


func support_plan_airstrike(point: Vector2) -> Dictionary:
	var view: Dictionary={"version":10,"generated":expedition.supply.generated,"survivors":[],"enemies":[]}
	for actor: FieldActor in expedition.survivors:
		view.survivors.append({"state":{"member_id":actor.member_id,"health":actor.health,"visible":actor.visible,"activity":actor.activity,"position":[actor.position.x,actor.position.y]}})
	for enemy: FieldActor in expedition.enemies:
		view.enemies.append({"state":{"actor_id":enemy.actor_id,"health":enemy.health,"visible":enemy.visible,"position":[enemy.position.x,enemy.position.y]}})
	return BuildAuthority.plan_airstrike_on_map(view,point,expedition.layout,expedition.navigation)


func refresh_power_factors() -> void:
	var factor: float=SpecialPowers.move_factor(expedition.powers,expedition.elapsed) if expedition.power_mode() else 1.0
	expedition.power_frozen=SpecialPowers.frozen(expedition.powers,expedition.elapsed) if expedition.power_mode() else false
	for actor: FieldActor in expedition.survivors: actor.power_move_factor=factor
	for actor: FieldActor in expedition.enemies:
		actor.motion_locked = expedition.power_frozen or (expedition.combat.screamer != null and expedition.combat.screamer.holds(actor)) \
			or (expedition.combat.burst != null and expedition.combat.burst.holds(actor)) \
			or (actor.enemy_behavior != null and actor.enemy_behavior.kind == NightHoundV1.KIND and actor.enemy_behavior.state == "windup")


func request_power(slot: int = 0) -> bool:
	if not expedition.power_mode() or not expedition.support_available() or not expedition.pending_power.is_empty() or not expedition.survivors.any(func(actor:FieldActor)->bool:return actor.health>0): return false
	if SpecialPowers.equipped_at(expedition.powers, slot) == SpecialPowers.RADIO:
		return expedition._support._request_aid_broadcast()
	var request: Dictionary=SpecialPowers.request(expedition.powers,slot)
	if request.is_empty(): return false
	return expedition._accept_power(expedition.support_world(),request)


func request_special() -> bool:
	# R fires the first ready expedition loadout power. Members have no separate active skill.
	if not expedition.power_mode():
		expedition._show_notice("当前没有可释放的特技")
		return false
	var slots: int = 1
	var loadout: Variant = expedition.powers.get("loadout")
	if loadout is Dictionary:
		slots = maxi(1, (loadout.slots as Array).size())
	elif expedition.third_power_panel != null:
		slots = 3
	elif expedition.second_power_panel != null:
		slots = 2
	for slot: int in range(slots):
		if SpecialPowers.equipped_at(expedition.powers, slot).is_empty():
			continue
		if expedition.request_power(slot):
			return true
	expedition._show_notice("当前没有可释放的特技")
	expedition._update_ui()
	return false


func _request_aid_broadcast() -> bool:
	if not expedition.support_commit.is_valid() or not expedition.basic_support.ready(SpecialPowers.RADIO):
		return false
	var before: Dictionary = expedition.support_world()
	var plan: Dictionary = BuildAuthority.plan_radio(before)
	if plan.is_empty():
		expedition._show_notice("急救广播 · 户外没有可治疗的在场队员，次数保留")
		expedition._update_ui()
		return false
	return expedition._accept_support(before, expedition.basic_support.request(SpecialPowers.RADIO, plan))


func _accept_power(before: Dictionary, request: Dictionary) -> bool:
	if not expedition.power_commit.is_valid(): return false
	var result: Dictionary=expedition.power_commit.call(before,request)
	if result.get("error",ERR_UNAVAILABLE)!=OK:
		expedition.pending_power={"before":before,"request":request}
		expedition.is_paused=true
		expedition.support_aiming=false
		expedition._show_notice("能力尚未确认，已暂停；解除故障后继续重试。"+String(result.get("reason","")))
		expedition._update_ui()
		return false
	expedition.pending_power={}
	expedition.powers=result.world.powers.duplicate(true)
	expedition.is_paused=false
	expedition.refresh_power_factors()
	expedition._show_notice("%s已生效 · 本次使用已保存"%SpecialPowers.definition(request.ability_id).name)
	expedition._update_ui()
	return true


func site_discovered(site: Expedition.SearchSite) -> bool:
	return expedition.recon_knowledge == null or site == expedition.recon_site or expedition.recon_knowledge.explored(site.door) \
		or (expedition.recon_site.searched and expedition._is_recon_target(site.id))


func _is_recon_target(id: StringName) -> bool:
	if expedition.recon_site == null:
		return false
	var marker: Dictionary = expedition.supply.generated.recon
	return String(id) in [marker.primary_id, marker.optional_id]


func _update_recon_knowledge() -> void:
	var changed: bool = false
	for actor: FieldActor in expedition.survivors:
		if actor.health > 0.0 and actor.visible and actor.activity != FieldActor.Activity.SEARCHING:
			if expedition.recon_knowledge.observe(actor.member_id, actor.position, expedition.elapsed):
				changed = true
	if changed:
		expedition.refresh_recon_view()


func recon_region() -> Rect2:
	var target: Vector2 = expedition.search_site(&"cash").door
	var origin: Vector2 = expedition.layout.world_bounds.position
	var size: Vector2 = Vector2.ONE * ReconActionV1.REGION
	var start: Vector2 = origin + ((target - origin) / size).floor() * size
	return Rect2(start, size).intersection(expedition.layout.world_bounds)
