class_name SurvivorPersona
extends RefCounted
## PROJECT_TEMP V1. Seeded identity facts only; no roster, actor, RNG or persistence owner.

const CATALOG_ID: String = "BH_SURVIVOR_PERSONA_V1"
const VERSION: int = 1
const FACT_KEYS: Array[String] = ["catalog_id", "version", "seed", "members"]
const RECIPE_KEYS: Array[String] = ["member_id", "definition_id", "positive_id", "negative_id"]
const POSITIVE: Dictionary = {
	"ranged_focus_v1":{"name":"枪械专长", "stat":"ranged_direct_damage", "factor":1.15, "description":"本人的枪械直接伤害提高15%；霰弹每颗弹丸乘一次，不作用于支援。"},
	"melee_practice_v1":{"name":"近战好手", "stat":"melee_direct_damage", "factor":1.20, "description":"本人的近战直接伤害提高20%；不改变起手、弧度、目标上限或射程。"},
	"light_step_v1":{"name":"轻盈步伐", "stat":"move_speed", "factor":1.10, "description":"本人有效移动速度提高10%。"},
	"quick_hands_v1":{"name":"装填熟手", "stat":"reload_duration", "factor":0.85, "description":"本人枪械换弹耗时减少15%；不增加弹匣容量或射速。"},
	"keen_search_v1":{"name":"搜寻敏锐", "stat":"work_duration", "factor":0.85, "description":"本人搜刮/户外回收耗时减少15%；奖励不变，不作用于救援接纳等待。"},
}
const NEGATIVE: Dictionary = {
	"heavy_step_v1":{"name":"步伐沉重", "stat":"move_speed", "factor":0.90, "description":"本人有效移动速度降低10%。"},
	"clumsy_reload_v1":{"name":"装填生疏", "stat":"reload_duration", "factor":1.15, "description":"本人枪械换弹耗时增加15%；近战武器无换弹，不触发。"},
	"distracted_search_v1":{"name":"搜寻分心", "stat":"work_duration", "factor":1.15, "description":"本人搜刮/户外回收耗时增加15%；奖励不变。"},
}
const INCOMPATIBLE_PAIRS: Array = [
	["light_step_v1", "heavy_step_v1"],
	["quick_hands_v1", "clumsy_reload_v1"],
	["keen_search_v1", "distracted_search_v1"],
]
const METRICS: Dictionary = {
	"ranged_direct_damage":"ranged", "melee_direct_damage":"melee", "move_speed":"move",
	"reload_duration":"reload", "work_duration":"work",
}


static func policy() -> Dictionary:
	return {"catalog_id":CATALOG_ID, "version":VERSION, "status":"PROJECT_TEMP",
		"positive":POSITIVE.duplicate(true), "negative":NEGATIVE.duplicate(true),
		"incompatible_pairs":INCOMPATIBLE_PAIRS.duplicate(true),
		"generation":{"domain":CATALOG_ID, "encoding":"UTF-8; no newline", "identity_order":[1, 2, 3, 4, 5],
			"rank_input":"BH_SURVIVOR_PERSONA_V1|{seed}|{member_id}|{definition_id}|{positive_id}|{negative_id}",
			"rank":"SHA-256 lowercase ascending, then positive_id, then negative_id", "choice":"first unused compatible pair"}}


static func generate(seed: String) -> Dictionary:
	if not _seed_valid(seed):
		return {}
	var members: Array[Dictionary] = []
	var used: Dictionary = {}
	for id: int in range(1, 6):
		var ranked: Array[Dictionary] = []
		for positive: String in POSITIVE:
			for negative: String in NEGATIVE:
				if not _compatible(positive, negative):
					continue
				var key: String = positive + "|" + negative
				if used.has(key):
					continue
				var input: String = "%s|%s|%d|crew_%d|%s|%s" % [CATALOG_ID, seed, id, id, positive, negative]
				ranked.append({"positive_id":positive, "negative_id":negative, "rank":input.sha256_text()})
		ranked.sort_custom(_rank_before)
		var choice: Dictionary = ranked[0]
		used[choice.positive_id + "|" + choice.negative_id] = true
		members.append({"member_id":id, "definition_id":"crew_%d" % id,
			"positive_id":choice.positive_id, "negative_id":choice.negative_id})
	return {"catalog_id":CATALOG_ID, "version":VERSION, "seed":seed, "members":members}


