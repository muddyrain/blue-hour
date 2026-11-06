class_name CombatRuntime
extends RefCounted
## Expedition-owned mode adapter. Original actors, XP, damage gate and transaction remain authoritative.
var actions: Dictionary={}
var toxic: Dictionary={}
var spawns: Dictionary={}
var toxic_view: Node2D

func snapshot() -> Dictionary:
	return {"version":1,"actions":actions.duplicate(true),"toxic":toxic.duplicate(true),"spawns":spawns.duplicate(true)}

func restore(value: Dictionary) -> void:
	actions=value.actions.duplicate(true)
	toxic=value.toxic.duplicate(true)
	spawns=value.spawns.duplicate(true)

func setup(world: Expedition) -> void:
	toxic=ToxicV1.initial()
	toxic_view=ToxicVisualV1.new()
	toxic_view.z_index=-1
	world.add_child(toxic_view)

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
	if gun not in ["fire_axe_v1","shotgun_v1"]: return
	var state: Dictionary=action(actor)
	var active: bool=actor.health>0 and actor.visible and actor.activity not in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]
	if not active:
		state.remaining=0.0
		return
	if gun=="fire_axe_v1" and state.remaining>0:
		state.remaining=maxf(0.0,float(state.remaining)-delta)
		actor.aim=Vector2(state.heading[0],state.heading[1])
		if state.remaining==0:
			var plan: Array[Dictionary]=CombatPatternsV1.axe_plan(actor.position,actor.aim,rows(world.enemies),world.shot_obstacles,actor.weapon_definition.shot_range)
			if not _commit(world,actor,plan,state): return
			actor.visual.show_fire(actor.aim)
			world.combat_feedback.emit({"kind":"axe_swing","member_id":actor.member_id,"sequence":state.sequence,"targets":state.committed.duplicate(),"elapsed":world.elapsed})
		return
	if actor.cooldown>0 or (actor.magazine!=null and not actor.magazine.can_fire()): return
	var target: FieldActor=_target(world,actor)
	if target==null: return
	actor.aim=actor.position.direction_to(target.position)
	state.heading=[actor.aim.x,actor.aim.y]
	if gun=="fire_axe_v1":
		state.sequence+=1
		state.committed=[]
		state.remaining=float(CombatPatternsV1.POLICY.axe.windup)
		actor.cooldown=actor.weapon_definition.interval
		return
	var muzzle: Vector2=actor.position+actor.visual.aimed_shot_offset(actor.aim)
	var plan: Dictionary=CombatPatternsV1.shotgun_plan(actor.position,CombatEquipment.shot_origin(actor.position),actor.aim,rows(world.enemies),world.shot_obstacles,actor.weapon_definition.shot_range)
	state.sequence+=1
	state.committed=[]
	if not _commit(world,actor,plan.targets,state):
		state.sequence-=1
		return
	actor.magazine.commit_shot()
	actor.cooldown=actor.weapon_definition.shot_interval(actor.trait_shot_factor)
	actor.visual.show_fire(actor.aim)
	for ray: Dictionary in plan.rays:
		if (ray.to-muzzle).dot(actor.aim)<=0: continue
		var line: Line2D=Line2D.new()
		line.add_point(muzzle)
		line.add_point(ray.to)
		line.width=1.8
		line.default_color=Color("ffd78b")
		world._effects.add_child(line)
		line.create_tween().tween_property(line,"modulate:a",0.0,0.10).finished.connect(line.queue_free)
	world.combat_feedback.emit({"kind":"shotgun","member_id":actor.member_id,"sequence":state.sequence,"targets":plan.targets,"magazine":actor.magazine.snapshot(),"elapsed":world.elapsed})

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
		if target.health<=actor.weapon_definition.damage*int(hit.hits):
			fatal+=1
			if world.growth_mode and not world.is_practice and (not world.growth_inputs.can_record(actor,target,world.elapsed) or not world.xp_inputs.can_record(world,actor,target)): return _blocked(world)
	if world.growth_mode and world.xp_inputs.events.size()+fatal>GrowthRules.MAX_EVENTS: return _blocked(world)
	# Validate the complete batch before any HP, ammo, feedback or XP changes.
	for hit: Dictionary in plan:
		var target: FieldActor=_enemy(world,int(hit.id))
		var damage: float=actor.weapon_definition.damage*int(hit.hits)
		if not target.take_damage(damage,actor.position.direction_to(target.position)): return _blocked(world)
		state.committed.append(int(hit.id))
		world._hit_effect(target.position,damage,false)
		if target.health==0:
			world.kills+=1
			actor.confirmed_kills+=1
			var event: Dictionary=world.growth_inputs.accept_defeat(actor,target,world.elapsed)
			if world.growth_mode and not world.xp_inputs.accept(world,actor,target,event): return _blocked(world)
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
	if String(actor.weapon_definition.id) not in ["fire_axe_v1","shotgun_v1"]: return
	if actor.combat_view==null:
		actor.combat_view=CombatWeaponVisualV1.new()
		actor.visual.add_child(actor.combat_view)
		actor.combat_view.bind_actor_visual(actor.visual)
	var state: Dictionary=action(actor)
	var phase: String="windup" if state.remaining>0 else "recover" if actor.cooldown>0 else "idle"
	var progress: float=1.0-float(state.remaining)/float(CombatPatternsV1.POLICY.axe.windup) if state.remaining>0 else 1.0-actor.cooldown/maxf(actor.weapon_definition.interval-(float(CombatPatternsV1.POLICY.axe.windup) if CombatEquipment.melee(String(actor.weapon_definition.id)) else 0.0),0.001)
	if actor.magazine!=null and actor.magazine.reloading:
		phase="reload"
		progress=1.0-actor.magazine.remaining/actor.magazine.seconds()
	actor.combat_view.present(String(actor.weapon_definition.id),Vector2(state.heading[0],state.heading[1]) if state.remaining>0 else actor.visual._facing,phase,clampf(progress,0.0,1.0))

