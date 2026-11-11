extends SceneTree
## Negative copies of real M48 sources. Never opens an input file for writing.
## Camp structure, business transition, and independently decoded record are separate layers.

var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var not_exercised: Array[Dictionary] = []
var output: String = ""
var camp_path: String = ""
var receipt_path: String = ""
var actual_camp: Dictionary = {}
var actual_receipt: Dictionary = {}
var _index: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return ""


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("M48_INVALID_FAIL " + label)


func _local_path(path: String) -> bool:
	return path.is_absolute_path() and "/.local/" in path.replace("\\", "/") \
		and ".." not in path and ProgressWriter._unlinked(path)


func _run() -> void:
	output = _argument("--flow-output=").replace("\\", "/").simplify_path()
	camp_path = _argument("--invalid-camp=").replace("\\", "/").simplify_path()
	receipt_path = _argument("--invalid-receipt=").replace("\\", "/").simplify_path()
	if not _local_path(output) or not _local_path(camp_path) or not _local_path(receipt_path) \
			or not FileAccess.file_exists(camp_path) or not FileAccess.file_exists(receipt_path) \
			or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) \
			or "/.local/" not in OS.get_user_data_dir().replace("\\", "/"):
		printerr("M48_INVALID_INPUT Requires two existing isolated inputs and a fresh isolated output directory")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	var input_hashes: Dictionary = {"camp":FileAccess.get_sha256(camp_path), "receipt":FileAccess.get_sha256(receipt_path)}
	actual_camp = _read_camp(camp_path)
	var source_record: Dictionary = ReceiptJournal.new(receipt_path.get_base_dir())._read_record(receipt_path)
	_check(source_record.get("error") == OK, "original real result record independently decodes and validates")
	if source_record.get("error") == OK: actual_receipt = source_record.receipt
	_check(not actual_camp.is_empty() and TransactionReceipt.camp_problem(actual_camp).is_empty(), "original real C camp passes full camp validation")
	_check(not actual_receipt.is_empty() and actual_receipt.get("phase") in ["RESULT_READY", "COMMITTED"]
		and actual_receipt.get("envelope", {}).get("result", {}).get("camp") is Dictionary,
		"input is an actual frozen sortie result rather than an edit or synthetic registration")
	if failures.is_empty():
		var result_camp: Dictionary = TransactionReceipt.camp(actual_receipt)
		_check(EconomyBuildV1.enabled(actual_camp) and TransactionReceipt.same(actual_camp, result_camp),
			"the real C camp and the supplied actual return record describe the same result")
	if failures.is_empty():
		_copy_variant_cases()
		_sold_operation_cases()
	_check(FileAccess.get_sha256(camp_path) == input_hashes.camp
		and FileAccess.get_sha256(receipt_path) == input_hashes.receipt, "both original source files remain byte-identical")
	_write_json("report.json", {"checks":checks, "failures":failures, "cases":observations, "not_exercised":not_exercised,
		"scope":"REAL_SOURCE_NEGATIVE_COPIES", "pid":OS.get_process_id(),
		"inputs":{"camp":camp_path, "receipt":receipt_path, "sha256":input_hashes},
		"layers":{"camp":"RunSave structural/preflight only", "receipt":"original base and source-bound result recomputation",
			"record":"independent ExactJSON single-record decoding, not an invented full journal chain"}})
	print("M48_INVALID_READBACK " + JSON.stringify({"checks":checks, "failures":failures, "case_count":observations.size(), "report":output.path_join("report.json")}))
	quit(0 if failures.is_empty() else 1)


func _read_camp(path: String) -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return {}
	var value: Dictionary = parser.data
	if value.has("record_encoding"):
		var decoded: Dictionary = RecordEncoding.unpack(value)
		if decoded.get("error") != OK: return {}
		value = decoded.payload
	if value.get("schema_version") != null: return value
	if value.get("camp") is Dictionary: return value.camp
	return {}


