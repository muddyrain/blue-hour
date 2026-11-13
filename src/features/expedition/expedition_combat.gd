class_name ExpeditionCombat
extends RefCounted

var expedition: Expedition


func _init(owner: Expedition) -> void:
	expedition = owner


func _update_combat() -> void:
	for actor: FieldActor in expedition.survivors:
		if expedition.combat_mode() and CombatRuntime.patterned(String(actor.weapon_definition.id)):
			expedition.combat.attack(expedition,actor,expedition.combat_delta)
			if expedition.is_paused: return
			continue
		if actor.activity in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING, FieldActor.Activity.RECOVERING]:
			continue
		if actor.magazine!=null and not actor.magazine.can_fire():continue
		var target: FieldActor = expedition._attack_target(actor)
		if target != null:
			actor.aim = target.position - actor.position
			var decision: AttackRules.Decision = expedition.evaluate_attack(actor, target)
			if decision.can_fire:
				expedition._fire_ranged(actor, target, decision)
				if expedition.is_paused:
					return
		else:
			actor.aim = Vector2.ZERO
	for enemy: FieldActor in expedition.enemies:
		if expedition.power_frozen or enemy.activity == FieldActor.Activity.DOWN or (expedition.encounter!=null and expedition.encounter.is_boss(enemy)):
			continue
		if expedition.combat_mode() and expedition.combat.holds(enemy): continue
		var target: FieldActor = expedition._nearest_target(enemy, expedition.survivors, 28.0)
		var damage: float = expedition.tuning.enemy_damage
		var behavior: EnemyBehavior = enemy.enemy_behavior
		if behavior != null and behavior.kind == BurstRuntimeV1.KIND and expedition.combat.burst != null and expedition.combat.burst.state.phase != "released":
			continue
		if behavior!=null and behavior.kind==EnemyRules.RUSH and target!=null and not behavior.legal(expedition,enemy,target,EnemyRules.POLICY.melee_range):
			target = null
		var hound: bool = behavior != null and behavior.kind == NightHoundV1.KIND
		var timed_attack: bool = hound or (behavior != null and behavior.kind == EnemyRules.HEAVY)
		if timed_attack:
			if behavior.state=="windup":
				if hound and behavior.windup_remaining > 0.0:
					continue
				target = behavior.locked_target(expedition)
				if target==null or not behavior.legal(expedition,enemy,target,EnemyRules.POLICY.melee_range):
					behavior.cancel(expedition,enemy,true)
					continue
				if behavior.windup_remaining>0.0:
					continue
			elif target!=null and enemy.cooldown<=0.0 and behavior.legal(expedition,enemy,target,EnemyRules.POLICY.melee_range):
				behavior.arm(expedition,enemy,target)
				continue
			else:
				continue
			damage = NightHoundV1.DAMAGE if hound else EnemyRules.POLICY.heavy_damage
		if target != null and enemy.cooldown <= 0.0:
			if behavior != null:
				damage = CombatRuntime.direct_melee_damage(behavior.kind, damage, expedition.powers, expedition.elapsed)
			var direction: Vector2 = (target.position - enemy.position).normalized()
			var health_before: float = target.health
			if not target.take_damage(damage, direction):
				if target.damage_gate.is_valid() and not expedition.is_paused:
					expedition._show_notice("保存确认未完成：已暂停，生命与攻击未应用。排除写入故障后继续重试。")
					expedition.toggle_pause()
				return
			if expedition.battle_survival and target.health == 0:
				expedition._show_notice("%02d %s 已阵亡 · 战斗死亡已持久确认" % [target.member_id,target.call_sign])
			expedition._clear_dead_worker()
			enemy.cooldown = behavior.attack_interval(expedition.tuning.enemy_interval) if hound else expedition.tuning.enemy_interval
			if timed_attack:
				behavior.reset(enemy,expedition.tuning.enemy_speed)
			enemy.visual.show_attack(direction)
			expedition._hit_effect(target.position, damage, true)
			var feedback: Dictionary = {"kind": "hit", "actor": target.actor_id, "member_id":target.member_id, "health": target.health,
				"applied_damage": health_before - target.health, "elapsed": expedition.elapsed}
			feedback.merge({"enemy_id":enemy.actor_id,"enemy_type":behavior.kind})
			expedition.combat_feedback.emit(feedback)
	expedition._update_enemy_behaviors(0.0)
	expedition._combat._reap_defeated_enemies()


