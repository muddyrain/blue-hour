class_name CombatRuntime
extends RefCounted
## Expedition-owned mode adapter. Original actors, XP, damage gate and transaction remain authoritative.
var actions: Dictionary={}
var toxic: Dictionary={}
var spawns: Dictionary={}
var toxic_view: Node2D
var screamer: ScreamerRuntimeV1
var burst: BurstRuntimeV1

func snapshot() -> Dictionary:
	var value: Dictionary = {"version":1,"actions":actions.duplicate(true),"toxic":toxic.duplicate(true),"spawns":spawns.duplicate(true)}
	if screamer != null:
		value.version = 2
		value.screamer = screamer.state.duplicate(true)
	if burst != null:
		value.version = 3
		value.burst = burst.state.duplicate(true)
	return value

func restore(value: Dictionary) -> void:
	actions=value.actions.duplicate(true)
	toxic=value.toxic.duplicate(true)
	spawns=value.spawns.duplicate(true)
	if screamer != null:
		screamer.state = value.screamer.duplicate(true)
	if burst != null:
		burst.state = value.burst.duplicate(true)

func setup(world: Expedition) -> void:
	toxic=ToxicV1.initial()
	toxic_view=ToxicVisualV1.new()
	toxic_view.z_index=-1
	world.add_child(toxic_view)
	if ScreamerPolicyV1.enabled(world.supply.generated):
		screamer = ScreamerRuntimeV1.new()
	if ContentWaveV1.eligible(world.supply.generated):
		burst = BurstRuntimeV1.new()

static func patterned(weapon_id: String) -> bool:
	return CombatEquipment.melee(weapon_id) or weapon_id == "shotgun_v1"

static func direct_melee_damage(kind: String, amount: float, powers: Dictionary, elapsed: float) -> float:
	if kind in [EnemyRules.NORMAL, EnemyRules.RUSH, EnemyRules.HEAVY] \
			and SpecialPowers.ability_remaining(powers, SpecialPowers.SUPPRESSION, elapsed) > 0.0:
		return amount * float(SpecialPowers.definition(SpecialPowers.SUPPRESSION).direct_damage_factor)
	return amount

func action(actor: FieldActor) -> Dictionary:
	var key: String=str(actor.member_id)
	if not actions.has(key): actions[key]={"sequence":0,"remaining":0.0,"heading":[1.0,0.0],"committed":[]}
	return actions[key]

func rows(actors: Array[FieldActor]) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for actor: FieldActor in actors:
		result.append({"id":actor.actor_id if actor.is_enemy else actor.member_id,"foot":actor.position,"alive":actor.health>0,"available":actor.visible and actor.activity not in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING]})
	return result