func _copy_variant_cases() -> void:
	var source: Dictionary = TransactionReceipt.camp(actual_receipt)
	var variant: Dictionary = source.duplicate(true)
	var first_tool: String = ""
	var changed: bool = false
	for edit: Dictionary in EconomyBuildV1.state(variant).edits:
		if edit.tools.is_empty(): continue
		if first_tool.is_empty(): first_tool = edit.tools[0]
		else:
			edit.tools[0] = first_tool
			changed = true
			break
	if changed: _result_case("two-edits-consume-one-tool", variant, "CAMP_REJECT")
	else: _missing("two-edits-consume-one-tool", "real C source needs two tool-consuming edits")
	var repair_row: int = -1
	var order_row: int = -1
	var returns: Array = EconomyBuildV1.state(source).returns
	for index: int in range(returns.size()):
		if returns[index].repairs.size() > 0: repair_row = index
		if returns[index].repairs.size() > 1: order_row = index
	if repair_row >= 0:
		variant = source.duplicate(true)
		var row: Dictionary = EconomyBuildV1.state(variant).returns[repair_row]
		var replacement: String = ""
		for item: Dictionary in variant.weapons:
			if item.condition == "ready" and item.instance_id not in row.repairs \
					and int(String(item.acquired_sortie).get_slice(":", 1)) < int(row.sortie):
				replacement = item.instance_id
				break
		if not replacement.is_empty():
			row.repairs[0] = replacement
			_result_case("auto-repair-wrong-old-ready-instance", variant, "CAMP_OR_TRANSITION_REJECT")
		else: _missing("auto-repair-wrong-old-ready-instance", "no earlier ready alternative exists in the real source")
	else: _missing("auto-repair-wrong-old-ready-instance", "real C source has no automatic repair event")
	if order_row >= 0:
		variant = source.duplicate(true)
		EconomyBuildV1.state(variant).returns[order_row].repairs.reverse()
		_result_case("auto-repair-order-reversed", variant, "CAMP_OR_TRANSITION_REJECT")
	elif "--invalid-require-two-repairs" in OS.get_cmdline_user_args():
		_missing("auto-repair-order-reversed", "real C source needs one tier-two two-instance automatic repair")
	else:
		not_exercised.append({"case":"auto-repair-order-reversed", "status":"NOT_EXERCISED",
			"reason":"This authentic camp has no two-instance automatic repair; directed tier-two sorting is tested separately in m48_sources.gd."})
	for kind: String in ["food", "repair", "planning"]:
		variant = source.duplicate(true)
		var target: Dictionary = {}
		var facility: String = {"food":"supply", "repair":"workshop", "planning":"planning"}[kind]
		for row: Dictionary in EconomyBuildV1.state(variant).returns:
			if row.facilities.get(facility, {}).get("level") == 0:
				target = row
				break
		if target.is_empty():
			_missing("unbuilt-facility-" + kind, "source needs a genuine earlier return before construction")
			continue
		match kind:
			"food": target.food = 2
			"repair": target.repairs = [String(variant.profile_id) + ":starter:1"]
			"planning":
				var trait_before: Dictionary = {"id":TraitRules.IDS[0], "level":1, "progress":0}
				var trait_after: Dictionary = {"id":TraitRules.IDS[0], "level":2, "progress":1}
				target.planning_candidates = [{"member_id":1, "trait":trait_before}]
				target.planning = {"member_id":1, "points":1, "before":trait_before, "after":trait_after}
		_result_case("unbuilt-facility-" + kind, variant, "CAMP_REJECT")
	variant = source.duplicate(true)
	var passive: String = ""
	for id: String in variant.journey.build.owned:
		if id not in variant.journey.build.progression.enhanced:
			passive = id
			break
	if not passive.is_empty():
		variant.journey.build.progression.enhanced.append(passive)
		_result_case("unpaid-passive-enhancement", variant, "CAMP_REJECT")
	else: _missing("unpaid-passive-enhancement", "real C source has no owned unenhanced passive")
	# Freeze metadata has its own boundary: the camp's history checks levels,
	# while the actual result transition must retain the complete departure row.
	variant = source.duplicate(true)
	if not EconomyBuildV1.state(variant).returns.is_empty():
		EconomyBuildV1.state(variant).returns.back().facilities.supply.built_sortie = int(variant.settled_sorties) + 20
		_result_case("forged-frozen-facility-source-metadata", variant, "CAMP_OR_TRANSITION_REJECT")


func _sold_operation_cases() -> void:
	# A final camp may be VICTORY. Its genuine departure base is ACTIVE, so a
	# sold-target refusal cannot be accidentally explained by the end-state guard.
	var before: Dictionary = actual_receipt.base
	_check(before.journey.state == "ACTIVE" and not CampaignState.ended(before), "sold operation probes use the genuine active departure camp")
	var sold: Array = EconomyBuildV1.state(before).sold
	if sold.is_empty():
		_missing("sold-instance-components-and-upgrade", "real active source needs an earlier confirmed sale")
		return
	var identity: String = sold[0].instance.instance_id
	for op: String in ["basic_component", "combat_component", "upgrade_weapon"]:
		var choice: String = "quick_v1" if op == "basic_component" else WeaponModifiers.PIERCE if op == "combat_component" else ""
		var edit_id: String = String(before.profile_id) + ":edit:" + RunSave.new_profile_id()
		var request: Dictionary = EconomyBuildV1.request(before, op, identity, choice, edit_id)
		var quote: Dictionary = EconomyBuildV1.offer(before, op, identity, choice)
		var proposed: Dictionary = CampEdit.propose(before, request)
		var previous: Dictionary = {"root_id":before.journey.root_id, "revision":actual_receipt.revision,
			"deaths":_prior_deaths(before)}
		var record: Dictionary = CampEdit.record(before, request, edit_id, previous)
		_check(not quote.available and quote.reason == "该实例已出售或不存在" and proposed.is_empty() and record.is_empty(),
			"pure proposal and edit-record preflight reject sold instance " + op)
		var after: Dictionary = before.duplicate(true)
		# A balanced debit alone can be a valid camp shape. Only the original edit
		# authority can decide whether this particular sold instance may be changed.
		if int(after.cash) >= 8:
			after.cash -= 8
			after.camp_spending += 8
		var forged: Dictionary = TransactionReceipt.registration(before, before.journey.root_id)
		forged.phase = "EDIT_READY"
		forged.revision = int(actual_receipt.revision) + 1
		forged.transaction_id = edit_id
		forged.deaths = previous.deaths
		forged.rules = {"ruleset_id":"camp-edit", "data_version":1, "request":request}
		forged.envelope = {"before_hash":SurvivalContracts.fingerprint(before),
			"after_hash":SurvivalContracts.fingerprint(after), "result":after}
		var observed: Dictionary = _layers("sold-instance-" + op, after, forged, "CAMP_OR_TRANSITION_REJECT")
		observed.proposal_rejected = proposed.is_empty()
		observed.record_preflight_rejected = record.is_empty()
		observed.offer_reason = quote.reason
		observed.instance_id = identity
		observations.append(observed)