func _update_enemy_behaviors(delta: float) -> void:
	if expedition.power_frozen:
		return
	for enemy: FieldActor in expedition.enemies:
		if enemy.enemy_behavior!=null and not (expedition.encounter!=null and expedition.encounter.is_boss(enemy)):
			enemy.enemy_behavior.update(expedition,enemy,delta)
			enemy.sync_enemy_visual()


func _reap_defeated_enemies() -> void:
	for index: int in range(expedition.enemies.size() - 1, -1, -1):
		if expedition.enemies[index].activity == FieldActor.Activity.DOWN:
			if expedition.combat.screamer != null:
				expedition.combat.screamer.removed(expedition, expedition.enemies[index].actor_id)
			if expedition.combat.burst != null:
				expedition.combat.burst.removed(expedition, expedition.enemies[index].actor_id)
			if expedition.enemies[index].enemy_behavior!=null:
				expedition.enemies[index].enemy_behavior.cancel(expedition,expedition.enemies[index])
			expedition._corpses.append(expedition.enemies[index])
			expedition._corpse_times.append(0.95)
			expedition.combat_feedback.emit({"kind": "defeat", "actor": expedition.enemies[index].actor_id, "elapsed": expedition.elapsed})
			expedition.enemies.remove_at(index)


func evaluate_attack(actor: FieldActor, target: FieldActor) -> AttackRules.Decision:
	return AttackRules.evaluate(expedition._combatant(actor), expedition._combatant(target),
		actor.position + actor.visual.aimed_shot_offset(target.position - actor.position),
		actor.weapon_definition.shot_range, actor.cooldown, expedition.shot_obstacles)


func _fire_ranged(actor: FieldActor, target: FieldActor, decision: AttackRules.Decision) -> void:
	var weapon: WeaponDefinition = actor.weapon_definition
	var secondary: FieldActor
	var impact: Vector2 = Vector2.INF
	var closest: float = INF
	if weapon.combat_affix == WeaponModifiers.PIERCE:
		for candidate: FieldActor in expedition.enemies:
			if candidate.actor_id == target.actor_id:
				continue
			var hit: Vector2 = AttackRules.pierce_hit(decision, actor.position, expedition._combatant(candidate),
				weapon.shot_range, expedition.shot_obstacles)
			if not hit.is_finite():
				continue
			var distance: float = decision.hit_to.distance_squared_to(hit)
			if distance < closest or (distance == closest and secondary != null and candidate.actor_id < secondary.actor_id):
				secondary = candidate
				impact = hit
				closest = distance
	var secondary_damage: float = weapon.damage * AttackRules.PIERCE_DAMAGE_FACTOR
	var fatal: int = int(target.health <= weapon.damage)
	if secondary != null and secondary.health <= secondary_damage:
		fatal += 1
	# Reserve room for both defeat facts before the first hit can change HP.
	if not expedition.xp_inputs.has_capacity() or expedition.xp_inputs.events.size() + fatal > GrowthRules.MAX_EVENTS:
		expedition._combat._reap_defeated_enemies()
		expedition._show_notice("成长账本达到安全容量，已暂停；不能丢弃事件或虚报保存成功。")
		expedition.toggle_pause()
		return
	if (not expedition._combat._ranged_hit_recordable(actor, target, weapon.damage)
			or (secondary != null and not expedition._combat._ranged_hit_recordable(actor, secondary, secondary_damage))):
		expedition._show_notice("成长来源不可提交，已暂停；生命、弹量与开火均未应用。")
		expedition.toggle_pause()
		return
	var recorded: Array[Dictionary] = []
	var cooldown_before: float = actor.cooldown
	var health_before: float = target.health
	if not expedition._combat._commit_ranged_hit(actor, target, weapon.damage, recorded):
		return
	var extra: Dictionary = {}
	if secondary != null:
		var secondary_before: float = secondary.health
		if expedition._combat._commit_ranged_hit(actor, secondary, secondary_damage, recorded):
			extra = {"target": secondary.actor_id, "target_health": secondary.health,
				"damage": secondary_damage, "applied_damage": secondary_before - secondary.health,
				"to": secondary.position, "hit_to": impact}
		elif expedition.is_paused:
			return
	actor.cooldown = weapon.shot_interval(actor.trait_shot_factor)
	var refunded: int = 0
	if actor.magazine != null:
		refunded = actor.magazine.commit_shot(weapon.combat_affix == WeaponModifiers.REFUND
			and target.activity == FieldActor.Activity.DOWN)
	for receipt: Dictionary in recorded:
		expedition.growth_input_recorded.emit(receipt)
	actor.visual.show_fire(actor.aim)
	var muzzle: Vector2 = actor.position + actor.visual.muzzle_offset(actor.aim)
	expedition._shot_effect(muzzle, target.position, weapon.damage)
	if not extra.is_empty():
		expedition._shot_trace(decision.hit_to, impact, Color("a5dfce"))
		expedition._feedback._draw_hit_effect(secondary.position, float(extra.applied_damage), false, "穿透 ")
	if refunded > 0:
		expedition._combat_popup(actor.position + Vector2(12, -136), "击倒补弹 +%d" % refunded, Color("a5dfce"))
	var feedback: Dictionary = {"kind": "shot", "actor": actor.actor_id,
		"target": target.actor_id, "target_health": target.health,
		"damage": weapon.damage, "from": actor.position, "to": target.position,
		"instance_id":actor.weapon_instance_id, "weapon_id":String(weapon.id), "interval":actor.cooldown,
		"applied_damage": health_before - target.health,
		"magazine":actor.magazine.snapshot() if actor.magazine!=null else {},"member_id":actor.member_id,"shot_from":muzzle,"hit_to":decision.hit_to,
		"foot_distance":decision.distance,"shot_range":weapon.shot_range,
		"blocker_id":String(decision.blocker_id),"attack_reason":String(decision.reason),
		"predicted_muzzle_error":muzzle.distance_to(decision.shot_from),
		"cooldown_before":cooldown_before,"cooldown_after":actor.cooldown,
		"moving": actor.activity == FieldActor.Activity.MOVING, "elapsed": expedition.elapsed,
		"weapon": String(actor.visual.weapon_view.id), "row": actor.visual.direction_row,
		"facing": actor.visual.presentation_state()["facing"]}
	if not weapon.combat_affix.is_empty():
		feedback.merge({"affix": weapon.combat_affix, "secondary": extra, "rounds_refunded": refunded})
	expedition.combat_feedback.emit(feedback)


