class_name PersonaViewModel
extends RefCounted
## One read-only projection for camp, live actors and the one revealed candidate.
static func camp(base: Dictionary, id: int, scope: String = "camp") -> Dictionary:
	var source: Dictionary=base
	if scope=="candidate":
		source=base.duplicate(true)
		RescuePoolState.grant(source,id)
	var member: Dictionary=SurvivorRoster.member(source.crew,id)
	if member.is_empty() or not PersonaState.enabled(base): return {}
	var recipe: Dictionary=SurvivorPersona.member(base.journey.build.persona,id,String(member.definition_id))
	var personal: Dictionary=SurvivorPersona.factors(recipe)
	if personal.is_empty(): return {}
	var passive: Dictionary=BuildItems.factors(base.journey.build.slots, BuildState.pool(base))
	var definition: SurvivorDefinition=SurvivorRoster.definition(id)
	var positive: Dictionary=SurvivorPersona.POSITIVE[recipe.positive_id]
	var negative: Dictionary=SurvivorPersona.NEGATIVE[recipe.negative_id]
	var model: Dictionary={"id":id,"definition_id":member.definition_id,"portrait":definition.portrait,
		"primary":TraitRules.NAMES[TraitRules.role(member)-1],"primary_short":TraitRules.NAMES[TraitRules.role(member)-1],
		"name":member.call_sign,"hp":member.health,"max_hp":GrowthRules.maximum(member),"level":member.growth.level,
		"alive":member.health>0,"status":"存活" if member.health>0 else "阵亡 · 只读历史","ammo":"",
		"positive":{"name":positive.name,"detail":positive.description},"negative":{"name":negative.name,"detail":negative.description},
		"trait_detail":TraitRules.description(member).replace("Trait ","").replace(" · PROJECT_TEMP",""),
		"scope":scope,"editable":scope=="camp" and member.health>0}
	if id == FirstAidV1.SOURCE_ID and CampaignRules.first_aid_enabled(base.journey.get("campaign")):
		if scope == "candidate":
			_show_first_aid(model)
			model.status = "确认归航入队后，下次出击生效"
		elif scope == "camp" and FirstAidV1.qualified(base):
			_show_first_aid(model)
	if id == WeaponInventory.MECHANIC_ID and scope != "candidate" and ContentWaveV1.enabled(base):
		model.primary = WeaponInventory.MECHANIC_TITLE
		model.primary_short = WeaponInventory.MECHANIC_TITLE
		var benefit: String = "生还归航并登记后，武器维修减 %d 币。" % WeaponInventory.MECHANIC_DISCOUNT
		if scope == "camp":
			benefit = "在营时武器维修减 %d 币。" % WeaponInventory.MECHANIC_DISCOUNT if WeaponInventory.mechanic_available(base) else "阵亡后不再提供维修折扣。"
		model.trait_detail = benefit + "与工坊取较高折扣，最低 1 币。\n" + String(model.trait_detail)
	var item: Dictionary=WeaponInventory.for_member(source,id)
	_weapon(model,item,personal,passive,TraitRules.factor(member,"shot"))
	var speed: float=125.0*TraitRules.factor(member,"move")*personal.move*passive.move
	model.move_detail="常态 %.2f · 当前 %.2f 像素/秒\n无临时疾行"%[speed,speed]
	model.work_detail="基准搜刮（30秒室内） %.4f 秒\n不影响救援接纳等待与奖励"%(30.0*TraitRules.factor(member,"search")*personal.work*passive.work)
	model.sources_detail="武器基础与实例等级/词条 → 主特长 → 个人特质 → 装备道具 → 临时能力，各自作用一次。\n主特长：射击间隔×%.3f，移动×%.2f，搜刮耗时×%.2f\n个人：枪伤×%.2f，近战×%.2f，移动×%.2f，换弹×%.2f，工作×%.2f\n道具：枪伤×%.2f，移动×%.2f，换弹×%.2f，工作×%.2f"%[TraitRules.factor(member,"shot"),TraitRules.factor(member,"move"),TraitRules.factor(member,"search"),personal.ranged,personal.melee,personal.move,personal.reload,personal.work,passive.damage,passive.move,passive.reload,passive.work]
	return model