func pick_spawn(world: Expedition,index: int) -> String:
	var kind: String=CombatEnemyRules.pick(world.sortie_id,index,int(world.threat.stage))
	var fallback: int=-1
	if kind==CombatEnemyRules.TOXIC:
		for actor: FieldActor in world.enemies:
			if actor.health>0 and actor.enemy_behavior!=null and actor.enemy_behavior.kind==CombatEnemyRules.TOXIC:
				kind=EnemyRules.NORMAL
				fallback=actor.actor_id
				break
	spawns[str(index)]={"kind":kind,"stage":int(world.threat.stage),"fallback":fallback}
	return kind

func holds(actor: FieldActor) -> bool:
	return toxic.get("casters",{}).get(str(actor.actor_id),{}).get("phase")=="windup"

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
		if actor.toxic_carrier!=null: actor.toxic_carrier.present(actor.visual._facing,holds(actor),1.0-float(toxic.casters.get(str(actor.actor_id),{}).get("remaining",0.0))/float(ToxicV1.POLICY.windup))
		if holds(actor) and not world.power_frozen:
			actor.clear_order()
			var point: Array=toxic.casters[str(actor.actor_id)].point
			actor.aim=actor.position.direction_to(Vector2(point[0],point[1]))
	for hit: Dictionary in plan.hits:
		var victim: FieldActor=null
		for actor: FieldActor in world.survivors:
			if actor.member_id==hit.member_id: victim=actor
		if victim==null: _blocked(world); return
		if victim.health<=0:
			toxic=ToxicV1.ack(toxic,hit)
			continue
		if not victim.take_damage(float(hit.amount)):
			_blocked(world)
			return
		toxic=ToxicV1.ack(toxic,hit)
		world._clear_dead_worker()
		world._update_enemy_behaviors(0.0)
		world._hit_effect(victim.position,float(hit.amount),true)
		world.combat_feedback.emit({"kind":"toxic_hit","zone_id":hit.zone_id,"tick":hit.tick,"member_id":hit.member_id,"health":victim.health,"elapsed":world.elapsed})
		print("BH_TOXIC_HIT zone=%s tick=%d member=%d health=%.2f"%[hit.zone_id,hit.tick,hit.member_id,victim.health])
	refresh_toxic(world)
	toxic_view.advance(delta,true)

func refresh_toxic(world: Expedition) -> void:
	toxic_view.present(toxic)
	for actor: FieldActor in world.enemies:
		if actor.toxic_carrier!=null:
			var intent: Dictionary=toxic.casters.get(str(actor.actor_id),{})
			var heading: Vector2=SortieSnapshot._vec(intent.point)-actor.position if intent.get("phase")=="windup" else actor.visual._facing
			actor.toxic_carrier.present(heading,intent.get("phase")=="windup",1.0-float(intent.get("remaining",0.0))/float(ToxicV1.POLICY.windup))

func cancel_unavailable(world: Expedition) -> void:
	for actor: FieldActor in world.survivors:
		if actions.has(str(actor.member_id)) and (actor.health<=0 or not actor.visible or actor.activity in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]): actions[str(actor.member_id)].remaining=0.0

