class_name SearchAssignments
extends RefCounted
## Value-only member/site ownership. Expedition owns availability, movement and progress.

const VERSION: int = 1
const MAX_EXACT_INTEGER: int = 9_007_199_254_740_991
const PHASES: Array[String] = ["approach", "working"]

var _assignments: Array[Dictionary] = []


static func problem(value: Variant, member_ids: Array[int], site_ids: Array[String]) -> String:
	var issue: String = _shape_problem(value)
	if not issue.is_empty():
		return issue
	var members: Dictionary = {}
	for member_id: int in member_ids:
		if not _positive_integer(member_id) or members.has(member_id):
			return "SEARCH_MEMBER_IDENTITIES"
		members[member_id] = true
	var sites: Dictionary = {}
	for site_id: String in site_ids:
		if site_id.is_empty() or sites.has(site_id):
			return "SEARCH_SITE_IDENTITIES"
		sites[site_id] = true
	for row: Dictionary in value.assignments:
		if not members.has(int(row.member_id)):
			return "SEARCH_MEMBER_MISSING"
		if not sites.has(row.site_id):
			return "SEARCH_SITE_MISSING"
	return ""


static func pick(candidates: Array[Dictionary]) -> int:
	var selected: int = 0
	var nearest: float = INF
	var seen: Dictionary = {}
	for row: Dictionary in candidates:
		if row.size() != 4 or not row.has_all(["member_id", "distance", "reachable", "available"]):
			return 0
		if not _positive_integer(row.member_id) or seen.has(int(row.member_id)):
			return 0
		if not row.reachable is bool or not row.available is bool or not _distance(row.distance):
			return 0
		var member_id: int = int(row.member_id)
		seen[member_id] = true
		if not row.reachable or not row.available:
			continue
		var distance: float = float(row.distance)
		if distance < nearest or distance == nearest and (selected == 0 or member_id < selected):
			selected = member_id
			nearest = distance
	return selected


static func _shape_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 2 or not value.has_all(["version", "assignments"]):
		return "SEARCH_FIELDS"
	if not _positive_integer(value.version) or value.version != VERSION or not value.assignments is Array:
		return "SEARCH_VERSION_OR_ASSIGNMENTS"
	var members: Dictionary = {}
	var sites: Dictionary = {}
	for row: Variant in value.assignments:
		if not row is Dictionary or row.size() != 3 or not row.has_all(["member_id", "site_id", "phase"]):
			return "SEARCH_ASSIGNMENT_FIELDS"
		if not _positive_integer(row.member_id) or not row.site_id is String or row.site_id.is_empty():
			return "SEARCH_ASSIGNMENT_IDENTITY"
		if not row.phase is String or row.phase not in PHASES:
			return "SEARCH_ASSIGNMENT_PHASE"
		var member_id: int = int(row.member_id)
		if members.has(member_id):
			return "SEARCH_MEMBER_DUPLICATE"
		if sites.has(row.site_id):
			return "SEARCH_SITE_DUPLICATE"
		members[member_id] = true
		sites[row.site_id] = true
	return ""


static func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 1 and value <= MAX_EXACT_INTEGER and float(value) == floorf(float(value))


static func _distance(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0


static func _before(left: Dictionary, right: Dictionary) -> bool:
	return left.site_id < right.site_id or left.site_id == right.site_id and left.member_id < right.member_id


func assign(member_id: int, site_id: String) -> bool:
	if not _positive_integer(member_id) or site_id.is_empty() or not site_for(member_id).is_empty() or member_for(site_id) != 0:
		return false
	_assignments.append({"member_id":member_id, "site_id":site_id, "phase":"approach"})
	return true


func begin(member_id: int) -> void:
	for row: Dictionary in _assignments:
		if row.member_id == member_id:
			row.phase = "working"
			return


func release_member(member_id: int) -> Dictionary:
	for index: int in range(_assignments.size()):
		if _assignments[index].member_id == member_id:
			var released: Dictionary = _assignments[index].duplicate(true)
			_assignments.remove_at(index)
			return released
	return {}


func member_for(site_id: String) -> int:
	for row: Dictionary in _assignments:
		if row.site_id == site_id:
			return int(row.member_id)
	return 0


func site_for(member_id: int) -> String:
	for row: Dictionary in _assignments:
		if row.member_id == member_id:
			return String(row.site_id)
	return ""


func phase_for(member_id: int) -> String:
	for row: Dictionary in _assignments:
		if row.member_id == member_id:
			return String(row.phase)
	return ""


func ordered() -> Array[Dictionary]:
	var result: Array[Dictionary] = _assignments.duplicate(true)
	result.sort_custom(_before)
	return result


func snapshot() -> Dictionary:
	return {"version":VERSION, "assignments":ordered()}


func restore(value: Dictionary) -> void:
	# External identity and world checks must succeed before this structural restore.
	if not _shape_problem(value).is_empty():
		return
	var restored: Array[Dictionary] = []
	for row: Dictionary in value.assignments:
		restored.append({"member_id":int(row.member_id), "site_id":String(row.site_id), "phase":String(row.phase)})
	restored.sort_custom(_before)
	_assignments = restored