static func problem(value: Variant, seed: String) -> String:
	if not _seed_valid(seed):
		return "PERSONA_SEED"
	var issue: String = _shape_problem(value)
	if not issue.is_empty():
		return issue
	if value.seed != seed:
		return "PERSONA_SEED_BINDING"
	var expected: Dictionary = generate(seed)
	for index: int in range(5):
		var row: Dictionary = value.members[index]
		var original: Dictionary = expected.members[index]
		if row.positive_id != original.positive_id or row.negative_id != original.negative_id:
			return "PERSONA_SOURCE"
	return ""


static func member(bundle: Dictionary, id: int, definition_id: String = "") -> Dictionary:
	# Callers authenticate the seed once at their boundary; identity reads never regenerate it.
	if id < 1 or id > 5 or (not definition_id.is_empty() and definition_id != "crew_%d" % id) or not _shape_problem(bundle).is_empty():
		return {}
	return bundle.members[id - 1].duplicate(true)


static func recipe_problem(value: Variant) -> String:
	if not _keys(value, RECIPE_KEYS):
		return "PERSONA_RECIPE_FIELDS"
	if not _integer(value.member_id, 1, 5) or not value.definition_id is String or value.definition_id != "crew_%d" % int(value.member_id):
		return "PERSONA_RECIPE_IDENTITY"
	if not value.positive_id is String or not POSITIVE.has(value.positive_id) or not value.negative_id is String or not NEGATIVE.has(value.negative_id):
		return "PERSONA_RECIPE_TRAIT"
	return "" if _compatible(value.positive_id, value.negative_id) else "PERSONA_RECIPE_INCOMPATIBLE"


static func factors(recipe: Variant) -> Dictionary:
	if not recipe_problem(recipe).is_empty():
		return {}
	var result: Dictionary = {"ranged":1.0, "melee":1.0, "move":1.0, "reload":1.0, "work":1.0}
	for definition: Dictionary in [POSITIVE[recipe.positive_id], NEGATIVE[recipe.negative_id]]:
		result[METRICS[definition.stat]] *= float(definition.factor)
	return result


static func _shape_problem(value: Variant) -> String:
	if not _keys(value, FACT_KEYS) or not value.catalog_id is String or value.catalog_id != CATALOG_ID or not _integer(value.version, VERSION, VERSION):
		return "PERSONA_FIELDS_OR_VERSION"
	if not value.seed is String or not _seed_valid(value.seed) or not value.members is Array or value.members.size() != 5:
		return "PERSONA_MEMBERS_OR_SEED"
	var used: Dictionary = {}
	for index: int in range(5):
		var row: Variant = value.members[index]
		var issue: String = recipe_problem(row)
		if not issue.is_empty():
			return issue
		if int(row.member_id) != index + 1:
			return "PERSONA_IDENTITY_ORDER"
		var key: String = row.positive_id + "|" + row.negative_id
		if used.has(key):
			return "PERSONA_PAIR_DUPLICATE"
		used[key] = true
	return ""


static func _compatible(positive: String, negative: String) -> bool:
	for pair: Array in INCOMPATIBLE_PAIRS:
		if pair[0] == positive and pair[1] == negative:
			return false
	return true


static func _rank_before(left: Dictionary, right: Dictionary) -> bool:
	return left.rank < right.rank if left.rank != right.rank else left.positive_id < right.positive_id if left.positive_id != right.positive_id else left.negative_id < right.negative_id


static func _seed_valid(seed: String) -> bool:
	if seed.length() != 32:
		return false
	for index: int in range(seed.length()):
		if seed.substr(index, 1) not in "0123456789abcdef":
			return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and value.has_all(keys)
