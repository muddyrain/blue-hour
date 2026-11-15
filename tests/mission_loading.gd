extends SceneTree
## The slow second-day seed must reject blocked approaches before costly route proofs.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var trace: Array[String] = []
	var started: int = Time.get_ticks_msec()
	var rejected: Dictionary = WorldgenLayout._assemble(
		"BH_LEVEL_V1:9ef1c388702bce319a31728515a0cd2bbf97616f70672bca2d020bdda4d54016",
		"large", "commercial", 0, false, "supply", false, false, OpenStreetsV1.SEEDED_VERSION, trace)
	var elapsed: int = Time.get_ticks_msec() - started
	_expect(rejected.is_empty() and trace == ["themed_approach"], "known slow candidate retains its original rejection")
	# The previous order spent about eight seconds on this rejected candidate alone.
	_expect(elapsed < 3000, "blocked approach is rejected within three seconds without full door proofs or dressing")
	_check_final_approach()
	var accepted: Dictionary = WorldgenLayout._assemble(
		"BH_LEVEL_V1:5a1d6fbbfaae8a47e3dae441efddb4468938afbe940bf1caac5fcad755326c64",
		"medium", "industrial", 0, false, "equipment", false, false, OpenStreetsV1.SEEDED_VERSION)
	# Captured from c7a2bcb's original generation order, including cosmetic dressing.
	_expect(RecordEncoding.fingerprint(accepted) == "2a06e03de38d9858abf8aee7e6fd395839f3ccd07286d79095a7f5fa26127e98",
		"accepted geometry, decoration and map identity remain byte-for-byte canonical")
	print("BH_MISSION_LOADING ", JSON.stringify({"checks":checks, "failures":failures, "rejected_candidate_ms":elapsed}))
	quit(0 if failures == 0 else 1)


func _check_final_approach() -> void:
	var data: Dictionary = {"themed_district":{"approaches":{"direct":[[64, 64], [192, 64]]}}}
	var street: StreetLayout = StreetLayout.new()
	street.bus_door = Vector2(32, 64)
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure([], Rect2(0, 0, 256, 192))
	_expect(ExplorationLayout._approach_problem(data, nav, street).is_empty(), "clear base approach can proceed to prop fitting")
	nav.configure([Rect2(112, 32, 32, 64)], Rect2(0, 0, 256, 192))
	_expect(ExplorationLayout._approach_problem(data, nav, street) == "themed_approach", "final approach still rejects a blocker added during prop fitting")
	data.warehouse_district = data.themed_district.duplicate(true)
	data.warehouse_district.family = "street_axis"
	data.erase("themed_district")
	_expect(ExplorationLayout._approach_problem(data, nav, street) == "warehouse_approach", "seeded warehouse uses the same early and final approach contract")


func _expect(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("BH_MISSION_LOADING_FAIL ", label)