static func field(world: Expedition, actor: FieldActor, status: String) -> Dictionary:
	if not world.persona_views.has(actor.member_id):
		var source: Dictionary=FieldJoinRules.action_base(world.field_departure,world.field_joins)
		world.persona_views[actor.member_id]=camp(source,actor.member_id,"field")
	var model: Dictionary=world.persona_views[actor.member_id].duplicate(true)
	if model.is_empty(): return {}
	model.scope="field"
	model.editable=false
	model.hp=actor.health
	model.max_hp=actor.max_health
	model.alive=actor.health>0
	model.name=actor.call_sign
	model.status="阵亡 · 只读历史" if actor.health<=0 else status
	if actor.member_id == FirstAidV1.SOURCE_ID:
		var first_aid: String = world.first_aid_status()
		if not first_aid.is_empty():
			_show_first_aid(model)
			model.first_aid_status = first_aid
			model.status = "%s · %s" % [first_aid, model.status]
		elif (not world.field_joins.is_empty() and world.field_joins[0].member_id == actor.member_id
				and CampaignRules.first_aid_enabled(world.field_departure.journey.get("campaign"))):
			_show_first_aid(model)
			model.trait_detail = "生还归航并登记后，下次出击可用。\n" + String(model.trait_detail)
	model.ammo=world._ammo_text(actor)
	var gun: WeaponDefinition=actor.weapon_definition
	model.weapon_detail=_weapon_text(gun,actor.trait_shot_factor)
	if actor.magazine!=null:
		model.reload_detail="%s\n实际换弹 %.3f 秒%s"%[model.ammo,gun.reload_seconds()*actor.magazine.reload_factor,"（工作期间暂停换弹）" if world.has_search_job(actor.member_id) else ""]
	model.move_detail="常态 %.2f · 当前 %.2f 像素/秒\n%s"%[actor.speed,actor.effective_speed(),"疾行剩余 %.2f 秒"%SpecialPowers.ability_remaining(world.powers,SpecialPowers.SPEED,world.elapsed) if actor.power_move_factor>1.0 else "无临时疾行"]
	var site: Expedition.SearchSite=world.member_site(actor.member_id)
	var seconds: float=world._site_seconds(site) if site!=null else 30.0
	var effective: float=seconds*actor.trait_search_factor*actor.persona_work_factor*BuildItems.frozen_factors(world.supply.generated.build).work
	model.work_detail="%s · 有效耗时 %.4f 秒\n%s"%[world.site_label(site) if site!=null else "基准搜刮（30秒室内）",effective,"进度 %.0f%%"%(site.progress/seconds*100.0) if site!=null else "接到任务后按实际站点基础计算"]
	return model

static func _show_first_aid(model: Dictionary) -> void:
	model.primary = FirstAidV1.TITLE
	model.primary_short = FirstAidV1.TITLE
	model.trait_detail = "每次出击可自动急救一次。为生命不高于 %.0f%%、相距不超过 %.0f 且无遮挡的队友恢复最多 %.0f HP。\n%s" % [
		FirstAidV1.HEALTH_RATIO * 100.0, FirstAidV1.RANGE, FirstAidV1.HEAL_AMOUNT, model.trait_detail]


static func _weapon(model: Dictionary, item: Dictionary, personal: Dictionary, passive: Dictionary, shot_factor: float) -> void:
	if item.is_empty():
		model.weapon_detail="无当前装备 · 历史武器以归航档案为准"
		model.reload_detail="无弹匣"
		return
	var gun: WeaponDefinition=WeaponModifiers.combat_definition(item)
	var melee: bool=CombatEquipment.melee(String(gun.id))
	if (melee and model.positive.name=="枪械专长") or (not melee and model.positive.name=="近战好手"):
		model.positive.detail+=" 当前武器不适用。"
	if melee:
		if model.positive.name=="装填熟手": model.positive.detail+=" 当前近战无换弹，不适用。"
		if model.negative.name=="装填生疏": model.negative.detail+=" 当前近战无换弹，不适用。"
	gun.damage*=personal.melee if melee else personal.ranged*passive.damage
	model.weapon_detail=_weapon_text(gun,shot_factor)
	model.weapon_texture=gun.presentation.texture
	if melee:
		model.ammo="近战 · 无弹匣"
		model.reload_detail="近战 · 无弹匣 / 无换弹\n装填特质对当前武器不适用"
	else:
		model.ammo="弹匣 %d/%d"%[gun.magazine_capacity(),gun.magazine_capacity()]
		model.reload_detail="容量 %d · 实际换弹 %.3f 秒\n备弹无限；搜刮期间暂停换弹"%[gun.magazine_capacity(),gun.reload_seconds()*personal.reload*passive.reload]

static func _weapon_text(gun: WeaponDefinition, shot_factor: float) -> String:
	var melee: bool=CombatEquipment.melee(String(gun.id))
	return "%s\n%s伤害 %.2f · 间隔 %.3f 秒\n%s %.0f"%[gun.display_name,"每弹丸（5颗，不保证全中）" if String(gun.id)=="shotgun_v1" else "单次",gun.damage,gun.interval if melee else gun.shot_interval(shot_factor),"距离" if melee else "射程",gun.shot_range]
