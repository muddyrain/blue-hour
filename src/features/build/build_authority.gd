class_name BuildAuthority
extends RefCounted
## Pure support proposals; RunTransaction alone publishes their full recoverable world.
static func factor(world: Dictionary, key: String) -> float:
	return BuildItems.frozen_factors(world.generated.build)[key] if (world.get("version")==10 or SortieSnapshot.combat_version(world.get("version"))) else 1.0

static func healed(events: Array, id: int) -> float:
	var amount: float=0.0
	for event: Dictionary in events:
		if healing_kind(event.kind) and event.facts.get("member_id")==id: amount+=float(event.facts.amount)
	return amount

static func healing_kind(kind: Variant) -> bool:
	return kind == "heal" or kind == FirstAidV1.KIND or kind == SpecialPowers.RADIO

static func radio_equipped(generated: Dictionary) -> bool:
	var equipment: Variant = generated.get("powers")
	if not equipment is Dictionary or not SurvivalContracts.integer(equipment.get("version"),
			SpecialPowers.M47_VERSION, SpecialPowers.M47_VERSION):
		return false
	var loadout: Variant = PowerState.loadout(equipment)
	return SpecialPowers.loadout_valid(loadout) and SpecialPowers.RADIO in loadout.slots

static func ability(event: Variant) -> bool:
	return event is Dictionary and event.get("source")=="ability"

static func ability_problem(event: Dictionary, transaction: String, include_member: bool = true) -> String:
	if include_member and not SurvivalContracts.integer(event.get("member_id"),1,5): return "ABILITY_DEFEAT_MEMBER"
	if event.size()!=(7 if include_member else 6) or not event.has_all(["kind","source","ability_id","request_id","enemy_id","at_ms"]) or event.kind!="defeat" or event.source!="ability" or event.ability_id!="airstrike_v1" or not event.request_id is String or not event.request_id.begins_with(transaction+":basic:"): return "ABILITY_DEFEAT_SOURCE"
	return ""

static func support_problem(value: Variant, token: Dictionary, generated: Dictionary, departure: Dictionary = {}) -> String:
	var first_aid: bool = FirstAidV1.enabled(generated) and FirstAidV1.qualified(departure) \
		and CampaignRules.first_aid_enabled(departure.get("journey", {}).get("campaign", {}))
	var issue: String=BasicSupport.problem(value,token,first_aid,radio_equipped(generated))
	if not issue.is_empty(): return issue
	var previous: int=-1
	var last: Dictionary={"heal":-30.0,"airstrike":-20.0}
	for event: Dictionary in value.accepted:
		var facts: Dictionary=event.facts
		if not SurvivalContracts.integer(facts.get("at_ms"),0,RunSave.MAX_COUNTER) or facts.at_ms<previous or not SurvivalContracts.number(facts.get("at")) or not SortieSnapshot.duration_matches(float(facts.at),facts.at_ms): return "SUPPORT_FACT_TIME"
		if event.kind in BasicSupport.KINDS and facts.at-last[event.kind]<BasicSupport.POLICY[event.kind+"_cooldown"]-0.00000001: return "SUPPORT_FACT_TIME"
		if not SurvivalContracts.integer(facts.get("member_id"),1,5): return "SUPPORT_FACT_MEMBER"
		if event.kind in ["heal", SpecialPowers.RADIO]:
			if facts.size()!=7 or not facts.has_all(["at","at_ms","member_id","health_before","health_after","amount","damage_received"]): return "HEAL_FACT_FIELDS"
			for key: String in ["health_before","health_after","amount","damage_received"]:
				if not SurvivalContracts.number(facts[key]): return "HEAL_FACT_NUMBER"
			var limit: float = float(SpecialPowers.RADIO_DEFINITION.heal_amount) if event.kind == SpecialPowers.RADIO \
				else BasicSupport.POLICY.heal_amount * BuildItems.frozen_factors(generated.build).heal
			if facts.health_before<=0 or facts.amount<=0 or facts.amount>limit or facts.health_after!=facts.health_before+facts.amount or facts.damage_received<0: return "HEAL_FACT_AMOUNT"
			if not TransactionReceipt.same(event.payload,{"member_id":facts.member_id,"amount":facts.amount}): return "HEAL_REQUEST_SOURCE"
		elif event.kind == FirstAidV1.KIND:
			var aid_issue: String = _first_aid_problem(facts, event.payload, generated)
			if not aid_issue.is_empty():
				return aid_issue
		else:
			if facts.size()!=4 or not facts.get("targets") is Array or not event.payload.has_all(["member_id","point","radius","targets"]) or event.payload.member_id!=facts.member_id or event.payload.radius!=BasicSupport.POLICY.airstrike_radius*BuildItems.frozen_factors(generated.build).blast: return "AIRSTRIKE_FACT_FIELDS"
			if generated.has("barricade") and (event.payload.size() != 4 or not SortieSnapshot._vector(event.payload.point)):
				return "AIRSTRIKE_REQUEST_POINT"
			var seen: Array[int]=[]
			for target: Variant in facts.targets:
				if not target is Dictionary or target.size()!=4 or not target.has_all(["enemy_id","health_before","health_after","amount"]) or not SurvivalContracts.integer(target.enemy_id,0,RunSave.MAX_COUNTER) or int(target.enemy_id) in seen: return "AIRSTRIKE_TARGET_FIELDS"
				for key: String in ["health_before","health_after","amount"]:
					if not SurvivalContracts.number(target[key]): return "AIRSTRIKE_TARGET_NUMBER"
				if target.health_before<=0 or target.health_after!=maxf(0.0,target.health_before-BasicSupport.POLICY.airstrike_damage) or target.amount!=target.health_before-target.health_after: return "AIRSTRIKE_TARGET_DAMAGE"
				seen.append(int(target.enemy_id))
			if not TransactionReceipt.same({"v":seen},{"v":event.payload.targets}): return "AIRSTRIKE_TARGET_SET"
		if event.kind in BasicSupport.KINDS:
			last[event.kind]=float(facts.at)
		previous=int(facts.at_ms)
	return ""

