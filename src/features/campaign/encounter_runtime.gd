class_name EncounterRuntime
extends RefCounted
## Integration adapter. All real damage, spawn, defeat and XP use Expedition's owners.
var world: Expedition
var actor: FieldActor
var behavior: BossBehavior=BossBehavior.new()
var warning: BossWarning
var definition: Dictionary={}
var defeat: Dictionary={}
var handling: Dictionary={}
var pump: PumpEncounter
var pump_visual: PumpBreacherArt

func setup(owner_world: Expedition, restoring: bool) -> void:
	world=owner_world;definition=world.supply.generated.encounter.duplicate(true)
	if definition.is_empty(): return
	behavior.configure(definition.boss_id)
	if not restoring:
		actor=world._make_actor(true,0,SortieSnapshot._vec(definition.position),{},EnemyRules.HEAVY)
		actor.max_health=BossDefinition.POLICY.health;actor.health=actor.max_health;actor.speed=BossDefinition.POLICY.speed
		world.enemies.append(actor);world._spawn_count+=1
	if PumpStationAction.enabled(world.supply.generated):
		pump = PumpEncounter.new()
		pump.walls = PumpEncounter.collision_walls(world.layout)
		world._effects.add_child(pump)
		_attach_pump_visual()
	warning=BossWarning.new();world._effects.add_child(warning)
	present()

func _attach_pump_visual() -> void:
	if is_instance_valid(actor):
		actor.visible = world.station_stopped()
		pump_visual = PumpBreacherArt.new()
		actor.add_child(pump_visual)

func activate_pump() -> void:
	if pump == null or not is_instance_valid(actor): return
	actor.show()
	world.combat_feedback.emit({"kind":"pump_stopped", "elapsed":world.elapsed})
	present()

func is_boss(value: FieldActor) -> bool:
	return not definition.is_empty() and value.actor_id==0

func holds(value: FieldActor) -> bool:
	if pump != null and is_boss(value):
		return not world.station_stopped() or pump.holds()
	return is_boss(value) and behavior.snapshot().state in ["melee_windup","slam_windup","dead"]

func health() -> float:
	return actor.health if is_instance_valid(actor) else 0.0

func record_defeat(value: FieldActor, receipt: Dictionary) -> void:
	if not is_boss(value) or value.health!=0 or receipt.is_empty() or not defeat.is_empty(): return
	# Called only after the same fatal shot was accepted by the existing XP ledger.
	defeat=world.xp_inputs.events.back().duplicate(true)
	behavior.step(0.0,0.0,false,[],value.position)
	# Applied hits remain on members; death cancels every unapplied part.
	handling={}
	if pump != null: pump.reset()
	world._show_notice("破阵者已击败 · 返回巴士并确认归航")
	world.combat_feedback.emit({"kind":"boss_defeated","boss_id":definition.boss_id,"elapsed":world.elapsed})

func advance(delta: float) -> void:
	if definition.is_empty(): return
	if world.power_frozen: present();return
	if not is_instance_valid(actor) or health()<=0:
		present();return
	if pump != null and not world.station_stopped():
		return
	var targets: Array[Dictionary]=[]
	if pump == null:
		for member: FieldActor in world.survivors:
			targets.append({"member_id":member.member_id,"position":member.position,"melee_legal":legal(member,BossDefinition.POLICY.melee_range),"slam_legal":legal(member,BossDefinition.POLICY.slam_range)})
	var requests: Array[Dictionary]=behavior.step(delta,health()/float(BossDefinition.POLICY.health),true,targets,actor.position)
	if holds(actor): actor.clear_order()
	for request: Dictionary in requests:
		if request.kind=="summon":
			var resolutions: Array[Dictionary]=[]
			for index: int in range(request.count):
				var resolution: Dictionary={"reason":"capacity","enemy_id":0}
				if world.enemies.size()<world.threat.rules.enemy_cap:
					resolution=world._spawn_enemy(EnemyRules.NORMAL,actor.position)
					if resolution.reason!="spawned": resolution.enemy_id=0
				resolutions.append(resolution)
			behavior.acknowledge(request.id,{"resolutions":resolutions})
			world.combat_feedback.emit({"kind":"boss_summon","threshold":request.threshold,"resolutions":resolutions,"elapsed":world.elapsed})
		else:
			if handling.is_empty(): handling={"request_id":request.id,"hits":[]}
			for member: FieldActor in world.survivors:
				if handling.hits.any(func(id:Variant)->bool:return int(id)==member.member_id): continue
				var hit: bool=member.member_id==request.target_id and legal(member,BossDefinition.POLICY.melee_range) if request.kind=="melee" else member.position.distance_to(SortieSnapshot._vec(request.position))<=BossDefinition.POLICY.slam_radius and legal(member,BossDefinition.POLICY.slam_range)
				if not hit: continue
				var before: float=member.health
				if not member.take_damage(BossDefinition.POLICY.melee_damage if request.kind=="melee" else BossDefinition.POLICY.slam_damage,(member.position-actor.position).normalized()):
					if not world.is_paused: world.toggle_pause()
					world._show_notice("首领伤害保存未确认；已暂停，确认后重试同次攻击")
					present();return
				handling.hits.append(member.member_id)
				world._clear_dead_worker()
				world._hit_effect(member.position,before-member.health,true)
				world.combat_feedback.emit({"kind":"hit","enemy_id":0,"enemy_type":"breacher_v1","member_id":member.member_id,"health":member.health,"applied_damage":before-member.health,"attack_id":request.id,"elapsed":world.elapsed})
			behavior.acknowledge(request.id,{"hits":handling.hits.duplicate()});handling={}
	if pump != null:
		pump.advance(delta, self)
	present()

