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
	write(folder.path_join("summary.json"), {"samples":samples,"checks":checks,"failures":failures,"seeds":seeds})
	print(JSON.stringify({"suite":"level_generation","checks":checks,"failures":failures,"samples":samples.size()}))
	quit(1 if failures else 0)

func reaches(nav: FieldNavigation, start: Vector2, point: Vector2) -> bool:
	var path: PackedVector2Array = nav.path_between(start,point)
	return nav.is_clear(point) and not path.is_empty() and path[-1].distance_to(point) <= 14

func write(path: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t"))