static func _first_aid_problem(facts: Dictionary, payload: Dictionary, generated: Dictionary) -> String:
	if facts.size() != 11 or not facts.has_all(["at", "at_ms", "member_id", "health_before", "health_after",
			"amount", "damage_received", "source_id", "source_point", "target_point", "max_health"]):
		return "FIRST_AID_FACT_FIELDS"
	if not SurvivalContracts.integer(facts.source_id, FirstAidV1.SOURCE_ID, FirstAidV1.SOURCE_ID) or facts.member_id == facts.source_id \
			or not SortieSnapshot._vector(facts.source_point) or not SortieSnapshot._vector(facts.target_point):
		return "FIRST_AID_SOURCE"
	for key: String in ["health_before", "health_after", "amount", "damage_received", "max_health"]:
		if not SurvivalContracts.number(facts[key]):
			return "FIRST_AID_FACT_NUMBER"
	if facts.max_health <= 0.0 or facts.health_before <= 0.0 or facts.health_before / facts.max_health > FirstAidV1.HEALTH_RATIO \
			or facts.damage_received < 0.0 or facts.amount <= 0.0 or facts.amount != minf(FirstAidV1.HEAL_AMOUNT, facts.max_health - facts.health_before) \
			or facts.health_after != facts.health_before + facts.amount:
		return "FIRST_AID_FACT_AMOUNT"
	if not TransactionReceipt.same(payload, {"source_id":facts.source_id, "member_id":facts.member_id, "amount":facts.amount}):
		return "FIRST_AID_REQUEST_SOURCE"
	var layout: StreetLayout = DailyActions.supply(generated).layout
	return "" if FirstAidV1.reach(layout, SortieSnapshot._vec(facts.source_point), SortieSnapshot._vec(facts.target_point)) else "FIRST_AID_REACH"

static func world_problem(world: Dictionary, receipt: Dictionary) -> String:
	var issue: String=support_problem(world.get("support"),RunTransaction.token_for(receipt),world.generated,receipt.base)
	if not issue.is_empty(): return issue
	if not TransactionReceipt.same({"v":world.support.accepted},{"v":receipt.get("support",[])}): return "SUPPORT_NOT_DURABLE"
	for kind: String in BasicSupport.KINDS:
		var last_at: float=-1.0
		for accepted: Dictionary in world.support.accepted:
			if accepted.kind==kind: last_at=float(accepted.facts.at)
		var expected: float=maxf(0.0,BasicSupport.POLICY[kind+"_cooldown"]-(float(world.sim.elapsed)-last_at)) if last_at>=0 else 0.0
		if absf(float(world.support.cooldowns[kind])-expected)>0.00000001: return "SUPPORT_COOLDOWN_CAUSAL_SOURCE"
	for event: Dictionary in world.support.accepted:
		if event.facts.at_ms>floori(world.sim.elapsed*1000.0): return "SUPPORT_FUTURE"
		if healing_kind(event.kind):
			var member: Dictionary=SurvivorRoster.member(FieldJoinRules.participants(receipt),int(event.facts.member_id))
			if member.is_empty() or event.facts.health_before+event.facts.damage_received!=member.health_before+healed(world.support.accepted.slice(0,world.support.accepted.find(event)),int(member.id)): return "HEAL_CAUSAL_SOURCE"
			var maximum: float = GrowthRules.maximum(SurvivorRoster.member(FieldJoinRules.context(receipt).crew,int(member.id)))
			if event.facts.health_after > maximum or (event.kind == FirstAidV1.KIND and event.facts.max_health != maximum): return "HEAL_MAXIMUM"
			if event.kind == SpecialPowers.RADIO and event.facts.amount != minf(
					float(SpecialPowers.RADIO_DEFINITION.heal_amount), maximum - float(event.facts.health_before)):
				return "AID_BROADCAST_AMOUNT"
	return ""

