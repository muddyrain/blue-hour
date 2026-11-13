extends SceneTree

const EXPEDITION: PackedScene = preload("res://src/features/expedition/expedition.tscn")

var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func run() -> void:
	if "/.local/" not in OS.get_user_data_dir().replace("\\","/"):
		printerr("WORLD_BUS_REQUIRES_ISOLATED_PROFILE")
		quit(2)
		return
	var app: Node = load("res://src/app/main.tscn").instantiate(); root.add_child(app)
	await process_frame
	app.playable_entry=false # Explicit historical fixture; normal new journeys use short V1.
	app._new_game()
	for offer: Dictionary in WorldActions.offers(app.camp_snapshot()):
		if offer.type=="rescue": app._select_mission(WorldActions.supply(offer)); break
	var world: Expedition = app.expedition
	if world == null or world.rescue_target == null:
		printerr("WORLD_BUS_FAIL historical sortie is unavailable")
		app.audio.shutdown()
		quit(1)
		return
	world.set_physics_process(false); world.set_process(false)
	world.step(2.5); world.step(0.25)
	check(world.bus_view.stage=="disembarking" and world.survivors[0].visible, "arrival presents the living crew")
	world.rescue_target.refresh()
	world.rescue_target.request()
	check(world.rescue_target.worker==0 and world.rescue_target.status=="AVAILABLE" and world.rescue_target.button.disabled, "arrival prevents an early rescue order")
	world.toggle_pause(); var at: Vector2=world._bus_sprite.position; world.step(1)
	check(world._bus_sprite.position==at and world.elapsed==0, "pause freezes arrival")
	world.toggle_pause(); world.bus_view.skip(); world.bus_view.skip()
	check(world.bus_view.stage=="exploring" and world.survivors.size()==2 and world.elapsed==0, "arrival skip is idempotent")
	world.rescue_target.request()
	check(world.rescue_target.status=="IN_PROGRESS", "rescue order becomes available after arrival")
	check_boarding_boundaries(world.supply)
	print("WORLD_BUS checks=%d failures=%d" % [checks, failures])
	await create_timer(0.5).timeout; app.audio.shutdown(); await create_timer(0.2).timeout; app.queue_free(); await process_frame; await process_frame; quit(0 if failures == 0 else 1)


func check_boarding_boundaries(supply: MissionSupply) -> void:
	# Standalone historical rescue scene with the same generated supply. It uses
	# the old independent NPC and original world owners without a camp writer.
	var world: Expedition = EXPEDITION.instantiate() as Expedition
	world.supply = supply
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.bus_view.skip()
	world.elapsed = world.tuning.bus_ready_seconds
	world._spawn_clock = INF
	world.request_bus_action()
	world.step(world.tuning.engine_seconds)
	check(world.phase == Expedition.Phase.BOARDING, "original engine leads to the gathering phase")

	var target: RescueTarget = world.rescue_target
	target.request()
	var waiting: FieldActor = world.search_member(target.worker)
	check(waiting != null and not world.field_join_mode, "original rescue request assigns one worker for an independent NPC")
	if waiting == null:
		world.queue_free()
		return
	var arrived: FieldActor = world.survivors[1] if waiting == world.survivors[0] else world.survivors[0]
	waiting.clear_order()
	waiting.position = target.npc.position
	for tick: int in range(40):
		target.step(0.25)
	check(target.status == "RESCUED" and not target.delivered(), "legacy assistance completes before its independent NPC is delivered")
	arrived.clear_order()
	arrived.position = world.layout.bus_door
	var state: Dictionary = world.boarding_status(true)
	check(state.arrived == 1 and state.required == 2 and state.rescue_waiting and state.waiting == [{"id":waiting.member_id, "call_sign":waiting.call_sign, "activity":"pending"}], "one outside member is named and the independent NPC is tracked separately")
	check(world.boarding_status() == {"arrived":1, "required":2, "working":0, "ordered":false}, "existing collection callers receive the original aggregate shape")

	var original_nav: FieldNavigation = world.navigation
	var blocked_nav: FieldNavigation = FieldNavigation.new()
	var blockers: Array[Rect2] = original_nav.obstacles.duplicate()
	var half_size: Vector2 = Vector2.ONE * (world.tuning.boarding_radius + FieldNavigation.CELL * 2.0)
	blockers.append(Rect2(world.layout.bus_door - half_size, half_size * 2.0))
	blocked_nav.configure(blockers, world.layout.world_bounds)
	world.navigation = blocked_nav
	var orders: Array[Dictionary] = []
	world.bus_gather_ordered.connect(func(value: Dictionary) -> void: orders.append(value))
	world.request_bus_gather()
	world.navigation = original_nav
	state = world.boarding_status(true)
	check(orders.is_empty() and not state.ordered and state.waiting.size() == 1 and state.waiting[0].activity == "pending" and "无法到达巴士集合区" in world._notice_text, "unreachable recall keeps the original failure and no travelling claim")

	var waiting_outside: Vector2 = waiting.position
	waiting.position = world.layout.bus_door + Vector2.RIGHT * 10.0
	world.step(0.0)
	check(world.phase == Expedition.Phase.BOARDING and world._hud.view._bus_status.text == "已集合 2/2" and world._hud.view._bus_waiting.text == "等待救援对象", "two arrived crew wait for the undelivered NPC")
	var npc_outside: Vector2 = target.npc.position
	target.npc.position = world.layout.bus_door
	check(target.delivered() and not world.boarding_status(true).rescue_waiting, "the original NPC delivery radius clears its separate waiting state")
	target.npc.position = npc_outside
	waiting.position = waiting_outside
	world.step(0.0)
	check(world._hud.view._bus_status.text == "已集合 1/2" and world.boarding_status(true).waiting.size() == 1, "leaving the radius immediately restores the pending row")
	check(waiting.take_damage(waiting.health), "controlled pending member receives lethal damage through the original actor")
	world.step(0.0)
	state = world.boarding_status(true)
	check(world.phase == Expedition.Phase.BOARDING and state.required == 1 and state.waiting.is_empty() and world._hud.view._bus_status.text == "已集合 1/1", "pending death updates denominator and removes its name while rescue still waits")
	var reports: Array[Dictionary] = []
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report))
	check(arrived.take_damage(arrived.health), "controlled last member receives lethal damage through the original actor")
	world.step(0.0)
	check(world.phase == Expedition.Phase.FINISHED and world.bus_view.stage == "exploring" and reports.size() == 1 and not reports[0].evacuated and reports[0].mission_outcome == "FAILED", "last death emits the original failure and never starts boarding")
	world.queue_free()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("WORLD_BUS_FAIL " + label)
