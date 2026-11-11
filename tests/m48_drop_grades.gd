extends SceneTree
## PARAMETER_ONLY: minimal reward/entropy contexts, no played map, receipt, save, or reward bank.
## Complete action source authentication is exercised separately by m48_sources.gd.

const PROFILE: String = "0123456789abcdef0123456789abcdef"
const ACTION_ID: String = "87c2d70415b557042a81f4134097aa257a4f287f53871bdd928cc9b5c5a6c85e"
const REPORT_LIMIT: int = 1_048_576
const SEARCH_LIMIT: int = 20_000
const DAYS: Array[Dictionary] = [
	{"day":2, "ordinary":1, "high":2}, {"day":4, "ordinary":1, "high":2},
	{"day":5, "ordinary":2, "high":3}, {"day":7, "ordinary":2, "high":3},
	{"day":8, "ordinary":3, "high":4}, {"day":10, "ordinary":3, "high":4},
	{"day":11, "ordinary":4, "high":5}, {"day":13, "ordinary":4, "high":5},
	{"day":14, "ordinary":5, "high":5}, {"day":17, "ordinary":5, "high":5},
	{"day":20, "ordinary":5, "high":5}, {"day":99, "ordinary":5, "high":5},
]
# Literal inclusive intervals from attachment 03, independent of the production weight arrays.
const QUALITY_RANGES: Dictionary = {
	1:{"common":[0,59], "enhanced":[60,89], "rare":[90,99]},
	2:{"common":[0,44], "enhanced":[45,79], "rare":[80,99]},
	3:{"common":[0,24], "enhanced":[25,64], "rare":[65,99]},
}
const EXPECTED_COUNTS: Dictionary = {
	1:{"common":60, "enhanced":30, "rare":10},
	2:{"common":45, "enhanced":35, "rare":20},
	3:{"common":25, "enhanced":40, "rare":35},
}
const LEVEL_FACTORS: Dictionary = {1:1.00, 2:1.10, 3:1.20, 4:1.30, 5:1.40}
const SIZE_GRADES: Dictionary = {"small":1, "medium":2, "large":3}
const BASIC_AFFIXES: Array[String] = ["quick_v1", "reach_v1"]
const COMBAT_AFFIXES: Array[String] = ["pierce_v1", "defeat_refund_v1"]

var rows: Array[Dictionary] = []
var failures: Array[String] = []
var witnesses: Dictionary = {}
var samples: Array[Dictionary] = []
var weight_counts: Dictionary = {}
var search_iterations: int = 0
var output: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	rows.append({"pass":value, "label":label})
	if not value:
		failures.append(label)
		printerr("M48_DROP_GRADES_FAIL " + label)


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--flow-output="): output = argument.trim_prefix("--flow-output=")
	if not output.is_empty() and (not output.is_absolute_path() or not output.replace("\\", "/").begins_with(isolated)
			or ".." in output or not ProgressWriter._unlinked(output) or FileAccess.file_exists(output.path_join("report.json"))):
		quit(2)
		return
	var began: int = Time.get_ticks_usec()
	_grade_and_day_matrix()
	_find_roll_witnesses()
	if witnesses.size() == 100:
		_weight_matrix()
		_compatibility_matrix()
		_repeat_and_order_cases()
	_level_schema_cases()
	_hammer_identity_case()
	var report: Dictionary = {"scope":"PARAMETER_ONLY", "checks":rows.size(), "failures":failures,
		"rows":rows, "day_expectations":DAYS, "quality_intervals":QUALITY_RANGES,
		"observed_quality_counts":weight_counts, "roll_witnesses":witnesses, "reward_samples":samples,
		"search_iterations":search_iterations, "wall_ms":(Time.get_ticks_usec() - began) / 1000.0,
		"full_source_authentication":"NOT_RUN_IN_PARAMETER_FIXTURES; m48_sources.gd covers complete canonical actions",
		"normal_campaign":"NOT_TESTED", "disk_writes":"REPORT_ONLY", "pid":OS.get_process_id()}
	if not output.is_empty():
		_write_report(report)
	print("M48_DROP_GRADES " + JSON.stringify({"scope":"PARAMETER_ONLY", "checks":rows.size(),
		"failures":failures, "weight_counts":weight_counts, "rolls_found":witnesses.size(),
		"search_iterations":search_iterations, "wall_ms":(Time.get_ticks_usec() - began) / 1000.0,
		"report":output.path_join("report.json") if not output.is_empty() else "NOT_REQUESTED"}))
	quit(0 if failures.is_empty() else 1)