func observe_frozen_health() -> void:
	if not definition.is_empty() and is_instance_valid(actor) and actor.health>0:
		behavior.observe_frozen_health(actor.health/float(BossDefinition.POLICY.health),actor.position)
	present()


func legal(member: FieldActor, distance: float) -> bool:
	return member.health>0 and AttackRules.evaluate(world._combatant(actor),world._combatant(member),actor.position+Vector2.UP*AttackRules.HIT_HEIGHT,distance,0.0,world.shot_obstacles).targetable

func present() -> void:
	if warning!=null:
		warning.visible = pump == null or world.station_stopped()
		warning.update_state(behavior.snapshot(),actor.position if is_instance_valid(actor) else SortieSnapshot._vec(definition.position),health(),BossDefinition.POLICY.health)
	if is_instance_valid(pump_visual) and is_instance_valid(actor):
		var winding: bool = not pump.state.lane.is_empty()
		actor.visual.enemy_windup = winding
		pump_visual.update_pose(actor.aim, winding, actor.health <= 0.0)

func snapshot() -> Dictionary:
	if definition.is_empty(): return {}
	var value: Dictionary = {"version":1,"boss_id":definition.boss_id,"health":health(),"behavior":behavior.snapshot(),"defeat":defeat.duplicate(true),"handling":handling.duplicate(true)}
	if pump != null:
		value.version = 2
		value.pump = pump.state.duplicate(true)
	return value

func restore(value: Dictionary) -> void:
	if definition.is_empty(): return
	for enemy: FieldActor in world.enemies:
		if is_boss(enemy): actor=enemy
	behavior.restore(value.behavior);defeat=value.defeat.duplicate(true);handling=value.handling.duplicate(true)
	if pump != null:
		pump.state = value.pump.duplicate(true)
		pump.queue_redraw()
		_attach_pump_visual()
	present()

static func facts_problem(value: Variant, generated: Dictionary, xp: Variant, sites: Variant = {}) -> String:
	if not value is Dictionary: return "ENCOUNTER_FIELDS"
	if generated.encounter.is_empty(): return "" if value.is_empty() else "ENCOUNTER_UNEXPECTED"
	if not xp is Dictionary or not xp.get("events") is Array: return "ENCOUNTER_XP_FIELDS"
	for event: Variant in xp.events:
		if not event is Dictionary or not event.has_all(["enemy_id","kind","member_id","at_ms","instance_id","weapon_id"]) and not (int(generated.get("version",0)) in [7,8,9] and BuildAuthority.ability(event) and BuildAuthority.ability_problem(event,String(event.get("request_id","")).get_slice(":",0)+":"+String(event.get("request_id","")).get_slice(":",1)).is_empty()): return "ENCOUNTER_XP_EVENT"
	var pump_mode: bool = PumpStationAction.enabled(generated)
	if value.size()!=6+int(pump_mode) or not value.has_all(["version","boss_id","health","behavior","defeat","handling"]) or value.version!=1+int(pump_mode) or value.boss_id!=generated.encounter.boss_id or not SurvivalContracts.number(value.health) or value.health<0 or value.health>BossDefinition.POLICY.health or not value.defeat is Dictionary or not value.handling is Dictionary: return "ENCOUNTER_IDENTITY"
	var issue: String=BossBehavior.problem(value.behavior,value.boss_id)
	if not issue.is_empty(): return issue
	if pump_mode:
		var stopped: bool = PumpStationAction.stopped(sites)
		if not sites is Dictionary or not sites.get(String(PumpStationAction.CONSOLE)) is Dictionary \
				or (not stopped and value.health != BossDefinition.POLICY.health):
			return "PUMP_BOSS_REQUIRES_SHUTDOWN"
		if not value.handling.is_empty() or value.behavior.sequence != 0 or value.behavior.state not in ["idle", "dead"]:
			return "PUMP_LEGACY_ATTACK"
		var pump_issue: String = PumpEncounter.problem(value.get("pump"), generated, stopped, value.health > 0.0)
		if not pump_issue.is_empty(): return pump_issue
	if value.health>0:
		if not value.defeat.is_empty() or value.behavior.state=="dead": return "ENCOUNTER_LIFE_FACT"
		if value.behavior.min_health_ratio>value.health/float(BossDefinition.POLICY.health)+0.0000001: return "ENCOUNTER_HEALTH_THRESHOLD"
	else:
		if value.behavior.state!="dead" or value.defeat.is_empty(): return "ENCOUNTER_DEFEAT_REQUIRED"
		var found: bool=false
		for event: Dictionary in xp.get("events",[]):
			if event.enemy_id==0 and TransactionReceipt.same(event,value.defeat): found=true
		if not found: return "ENCOUNTER_DEFEAT_SOURCE"
	if not value.handling.is_empty():
		if value.handling.size()!=2 or not value.handling.has_all(["request_id","hits"]) or not value.handling.request_id is String or not value.handling.hits is Array or value.handling.hits.size()>4: return "ENCOUNTER_HANDLING"
		var request_found: bool=false
		for request: Dictionary in value.behavior.pending:
			if request.id==value.handling.request_id and request.kind in ["melee","slam"]: request_found=true
		if not request_found: return "ENCOUNTER_HANDLING_SOURCE"
		var seen: Array[int]=[]
		for id: Variant in value.handling.hits:
			if not SurvivalContracts.integer(id,1,5) or int(id) in seen: return "ENCOUNTER_HANDLING_MEMBER"
			seen.append(int(id))
	return ""


static func summon_ids(value: Dictionary) -> Array[int]:
	var result: Array[int]=[]
	for threshold: Dictionary in value.behavior.thresholds:
		if threshold.handled:
			for resolution: Dictionary in threshold.result.resolutions:
				if resolution.reason=="spawned": result.append(int(resolution.enemy_id))
	return result
