class_name BuildItems
extends RefCounted
## PROJECT_TEMP V1. Pure journey inventory and frozen-slot derivation; no reward writer.

const VERSION: int = 1
const SLOT_COUNT: int = 2
const IDS: Array[String] = [
	"pressure_rounds_v1", "quick_loader_v1", "light_boots_v1",
	"field_tools_v1", "wide_blast_v1", "medical_pack_v1",
]
const DEFINITIONS: Dictionary = {
	"pressure_rounds_v1": {"name":"高压弹头", "effect":"枪械直伤 ×1.20", "key":"damage", "factor":1.20, "source":"PROJECT_TEMP"},
	"quick_loader_v1": {"name":"快装组件", "effect":"换弹时长 ×0.75", "key":"reload", "factor":0.75, "source":"PROJECT_TEMP"},
	"light_boots_v1": {"name":"轻便行装", "effect":"移动速度 ×1.15", "key":"move", "factor":1.15, "source":"PROJECT_TEMP"},
	"field_tools_v1": {"name":"野外工具", "effect":"搜刮 / 户外回收耗时 ×0.75", "key":"work", "factor":0.75, "source":"PROJECT_TEMP"},
	"wide_blast_v1": {"name":"扩散装药", "effect":"基础空袭半径 ×1.30", "key":"blast", "factor":1.30, "source":"PROJECT_TEMP"},
	"medical_pack_v1": {"name":"医疗补包", "effect":"基础治疗恢复上限 ×1.50", "key":"heal", "factor":1.50, "source":"PROJECT_TEMP"},
}
const BASE_FACTORS: Dictionary = {
	"damage":1.0, "reload":1.0, "move":1.0, "work":1.0, "blast":1.0, "heal":1.0,
}
const CONTEXT_KEYS: Array[String] = ["run_id", "seed", "day", "action_id", "site_id", "version"]


static func definitions() -> Dictionary:
	return DEFINITIONS.duplicate(true)


static func ids() -> Array[String]:
	return IDS.duplicate()


static func drop(context: Dictionary, owned: Array) -> Array[String]:
	var result: Array[String] = []
	if not _context_problem(context).is_empty() or not problem(owned, ["", ""]).is_empty():
		return result
	# Inventory order, slot edits and other random consumers cannot reroll a candidate.
	var canonical_owned: Array[String] = []
	canonical_owned.assign(owned)
	canonical_owned.sort()
	var canonical_context: Dictionary = {
		"run_id":context.run_id, "seed":context.seed, "day":int(context.day),
		"action_id":context.action_id, "site_id":context.site_id, "version":int(context.version),
	}
	var binding: String = JSON.stringify({"context":canonical_context, "owned":canonical_owned}, "", true, true)
	var candidates: Array[String] = []
	for id: String in IDS:
		if id not in owned:
			candidates.append(id)
	# Hash ranking has no shared RNG state and has an explicit tie-break across processes.
	candidates.sort_custom(func(left: String, right: String) -> bool:
		var left_rank: String = (binding + ":" + left).sha256_text()
		var right_rank: String = (binding + ":" + right).sha256_text()
		return left < right if left_rank == right_rank else left_rank < right_rank
	)
	for index: int in range(mini(SLOT_COUNT, candidates.size())):
		result.append(candidates[index])
	return result


static func problem(owned: Variant, slots: Variant) -> String:
	if not owned is Array or owned.size() > IDS.size():
		return "BUILD_ITEMS_OWNED_FIELDS"
	var seen: Array[String] = []
	for id: Variant in owned:
		if not id is String or not DEFINITIONS.has(id) or id in seen:
			return "BUILD_ITEMS_OWNED_ID"
		seen.append(id)
	var issue: String = _slots_problem(slots)
	if not issue.is_empty():
		return issue
	for id: String in slots:
		if not id.is_empty() and id not in owned:
			return "BUILD_ITEMS_SLOT_NOT_OWNED"
	return ""


static func factors(slots: Array) -> Dictionary:
	if not _slots_problem(slots).is_empty():
		return {}
	# Start from immutable original factors on every query; never compound a prior view.
	var result: Dictionary = BASE_FACTORS.duplicate(true)
	for id: String in slots:
		if not id.is_empty():
			var definition: Dictionary = DEFINITIONS[id]
			result[definition.key] = definition.factor
	return result


static func _slots_problem(slots: Variant) -> String:
	if not slots is Array or slots.size() != SLOT_COUNT:
		return "BUILD_ITEMS_SLOT_FIELDS"
	var equipped: Array[String] = []
	for id: Variant in slots:
		if not id is String or (not id.is_empty() and (not DEFINITIONS.has(id) or id in equipped)):
			return "BUILD_ITEMS_SLOT_ID"
		if not id.is_empty():
			equipped.append(id)
	return ""


static func _context_problem(context: Dictionary) -> String:
	if context.size() != CONTEXT_KEYS.size() or not context.has_all(CONTEXT_KEYS):
		return "BUILD_ITEMS_DROP_FIELDS"
	if not SurvivalContracts.integer(context.version, VERSION, VERSION):
		return "BUILD_ITEMS_DROP_VERSION"
	for key: String in ["run_id", "seed"]:
		if not context[key] is String or context[key].length() != 32 or not context[key].is_valid_hex_number(false):
			return "BUILD_ITEMS_DROP_IDENTITY"
	if not SurvivalContracts.integer(context.day, 2, RunSave.MAX_COUNTER):
		return "BUILD_ITEMS_DROP_DAY"
	for key: String in ["action_id", "site_id"]:
		if not context[key] is String or context[key].is_empty() or context[key].length() > 256:
			return "BUILD_ITEMS_DROP_SITE"
	return ""