func _source(seed_value: String, action_id: String, day: int, size: String, gun: String = "carbine", rare: bool = false) -> Dictionary:
	var site: Dictionary = {"id":"cash", "kind":"cash", "weapon":true, "work_mode":"outdoor",
		"drop":{"version":2, "weapon_id":gun}}
	var source: Dictionary = {"version":9, "seed":seed_value, "id":action_id, "day":day, "slot":2,
		"type":"airdrop", "campaign":{"run_id":PROFILE, "is_finale":false},
		"layout":{"size":size, "topology":"industrial"}, "sites":[site]}
	if rare: source.rare_policy = 1
	if gun == CombatEquipment.HAMMER_ID:
		site.drop = {"version":WeaponInventory.HAMMER_DROP_VERSION, "weapon_id":CombatEquipment.HAMMER_ID}
		source.mission_policy = 1
		source.content_wave_policy = 1
		source.powers = {"version":SpecialPowers.M48_VERSION}
	return EconomyActions.freeze(source)


func _reward(action: Dictionary) -> Dictionary:
	return EconomyBuildV1.site_reward("%s:%d" % [PROFILE, int(action.day) - 1], action, action.sites[0])


func _grade_and_day_matrix() -> void:
	for size: String in SIZE_GRADES:
		var literal_grade: int = int(SIZE_GRADES[size])
		for expected: Dictionary in DAYS:
			for gun: String in ["carbine", "long_rifle", "shotgun_v1", "fire_axe_v1"]:
				var action: Dictionary = _source("m48-date-boundary".md5_text(), ACTION_ID, int(expected.day), size, gun)
				_check(EconomyActions.grade(action) == literal_grade, "literal size grade %s → %d" % [size, literal_grade])
				var item: Dictionary = _reward(action)
				var literal_level: int = int(expected.high if size == "large" else expected.ordinary)
				_check(not item.is_empty() and item.get("weapon_level") == literal_level,
					"literal day %d %s %s → level %d" % [int(expected.day), size, gun, literal_level])
				if item.is_empty(): continue
				_check(item.drop.get("loot_grade") == literal_grade and item.drop.get("day") == expected.day,
					"drop freezes the actual grade and departure day")
				_check(WeaponModifiers.problem(item).is_empty(), "new parameter result passes its explicit attribute schema")
				var actual_factor: float = float(WeaponModifiers.effective(item).damage) / WeaponInventory.definition(gun).damage
				_check(is_equal_approx(actual_factor, float(LEVEL_FACTORS[literal_level])),
					"literal direct-damage multiplier applies once to gun or melee")
	for size: String in SIZE_GRADES:
		for expected: Dictionary in DAYS:
			var action: Dictionary = _source("m48-rare-grade".md5_text(), ACTION_ID, int(expected.day), size, "long_rifle", true)
			var item: Dictionary = _reward(action)
			_check(EconomyActions.grade(action) == 3 and item.get("weapon_level") == expected.high,
				"rare equipment retains literal grade3 in %s on day%d" % [size, int(expected.day)])


func _entropy_roll(seed_value: String, action_id: String, site_id: String) -> int:
	# This documented stable input only locates concrete test rolls. It does not
	# derive the expected quality, grade, level, or the production reward itself.
	return ("BH_M48_WEAPON:%s:%s:%s:0" % [seed_value, action_id, site_id]).sha256_text().substr(0, 8).hex_to_int() % 100


func _find_roll_witnesses() -> void:
	for index: int in range(SEARCH_LIMIT):
		var seed_value: String = ("m48-parameter-roll-%d" % index).md5_text()
		var roll: int = _entropy_roll(seed_value, ACTION_ID, "cash")
		if not witnesses.has(roll): witnesses[roll] = seed_value
		search_iterations = index + 1
		if witnesses.size() == 100: break
	_check(witnesses.size() == 100, "bounded deterministic search finds every inclusive roll0..99")


func _literal_quality(grade_value: int, roll: int) -> String:
	for quality: String in ["common", "enhanced", "rare"]:
		var interval: Array = QUALITY_RANGES[grade_value][quality]
		if roll >= int(interval[0]) and roll <= int(interval[1]): return quality
	return "NO_SPEC_EXPECTATION"


