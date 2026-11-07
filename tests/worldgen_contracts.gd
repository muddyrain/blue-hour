extends "res://tests/persona_rules.gd"
## Pure description/capability fixtures; no earned completion, profile or save claim.
func run() -> void:
	var base: Dictionary=_camp_fixture()
	base.journey.build=WorldgenState.initial_build(base.journey.seed)
	expect(TransactionReceipt.camp_problem(JSON.parse_string(JSON.stringify(base,"",true,true))).is_empty(),"build6 survives actual camp JSON readback")
	expect(TransactionReceipt.camp_problem(base).is_empty(),"new build6 is strictly admitted by original camp owner")
	var old: Dictionary=base.duplicate(true)
	old.journey.build.version=5;old.journey.build.erase("worldgen")
	expect(TransactionReceipt.camp_problem(old).is_empty(),"explicit old build5 remains valid without worldgen")
	var member: Dictionary=GrowthRules.legacy_view(old.crew[0])
	member.growth.trait={"id":null,"level":null,"progress":null}
	member.growth.training_state="unavailable"
	member.service.sorties=1
	var action_camp: Dictionary=old.duplicate(true);action_camp.settled_sorties=1
	member.growth.last_action={"settlement_id":old.profile_id+":1","map_id":"worldgen_v1_"+"a".repeat(32),"duration_ms":1000,"total":0,"recent":[],"evacuated":true}
	expect(not SurvivorGrowth._validate_legacy_member(member,action_camp,true).is_empty(),"old build5 rejects a new layout map identity in action history")
	member.growth.last_action.map_id="explore_v1_"+"a".repeat(32)
	expect(SurvivorGrowth._validate_legacy_member(member,action_camp,true).is_empty(),"old build5 retains its valid old map history")
	var current: Array[Dictionary]=DailyActions.offers(base)
	var original: Array[Dictionary]=ExplorationActions.offers(old)
	expect(current.size()==3,"normal new mode exposes all three task choices")
	var sizes: Array[String]=[]
	for i: int in range(current.size()):
		var value: Dictionary=current[i]
		expect(not value.is_empty(),"bounded new map and content creation succeeds")
		if value.is_empty(): continue
		expect(value.version==9 and value.layout.version==5 and value.has("worldgen") and value.exploration.version==1,"new explicit generation/layout capabilities")
		sizes.append(value.layout["size"])
		expect(ExplorationActions.problem(value).is_empty(),"complete new canonical description authenticates")
		expect(TransactionReceipt.same(ExplorationActions.origin(value),ExplorationActions.origin(original[i])),"original task/reward/drop/ability/persona source is unchanged")
		expect(DailyActions.matches(base,value) and not DailyActions.matches(old,value),"new descriptions bind only to new camp capability")
		var decoded: Dictionary=RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(value))).payload
		expect(ExplorationActions.problem(decoded).is_empty(),"exact transport retains new canonical map/routes/facts")
		var rules: Dictionary=FrozenSettlement.pool_rules(base,DailyActions.supply(value))
		expect(rules.data_version==10 and FrozenSettlement._rules_problem(rules).is_empty(),"rules10 owns complete new generated9 mission")
		var changed: Dictionary=value.duplicate(true);changed.erase("worldgen")
		expect(not DailyActions.problem(changed).is_empty(),"layout5 cannot masquerade as old explored geometry")
		changed=value.duplicate(true);changed.worldgen.version=99
		expect(not DailyActions.problem(changed).is_empty(),"unknown worldgen policy rejects")
		changed=value.duplicate(true);changed.worldgen.erase("revision")
		expect(not DailyActions.problem(changed).is_empty(),"unpublished R0 policy is rejected, never silently regenerated as R1")
		var malformed: Dictionary=value.duplicate(true);malformed.campaign.run_id="bad"
		expect(not DailyActions.problem(malformed).is_empty(),"malformed source identity rejects before original constructor")
		var bad: Dictionary=value.duplicate(true);bad.cash+=1
		expect(not DailyActions.problem(bad).is_empty(),"unearned extra total budget rejects")
		bad=value.duplicate(true);bad.sites[-1].amount+=1
		expect(not DailyActions.problem(bad).is_empty(),"one object cannot copy or inflate reward")
		bad=value.duplicate(true);bad.layout.objects[0].work_point[0]+=16
		expect(not DailyActions.problem(bad).is_empty(),"work point cannot drift from frozen object identity")
		bad=value.duplicate(true);bad.exploration.optional_objectives[0].site_ids=["missing_object"]
		expect(not DailyActions.problem(bad).is_empty(),"optional objectives bind real canonical objects")
		bad=value.duplicate(true);bad.version=8
		expect(not DailyActions.problem(bad).is_empty(),"new geometry cannot masquerade as old V8")
		var facts: Dictionary={}
		for site: Dictionary in value.sites:facts[site.id]={"searched":false,"progress":0.0}
		expect(WorldSites.problem(value.sites,facts,true).is_empty(),"precise new object fact set is valid")
		facts[value.sites[-1].id].progress=value.sites[-1].seconds+0.1
		expect(not WorldSites.problem(value.sites,facts,true).is_empty(),"new progress is bounded by its exact object's seconds")
	sizes.sort()
	expect(sizes==["large","medium","small"],"ordinary menu always offers small medium and large actual geometry")
	var finale: Dictionary=base.duplicate(true)
	finale.journey.campaign.preparations=4
	expect(TransactionReceipt.same({"v":DailyActions.offers(finale)},{"v":PersonaActions.offers(finale)}),"finale descriptor and geometry remain byte-identical original mode")
	for mutation: String in ["marker","version","extra"]:
		var bad: Dictionary=base.duplicate(true)
		if mutation=="marker":bad.journey.build.exploration.version=2
		elif mutation=="version":bad.journey.build.version=7
		else:bad.journey.build.exploration.unlocked=true
		expect(not BuildState.problem(bad).is_empty(),"unknown capability fields/version reject "+mutation)
	print(JSON.stringify({"suite":"worldgen_contracts","checks":checks,"failures":failures,"scope":"PURE_DESCRIPTION_AND_EXPLICIT_MODE"}))
	quit(1 if failures else 0)