func _prior_deaths(before: Dictionary) -> Array:
	var result: Array = []
	for checkpoint: Dictionary in actual_receipt.deaths:
		var member: Dictionary = SurvivorRoster.member(before.crew, int(checkpoint.death.member_id))
		if not member.is_empty() and member.health <= 0: result.append(checkpoint.duplicate(true))
	return result


func _result_case(label: String, variant: Dictionary, expectation: String) -> void:
	var forged: Dictionary = actual_receipt.duplicate(true)
	forged.envelope.result.camp = variant
	# Preserve real base, battle, accepted facts, timing and rules. Recompute only
	# the normal outer result digest so rejection tests business/source checks.
	forged.envelope = SurvivalContracts.transaction(forged.base, forged.envelope.result, forged.transaction_id)
	observations.append(_layers(label, variant, forged, expectation))


func _layers(label: String, variant: Dictionary, forged: Dictionary, expectation: String) -> Dictionary:
	var folder: String = output.path_join("case-%02d-%s" % [_index, label])
	_index += 1
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("run.enemy-v1.json")
	var store: RunSave = RunSave.new(path)
	store._enemy_format = true
	var issue: String = TransactionReceipt.camp_problem(variant)
	var preflight: Error = store._save_owned(variant)
	var preflight_reason: String = store.diagnostic
	var text: String = JSON.stringify(variant, "\t", true, true) + "\n"
	_write_bytes(path, text.to_utf8_buffer())
	var independent: RunSave = RunSave.new(path)
	independent._enemy_format = true
	var reread: Dictionary = independent.read_transaction_exact()
	var receipt_issue: String = TransactionReceipt.problem(forged)
	var exact_path: String = folder.path_join("forged-record.json")
	_write_bytes(exact_path, RecordEncoding.stringify(forged).to_utf8_buffer())
	var decoded: Dictionary = ReceiptJournal.new(folder)._read_record(exact_path)
	var camp_rejected: bool = not issue.is_empty() and preflight != OK and reread.get("error") != OK
	if expectation == "CAMP_REJECT":
		_check(camp_rejected, label + " rejected separately by camp structure, write preflight and independent camp read")
	else:
		_check((issue.is_empty() and preflight == OK and reread.get("error") == OK) or camp_rejected,
			label + " reports a consistent actual camp-validation boundary")
	_check(not receipt_issue.is_empty() and decoded.get("error") != OK, label + " rejected by the real source-bound receipt and independently decoded record")
	_check(decoded.get("reason", "") == receipt_issue, label + " independent record reaches the same business rejection rather than only a transport error")
	return {"case":label, "expectation":expectation, "scope":"NEGATIVE_COPY_OF_REAL_INPUT",
		"camp_structure_issue":issue, "write_preflight_error":preflight, "write_preflight_reason":preflight_reason,
		"independent_camp_read_error":reread.get("error"), "independent_camp_read_reason":reread.get("message", independent.diagnostic),
		"camp_rejected":camp_rejected, "camp_accepted":issue.is_empty() and preflight == OK and reread.get("error") == OK,
		"receipt_issue":receipt_issue, "independent_record_error":decoded.get("error"), "independent_record_reason":decoded.get("reason", ""),
		"actual_boundary":"CAMP_AND_TRANSACTION_REJECT" if camp_rejected else "CAMP_STRUCTURE_ACCEPTS_TRANSACTION_REJECTS",
		"camp_file":path, "record_file":exact_path}


func _missing(label: String, reason: String) -> void:
	observations.append({"case":label, "status":"NOT_TESTED", "reason":reason})
	_check(false, label + " lacks the required genuine source fixture: " + reason)


func _write_json(name: String, value: Dictionary) -> void:
	_write_bytes(output.path_join(name), (JSON.stringify(value, "\t", true, true) + "\n").to_utf8_buffer())


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	_check(path.begins_with(output + "/") and path != camp_path and path != receipt_path,
		"negative artifact write remains inside the fresh output directory")
	if not path.begins_with(output + "/") or path == camp_path or path == receipt_path: return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "isolated negative artifact is writable")
	if file == null: return
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	_check(error == OK and FileAccess.get_file_as_bytes(path) == bytes, "negative artifact preserves the exact intended bytes")
