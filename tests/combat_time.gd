extends SceneTree
## Shared sortie behavior; only named DD observations are reference-consistency claims.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_range_and_orders()
	_check_bus_baseline()
	_check_timers()
	_check_fixture_boundary()
	await process_frame
	print("BH_COMBAT_TIME checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fixture() -> Expedition:
	var sortie: Expedition = Expedition.new()
	root.add_child(sortie)
	sortie.set_physics_process(false)
	sortie._spawn_clock = INF
	sortie._ai_clock = INF
	# Isolate one shooter without inventing original two-target priority or enemy movement.
	sortie.survivors[1].activity = FieldActor.Activity.SEARCHING
	sortie.survivors[1].hide()
	return sortie


func _target(sortie: Expedition, point: Vector2) -> FieldActor:
	var enemy: FieldActor = sortie._make_actor(true, 50, point)
	enemy.health = 540.0
	enemy.max_health = 540.0
	sortie.enemies.append(enemy)
	return enemy


func _check_range_and_orders() -> void:
	var sortie: Expedition = _fixture()
	var shooter: FieldActor = sortie.survivors[0]
	shooter.position = Vector2(1088, 1136)
	var enemy: FieldActor = _target(sortie, shooter.position + Vector2(211, 0))
	sortie.step(0.01)
	_expect(enemy.health == 540.0, "TMP-101: out of prototype range causes no damage")
	sortie.command_move(Vector2(1200, 1160))
	var goal: Vector2 = sortie.goal
	sortie.step(0.02)
	_expect(enemy.health == 522.0 and shooter.activity == FieldActor.Activity.MOVING, "DD-OBS-011/025: actual damage while executing movement")
	_expect(sortie.goal == goal and shooter.path.size() > 0, "shooting retains explicit movement order")
	sortie.command_move(Vector2(940, 1160))
	for tick: int in range(30):
		sortie.step(0.1)
	var after_retreat: float = enemy.health
	var parked: Vector2 = shooter.position
	for tick: int in range(20):
		sortie.step(0.1)
	_expect(enemy.health == after_retreat and shooter.aim == Vector2.ZERO, "TMP-101: leaving range clears aim and stops damage")
	_expect(shooter.position == parked, "prototype holds reached goal; original pursuit remains uncalibrated")
	sortie.command_move(Vector2(1200, 1160))
	for tick: int in range(25):
		sortie.step(0.1)
	_expect(enemy.health < after_retreat and sortie.goal == Vector2(1200, 1160), "re-entry resumes shared combat without replacing goal")
	sortie.queue_free()


func _check_bus_baseline() -> void:
	var sortie: Expedition = _fixture()
	sortie.survivors[0].position = sortie.layout.bus_block.get_center() + Vector2(0, 90)
	var enemy: FieldActor = _target(sortie, sortie.layout.bus_block.get_center() - Vector2(0, 90))
	sortie.step(0.01)
	_expect(enemy.health == 522.0, "TMP-113 only: existing no-occlusion baseline across bus; original B remains unverified")
	sortie.queue_free()


func _check_timers() -> void:
	var sortie: Expedition = _fixture()
	_expect(sortie.time_status()["sortie_seconds"] == 105 and sortie.time_status()["bus_seconds"] == 20, "separate prototype sortie and bus clocks")
	var initial_colour: Color = sortie._hud._time_fill.bg_color
	sortie.toggle_pause()
	var before: Dictionary = sortie.time_status()
	sortie.step(9.0)
	_expect(sortie.time_status() == before and sortie._hud._time_bar.value == 1.0, "DD-OBS-009/026: pause freezes both clocks and visible track")
	sortie.toggle_pause()
	sortie.step(20.0)
	_expect(sortie.time_status()["bus_seconds"] == 0 and sortie.time_status()["sortie_seconds"] == 85, "bus ready does not end sortie countdown")
	sortie.request_extraction()
	_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.time_status()["engine_seconds"] == 3, "DD-OBS-017: engine has a third independent timer")
	sortie.toggle_pause()
	before = sortie.time_status()
	sortie.step(5.0)
	_expect(sortie.time_status() == before, "pause freezes engine as well as sortie countdown")
	sortie.toggle_pause()
	sortie.step(3.1)
	_expect(sortie.phase == Expedition.Phase.BOARDING and sortie.time_status()["sortie_seconds"] == 82, "DD-OBS-017: engine changes to waiting while sortie clock continues")
	sortie.step(40.0)
	_expect(sortie._hud._time_fill.bg_color != initial_colour and sortie._hud._time_bar.value < 0.5, "DD-OBS-026 qualitative feedback: remaining time becomes warmer; exact gradient is TMP-114")
	sortie.step(80.0)
	_expect(sortie.time_status()["sortie_seconds"] == 0 and sortie.time_status()["sortie_fraction"] == 0.0, "countdown clamps at zero without negative UI")
	_expect(sortie.phase == Expedition.Phase.BOARDING, "zero time retains boarding; project threat must not force failure or evacuation")
	sortie.queue_free()


func _check_fixture_boundary() -> void:
	var sortie: Expedition = _fixture()
	sortie.practice_far_target()
	_expect(sortie.enemies.is_empty(), "practice durable-target intent cannot inject enemies into normal sortie")
	sortie.is_practice = true
	sortie.practice_far_target()
	_expect(sortie.enemies.size() == 1 and sortie.enemies[0].health == 540.0, "TMP-112: explicit durable fixture uses normal FieldActor")
	_expect(sortie.survivors[0].position.distance_to(sortie.enemies[0].position) > sortie.survivors[0].weapon_definition.shot_range, "fixture begins beyond configured attack range")
	sortie.queue_free()


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("BH_COMBAT_TIME " + label)