static func line_clear(layout: StreetLayout, start: Vector2, end: Vector2) -> bool:
	return ToxicV1.line_clear(start, end, layout.shot_obstacles())

static func plan_heal(world: Dictionary) -> Dictionary:
	var support: BasicSupport=BasicSupport.new()
	support.restore(world.support,FirstAidV1.enabled(world.generated),radio_equipped(world.generated))
	var members: Array[Dictionary]=[]
	for row: Dictionary in world.survivors:
		members.append({"member_id":row.state.member_id,"health":row.state.health,"max_health":row.state.max_health,"present":row.state.activity!=FieldActor.Activity.DOWN})
	return support.plan_heal(members,factor(world,"heal"))

static func plan_radio(world: Dictionary) -> Dictionary:
	if not world.get("generated") is Dictionary or not radio_equipped(world.generated) or not world.get("survivors") is Array:
		return {}
	var members: Array[Dictionary] = []
	for row: Variant in world.survivors:
		if not row is Dictionary or not row.get("state") is Dictionary:
			return {}
		var state: Dictionary = row.state
		# Indoor search hides its worker. Bus boarding closes field support
		# before any passenger leaves the deployed roster.
		var activity: Variant = state.get("activity")
		if not SurvivalContracts.integer(activity, FieldActor.Activity.IDLE, FieldActor.Activity.RECOVERING):
			return {}
		var outdoors: bool = state.get("visible") == true and int(activity) in [
			FieldActor.Activity.IDLE, FieldActor.Activity.MOVING, FieldActor.Activity.RECOVERING]
		members.append({"member_id":state.get("member_id"), "health":state.get("health"),
			"max_health":state.get("max_health"), "present":outdoors})
	return BasicSupport.plan_recovery(members, float(SpecialPowers.RADIO_DEFINITION.heal_amount))

static func plan_first_aid(world: Dictionary) -> Dictionary:
	if not FirstAidV1.enabled(world.generated):
		return {}
	var states: Array[Dictionary] = []
	for row: Variant in world.survivors:
		if not row is Dictionary or not row.get("state") is Dictionary:
			return {}
		states.append(row.state)
	return FirstAidV1.plan(states, DailyActions.supply(world.generated).layout)

static func plan_airstrike(world: Dictionary, point: Vector2) -> Dictionary:
	var stamp: int = FreezeProfile.enter("support.airstrike_plan")
	var map_stamp: int = FreezeProfile.enter("support.airstrike_map")
	var layout: StreetLayout = DailyActions.supply(world.generated).layout
	var navigation: FieldNavigation
	if BarricadeV1.enabled(world.generated):
		var opened: bool = BarricadeState.opened(world.generated, world.support.accepted, layout)
		navigation = BarricadeV1.navigation(world.generated, opened)
	elif world.generated.get("version") == 9 and not PumpStationAction.enabled(world.generated):
		# The same validated final geometry certifies the field and receipt replay.
		navigation = ExplorationLayout._routing(layout.world_data).nav
		FreezeProfile.count("airstrike_navigation_reuses")
	else:
		navigation = FieldNavigation.new()
		navigation.configure(layout.blockers(), layout.world_bounds)
		FreezeProfile.count("airstrike_navigation_builds")
	FreezeProfile.leave("support.airstrike_map", map_stamp)
	var plan: Dictionary = plan_airstrike_on_map(world, point, layout, navigation)
	FreezeProfile.leave("support.airstrike_plan", stamp)
	return plan