func attack(world: Expedition,actor: FieldActor,delta: float) -> void:
	var gun: String=String(actor.weapon_definition.id)
	if not patterned(gun): return
	var melee: bool = CombatEquipment.melee(gun)
	var state: Dictionary=action(actor)
	var active: bool=actor.health>0 and actor.visible and actor.activity not in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]
	if not active:
		state.remaining=0.0
		return
	if melee and state.remaining>0:
		state.remaining=maxf(0.0,float(state.remaining)-delta)
		actor.aim=Vector2(state.heading[0],state.heading[1])
		if state.remaining==0:
			var plan: Array[Dictionary]=CombatPatternsV1.melee_plan(gun,actor.position,actor.aim,rows(world.enemies),world.shot_obstacles,actor.weapon_definition.shot_range)
			if not _commit(world,actor,plan,state): return
			actor.visual.show_fire(actor.aim)
			world.combat_feedback.emit({"kind":"hammer_swing" if gun == CombatEquipment.HAMMER_ID else "axe_swing","member_id":actor.member_id,"sequence":state.sequence,"targets":state.committed.duplicate(),"elapsed":world.elapsed})
		return
	if actor.cooldown>0 or (actor.magazine!=null and not actor.magazine.can_fire()): return
	var target: FieldActor=_target(world,actor)
	if target==null: return
	actor.aim=actor.position.direction_to(target.position)
	state.heading=[actor.aim.x,actor.aim.y]
	if melee:
		state.sequence+=1
		state.committed=[]
		state.remaining=float(CombatEquipment.melee_policy(gun).windup)
		actor.cooldown=actor.weapon_definition.interval
		return
	var muzzle: Vector2=actor.position+actor.visual.aimed_shot_offset(actor.aim)
	var plan: Dictionary=CombatPatternsV1.shotgun_plan(actor.position,CombatEquipment.shot_origin(actor.position),actor.aim,rows(world.enemies),world.shot_obstacles,actor.weapon_definition.shot_range,actor.weapon_definition.combat_affix == WeaponModifiers.PIERCE)
	var kills_before: int = actor.confirmed_kills
	state.sequence+=1
	state.committed=[]
	if not _commit(world,actor,plan.targets,state):
		state.sequence-=1
		return
	var refunded: int = actor.magazine.commit_shot(actor.weapon_definition.combat_affix == WeaponModifiers.REFUND and actor.confirmed_kills > kills_before)
	if refunded > 0:
		world._combat_popup(actor.position + Vector2(12,-136),"击倒补弹 +1",Color("a5dfce"))
	actor.cooldown=actor.weapon_definition.shot_interval(actor.trait_shot_factor)
	actor.visual.show_fire(actor.aim)
	for ray: Dictionary in plan.rays:
		if (ray.to-muzzle).dot(actor.aim)<=0: continue
		var line: Line2D=Line2D.new()
		line.add_point(IsoSpace.to_view(muzzle))
		line.add_point(IsoSpace.to_view(ray.to))
		line.width=1.8
		line.default_color=Color("ffd78b")
		world._effects.add_child(line)
		line.create_tween().tween_property(line,"modulate:a",0.0,0.10).finished.connect(line.queue_free)
		if ray.has("pierce_to"):
			world._shot_trace(ray.to,ray.pierce_to,Color("a5dfce"))
	world.combat_feedback.emit({"kind":"shotgun","member_id":actor.member_id,"instance_id":actor.weapon_instance_id,"sequence":state.sequence,"targets":plan.targets,"rays":plan.rays,"rounds_refunded":refunded,"damage":actor.weapon_definition.damage,"magazine":actor.magazine.snapshot(),"elapsed":world.elapsed})

func _target(world: Expedition,actor: FieldActor) -> FieldActor:
	var ordered: Array[FieldActor]=world.enemies.duplicate()
	ordered.sort_custom(func(a:FieldActor,b:FieldActor)->bool:return actor.position.distance_squared_to(a.position)<actor.position.distance_squared_to(b.position) or (actor.position.distance_squared_to(a.position)==actor.position.distance_squared_to(b.position) and a.actor_id<b.actor_id))
	for target: FieldActor in ordered:
		var start: Vector2=CombatEquipment.shot_origin(actor.position)
		if AttackRules.evaluate(world._combatant(actor),world._combatant(target),start,actor.weapon_definition.shot_range,0.0,world.shot_obstacles).targetable: return target
	return null

