extends "res://tests/persona_rules.gd"
## Bounded pure candidates; these fixtures never claim earned gameplay progress.
var samples: Array = []
var structural: Dictionary = {}

func run() -> void:
	var folder: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level-output="):
			folder = arg.trim_prefix("--level-output=")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("user://level-generation")
	DirAccess.make_dir_recursive_absolute(folder)
	var base: Dictionary = _camp_fixture()
	base.journey.build = WorldgenState.initial_build(base.journey.seed,true)
	expect(BuildState.problem(base).is_empty(), "explicit new marker admitted without changing build/rules/world versions")
	expect(not ExplorationActions.matches(base,[]) and not ExplorationActions.matches(base,{"worldgen":[]}), "malformed mode values reject without calling dictionary methods on another type")
	var normal: Array[Dictionary]=DailyActions.offers(base)
	expect(normal.size()==3 and ExplorationActions.matches(base,normal[0]),"ordinary complete new candidate binds to its exact camp")
	var tampered: Dictionary=normal[0].duplicate(true)
	tampered.objective.member_id+=1
	expect(not ExplorationActions.matches(base,tampered),"warm match proof cannot hide a changed objective")
	var old_marker: Dictionary=base.duplicate(true)
	old_marker.journey.build.worldgen={"version":1,"policy_id":"BH_WORLDGEN_V1"}
	expect(not ExplorationActions.matches(old_marker,normal[0]),"complete base marker participates in warm match identity")
	var finale: Dictionary=base.duplicate(true)
	finale.journey.campaign.preparations=4
	var final_offers: Array[Dictionary]=DailyActions.offers(finale)
	expect(TransactionReceipt.same({"v":final_offers},{"v":PersonaActions.offers(finale)}),"new level marker retains the exact original finale generation contract")
	expect(final_offers.size()==1 and DailyActions.problem(final_offers[0]).is_empty() and DailyActions.supply(final_offers[0]).layout!=null,"original finale descriptor and actual layout resource load under the new camp marker")
	var seeds: Dictionary = {}
	for index: int in range(40):
		var label: String = "m15-level-%d" % index
		var probe: Dictionary = base.duplicate(true)
		probe.journey.seed = EnemyState.initial(label).seed
		for source: Dictionary in TaskActions.offers(probe):
			if source.layout["size"] == "medium" and source.type not in seeds:
				seeds[source.type] = {"label":label, "seed":probe.journey.seed,"slot":source.slot,"topology":source.layout.topology}
		if seeds.size() == 4:
			break
	write(folder.path_join("seeds.json"), seeds)
	for type: String in TaskActions.TYPES:
		for size: String in NeighborhoodLayout.SIZES:
			for index: int in range(1 if type == "airdrop" else 2):
				var seed: String = ("m15-pure-%d" % index).md5_text()
				var topology: String = ["commercial","industrial"][index] if type != "rescue" else ["residential","commercial"][index]
				var source: Dictionary = TaskActions._make(seed,2,0,type,topology,size,3 if type == "rescue" else 0)
				source = CampaignActions._upgrade(WeaponActions._upgrade(source),base.profile_id,0)
				source = CombatActions.upgrade(BuildActions.upgrade(source,[],["",""]))
				source = PersonaActions.upgrade(PowerActions.upgrade(source,[],""),SurvivorPersona.generate(seed))
				var value: Dictionary = ExplorationActions.upgrade(source,true,true)
				var label: String = "%s/%s/%d" % [type,size,index]
				expect(not value.is_empty(), "bounded policy generation " + label)
				if value.is_empty():
					continue
				expect(TransactionReceipt.same(value,ExplorationActions.upgrade(source,true,true)), "identical inputs freeze identical complete candidates " + label)
				expect(ExplorationActions.problem(value).is_empty(), "canonical full policy, budget and sources " + label)
				var routing: Dictionary = ExplorationLayout._routing(value.layout)
				var nav: FieldNavigation = routing.nav
				var bus: Vector2 = WorldLayout.point(value.layout.bus.door)
				var reachable: bool = true
				for entity: Dictionary in value.layout.entities:
					reachable = reachable and reaches(nav,bus,WorldLayout.point(entity.door))
				for site: Dictionary in value.sites:
					reachable = reachable and reaches(nav,bus,ExplorationSites.site_point(value.layout,site))
				for point: Array in value.layout.arrivals:
					reachable = reachable and reaches(nav,bus,WorldLayout.point(point))
				reachable = reachable and reaches(nav,bus,WorldLayout.point(value.layout.rescue))
				expect(reachable, "all final doors, work, rescue and gathering points reachable " + label)
				expect(value.sites.size() <= 15 and value.layout.objects.size() == ExplorationLayout.SIZES[size].vehicles + ExplorationLayout.SIZES[size].fruit_trees, "unchanged object and interaction budgets " + label)
				var sweep: Rect2 = WorldLayout.rect(value.layout.bus.sweep)
				var street: StreetLayout = ExplorationLayout.resource(value.layout)
				var clear: bool = true
				for block: Rect2 in street.blockers():
					if block != street.bus_block:
						clear = clear and not sweep.intersects(block)
						for x: int in range(-160, int(value.layout.bounds[2])+161, 64):
							clear = clear and not Rect2(Vector2(x,street.bus_block.position.y),street.bus_block.size).intersects(block)
				expect(clear, "full original bus sweep clear after objects and thin walls " + label)
				var zones: Dictionary = ExplorationSites._zone_counts(value.exploration.metrics.routes)
				expect(zones.near > 0 and zones.middle > 0 and zones.far > 0, "real near middle far content " + label)
				if type == "supply":
					var a: Vector2 = TaskActions.site_point(value,value.sites.filter(func(site: Dictionary) -> bool: return site.id == "food")[0])
					var b: Vector2 = TaskActions.site_point(value,value.sites.filter(func(site: Dictionary) -> bool: return site.id == "food_2")[0])
					expect(a != b and ExplorationLayout._length(nav.path_between(a,b)) <= LevelPolicy.FOOD_PAIR_LIMIT, "two distinct walk-adjacent food targets " + label)
				if type == "equipment":
					var gear: Dictionary = value.sites.filter(func(site: Dictionary) -> bool: return site.id == "cash")[0]
					expect(gear.weapon and value.layout.entities.any(func(entity: Dictionary) -> bool: return entity.id == gear.building and entity.archetype in TaskActions.GEAR_TYPES), "unique weapon retains real gear source " + label)
					var route: Dictionary = value.exploration.metrics.routes.cash
					expect(route.zone != "near", "gear site requires a real deeper approach " + label)
				if size=="medium" and type!="airdrop":
					var signature: String = WorldgenStructure.signature(value.layout)
					if structural.has(type):
						expect(structural[type]!=signature, "two seeds differ beyond translation mirror art IDs " + type)
					structural[type]=signature
				var identity: String = "%s-%s-%d" % [type,size,index]
				write(folder.path_join(identity+".json"),value)
				samples.append({"structure_signature":WorldgenStructure.signature(value.layout),"structure_metrics":WorldgenStructure.metrics(value.layout),"id":identity,"buildings":value.layout.entities.size(),"parcels":value.layout.parcels,"graph":value.layout.graph,"main":value.objective,"routes":value.exploration.level,"fallback":value.layout.fallback})
				if size == "medium" and type != "airdrop":
					for field: String in ["task","objective","parcel","reward","policy"]:
						var bad: Dictionary = value.duplicate(true)
						if field == "task": bad.type = "airdrop"
						elif field == "objective": bad.objective.site_ids = ["missing"]
						elif field == "parcel": bad.layout.parcels[0].kind = "forged"
						elif field == "reward": bad.sites[0].amount += 1
						else: bad.worldgen.revision += 1
						expect(not ExplorationActions.problem(bad).is_empty(), "warm cache rejects full-description " + field + " tamper " + label)
	var fallback: Dictionary = WorldgenLayout._assemble("m15-explicit-fallback","medium","commercial",0,true,"supply")
	expect(not fallback.is_empty() and fallback.fallback and WorldgenLayout.validate(fallback,false).is_empty(), "explicit same-policy bounded fallback is valid")
	if not fallback.is_empty():
		var fallback_content: Dictionary=ExplorationSites.generate(fallback,"supply",3,6,0,"a".repeat(64))
		expect(not fallback_content.is_empty(), "explicit forced fallback supports the original complete site budget")
		if not fallback_content.is_empty():
			expect(not LevelSummary.freeze(fallback,fallback_content.sites,fallback_content.objective,"supply").is_empty(), "explicit forced fallback completes real navigation routes and optional choice")
	_industrial_yard()
	_action_choices()
	write(folder.path_join("summary.json"), {"samples":samples,"checks":checks,"failures":failures,"seeds":seeds})
	print(JSON.stringify({"suite":"level_generation","checks":checks,"failures":failures,"samples":samples.size()}))
	quit(1 if failures else 0)

