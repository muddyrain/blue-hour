extends SceneTree
## Geometry tests use the exact warning/damage footprint and journal transport.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var clear: Array[Rect2] = []
	var direction: Vector2 = Vector2(100, 0)
	var armed: Dictionary = PumpCharge.arm(Vector2.ZERO, direction, clear)
	_expect(PumpCharge.problem(PumpCharge.initial(), clear).is_empty(), "idle geometry is authentic")
	_expect(PumpCharge.arm(Vector2.ZERO, Vector2.ZERO, clear).is_empty(), "zero aim never arms")
	_expect(armed.to == [PumpCharge.RANGE, 0.0], "aim direction persists to fixed maximum range")
	_expect(PumpCharge.hit(armed, Vector2(100, 24)), "exact warning edge takes damage")
	_expect(not PumpCharge.hit(armed, Vector2(100, 25)), "one unit sideways out of warning avoids damage")
	_expect(not PumpCharge.hit(armed, Vector2(-1, 0)), "backward half line is safe")
	_expect(not PumpCharge.hit(armed, Vector2(PumpCharge.RANGE + 1, 0)), "beyond warning end is safe")

	var blockers: Array[Rect2] = [Rect2(100, -20, 16, 40), Rect2(90, 20, 12, 8)]
	var clipped: Dictionary = PumpCharge.arm(Vector2.ZERO, direction, blockers)
	_expect(clipped.to == [90.0 - PumpCharge.WALL_CLEARANCE, 0.0], "earliest real wall can touch the side of the sweep")
	blockers.reverse()
	_expect(PumpCharge.arm(Vector2.ZERO, direction, blockers) == clipped, "wall iteration order does not affect the lock")
	_expect(PumpCharge.hit(clipped, Vector2(65, 23)), "near side remains dangerous")
	_expect(not PumpCharge.hit(clipped, Vector2(110, 0)), "wall shields feet behind it")
	var outside: Array[Rect2] = [Rect2(-100, -10, 50, 20), Rect2(80, 25, 20, 100)]
	_expect(PumpCharge.arm(Vector2.ZERO, direction, outside) == armed, "walls behind and outside the sweep are irrelevant")
	var at_origin: Array[Rect2] = [Rect2(8, -10, 16, 20)]
	_expect(PumpCharge.arm(Vector2.ZERO, direction, at_origin).is_empty(), "no attack starts inside clearance")

	var diagonal: Array[Rect2] = [Rect2(100, 112, 20, 30)]
	var angled: Dictionary = PumpCharge.arm(Vector2.ZERO, Vector2(100, 100), diagonal)
	_expect(PumpCharge.hit(angled, Vector2(78, 78)) and not PumpCharge.hit(angled, Vector2(100, 100)), "diagonal sweep also terminates at a wall corner")
	var envelope: Dictionary = JSON.parse_string(RecordEncoding.stringify(angled))
	var restored: Dictionary = RecordEncoding.unpack(envelope)
	_expect(restored.error == OK and PumpCharge.problem(restored.payload, diagonal).is_empty(), "diagonal snapshot transports exactly")
	var changed: Dictionary = angled.duplicate(true)
	changed.to[0] += 0.0000001
	_expect(not PumpCharge.problem(changed, diagonal).is_empty(), "subpixel endpoint tampering is rejected")
	changed.to[0] = NAN
	_expect(not PumpCharge.problem(changed, diagonal).is_empty(), "invalid coordinates are rejected")
	_expect(not PumpCharge.problem(angled, clear).is_empty(), "restore refuses a different wall geometry")
	print("PUMP_CHARGE checks=%d failures=%d" % [_checks, _failures])
	quit(int(_failures != 0))


func _expect(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		printerr("PUMP_CHARGE_FAIL " + label)
