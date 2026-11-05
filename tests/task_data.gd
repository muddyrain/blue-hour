extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("TASK_DATA_FAIL "+label)
func run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\","/")
	if not OS.get_user_data_dir().replace("\\","/").begins_with(isolated):
		printerr("TASK_DATA_REJECT_NON_ISOLATED_PROFILE"); quit(2); return
	for argument: String in OS.get_cmdline_user_args():
		for prefix: String in ["--bh-progress=","--bh-audio-settings="]:
			if argument.begins_with(prefix) and not argument.trim_prefix(prefix).replace("\\","/").simplify_path().begins_with(isolated):
				printerr("TASK_DATA_REJECT_NON_ISOLATED_PATH"); quit(2); return
	var main: Node = load("res://src/app/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	main._new_game()
	var base: Dictionary = main.camp_snapshot()
	var examples: Dictionary = {}
	for seed: String in ["task-v4-0","task-v4-1","task-v4-2","task-v4-3"]:
		var fixture: Dictionary = base.duplicate(true); fixture.journey.seed=seed.md5_text()
		var offers: Array[Dictionary] = TaskActions.offers(fixture)
		check(offers.size()==3 and TransactionReceipt.same({"v":offers},{"v":TaskActions.offers(fixture)}),"same day deterministic")
		var types: Array = []
		for offer: Dictionary in offers:
			check(offer.type not in types,"unique offered types"); types.append(offer.type)
			examples[offer.type]=seed
	for type: String in TaskActions.TYPES:
		for size: String in NeighborhoodLayout.SIZES:
			for topology: String in NeighborhoodLayout.TOPOLOGIES:
				if type=="equipment" and topology=="residential": continue
				var offer: Dictionary = TaskActions._make("task-grid".md5_text(),2,0,type,topology,size,3 if type=="rescue" else 0)
				check(TaskActions.problem(offer).is_empty(),"canonical "+type+size+topology)
				var supply: MissionSupply = TaskActions.supply(offer)
				var nav: FieldNavigation = FieldNavigation.new(); nav.configure(supply.layout.blockers(),supply.layout.world_bounds)
				var cash: int = 0; var food: int = 0; var weapons: int = 0
				for site: Dictionary in offer.sites:
					if site.kind=="cash": cash+=int(site.amount)
					else: food+=int(site.amount)
					weapons+=int(site.weapon)
					var point: Vector2 = TaskActions.site_point(offer,site)
					var path: PackedVector2Array = nav.path_between(supply.layout.bus_door,point)
					check(nav.is_clear(point) and not path.is_empty() and path[-1].distance_to(point)<16,"real reachable target")
					if site.id in offer.objective.site_ids and type in ["supply","equipment"]:
						var entity: Dictionary = offer.layout.entities.filter(func(e: Dictionary) -> bool:return e.id==site.building)[0]
						check(entity.archetype in (TaskActions.FOOD_TYPES if type=="supply" else TaskActions.GEAR_TYPES),"matching target building")
				check(cash==offer.cash and food==offer.food and weapons==offer.weapons and weapons<=1,"single task budget and unique weapon")
				var bad: Dictionary = offer.duplicate(true); bad.objective.site_ids=["missing"]
				check(not TaskActions.problem(bad).is_empty(),"warm validation rejects target id mutation")
				bad=offer.duplicate(true); bad.cash+=1
				check(not TaskActions.problem(bad).is_empty(),"warm validation rejects budget mutation")
				bad=offer.duplicate(true); bad.parameters.reinforcements=3
				check(not TaskActions.problem(bad).is_empty(),"versioned parameter contract")
				bad=offer.duplicate(true); bad.extra=true
				check(not TaskActions.problem(bad).is_empty(),"unknown field rejected")
	# Synthetic full roster fixture only tests eligibility, never drives gameplay completion.
	var full: Dictionary = base.duplicate(true); RescuePoolState.grant(full,3); RescuePoolState.grant(full,4)
	var full_offers: Array[Dictionary] = TaskActions.offers(full)
	check(full_offers.all(func(o: Dictionary) -> bool:return o.type!="rescue") and full_offers[0].type!=full_offers[1].type and full_offers[1].type!=full_offers[2].type and full_offers[0].type!=full_offers[2].type,"full pool has three distinct legal tasks")
	print("TASK_DATA checks=",checks," failures=",failures," seed_examples=",JSON.stringify(examples))
	main.audio.shutdown(); main.queue_free(); await process_frame
	quit(1 if failures else 0)