func _commit(world: Expedition,actor: FieldActor,plan: Array,state: Dictionary) -> bool:
	var fatal: int=0
	for hit: Dictionary in plan:
		var target: FieldActor=_enemy(world,int(hit.id))
		if target==null: return false
		if target.health<=actor.weapon_definition.damage*float(hit.hits):
			fatal+=1
			if (not world.growth_inputs.can_record(actor,target,world.elapsed) or not world.xp_inputs.can_record(world,actor,target)): return _blocked(world)
	if world.xp_inputs.events.size()+fatal>GrowthRules.MAX_EVENTS: return _blocked(world)
	# Validate the complete batch before any HP, ammo, feedback or XP changes.
	for hit: Dictionary in plan:
		var target: FieldActor=_enemy(world,int(hit.id))
		var damage: float=actor.weapon_definition.damage*float(hit.hits)
		if not target.take_damage(damage,actor.position.direction_to(target.position)): return _blocked(world)
		state.committed.append(int(hit.id))
		world._hit_effect(target.position,damage,false)
		if target.health==0:
			world.kills+=1
			actor.confirmed_kills+=1
			var event: Dictionary=world.growth_inputs.accept_defeat(actor,target,world.elapsed)
			if not world.xp_inputs.accept(world,actor,target,event): return _blocked(world)
			if world.encounter!=null: world.encounter.record_defeat(target,event)
			world.growth_input_recorded.emit(event)
	return true

func _blocked(world: Expedition) -> bool:
	world._show_notice("战斗提交未完成，已暂停；请排除故障后继续。")
	if not world.is_paused: world.toggle_pause()
	return false

func _enemy(world: Expedition,id: int) -> FieldActor:
	for actor: FieldActor in world.enemies:
		if actor.actor_id==id: return actor
	return null

func present(actor: FieldActor) -> void:
	var gun: String = String(actor.weapon_definition.id)
	if not patterned(gun): return
	if actor.combat_view==null:
		actor.combat_view=CombatWeaponVisualV1.new()
		actor.visual.add_child(actor.combat_view)
		actor.combat_view.bind_actor_visual(actor.visual)
	var state: Dictionary=action(actor)
	var phase: String="windup" if state.remaining>0 else "recover" if actor.cooldown>0 else "idle"
	var windup: float = float(CombatEquipment.melee_policy(gun).get("windup", 0.0))
	var progress: float=1.0-float(state.remaining)/windup if state.remaining>0 else 1.0-actor.cooldown/maxf(actor.weapon_definition.interval-windup,0.001)
	if actor.magazine!=null and actor.magazine.reloading:
		phase="reload"
		progress=1.0-actor.magazine.remaining/actor.magazine.seconds()
	actor.combat_view.present(String(actor.weapon_definition.id),Vector2(state.heading[0],state.heading[1]) if state.remaining>0 else actor.visual._facing,phase,clampf(progress,0.0,1.0))

func pick_spawn(world: Expedition,index: int) -> String:
	var kind: String=CombatEnemyRules.pick(world.sortie_id,index,int(world.threat.stage))
	var fallback: int=-1
	if kind == EnemyRules.NORMAL and screamer != null and screamer.state.actor_id == -1 \
			and world.threat.stage >= ThreatDirector.Stage.LATE:
		kind = ScreamerPolicyV1.KIND
	elif kind == EnemyRules.NORMAL and burst != null and burst.state.actor_id == -1 \
			and world.threat.stage == ThreatDirector.Stage.LATE:
		kind = BurstRuntimeV1.KIND
	elif kind == EnemyRules.NORMAL and world.threat.stage >= ThreatDirector.Stage.NIGHT \
			and NightHoundV1.enabled(world.supply.generated) \
			and not spawns.values().any(func(source: Dictionary) -> bool: return source.kind == NightHoundV1.KIND):
		kind = NightHoundV1.KIND
	if kind==CombatEnemyRules.TOXIC:
		for actor: FieldActor in world.enemies:
			if actor.health>0 and actor.enemy_behavior!=null and actor.enemy_behavior.kind==CombatEnemyRules.TOXIC:
				kind=EnemyRules.NORMAL
				fallback=actor.actor_id
				break
	spawns[str(index)]={"kind":kind,"stage":int(world.threat.stage),"fallback":fallback}
	return kind

func holds(actor: FieldActor) -> bool:
	return (screamer != null and screamer.holds(actor)) or (burst != null and burst.holds(actor)) \
		or toxic.get("casters",{}).get(str(actor.actor_id),{}).get("phase")=="windup"

