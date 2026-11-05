extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value: failures+=1;printerr("CAMPAIGN_CONTRACT_FAIL "+label)
func run() -> void:
	assert("/.local/" in OS.get_user_data_dir().replace("\\","/"))
	var app: Node=load("res://src/app/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app._new_game()
	var base: Dictionary=app.camp_snapshot()
	check(TransactionReceipt.camp_problem(base).is_empty(),"normal new short camp strict")
	for action:Dictionary in DailyActions.offers(base):
		var supply:MissionSupply=DailyActions.supply(action)
		var rules:Dictionary=FrozenSettlement.pool_rules(base,supply)
		var issue:String=FrozenSettlement._rules_problem(rules)
		print("CAMPAIGN_POLICY ",issue," version ",rules.data_version," mission ",DailyActions.mission_problem(rules.mission))
		check(issue.is_empty(),"new rules authenticate "+issue)
		var receipt:Dictionary=TransactionReceipt.initial(base,base.profile_id+":1",rules,TransactionReceipt.registration(base,base.journey.root_id))
		check(TransactionReceipt.problem(receipt).is_empty(),"new receipt strict "+TransactionReceipt.problem(receipt))
		var decoded:Dictionary=RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(receipt)))
		print("CAMPAIGN_READBACK ",FrozenSettlement._rules_problem(decoded.payload.rules)," action ",DailyActions.problem(decoded.payload.rules.mission.generated))
		check(TransactionReceipt.problem(decoded.payload).is_empty(),"exact new receipt roundtrip "+TransactionReceipt.problem(decoded.payload))
	check(not DailyActions.matches(base,WeaponActions.offers(base)[0]),"short mode rejects old task policy before departure")
	# Pure generator fixtures below do not count as a played or settled journey.
	for preparations:int in range(5):
		var fixture:Dictionary=base.duplicate(true)
		fixture.journey.campaign.preparations=preparations
		fixture.day=preparations+2;fixture.settled_sorties=preparations
		var offers:Array[Dictionary]=DailyActions.offers(fixture)
		check(offers.size()==(1 if preparations==4 else 3),"pure phase offer count")
		for action:Dictionary in offers:
			check(DailyActions.matches(fixture,action),"phase identity binds to confirmed count")
			check(action.campaign.pressure==(0.9 if preparations in [2,3] else 1.0),"single explicit pressure parameter")
			var bad:Dictionary=action.duplicate(true);bad.campaign.pressure=0.81
			check(not DailyActions.problem(bad).is_empty(),"cannot compound stage pressure")
			bad=action.duplicate(true);bad.campaign.run_id="bad"
			check(not DailyActions.problem(bad).is_empty(),"malformed action run identity rejects normally")
			if preparations==4:
				var supply:MissionSupply=DailyActions.supply(action)
				var nav:FieldNavigation=FieldNavigation.new();nav.configure(supply.layout.blockers(),supply.layout.world_bounds)
				var point:Vector2=SortieSnapshot._vec(action.encounter.position)
				check(nav.is_clear(point) and nav.path_between(supply.layout.arrivals[0],point).size()>=2,"boss spawn and original bus arrival share real navigation")
				bad=action.duplicate(true);bad.encounter.position=[0,0]
				check(not DailyActions.problem(bad).is_empty(),"boss spawn cannot be replaced")
	var legacy:Dictionary=base.duplicate(true);legacy.journey.erase("campaign")
	check(TransactionReceipt.camp_problem(legacy).is_empty() and DailyActions.offers(legacy)[0].version==5,"old completed camp keeps old mode and V5 offers")
	for key:String in ["settled_sorties","last_day"]:
		var bad:Dictionary=base.duplicate(true);bad.erase(key)
		check(not TransactionReceipt.camp_problem(bad).is_empty(),"short camp rejects missing "+key+" without attribute errors")
	app.audio.shutdown();app.queue_free();await process_frame
	print("CAMPAIGN_CONTRACTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
