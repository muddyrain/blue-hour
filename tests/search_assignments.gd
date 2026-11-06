extends SceneTree
## Pure ownership fixtures; movement, damage, work progress and receipts remain A's tests.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SEARCH_ASSIGNMENTS_FAIL " + label)


func candidate(member_id: int, distance: float, reachable: bool = true, available: bool = true) -> Dictionary:
	return {"member_id":member_id, "distance":distance, "reachable":reachable, "available":available}


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var jobs: SearchAssignments = SearchAssignments.new()
	var member_ids: Array[int] = [1, 2, 3, 4]
	var site_ids: Array[String] = ["food:west", "food:east", "cash", "airdrop"]
	expect(jobs.snapshot() == {"version":1, "assignments":[]}, "fresh state is explicit empty version one")
	expect(SearchAssignments.problem(jobs.snapshot(), member_ids, site_ids).is_empty(), "empty assignments authenticate")
	expect(jobs.member_for("cash") == 0 and jobs.site_for(1).is_empty() and jobs.phase_for(1).is_empty(), "unassigned queries return defined sentinels")
	for size: int in [2, 3, 4]:
		var all_work: SearchAssignments = SearchAssignments.new()
		for index: int in range(size):
			expect(all_work.assign(index + 1, site_ids[index]), "each member can be assigned without guard reservation")
		expect(all_work.ordered().size() == size, "full two three or four member team may all work")
	expect(jobs.assign(2, "food:west") and jobs.assign(1, "food:east"), "same resource type retains distinct site identities")
	jobs.begin(2)
	var before: Dictionary = jobs.snapshot()
	expect(not jobs.assign(3, "food:west") and not jobs.assign(2, "cash"), "occupied site and assigned member cannot be preempted")
	expect(not jobs.assign(2, "food:west") and jobs.snapshot() == before, "duplicate request does not reset working phase")
	expect(jobs.phase_for(2) == "working" and jobs.phase_for(1) == "approach", "begin changes only that member")
	jobs.begin(99)
	jobs.begin(2)
	expect(jobs.snapshot() == before, "unknown begin and repeated begin are no ops")
	var released: Dictionary = jobs.release_member(2)
	expect(released == {"member_id":2, "site_id":"food:west", "phase":"working"}, "cancel returns exact released ownership")
	expect(jobs.member_for("food:west") == 0 and jobs.site_for(2).is_empty() and jobs.phase_for(2).is_empty(), "cancel clears both ownership directions")
	expect(jobs.member_for("food:east") == 1 and jobs.phase_for(1) == "approach", "cancel leaves independent same type assignment intact")
	expect(jobs.release_member(2).is_empty(), "independent cancel is once only")
	expect(jobs.assign(3, "food:west"), "released site can be assigned without affecting other work")
	var rows: Array[Dictionary] = jobs.ordered()
	expect(rows[0].site_id == "food:east" and rows[1].site_id == "food:west", "snapshot order follows stable site identity")
	rows[0].phase = "working"
	rows.clear()
	expect(jobs.phase_for(1) == "approach" and jobs.ordered().size() == 2, "ordered returns detached values")
	var captured: Dictionary = jobs.snapshot()
	captured.assignments[0].member_id = 4
	expect(jobs.member_for("food:east") == 1, "snapshot cannot mutate live ownership")
	var equivalent: SearchAssignments = SearchAssignments.new()
	equivalent.assign(3, "food:west")
	equivalent.assign(1, "food:east")
	expect(equivalent.snapshot() == jobs.snapshot(), "assignment arrival order does not change serialized order")
	var saved: Dictionary = jobs.snapshot()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	expect(SearchAssignments.problem(decoded, member_ids, site_ids).is_empty(), "JSON integer valued numbers preserve identity")
	var restored: SearchAssignments = SearchAssignments.new()
	restored.restore(decoded)
	expect(restored.snapshot() == saved and typeof(restored.ordered()[0].member_id) == TYPE_INT, "restore normalizes identities and preserves phases")
	decoded.assignments[0].phase = "working"
	expect(restored.phase_for(1) == "approach", "restore does not retain caller owned dictionaries")
	var unsorted: Dictionary = saved.duplicate(true)
	unsorted.assignments.reverse()
	restored.restore(unsorted)
	expect(restored.snapshot() == saved, "valid incoming order canonicalizes without reassigning members")
	for change: String in ["extra", "missing_version", "bad_version", "fraction_version", "missing_rows", "rows_type", "row_type", "row_extra", "row_missing", "zero_id", "fraction_id", "string_id", "nonfinite_id", "empty_site", "site_type", "phase", "phase_type", "duplicate_member", "duplicate_site"]:
		var bad: Dictionary = JSON.parse_string(JSON.stringify(saved))
		match change:
			"extra": bad.extra = 0
			"missing_version": bad.erase("version")
			"bad_version": bad.version = 2
			"fraction_version": bad.version = 1.5
			"missing_rows": bad.erase("assignments")
			"rows_type": bad.assignments = {}
			"row_type": bad.assignments[0] = "food:east"
			"row_extra": bad.assignments[0].progress = 10
			"row_missing": bad.assignments[0].erase("phase")
			"zero_id": bad.assignments[0].member_id = 0
			"fraction_id": bad.assignments[0].member_id = 1.5
			"string_id": bad.assignments[0].member_id = "1"
			"nonfinite_id": bad.assignments[0].member_id = INF
			"empty_site": bad.assignments[0].site_id = ""
			"site_type": bad.assignments[0].site_id = 1
			"phase": bad.assignments[0].phase = "queued"
			"phase_type": bad.assignments[0].phase = 1
			"duplicate_member": bad.assignments[1].member_id = bad.assignments[0].member_id
			"duplicate_site": bad.assignments[1].site_id = bad.assignments[0].site_id
		expect(not SearchAssignments.problem(bad, member_ids, site_ids).is_empty(), "strictly reject " + change)
		restored.restore(bad)
		expect(restored.snapshot() == saved, "bad restore preserves existing state " + change)
	var missing_member: Array[int] = [2, 3, 4]
	var missing_site: Array[String] = ["food:west", "cash", "airdrop"]
	expect(not SearchAssignments.problem(saved, missing_member, site_ids).is_empty(), "missing actual member identity rejects")
	expect(not SearchAssignments.problem(saved, member_ids, missing_site).is_empty(), "missing actual site identity rejects")
	var duplicate_members: Array[int] = [1, 1, 3]
	var duplicate_sites: Array[String] = ["food:east", "food:west", "food:east"]
	expect(not SearchAssignments.problem(saved, duplicate_members, site_ids).is_empty(), "duplicate member identity catalog rejects")
	expect(not SearchAssignments.problem(saved, member_ids, duplicate_sites).is_empty(), "duplicate site identity catalog rejects")
	expect(not jobs.assign(0, "cash") and not jobs.assign(4, ""), "new ownership rejects sentinel identities")
	var candidates: Array[Dictionary] = [candidate(4, 1.0, false), candidate(1, 2.0, true, false), candidate(3, 10.0), candidate(2, 10.0)]
	var original: Array[Dictionary] = candidates.duplicate(true)
	expect(SearchAssignments.pick(candidates) == 2, "only available reachable candidates then distance and member ID")
	expect(candidates == original, "pick never changes candidates")
	candidates.reverse()
	expect(SearchAssignments.pick(candidates) == 2, "pick stable under candidate order")
	candidates = [candidate(4, 0.0), candidate(1, 0.01)]
	expect(SearchAssignments.pick(candidates) == 4, "closer member beats lower ID and zero distance is valid")
	candidates = [candidate(1, 1.0, true, false), candidate(2, 0.0, false)]
	expect(SearchAssignments.pick(candidates) == 0, "no idle or reachable member returns zero")
	candidates.clear()
	expect(SearchAssignments.pick(candidates) == 0, "empty candidates return zero")
	for change: String in ["duplicate", "negative", "nan", "infinite", "fraction_id", "missing", "extra", "available_type", "reachable_type"]:
		candidates = [candidate(1, 2.0), candidate(2, 1.0)]
		match change:
			"duplicate": candidates[1].member_id = 1
			"negative": candidates[1].distance = -1.0
			"nan": candidates[1].distance = NAN
			"infinite": candidates[1].distance = INF
			"fraction_id": candidates[1].member_id = 1.5
			"missing": candidates[1].erase("available")
			"extra": candidates[1].priority = 1
			"available_type": candidates[1].available = 1
			"reachable_type": candidates[1].reachable = 1
		expect(SearchAssignments.pick(candidates) == 0, "ambiguous or malformed candidates fail closed " + change)
	print(JSON.stringify({"checks":checks, "failures":failures, "scope":"pure_assignment_ownership"}))
	quit(0 if failures == 0 else 1)