func _industrial_yard() -> void:
	for label: String in ["m19-mission-7", "m19-mission-1"]:
		var old: Dictionary = _camp_fixture()
		var seed: String = label.md5_text()
		old.journey.seed = seed
		old.journey.campaign = CampaignRules.initial_mission(old.profile_id)
		old.journey.build = WorldgenState.initial_build(seed, true)
		var current: Dictionary = old.duplicate(true)
		current.journey.build = WorldgenState.initial_build(seed, true, true)
		var prior: Array[Dictionary] = DailyActions.offers(old)
		var offered: Array[Dictionary] = DailyActions.offers(current)
		expect(prior.size() == 3 and offered.size() == 3, "both camp policies retain the ordinary daily offers " + label)
		if prior.size() != 3 or offered.size() != 3:
			continue
		var gear: Dictionary = offered[1]
		var yard: Dictionary = gear.layout.get("loading_yard", {})
		expect(not yard.is_empty() and gear.worldgen.revision == 2 and gear.type == "airdrop", "industrial equipment has a distinct frozen revision " + label)
		if yard.is_empty():
			continue
		expect(prior[1].worldgen.revision == 1 and not prior[1].layout.has("loading_yard")
			and ExplorationActions.problem(prior[1]).is_empty() and DailyActions.matches(old, prior[1])
			and not DailyActions.matches(old, gear), "old camp retains and authenticates its original offer " + label)
		expect(TransactionReceipt.same(prior[0], offered[0]) and TransactionReceipt.same(prior[2], offered[2]),
			"yard opt-in preserves supply and clue offers " + label)
		var old_site: Dictionary = prior[1].sites.filter(func(site: Dictionary) -> bool: return site.id == "cash")[0]
		var work_site: Dictionary = gear.sites.filter(func(site: Dictionary) -> bool: return site.id == "cash")[0]
		expect(work_site.weapon and work_site.amount == old_site.amount and work_site.seconds == old_site.seconds
			and TransactionReceipt.same(work_site.drop, old_site.drop)
			and TaskActions.site_point(gear, work_site) == WorldLayout.point(yard.work_point), "same drop and work at one shared physical site " + label)
		var routing: Dictionary = ExplorationLayout._routing(gear.layout)
		expect(IndustrialYard.certified(gear.layout, routing.nav) and WorldgenLayout.validate(gear.layout, false).is_empty()
			and ExplorationActions.problem(gear).is_empty() and DailyActions.matches(current, gear), "both real passages and bus return certify after props " + label)
		var changed: Dictionary = gear.duplicate(true)
		changed.layout.loading_yard.service.gate[0] += 16
		expect(not WorldgenLayout.validate(changed.layout).is_empty() and not DailyActions.matches(current, changed),
			"forged maintenance opening fails the frozen proof " + label)
		changed = gear.duplicate(true)
		changed.worldgen.revision = 1
		expect(not ExplorationActions.problem(changed).is_empty(), "old revision cannot claim the new layout " + label)