func _weight_matrix() -> void:
	for size: String in SIZE_GRADES:
		var grade_value: int = int(SIZE_GRADES[size])
		var counts: Dictionary = {"common":0, "enhanced":0, "rare":0}
		for roll: int in range(100):
			var seed_value: String = witnesses[roll]
			var action: Dictionary = _source(seed_value, ACTION_ID, 8, size)
			var item: Dictionary = _reward(action)
			_check(not item.is_empty(), "quality boundary parameter source produces a reward")
			if item.is_empty(): continue
			var quality: String = _literal_quality(grade_value, roll)
			_check(item.get("quality") == quality, "literal quality grade%d roll%d → %s" % [grade_value, roll, quality])
			if counts.has(item.get("quality")): counts[item.quality] += 1
			_check(item.get("weapon_level") == (4 if grade_value == 3 else 3), "quality roll never changes the literal date-derived level")
			_check(is_equal_approx(float(WeaponModifiers.effective(item).damage) / WeaponInventory.definition("carbine").damage,
				1.30 if grade_value == 3 else 1.20), "quality itself contributes no extra damage multiplier")
			_affix_expectation(item, quality, "carbine")
			samples.append({"grade":grade_value, "roll":roll, "seed":seed_value, "action":ACTION_ID,
				"quality":item.get("quality"), "level":item.get("weapon_level"), "affixes":item.get("affixes")})
		_check(counts == EXPECTED_COUNTS[grade_value], "every roll accounts for the exact literal %d/%d/%d weight" % [
			int(EXPECTED_COUNTS[grade_value].common), int(EXPECTED_COUNTS[grade_value].enhanced), int(EXPECTED_COUNTS[grade_value].rare)])
		weight_counts[grade_value] = counts
	# Grade3 is also mandatory for rare equipment whose original map was smaller.
	for roll: int in range(100):
		var item: Dictionary = _reward(_source(witnesses[roll], ACTION_ID, 8, "small", "carbine", true))
		_check(item.get("quality") == _literal_quality(3, roll), "rare source uses grade3 thresholds for roll%d" % roll)


func _affix_expectation(item: Dictionary, quality: String, gun: String) -> void:
	var affixes: Array = item.get("affixes", [])
	var expected_count: int = int({"common":0, "enhanced":1, "rare":2}[quality])
	_check(affixes.size() == expected_count, "literal quality fixes the exact affix count")
	if affixes.size() != expected_count: return
	if quality == "common": return
	_check(affixes[0] in BASIC_AFFIXES, "enhanced and rare first position is a compatible basic affix")
	if quality != "rare": return
	_check(affixes[0] != affixes[1], "rare affixes are different")
	_check(affixes[1] in (BASIC_AFFIXES if CombatEquipment.melee(gun) else COMBAT_AFFIXES),
		"rare second position follows the explicit gun or melee compatibility pool")


func _compatibility_matrix() -> void:
	for gun: String in ["carbine", "long_rifle", "shotgun_v1", "fire_axe_v1", CombatEquipment.HAMMER_ID]:
		for selected: Dictionary in [{"roll":0, "quality":"common"}, {"roll":45, "quality":"enhanced"}, {"roll":80, "quality":"rare"}]:
			var action: Dictionary = _source(witnesses[selected.roll], ACTION_ID, 8, "medium", gun)
			var item: Dictionary = _reward(action)
			_check(not item.is_empty() and item.get("weapon_id") == gun and item.get("quality") == selected.quality,
				"all three qualities retain the intended five-type weapon identity: " + gun)
			if item.is_empty(): continue
			_affix_expectation(item, selected.quality, gun)
			_check(WeaponModifiers.problem(item).is_empty(), "five-type new drop has a compatible explicit attribute shape")
			if selected.quality == "rare" and item.get("affixes", []).size() == 2:
				var duplicate: Dictionary = item.duplicate(true)
				duplicate.affixes[1] = duplicate.affixes[0]
				_check(not WeaponModifiers.problem(duplicate).is_empty(), "duplicate rare affixes are rejected")
				if CombatEquipment.melee(gun):
					var invalid: Dictionary = item.duplicate(true)
					invalid.affixes[1] = WeaponModifiers.PIERCE
					_check(not WeaponModifiers.problem(invalid).is_empty(), "gun combat affix cannot enter a melee result")


func _repeat_and_order_cases() -> void:
	var definitions: Array[Dictionary] = []
	var first: Dictionary = {}
	for index: int in range(3):
		var action: Dictionary = _source(witnesses[25 + index * 25], ("m48-call-order-%d" % index).sha256_text(), 8 + index, ["small", "medium", "large"][index])
		var item: Dictionary = _reward(action)
		_check(not item.is_empty(), "stable-stream parameter context produces a reward")
		if not item.is_empty():
			definitions.append(action)
			first[action.id] = item
	for index: int in range(100): randf() # An unrelated random consumer cannot change a source-owned stream.
	definitions.reverse()
	for action: Dictionary in definitions:
		_check(TransactionReceipt.same(first[action.id], _reward(action)), "reverse scavenging call order cannot reroll this source")
		_check(TransactionReceipt.same(_reward(action), _reward(action)), "same seed/action/site/ordinal always reproduces its exact reward")
		var original: Dictionary = first[action.id]
		var read: Dictionary = JSON.parse_string(JSON.stringify(action, "", true, true))
		_check(TransactionReceipt.same(original, _reward(read)), "JSON numeric roundtrip preserves the frozen drop result")
		# This is still a parameter-only in-memory context, never a valid camp or bank.
		var repair_context: Dictionary = {"weapons":[original.duplicate(true)], "cash":100, "camp_spending":0}
		var result: Dictionary = WeaponInventory.repair(repair_context, original.instance_id)
		var repaired: Dictionary = WeaponInventory.find(result.get("data", {"weapons":[]}), original.instance_id)
		var expected: Dictionary = original.duplicate(true)
		expected.condition = "ready"
		_check(not repaired.is_empty() and TransactionReceipt.same(repaired, expected),
			"real repair function changes condition without rerolling any confirmed drop field")
		_check(TransactionReceipt.same(original, _reward(action)), "repair call cannot reroll this source-owned reward stream")