func advance_toxic(world: Expedition,delta: float) -> void:
	var casters: Array[Dictionary]=[]
	for row: Dictionary in rows(world.enemies):
		var actor: FieldActor=_enemy(world,int(row.id))
		if actor.enemy_behavior!=null and actor.enemy_behavior.kind==CombatEnemyRules.TOXIC: casters.append(row)
	var prior_sequence: int=int(toxic.sequence)
	var plan: Dictionary=ToxicV1.plan(toxic,delta,casters,rows(world.survivors),world.shot_obstacles,not world.power_frozen)
	toxic=plan.state
	if int(toxic.sequence)>prior_sequence: world._show_notice("毒气预警 · 离开危险区域。")
	for actor: FieldActor in world.enemies:
		if toxic.casters.get(str(actor.actor_id), {}).get("phase") == "windup" and not world.power_frozen:
			actor.clear_order()
			var point: Array=toxic.casters[str(actor.actor_id)].point
			actor.aim=actor.position.direction_to(Vector2(point[0],point[1]))
	for hit: Dictionary in plan.hits:
		var victim: FieldActor=null
		for actor: FieldActor in world.survivors:
			if actor.member_id==hit.member_id: victim=actor
		if victim == null:
			refresh_toxic(world)
			_blocked(world)
			return
		if victim.health<=0:
			toxic=ToxicV1.ack(toxic,hit)
			continue
		var amount: float = float(hit.amount)
		var build: Dictionary = world.supply.generated.get("build", {})
		if BuildItems.has_catalog(int(build.get("version", BuildItems.VERSION))):
			amount *= float(BuildItems.frozen_factors(build).get("poison", 1.0))
		if not victim.take_damage(amount):
			refresh_toxic(world)
			_blocked(world)
			return
		toxic=ToxicV1.ack(toxic,hit)
		world._clear_dead_worker()
		world._update_enemy_behaviors(0.0)
		world._hit_effect(victim.position,amount,true)
		world.combat_feedback.emit({"kind":"toxic_hit","zone_id":hit.zone_id,"tick":hit.tick,"member_id":hit.member_id,"health":victim.health,"elapsed":world.elapsed})
	refresh_toxic(world)

func refresh_toxic(world: Expedition) -> void:
	toxic_view.present(toxic)
	for actor: FieldActor in world.enemies:
		if actor.enemy_behavior != null and actor.enemy_behavior.kind == CombatEnemyRules.TOXIC:
			var intent: Dictionary=toxic.casters.get(str(actor.actor_id),{})
			var casting: bool = intent.get("phase") == "windup"
			var heading: Vector2 = ToxicV1._vec(intent.point) - actor.position if casting else actor.visual._facing
			var progress: float = 1.0 - float(intent.get("remaining", 0.0)) / float(ToxicV1.POLICY.windup)
			actor.visual.present_toxic_cast(heading, casting, progress)

func cancel_unavailable(world: Expedition) -> void:
	for actor: FieldActor in world.survivors:
		if actions.has(str(actor.member_id)) and (actor.health<=0 or not actor.visible or actor.activity in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]): actions[str(actor.member_id)].remaining=0.0

