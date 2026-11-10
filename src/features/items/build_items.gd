class_name BuildItems
extends RefCounted
## PROJECT_TEMP V1. Pure journey inventory and frozen-slot derivation; no reward writer.

const VERSION: int = 1
const CATALOG_POOL: int = 2
const WAVE_POOL: int = 3
const WAVE_CATALOG_POOL: int = 4
const SPECIALTY_POOL: int = 5
const SPECIALTY_CATALOG_POOL: int = 6
const FILTER: String = "filter_mask_v1"
const FILTER_DEFINITION: Dictionary = {"name":"滤毒面罩", "effect":"毒区周期伤害 ×0.50", "key":"poison", "factor":0.50, "source":"PROJECT_TEMP"}
const LINER: String = "impact_liner_v1"
const LINER_DEFINITION: Dictionary = {"name":"缓冲内衬", "effect":"小队所受爆囊脉冲伤害 ×0.65", "key":"burst", "factor":0.65, "source":"PROJECT_TEMP"}
const AID_KIT: String = "aid_kit_v1"
const STRIDE_HARNESS: String = "stride_harness_v1"
const GUIDED_MAG: String = "guided_mag_v1"
const SPECIALTY_REWARDS: Dictionary = {
	"scavenge": STRIDE_HARNESS, "firepower": GUIDED_MAG, "support": "aid_broadcast_v1",
}
const SPECIALTY_DEFINITIONS: Dictionary = {
	AID_KIT: {"name":"急救绑包", "effect":"基础治疗 Q 恢复上限 ×1.20", "key":"heal", "factor":1.20, "source":"PROJECT_TEMP"},
	STRIDE_HARNESS: {"name":"轻行束带", "effect":"队员步行速度 ×1.10", "key":"move", "factor":1.10, "source":"PROJECT_TEMP"},
	GUIDED_MAG: {"name":"导向弹匣套", "effect":"枪械最终换弹时长 ×0.90", "key":"reload", "factor":0.90, "source":"PROJECT_TEMP"},
}
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


static func definitions(pool: int = VERSION) -> Dictionary:
	var result: Dictionary = DEFINITIONS.duplicate(true)
	if has_catalog(pool):
		result[FILTER] = FILTER_DEFINITION.duplicate(true)
	if wave_pool(pool):
		result[LINER] = LINER_DEFINITION.duplicate(true)
	if specialty_pool(pool):
		result.merge(SPECIALTY_DEFINITIONS.duplicate(true))
	return result


static func ids(pool: int = VERSION) -> Array[String]:
	var result: Array[String] = IDS.duplicate()
	if has_catalog(pool):
		result.append(FILTER)
	if wave_pool(pool):
		result.append(LINER)
	if specialty_pool(pool):
		result.append_array([AID_KIT, STRIDE_HARNESS, GUIDED_MAG])
	return result


static func valid_pool(value: Variant) -> bool:
	return SurvivalContracts.integer(value, VERSION, SPECIALTY_CATALOG_POOL)


static func has_catalog(pool: int) -> bool:
	return pool in [CATALOG_POOL, WAVE_CATALOG_POOL, SPECIALTY_CATALOG_POOL]


static func wave_pool(pool: int) -> bool:
	return pool in [WAVE_POOL, WAVE_CATALOG_POOL] or specialty_pool(pool)


static func specialty_pool(pool: int) -> bool:
	return pool in [SPECIALTY_POOL, SPECIALTY_CATALOG_POOL]


static func _ordinary_pool(pool: int) -> int:
	if not specialty_pool(pool):
		return pool
	return WAVE_CATALOG_POOL if has_catalog(pool) else WAVE_POOL


static func drop(context: Dictionary, owned: Array, pool: int = VERSION) -> Array[String]:
	var result: Array[String] = []
	if not _context_problem(context, pool).is_empty() or not problem(owned, ["", ""], pool).is_empty():
		return result
	# Inventory order, slot edits and other random consumers cannot reroll a candidate.
	var canonical_owned: Array[String] = []
	for id: String in owned:
		if not SPECIALTY_DEFINITIONS.has(id):
			canonical_owned.append(id)
	canonical_owned.sort()
	var ordinary_pool: int = _ordinary_pool(int(context.version))
	var canonical_context: Dictionary = {
		"run_id":context.run_id, "seed":context.seed, "day":int(context.day),
		"action_id":context.action_id, "site_id":context.site_id, "version":ordinary_pool,
	}
	if context.has("liner"):
		canonical_context.liner = true
		if LINER not in owned:
			result.append(LINER)
	var binding: String = JSON.stringify({"context":canonical_context, "owned":canonical_owned}, "", true, true)
	var candidates: Array[String] = []
	for id: String in ids(ordinary_pool):
		if id != LINER and id not in owned:
			candidates.append(id)
	# Hash ranking has no shared RNG state and has an explicit tie-break across processes.
	candidates.sort_custom(func(left: String, right: String) -> bool:
		var left_rank: String = (binding + ":" + left).sha256_text()
		var right_rank: String = (binding + ":" + right).sha256_text()
		return left < right if left_rank == right_rank else left_rank < right_rank
	)
	for index: int in range(mini(SLOT_COUNT - result.size(), candidates.size())):
		result.append(candidates[index])
	var position: int = replaceable_slot(result) if context.has("specialty") else -1
	if position >= 0:
		var candidate: String = specialty_candidate(context.specialty, owned)
		if candidate == SPECIALTY_REWARDS.support:
			result.remove_at(position)
		elif not candidate.is_empty():
			result[position] = candidate
	return result


