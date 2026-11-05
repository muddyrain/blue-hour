extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("WEAPON_V1_FAIL "+label)
func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").begins_with(ProjectSettings.globalize_path("res://.local/")):quit(2);return
	var app: Node=load("res://src/app/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app._new_game()
	var base: Dictionary=app.camp_snapshot()
	var types: Dictionary={}
	var examples: Array=[]
	for seed: String in ["task-v4-0","task-v4-1","task-v4-2","task-v4-3"]:
		var fixture: Dictionary=base.duplicate(true);fixture.journey.seed=seed.md5_text()
		var offers: Array[Dictionary]=WeaponActions.offers(fixture)
		expect(TransactionReceipt.same({"v":offers},{"v":WeaponActions.offers(fixture)}),"new candidates stable")
		for offer: Dictionary in offers:
			expect(DailyActions.problem(offer).is_empty(),"V5 action/drop authenticates")
			var rules: Dictionary=FrozenSettlement.pool_rules(fixture,DailyActions.supply(offer))
			expect(rules.data_version==6 and FrozenSettlement._rules_problem(rules).is_empty(),"V6 rules bind V5 action")
			for site: Dictionary in offer.sites:
				if not site.weapon:continue
				var item: Dictionary=WeaponInventory.site_reward(base.profile_id+":1",offer,site,true)
				types[item.weapon_id]=true
				examples.append({"seed":seed,"type":offer.type,"gun":item.weapon_id})
				expect(item.weapon_id==WeaponInventory.drop_weapon(offer.seed,offer.id,site.id) and TransactionReceipt.same(item,WeaponInventory.instance_reward(fixture,item)),"carried drop agrees with durable camp provenance")
				var altered: Dictionary=offer.duplicate(true)
				for row: Dictionary in altered.sites:
					if row.weapon:row.drop.weapon_id="long_rifle" if item.weapon_id=="carbine" else "carbine"
				expect(not DailyActions.problem(altered).is_empty(),"changed frozen gun rejected")
	expect(types.has_all(["carbine","long_rifle"]),"fixed seed fixtures cover both guns")
	expect(WeaponInventory.reward(base.profile_id+":1",true).weapon_id=="long_rifle","historical reward stays fixed")
	for gun: String in ["carbine","long_rifle"]:
		var magazine: WeaponMagazine=WeaponMagazine.new("instance",gun)
		expect(magazine.rounds==magazine.capacity(),"fresh full "+gun)
		for shot: int in range(magazine.capacity()):magazine.commit_shot()
		expect(not magazine.can_fire() and magazine.rounds==0 and magazine.remaining==magazine.seconds(),"last shot starts full timer "+gun)
		magazine.advance(magazine.seconds()*0.5)
		var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(magazine.snapshot()))).payload
		expect(WeaponMagazine.problem(exact,"instance",gun).is_empty(),"exact half reload authenticates "+gun)
		var copy: WeaponMagazine=WeaponMagazine.new("instance",gun);copy.restore(exact)
		expect(copy.rounds==0 and copy.remaining==magazine.remaining,"restore cannot refill "+gun)
		copy.advance(copy.remaining-0.01)
		expect(not copy.can_fire(),"no early finish "+gun)
		copy.advance(0.01)
		expect(copy.can_fire() and copy.rounds==copy.capacity(),"finish fills exactly once "+gun)
		for change: String in ["identity","negative","overflow","fraction","time","nan","phase","unknown","version"]:
			var bad: Dictionary=exact.duplicate(true)
			match change:
				"identity":bad.instance_id="other"
				"negative":bad.rounds=-1
				"overflow":bad.rounds=magazine.capacity()+1
				"fraction":bad.rounds=0.5
				"time":bad.remaining=magazine.seconds()+1
				"nan":bad.remaining=NAN
				"phase":bad.reloading=false
				"unknown":bad.extra=0
				"version":bad.version=2
			expect(not WeaponMagazine.problem(bad,"instance",gun).is_empty(),"reject "+gun+change)
	print(JSON.stringify({"checks":checks,"failures":failures,"types":types,"examples":examples,"parameters":WeaponDefinition.MAGAZINES}))
	app.audio.shutdown();app.queue_free();await process_frame
	quit(0 if failures==0 else 1)