func _level_schema_cases() -> void:
	var action: Dictionary = _source("m48-schema-level".md5_text(), ACTION_ID, 14, "large")
	var modern: Dictionary = _reward(action)
	_check(modern.get("weapon_level") == 5 and WeaponModifiers.problem(modern).is_empty(), "new attribute schema accepts the literal capped level5 result")
	var modern_json: Dictionary = JSON.parse_string(JSON.stringify(modern, "", true, true))
	_check(WeaponModifiers.problem(modern_json).is_empty(), "new level5.0 remains valid after JSON readback")
	for invalid_level: Variant in [0, 6, 99, 2.5]:
		var invalid: Dictionary = modern.duplicate(true)
		invalid.weapon_level = invalid_level
		_check(not WeaponModifiers.problem(invalid).is_empty(), "new level attribute rejects invalid boundary " + str(invalid_level))
	var legacy: Dictionary = WeaponInventory.reward(PROFILE + ":4", true)
	legacy.weapon_level = 2
	_check(WeaponModifiers.problem(legacy).is_empty() and is_equal_approx(
		float(WeaponModifiers.effective(legacy).damage) / WeaponInventory.definition(legacy.weapon_id).damage, 1.10),
		"historical attribute schema keeps its level2 maximum and one ten-percent factor")
	var legacy_json: Dictionary = JSON.parse_string(JSON.stringify(legacy, "", true, true))
	_check(WeaponModifiers.problem(legacy_json).is_empty(), "old level2.0 remains valid after JSON readback")
	for invalid_level: Variant in [0, 3, 5, 2.5]:
		var invalid: Dictionary = legacy.duplicate(true)
		invalid.weapon_level = invalid_level
		_check(not WeaponModifiers.problem(invalid).is_empty(), "old schema does not acquire new levels: " + str(invalid_level))


func _hammer_identity_case() -> void:
	var modern_action: Dictionary = _source("m48-hammer-fixed".md5_text(), ACTION_ID, 14, "medium", CombatEquipment.HAMMER_ID)
	var modern: Dictionary = _reward(modern_action)
	_check(modern.get("weapon_id") == CombatEquipment.HAMMER_ID and modern.get("weapon_level") == 5,
		"M48 applies literal level5 growth while preserving the hammer's fixed source identity")
	var historical_action: Dictionary = EconomyActions.origin(modern_action).duplicate(true)
	historical_action.powers.version = SpecialPowers.WAVE_VERSION
	var legacy: Dictionary = WeaponInventory.site_reward(PROFILE + ":13", historical_action, historical_action.sites[0], true)
	_check(legacy.get("weapon_id") == CombatEquipment.HAMMER_ID and legacy.get("weapon_level") == 1
		and legacy.get("quality") == "common" and legacy.get("affixes") == [],
		"original M38 hammer source retains its fixed level1 common result")
	_check(WeaponModifiers.problem(legacy).is_empty(), "historical hammer still passes its own original attribute contract")


func _write_report(report: Dictionary) -> void:
	var text: String = JSON.stringify(report, "\t", true, true) + "\n"
	_check(text.to_utf8_buffer().size() <= REPORT_LIMIT, "parameter report stays within the one-MiB evidence budget")
	if text.to_utf8_buffer().size() > REPORT_LIMIT: return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_check(false, "parameter report directory is writable")
		return
	var file: FileAccess = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	_check(file != null, "parameter report is writable")
	if file == null: return
	report.checks = rows.size()
	report.failures = failures
	text = JSON.stringify(report, "\t", true, true) + "\n"
	if text.to_utf8_buffer().size() > REPORT_LIMIT:
		file.close()
		_check(false, "complete report including its write checks stays within budget")
		return
	file.store_string(text)
	file.close()