static func plan_airstrike_on_map(world: Dictionary, point: Vector2, layout: StreetLayout,
		navigation: FieldNavigation) -> Dictionary:
	if not layout.world_bounds.has_point(point) or not navigation.is_clear(point): return {}
	var obstacles: Array[ShotObstacle] = layout.shot_obstacles()
	var callers: Array[Dictionary]=[]
	for row: Dictionary in world.survivors:
		var state: Dictionary=row.state
		var position: Vector2 = SortieSnapshot._vec(state.position)
		var distance: float = position.distance_to(point)
		if (state.health > 0 and state.visible and state.activity not in [2, 3, 4]
				and distance <= BasicSupport.POLICY.airstrike_range
				and ToxicV1.line_clear(position, point, obstacles)
				and not navigation.path_between(position, point).is_empty()):
			callers.append({"id":state.member_id,"distance":distance})
	if callers.is_empty(): return {}
	callers.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.distance<b.distance or (a.distance==b.distance and a.id<b.id))
	var radius: float=BasicSupport.POLICY.airstrike_radius*factor(world,"blast")
	var targets: Array[int]=[]
	for row: Dictionary in world.enemies:
		if row.state.actor_id == 0 and PumpStationAction.enabled(world.generated) and not row.state.get("visible", false):
			continue
		var position: Vector2 = SortieSnapshot._vec(row.state.position)
		if row.state.health > 0 and position.distance_to(point) <= radius and ToxicV1.line_clear(point, position, obstacles):
			targets.append(int(row.state.actor_id))
	targets.sort()
	return {"member_id":callers[0].id,"point":[point.x,point.y],"radius":radius,"targets":targets}

static func propose(before: Dictionary, request: Dictionary) -> Dictionary:
	if (before.get("version")!=10 and not SortieSnapshot.combat_version(before.get("version"))) or request.size()!=3 or not request.has_all(["id","kind","payload"]) or not request.kind is String or not request.payload is Dictionary: return {}
	var component: BasicSupport=BasicSupport.new()
	component.restore(before.support,FirstAidV1.enabled(before.generated),radio_equipped(before.generated))
	if not TransactionReceipt.same(request,component.request(request.kind,request.payload)): return {}
	var expected: Dictionary = {}
	match request.kind:
		"heal":
			expected = plan_heal(before)
		"airstrike":
			if SortieSnapshot._vector(request.payload.get("point")):
				expected = plan_airstrike(before, SortieSnapshot._vec(request.payload.point))
		FirstAidV1.KIND:
			expected = plan_first_aid(before)
		SpecialPowers.RADIO:
			expected = plan_radio(before)
	if expected.is_empty() or not TransactionReceipt.same(expected,request.payload): return {}
	var after: Dictionary=before.duplicate(true)
	var facts: Dictionary={"at":before.sim.elapsed,"at_ms":floori(before.sim.elapsed*1000.0),"member_id":request.payload.member_id}
	if healing_kind(request.kind):
		var row: Dictionary=SortieSnapshot._member(after.survivors,int(request.payload.member_id))
		facts.merge({"health_before":row.state.health,"health_after":row.state.health+request.payload.amount,"amount":request.payload.amount,"damage_received":row.state.damage_received})
		if request.kind == FirstAidV1.KIND:
			var source: Dictionary = SortieSnapshot._member(after.survivors, FirstAidV1.SOURCE_ID)
			facts.merge({"source_id":FirstAidV1.SOURCE_ID, "source_point":source.state.position.duplicate(),
				"target_point":row.state.position.duplicate(), "max_health":row.state.max_health})
		row.state.health=facts.health_after
	else:
		var kills: int=0
		for id: int in request.payload.targets:
			for row: Dictionary in before.enemies:
				if row.state.actor_id==id and row.state.health<=BasicSupport.POLICY.airstrike_damage: kills+=1
		if before.xp_inputs.events.size()+kills>GrowthRules.MAX_EVENTS: return {}
		facts.targets=[]
		for id: int in request.payload.targets:
			var row: Dictionary={}
			for enemy: Dictionary in after.enemies:
				if enemy.state.actor_id==id: row=enemy
			var hp: float=row.state.health
			row.state.health=maxf(0.0,hp-BasicSupport.POLICY.airstrike_damage)
			facts.targets.append({"enemy_id":id,"health_before":hp,"health_after":row.state.health,"amount":hp-row.state.health})
			if row.state.health==0:
				var event: Dictionary={"kind":"defeat","source":"ability","ability_id":"airstrike_v1","request_id":request.id,"enemy_id":id,"at_ms":facts.at_ms,"member_id":request.payload.member_id}
				after.xp_inputs.events.append(event)
				var recent: Dictionary=event.duplicate(true)
				recent.erase("member_id")
				for member: Dictionary in after.growth.members:
					if member.member_id==request.payload.member_id:
						member.total+=1
						member.recent.append(recent)
						if member.recent.size()>SurvivorGrowth.RECENT_LIMIT: member.recent.pop_front()
				SortieSnapshot._member(after.survivors,int(request.payload.member_id)).state.confirmed_kills+=1
				after.sim.kills+=1
				after.enemies.erase(row)
				if SortieSnapshot.combat_version(after.get("version")): after.combat.toxic.casters.erase(str(id))
				if after.get("combat", {}).has("screamer"):
					ScreamerRuntimeV1.cancel(after.combat.screamer, id)
				if after.get("combat", {}).has("burst"):
					BurstRuntimeV1.cancel(after.combat.burst, id)
				if id==0 and not after.generated.encounter.is_empty():
					after.encounter.health=0.0
					after.encounter.defeat=event.duplicate(true)
					var behavior: BossBehavior=BossBehavior.new()
					behavior.restore(after.encounter.behavior)
					behavior.step(0.0,0.0,false,[],SortieSnapshot._vec(row.state.position))
					after.encounter.behavior=behavior.snapshot()
					after.encounter.handling={}
					if PumpStationAction.enabled(after.generated):
						after.encounter.pump = PumpEncounter.initial()
			elif id==0 and not after.generated.encounter.is_empty():
				after.encounter.health=row.state.health
				var behavior: BossBehavior=BossBehavior.new()
				behavior.restore(after.encounter.behavior)
				var targets: Array[Dictionary]=[]
				var layout: StreetLayout=DailyActions.supply(after.generated).layout
				for member: Dictionary in after.survivors:
					var state: Dictionary=member.state
					var distance: float=SortieSnapshot._vec(state.position).distance_to(SortieSnapshot._vec(row.state.position))
					var legal: bool=state.health>0 and state.visible and int(state.activity) not in [2,3] and line_clear(layout,SortieSnapshot._vec(row.state.position),SortieSnapshot._vec(state.position))
					targets.append({"member_id":int(state.member_id),"position":SortieSnapshot._vec(state.position),"melee_legal":legal and distance<BossDefinition.POLICY.melee_range,"slam_legal":legal and distance<BossDefinition.POLICY.slam_range})
				if PumpStationAction.enabled(after.generated) or (SortieSnapshot.power_version(after.get("version")) and SpecialPowers.frozen(after.powers,float(after.sim.elapsed))):
					behavior.observe_frozen_health(row.state.health/float(BossDefinition.POLICY.health),SortieSnapshot._vec(row.state.position))
				else: behavior.step(0.0,row.state.health/float(BossDefinition.POLICY.health),true,targets,SortieSnapshot._vec(row.state.position))
				after.encounter.behavior=behavior.snapshot()
	if not component.accept(request,facts): return {}
	after.support=component.snapshot()
	return after