static func problem(value: Variant,world: Dictionary,receipt: Dictionary) -> String:
	var screaming: bool = world.get("generated") is Dictionary and ScreamerPolicyV1.enabled(world.generated)
	var bursting: bool = world.get("generated") is Dictionary and ContentWaveV1.eligible(world.generated)
	var version: int = 3 if bursting else 1 + int(screaming)
	if not value is Dictionary or value.size()!=4 + int(screaming) + int(bursting) or not value.has_all(["version","actions","toxic","spawns"]) or value.version!=version or not value.actions is Dictionary or not value.spawns is Dictionary or value.spawns.size()>GrowthRules.MAX_EVENTS: return "COMBAT_WORLD_FIELDS"
	if not CombatActions.enabled(receipt.base): return "COMBAT_WORLD_MODE"
	var issue: String=ToxicV1.problem(value.toxic)
	if not issue.is_empty(): return issue
	if not world.get("survivors") is Array or not world.get("enemies") is Array: return "COMBAT_ACTORS"
	for row: Dictionary in world.enemies:
		if not row.get("behavior") is Dictionary: return "COMBAT_ENEMY_FIELDS"
	var required: Array[String]=[]
	for row: Dictionary in world.survivors:
		var gun: Dictionary=WeaponInventory.for_member(FieldJoinRules.context(receipt),int(row.state.member_id))
		if patterned(gun.get("weapon_id", "")): required.append(str(int(row.state.member_id)))
	if value.actions.size()!=required.size(): return "COMBAT_ACTION_SET"
	for key: String in required:
		if not value.actions.has(key): return "COMBAT_ACTION_MISSING"
	for id: Variant in value.actions:
		if not id is String or id not in ["1","2","3","4","5"]: return "COMBAT_MEMBER"
		var actor: Dictionary=SortieSnapshot._member(world.survivors,int(id))
		var state: Variant=value.actions[id]
		var weapon: Dictionary=WeaponInventory.for_member(FieldJoinRules.context(receipt),int(id))
		var gun: String = weapon.get("weapon_id", "")
		var melee_policy: Dictionary = CombatEquipment.melee_policy(gun)
		if actor.is_empty() or not patterned(gun) or not state is Dictionary or state.size()!=4 or not state.has_all(["sequence","remaining","heading","committed"]) or not SurvivalContracts.integer(state.sequence,0,RunSave.MAX_COUNTER) or not SurvivalContracts.number(state.remaining) or state.remaining<0 or state.remaining>float(melee_policy.get("windup",CombatPatternsV1.POLICY.axe.windup)) or not SortieSnapshot._vector(state.heading) or not state.committed is Array: return "COMBAT_ACTION_FIELDS"
		if not Vector2(state.heading[0],state.heading[1]).is_normalized() or (state.remaining>0 and (melee_policy.is_empty() or actor.state.health<=0 or not actor.state.visible or int(actor.state.activity) in [2,3,4] or actor.state.cooldown<=0 or state.sequence==0 or not state.committed.is_empty())): return "COMBAT_ACTION_PHASE"
		var seen: Array[int]=[]
		for target: Variant in state.committed:
			if not SurvivalContracts.integer(target,0,int(world.sim._spawn_count)-1) or int(target) in seen: return "COMBAT_ACTION_TARGETS"
			seen.append(int(target))
		if seen.size()>int(melee_policy.get("max_targets",5)): return "COMBAT_ACTION_CAP"
	var alive_toxic: int=0
	for row: Dictionary in world.enemies:
		if row.get("behavior",{}).get("kind")==CombatEnemyRules.TOXIC: alive_toxic+=1
	if alive_toxic!=value.toxic.casters.size(): return "TOXIC_CASTER_SET"
	if alive_toxic>1: return "TOXIC_ALIVE_CAP"

	var supply: MissionSupply=SortieSnapshot.supply_for_world(world)
	if supply==null: return "COMBAT_WORLD_GENERATION"
	var layout: StreetLayout=supply.layout
	var hounding: bool = NightHoundV1.enabled(world.generated)
	var first_hound_slot: int = -1
	var hound_id: int = -1
	for key: Variant in value.spawns:
		var source: Variant=value.spawns[key]
		if not key is String or not key.is_valid_int() or key!=str(int(key)) or int(key)<0 or int(key)>=world.sim._spawn_count or not source is Dictionary or source.size()!=3 or not source.has_all(["kind","stage","fallback"]) or not SurvivalContracts.integer(source.stage,0,int(world.threat.stage)) or not source.kind is String or not SurvivalContracts.integer(source.fallback,-1,int(key)-1): return "COMBAT_SPAWN_FIELDS"
		var rolled: String=CombatEnemyRules.pick(receipt.transaction_id,int(key),int(source.stage))
		var replacement: bool = screaming and source.kind == ScreamerPolicyV1.KIND and rolled == EnemyRules.NORMAL \
			and int(source.stage) >= ThreatDirector.Stage.LATE and source.fallback == -1 \
			and value.get("screamer") is Dictionary and value.screamer.get("actor_id") == int(key)
		replacement = replacement or (bursting and source.kind == BurstRuntimeV1.KIND and rolled == EnemyRules.NORMAL \
			and int(source.stage) == ThreatDirector.Stage.LATE and source.fallback == -1 \
			and value.get("burst") is Dictionary and value.burst.get("actor_id") == int(key))
		if hounding and NightHoundV1.ordinary_slot(rolled, source.kind, int(source.stage)):
			first_hound_slot = int(key) if first_hound_slot < 0 else mini(first_hound_slot, int(key))
			if source.kind == NightHoundV1.KIND and source.fallback == -1 and hound_id == -1:
				hound_id = int(key)
				replacement = true
		if source.kind!=rolled and not replacement and not (rolled==CombatEnemyRules.TOXIC and source.kind==EnemyRules.NORMAL and source.fallback>=0 and value.spawns.get(str(int(source.fallback)),{}).get("kind")==CombatEnemyRules.TOXIC): return "COMBAT_SPAWN_SOURCE"
	if hound_id != first_hound_slot:
		return "HOUND_SPAWN_PRIORITY"
	if screaming:
		var screamer_issue: String = ScreamerRuntimeV1.problem(value.get("screamer"), world, receipt, layout)
		if not screamer_issue.is_empty(): return screamer_issue
	if bursting:
		var burst_issue: String = BurstRuntimeV1.problem(value.get("burst"), world, receipt, layout)
		if not burst_issue.is_empty(): return burst_issue

	for source: Dictionary in value.toxic.releases:
		if value.spawns.get(str(int(source.source_id)),{}).get("kind")!=CombatEnemyRules.TOXIC or not layout.world_bounds.has_point(SortieSnapshot._vec(source.source_point)) or not layout.world_bounds.has_point(SortieSnapshot._vec(source.point)) or not ToxicV1.line_clear(SortieSnapshot._vec(source.source_point),SortieSnapshot._vec(source.point),layout.shot_obstacles()): return "TOXIC_RELEASE_WORLD_SOURCE"
	for hit: Dictionary in value.toxic.pending.get("hits",[]):
		var zone: Dictionary={}
		for candidate: Dictionary in value.toxic.zones:
			if candidate.id==hit.zone_id: zone=candidate
		if SortieSnapshot._member(world.survivors,int(hit.member_id)).is_empty() or zone.is_empty() or not ToxicV1.line_clear(SortieSnapshot._vec(zone.point),SortieSnapshot._vec(hit.member_point),layout.shot_obstacles()): return "TOXIC_PENDING_WORLD_LOS"
	for id: String in value.toxic.casters:
		var found: bool=false
		for row: Dictionary in world.enemies:
			if row.state.actor_id==int(id) and row.get("behavior",{}).get("kind")==CombatEnemyRules.TOXIC:
				found=true
				var intent: Dictionary=value.toxic.casters[id]
				if intent.phase=="windup" and (row.state.activity!=FieldActor.Activity.IDLE or not row.state.path.is_empty() or not layout.world_bounds.has_point(SortieSnapshot._vec(intent.point)) or not ToxicV1._cast_legal(SortieSnapshot._vec(row.state.position),SortieSnapshot._vec(intent.point),layout.shot_obstacles())): return "TOXIC_WINDUP_WORLD_SOURCE"
		if not found: return "TOXIC_CASTER_WORLD_SOURCE"
	return ""