static func replaceable_slot(drops: Array) -> int:
	# Milestone and dedicated rewards retain their original positions.
	for index: int in range(drops.size() - 1, -1, -1):
		if drops[index] in IDS:
			return index
	return -1


static func specialty_candidate(policy: Dictionary, owned: Array) -> String:
	if not _specialty_policy_valid(policy):
		return ""
	var preferred: String = SPECIALTY_REWARDS[policy.plan]
	var available: Array[String] = []
	for id: String in policy.eligible:
		if id not in owned and (id != SPECIALTY_REWARDS.support or not policy.radio_owned):
			available.append(id)
	if preferred in available:
		return preferred
	return available[0] if not available.is_empty() else ""


static func problem(owned: Variant, slots: Variant, pool: int = VERSION) -> String:
	if not valid_pool(pool):
		return "BUILD_ITEMS_POOL"
	var allowed: Array[String] = ids(pool)
	if not owned is Array or owned.size() > allowed.size():
		return "BUILD_ITEMS_OWNED_FIELDS"
	var seen: Array[String] = []
	for id: Variant in owned:
		if not id is String or id not in allowed or id in seen:
			return "BUILD_ITEMS_OWNED_ID"
		seen.append(id)
	var issue: String = _slots_problem(slots, pool)
	if not issue.is_empty():
		return issue
	for id: String in slots:
		if not id.is_empty() and id not in owned:
			return "BUILD_ITEMS_SLOT_NOT_OWNED"
	return ""


static func factors(slots: Array, pool: int = VERSION) -> Dictionary:
	if not _slots_problem(slots, pool).is_empty():
		return {}
	# Start from immutable original factors on every query; never compound a prior view.
	var result: Dictionary = BASE_FACTORS.duplicate(true)
	for id: String in slots:
		if not id.is_empty() and not SPECIALTY_DEFINITIONS.has(id):
			var definition: Dictionary = FILTER_DEFINITION if id == FILTER else LINER_DEFINITION if id == LINER else DEFINITIONS[id]
			result[definition.key] = definition.factor
	if not specialty_pool(pool):
		return result
	for id: String in slots:
		if SPECIALTY_DEFINITIONS.has(id):
			var definition: Dictionary = SPECIALTY_DEFINITIONS[id]
			result[definition.key] *= definition.factor
	return result


static func frozen_factors(build: Dictionary) -> Dictionary:
	return factors(build.slots, int(build.get("version", VERSION)))


static func _slots_problem(slots: Variant, pool: int) -> String:
	if not slots is Array or slots.size() != SLOT_COUNT:
		return "BUILD_ITEMS_SLOT_FIELDS"
	var equipped: Array[String] = []
	for id: Variant in slots:
		if not id is String or (not id.is_empty() and (id not in ids(pool) or id in equipped)):
			return "BUILD_ITEMS_SLOT_ID"
		if not id.is_empty():
			equipped.append(id)
	return ""


static func _context_problem(context: Dictionary, pool: int = VERSION) -> String:
	var liner: bool = context.has("liner")
	var specialty: bool = context.has("specialty")
	if context.size() != CONTEXT_KEYS.size() + int(liner) + int(specialty) or not context.has_all(CONTEXT_KEYS):
		return "BUILD_ITEMS_DROP_FIELDS"
	if not valid_pool(context.version):
		return "BUILD_ITEMS_DROP_VERSION"
	var version: int = int(context.version)
	if (version != VERSION and version != pool) or (liner and (not wave_pool(version) or context.liner != true)):
		return "BUILD_ITEMS_DROP_VERSION"
	for key: String in ["run_id", "seed"]:
		if not context[key] is String or context[key].length() != 32 or not context[key].is_valid_hex_number(false):
			return "BUILD_ITEMS_DROP_IDENTITY"
	if not SurvivalContracts.integer(context.day, 2, RunSave.MAX_COUNTER):
		return "BUILD_ITEMS_DROP_DAY"
	if liner and (int(context.day) < 3 or context.site_id != "cash"):
		return "BUILD_ITEMS_LINER_SITE"
	if specialty and (liner or not specialty_pool(version) or context.site_id != "cash" \
			or not _specialty_policy_valid(context.specialty)):
		return "BUILD_ITEMS_SPECIALTY_POLICY"
	for key: String in ["action_id", "site_id"]:
		if not context[key] is String or context[key].is_empty() or context[key].length() > 256:
			return "BUILD_ITEMS_DROP_SITE"
	return ""


static func _specialty_policy_valid(policy: Variant) -> bool:
	if not policy is Dictionary or policy.size() != 3 or not policy.has_all(["plan", "eligible", "radio_owned"]) \
			or not policy.plan is String or not SPECIALTY_REWARDS.has(policy.plan) \
			or not policy.radio_owned is bool or not policy.eligible is Array or policy.eligible.size() > SPECIALTY_REWARDS.size():
		return false
	var prior: String = ""
	for id: Variant in policy.eligible:
		if not id is String or not SPECIALTY_REWARDS.values().has(id) or id <= prior:
			return false
		prior = id
	return true