func _action_choices() -> void:
	var base: Dictionary = _camp_fixture()
	var seed: String = "m19-mission-9".md5_text()
	base.journey.seed = seed
	base.journey.build = WorldgenState.initial_build(seed, true, true)
	base.journey.campaign = CampaignRules.initial_mission(base.profile_id)
	var old: Array[Dictionary] = DailyActions.offers(base)
	var current: Dictionary = base.duplicate(true)
	current.journey.campaign = CampaignRules.initial_mission(base.profile_id, true)
	expect(CampaignRules.problem(current.journey.campaign).is_empty()
		and CampaignRules.action_choices_enabled(current.journey.campaign)
		and not CampaignRules.action_choices_enabled(base.journey.campaign), "new action strategy requires the explicit mission marker")
	for marker: Variant in [0, 2, "1", true]:
		var invalid: Dictionary = current.journey.campaign.duplicate()
		invalid.action_policy = marker
		expect(not CampaignRules.problem(invalid).is_empty(), "unknown or mistyped action strategy is rejected")
	var offered: Array[Dictionary] = DailyActions.offers(current)
	expect(old.size() == 3 and offered.size() == 3, "new and previous starts each retain three valid choices")
	if old.size() != 3 or offered.size() != 3:
		return
	expect(TransactionReceipt.same(old[0], offered[0]) and TransactionReceipt.same(old[2], offered[2])
		and old[1].type == "airdrop" and offered[1].type == "rescue", "legacy gear remains signed while the opted-in seed offers rescue")
	var rescue: Dictionary = offered[1]
	var eligible: int = RescuePoolState.choice(current, "%s:1" % current.profile_id)
	expect(eligible > 0 and rescue.recruit == eligible and rescue.objective.member_id == eligible
		and WorldgenLayout.validate(rescue.layout).is_empty() and DailyActions.problem(rescue).is_empty()
		and DailyActions.matches(current, rescue) and not DailyActions.matches(base, rescue)
		and DailyActions.matches(base, old[1]), "reachable rescue uses the same candidate and canonical dispatch proofs")
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(current))).payload
	expect(RecordEncoding.fingerprint({"offers": DailyActions.offers(decoded)}) == RecordEncoding.fingerprint({"offers": offered}),
		"exact camp round trip preserves offer order, IDs and rewards")
	var later: Dictionary = current.duplicate(true)
	later.day = 3
	later.settled_sorties = 1
	var next: Array[Dictionary] = DailyActions.offers(later)
	expect(next.size() == 3 and next[1].type == "airdrop", "same seed on a different date can offer original equipment recovery")
	var full: Dictionary = current.duplicate(true)
	RescuePoolState.grant(full, 3)
	RescuePoolState.grant(full, 4)
	var fallback: Array[Dictionary] = DailyActions.offers(full)
	expect(RescuePoolState.available(full).is_empty() and fallback.size() == 3 and fallback[1].type == "airdrop"
		and DailyActions.matches(full, fallback[1]), "rescue preference with no eligible recruit falls back to legal gear")


func reaches(nav: FieldNavigation, start: Vector2, point: Vector2) -> bool:
	var path: PackedVector2Array = nav.path_between(start,point)
	return nav.is_clear(point) and not path.is_empty() and path[-1].distance_to(point) <= 14

func write(path: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t"))