func _ranged_hit_recordable(actor: FieldActor, target: FieldActor, damage: float) -> bool:
	return target.health > damage or (expedition.growth_inputs.can_record(actor, target, expedition.elapsed)
		and expedition.xp_inputs.can_record(expedition, actor, target))


func _commit_ranged_hit(actor: FieldActor, target: FieldActor, damage: float, recorded: Array[Dictionary]) -> bool:
	if not target.take_damage(damage, actor.position.direction_to(target.position)):
		return false
	if target.activity == FieldActor.Activity.DOWN:
		expedition.kills += 1
		actor.confirmed_kills += 1
		if not expedition.loadout_snapshot.is_empty():
			var receipt: Dictionary = expedition.growth_inputs.accept_defeat(actor, target, expedition.elapsed)
			if not receipt.is_empty():
				if not expedition.xp_inputs.accept(expedition, actor, target, receipt):
					expedition._show_notice("成长来源校验失败，已暂停；本次不会伪造经验。")
					expedition.toggle_pause()
					return false
				recorded.append(receipt)
			if expedition.encounter != null:
				expedition.encounter.record_defeat(target, receipt)
	return true


func _combatant(actor: FieldActor) -> AttackRules.Combatant:
	return AttackRules.Combatant.new(actor.position, actor.health > 0.0,
		actor.visible and actor.activity not in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING], actor.is_enemy)


func _attack_target(actor: FieldActor) -> FieldActor:
	var closest: float = INF
	var result: FieldActor
	for candidate: FieldActor in expedition.enemies:
		var decision: AttackRules.Decision = expedition.evaluate_attack(actor, candidate)
		if decision.targetable and decision.distance < closest:
			closest = decision.distance
			result = candidate
	return result


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


func _visual_contact(enemy: FieldActor) -> Vector2:
	# Read-only display query; never chooses or changes the combat target/path.
	var nearest: Vector2 = Vector2.INF
	var distance: float = 50.0
	for actor: FieldActor in expedition.survivors:
		if actor.health <= 0.0 or not actor.visible or actor.activity == FieldActor.Activity.SEARCHING:
			continue
		var offset: Vector2 = actor.position - enemy.position
		if offset.length() < distance:
			distance = offset.length()
			nearest = offset
	return nearest