static func lethal_source(event: Dictionary, support: Array) -> bool:
	for request: Dictionary in support:
		if request.id!=event.request_id or request.kind!="airstrike" or request.facts.member_id!=event.member_id or request.facts.at_ms!=event.at_ms: continue
		for target: Dictionary in request.facts.targets:
			if target.enemy_id==event.enemy_id and target.health_after==0.0: return true
	return false

static func transition(previous: Dictionary, next: Dictionary) -> String:
	if not previous.get("support") is Array or not next.get("support") is Array: return "SUPPORT_TRANSITION_FIELDS"
	if TransactionReceipt.same({"v":previous.support},{"v":next.support}): return ""
	if next.phase!="SUSPEND_READY" or next.support.size()!=previous.support.size()+1 or not TransactionReceipt.same({"v":next.support.slice(0,previous.support.size())},{"v":previous.support}): return "SUPPORT_RETRACTED_OR_PHASE"
	var proof: Variant=next.envelope.get("support_proposal")
	if not proof is Dictionary or proof.size()!=2 or not proof.get("before") is Dictionary or not proof.get("request") is Dictionary: return "SUPPORT_PROOF_REQUIRED"
	var before: Dictionary=proof.before
	if (before.get("version")!=10 and not SortieSnapshot.combat_version(before.get("version"))): return "SUPPORT_PROOF_VERSION"
	var checkpoint: Dictionary=previous.duplicate(true)
	for row: Dictionary in before.survivors:
		var old: Dictionary=SurvivorRoster.member(previous.health,int(row.state.member_id))
		if old.is_empty() or row.state.health>old.health: return "SUPPORT_PREVIOUS_HEALTH"
		SurvivorRoster.member(checkpoint.health,int(row.state.member_id)).health=row.state.health
	var issue: String=SortieSnapshot.problem(before,checkpoint)
	if not issue.is_empty(): return "SUPPORT_BEFORE:"+issue
	var after: Dictionary=propose(before,proof.request)
	return "" if not after.is_empty() and TransactionReceipt.same(after,next.envelope.world) else "SUPPORT_AFTER_PROOF"