static func problem(value: Variant,world: Dictionary,receipt: Dictionary) -> String:
	if not value is Dictionary or value.size()!=4 or not value.has_all(["version","actions","toxic","spawns"]) or value.version!=1 or not value.actions is Dictionary or not value.spawns is Dictionary or value.spawns.size()>GrowthRules.MAX_EVENTS: return "COMBAT_WORLD_FIELDS"
	if not CombatActions.enabled(receipt.base): return "COMBAT_WORLD_MODE"
	var issue: String=ToxicV1.problem(value.toxic)
	if not issue.is_empty(): return issue
	if not world.get("survivors") is Array or not world.get("enemies") is Array: return "COMBAT_ACTORS"
	for row: Dictionary in world.enemies:
		if not row.get("behavior") is Dictionary: return "COMBAT_ENEMY_FIELDS"
	var required: Array[String]=[]
	for row: Dictionary in world.survivors:
		var gun: Dictionary=WeaponInventory.for_member(FieldJoinRules.context(receipt),int(row.state.member_id))
		if gun.get("weapon_id") in ["fire_axe_v1","shotgun_v1"]: required.append(str(int(row.state.member_id)))
	if value.actions.size()!=required.size(): return "COMBAT_ACTION_SET"
	for key: String in required:
		if not value.actions.has(key): return "COMBAT_ACTION_MISSING"
	for id: Variant in value.actions:
		if not id is String or id not in ["1","2","3","4","5"]: return "COMBAT_MEMBER"
		var actor: Dictionary=SortieSnapshot._member(world.survivors,int(id))
		var state: Variant=value.actions[id]
		var weapon: Dictionary=WeaponInventory.for_member(FieldJoinRules.context(receipt),int(id))
		if actor.is_empty() or weapon.is_empty() or weapon.weapon_id not in ["fire_axe_v1","shotgun_v1"] or not state is Dictionary or state.size()!=4 or not state.has_all(["sequence","remaining","heading","committed"]) or not SurvivalContracts.integer(state.sequence,0,RunSave.MAX_COUNTER) or not SurvivalContracts.number(state.remaining) or state.remaining<0 or state.remaining>float(CombatPatternsV1.POLICY.axe.windup) or not SortieSnapshot._vector(state.heading) or not state.committed is Array: return "COMBAT_ACTION_FIELDS"
		if not Vector2(state.heading[0],state.heading[1]).is_normalized() or (state.remaining>0 and (weapon.weapon_id!="fire_axe_v1" or actor.state.health<=0 or not actor.state.visible or int(actor.state.activity) in [2,3,4] or actor.state.cooldown<=0 or state.sequence==0 or not state.committed.is_empty())): return "COMBAT_ACTION_PHASE"
		var seen: Array[int]=[]
		for target: Variant in state.committed:
			if not SurvivalContracts.integer(target,0,int(world.sim._spawn_count)-1) or int(target) in seen: return "COMBAT_ACTION_TARGETS"
			seen.append(int(target))
		if seen.size()>(3 if weapon.weapon_id=="fire_axe_v1" else 5): return "COMBAT_ACTION_CAP"
	var alive_toxic: int=0
	for row: Dictionary in world.enemies:
		if row.get("behavior",{}).get("kind")==CombatEnemyRules.TOXIC: alive_toxic+=1
	if alive_toxic!=value.toxic.casters.size(): return "TOXIC_CASTER_SET"
	if alive_toxic>1: return "TOXIC_ALIVE_CAP"

	var supply: MissionSupply=SortieSnapshot.supply_for_world(world)
	if supply==null: return "COMBAT_WORLD_GENERATION"
	var layout: StreetLayout=supply.layout
	for key: Variant in value.spawns:
		var source: Variant=value.spawns[key]
		if not key is String or not key.is_valid_int() or key!=str(int(key)) or int(key)<0 or int(key)>=world.sim._spawn_count or not source is Dictionary or source.size()!=3 or not source.has_all(["kind","stage","fallback"]) or not SurvivalContracts.integer(source.stage,0,int(world.threat.stage)) or not source.kind is String or not SurvivalContracts.integer(source.fallback,-1,int(key)-1): return "COMBAT_SPAWN_FIELDS"
		var rolled: String=CombatEnemyRules.pick(receipt.transaction_id,int(key),int(source.stage))
		if source.kind!=rolled and not (rolled==CombatEnemyRules.TOXIC and source.kind==EnemyRules.NORMAL and source.fallback>=0 and value.spawns.get(str(int(source.fallback)),{}).get("kind")==CombatEnemyRules.TOXIC): return "COMBAT_SPAWN_SOURCE"

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
