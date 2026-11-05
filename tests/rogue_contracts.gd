extends SceneTree
## New rules identity/transport negatives; historical branches remain explicit.
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("ROGUE_CONTRACT_FAIL "+label)
func run() -> void:
	assert("/.local/" in OS.get_user_data_dir().replace("\\","/"))
	var main: Node=load("res://src/app/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.playable_entry=false # Explicit historical fixture; normal new journeys use short V1.
	main._new_game() # Existing isolated business initializer, not a fabricated camp.
	var base: Dictionary=main.camp_snapshot()
	expect(TransactionReceipt.camp_problem(base).is_empty(),"real initial complete-mode fixture is strict")
	var offers: Array[Dictionary]=RogueActions.offers(base)
	for offer: Dictionary in offers:
		var rules: Dictionary=FrozenSettlement.pool_rules(base,RogueActions.supply(offer))
		expect(rules.data_version==2 and FrozenSettlement._rules_problem(rules).is_empty(),"explicit new rules branch validates")
		var registration: Dictionary=TransactionReceipt.registration(base,base.journey.root_id)
		var receipt: Dictionary=TransactionReceipt.initial(base,base.profile_id+":1",rules,registration)
		expect(TransactionReceipt.problem(receipt).is_empty(),"task descriptor authenticated in receipt")
		var encoded: String=RecordEncoding.stringify(receipt)
		var decoded: Dictionary=RecordEncoding.unpack(JSON.parse_string(encoded))
		expect(decoded.error==OK and TransactionReceipt.problem(decoded.payload).is_empty() and TransactionReceipt.same(receipt,decoded.payload),"exact codec roundtrip preserves new task and geometry")
		var bad: Dictionary=receipt.duplicate(true);bad.rules.mission.generated.version=98
		expect(not TransactionReceipt.problem(bad).is_empty(),"unknown generator/task rejected")
		bad=receipt.duplicate(true);bad.rules.mission.cash_reward+=1
		expect(not TransactionReceipt.problem(bad).is_empty(),"reward and descriptor mismatch rejected")
		bad=receipt.duplicate(true);bad.rules.mission.generated.layout.entities[0].rect[0]+=16
		expect(not TransactionReceipt.problem(bad).is_empty(),"changed geometry rejected")
		bad=receipt.duplicate(true);bad.rules.data_version=1
		expect(not TransactionReceipt.problem(bad).is_empty(),"new descriptor cannot downgrade into old rules")
		bad=receipt.duplicate(true);bad.rules.mission.generated.seed="f".repeat(32)
		expect(not TransactionReceipt.problem(bad).is_empty(),"foreign journey cannot replace selected task")
		bad=receipt.duplicate(true);bad.rules.data_version=400
		expect(not TransactionReceipt.problem(bad).is_empty(),"unknown policy version rejected")

	var descriptor: Dictionary=offers[0]
	var supply: MissionSupply=RogueActions.supply(descriptor)
	var rules: Dictionary=FrozenSettlement.pool_rules(base,supply)
	var registration: Dictionary=TransactionReceipt.registration(base,base.journey.root_id)
	var receipt: Dictionary=TransactionReceipt.initial(base,base.profile_id+":1",rules,registration)
	# Use the real composition path: it installs PersistedDamageGate and all mode wiring.
	main.progress_session.daily_actions=false # Explicit historical generator probe.
	main._select_mission(supply)
	var world: Expedition=main.expedition
	world.set_physics_process(false);world.toggle_pause()
	receipt=main.progress_session._transaction.recover().receipt
	var snapshot: Dictionary=SortieSnapshot.capture(world)
	var snapshot_issue: String=SortieSnapshot.problem(snapshot,receipt)
	print("ROGUE_SNAPSHOT_FIXTURE issue=",snapshot_issue," setup=",world.setup_problem," task=",descriptor.type)
	expect(snapshot_issue.is_empty(),"actual generated field snapshot validates")
	var decoded_world: Dictionary=RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(snapshot)))
	print("ROGUE_ROUNDTRIP_FIXTURE issue=",SortieSnapshot.problem(decoded_world.payload,receipt))
	expect(decoded_world.error==OK and SortieSnapshot.problem(decoded_world.payload,receipt).is_empty(),"generated world exact transport remains authenticatable")
	var changed: Dictionary=snapshot.duplicate(true);changed.generated.layout.version=9
	expect(not SortieSnapshot.problem(changed,receipt).is_empty(),"world unknown layout version rejected before restore")
	changed=snapshot.duplicate(true);changed.map="market_loop"
	expect(not SortieSnapshot.problem(changed,receipt).is_empty(),"world map identity cannot diverge from selected task")
	changed=snapshot.duplicate(true);changed.build+="-unknown"
	expect(not SortieSnapshot.problem(changed,receipt).is_empty(),"world unknown build rejected")
	changed=snapshot.duplicate(true);changed.erase("generated")
	expect(not SortieSnapshot.problem(changed,receipt).is_empty(),"generated descriptor is mandatory")
	changed=snapshot.duplicate(true);changed.sim.loot=descriptor.cash
	expect(not SortieSnapshot.problem(changed,receipt).is_empty(),"world cannot invent collected cash")
	changed=snapshot.duplicate(true);changed.version=2
	expect(not SortieSnapshot.problem(changed,receipt).is_empty(),"generated action cannot downgrade to fixed-world version")
	world.queue_free();await process_frame
	var old: Dictionary=FrozenSettlement.pool_rules(base,preload("res://src/features/camp/supermarket.tres"))
	expect(old.data_version==1 and old.mission.size()==5 and FrozenSettlement._rules_problem(old).is_empty(),"old fixed rules authenticate through unchanged branch")
	var unknown: Dictionary=old.duplicate(true);unknown.mission.map_id="unknown-map"
	expect(not FrozenSettlement._rules_problem(unknown).is_empty(),"old invalid map still rejected")
	main.audio.shutdown();await create_timer(0.2).timeout;main.queue_free();await process_frame
	print("ROGUE_CONTRACTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
