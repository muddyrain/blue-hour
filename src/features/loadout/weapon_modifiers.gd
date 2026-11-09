class_name WeaponModifiers
extends RefCounted
## PROJECT_TEMP instance policy. No random global state, ownership or persistence.

const KEYS: Array[String] = ["weapon_level","quality","affixes"]
const RULESET: String = "BH_WEAPON_MODIFIERS_V1"
const PIERCE: String = "pierce_v1"
const REFUND: String = "defeat_refund_v1"
const SITE_RARE_AFFIXES: Array[String] = [PIERCE, REFUND, "reach_v1", "quick_v1"]


static func baseline(item: Dictionary) -> Dictionary:
	var value: Dictionary = item.duplicate(true)
	value.merge({"weapon_level":1,"quality":"common","affixes":[]})
	return value


static func reward(item: Dictionary) -> Dictionary:
	var value: Dictionary = baseline(item)
	var entropy: String = (RULESET+":"+String(item.instance_id)).sha256_text()
	value.weapon_level = 1+entropy.substr(0,2).hex_to_int()%2
	value.quality = "common" if entropy.substr(2,2).hex_to_int()%2==0 else "rare"
	value.affixes = [] if value.quality=="common" else ["reach_v1" if entropy.substr(4,2).hex_to_int()%2==0 else "quick_v1"]
	return value


static func site_affix_reward(item: Dictionary, seed: String, action: String, site: String) -> Dictionary:
	var value: Dictionary = reward(item)
	var entropy: String = ("BH_SITE_WEAPON_AFFIX_V1:%s:%s:%s" % [seed, action, site]).sha256_text()
	value.quality = "common" if entropy.substr(0, 2).hex_to_int() % 2 == 0 else "rare"
	value.affixes = [] if value.quality == "common" else [SITE_RARE_AFFIXES[entropy.substr(2, 2).hex_to_int() % SITE_RARE_AFFIXES.size()]]
	return value


static func problem(item: Dictionary) -> String:
	if item.size()!=(9 if item.has("drop") else 8) or not item.has_all(KEYS) or not SurvivalContracts.integer(item.weapon_level,1,2) or not item.quality is String or item.quality not in ["common","rare"] or not item.affixes is Array:
		return "WEAPON_MODIFIER_FIELDS"
	for key: String in ["instance_id","weapon_id","condition","origin","acquired_sortie"]:
		if not item.get(key) is String:
			return "WEAPON_INSTANCE_STRINGS"
	if item.affixes.size()!=(0 if item.quality=="common" else 1):
		return "WEAPON_MODIFIER_COUNT"
	if item.weapon_id == CombatEquipment.HAMMER_ID:
		var drop: Variant = item.get("drop")
		if not drop is Dictionary or drop.get("version") != WeaponInventory.HAMMER_DROP_VERSION \
				or item.weapon_level != 1 or item.quality != "common":
			return "WEAPON_HAMMER_SOURCE"
	var affix_drop: bool = _site_affix_drop(item)
	if affix_drop and item.weapon_id != "long_rifle":
		return "WEAPON_AFFIX_SOURCE"
	for id: Variant in item.affixes:
		if not id is String or id not in (SITE_RARE_AFFIXES if affix_drop else ["reach_v1", "quick_v1"]):
			return "WEAPON_MODIFIER_ID"
	return ""


static func effective(item: Dictionary, personal_factor: float = 1.0) -> Dictionary:
	var base: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	var level_factor: float = 1.10 if item.get("weapon_level",1)==2 else 1.0
	var affixes: Array = item.get("affixes",[])
	return {"damage":base.damage*level_factor,"interval":base.interval*(0.90 if "quick_v1" in affixes else 1.0)*(1.0 if CombatEquipment.melee(item.weapon_id) else personal_factor),"range":base.shot_range*(1.15 if "reach_v1" in affixes else 1.0)}


static func combat_definition(item: Dictionary) -> WeaponDefinition:
	var value: WeaponDefinition = WeaponInventory.definition(item.weapon_id).duplicate() as WeaponDefinition
	var stats: Dictionary = effective(item)
	value.damage = stats.damage
	value.interval = stats.interval
	value.shot_range = stats.range
	value.combat_affix = combat_affix(item)
	return value


static func combat_affix(item: Dictionary) -> String:
	var affixes: Variant = item.get("affixes")
	if _site_affix_drop(item) and item.get("weapon_id") == "long_rifle" and item.get("quality") == "rare" \
			and affixes is Array and affixes.size() == 1 and affixes[0] in [PIERCE, REFUND]:
		return affixes[0]
	return ""


static func _site_affix_drop(item: Dictionary) -> bool:
	var drop: Variant = item.get("drop")
	return drop is Dictionary and SurvivalContracts.integer(drop.get("version"),
		WeaponInventory.AFFIX_DROP_VERSION, WeaponInventory.AFFIX_DROP_VERSION)


static func description(item: Dictionary) -> String:
	var names: PackedStringArray = []
	for id: String in item.get("affixes",[]):
		match id:
			"reach_v1": names.append("延长握柄：距离×1.15" if CombatEquipment.melee(item.weapon_id) else "延伸瞄具：射程×1.15")
			"quick_v1": names.append("轻快机件：间隔×0.90")
			PIERCE: names.append("穿透弹")
			REFUND: names.append("击倒补弹")
	return "武器Lv%d · %s · %s" % [int(item.get("weapon_level",1)),"稀有" if item.get("quality","")=="rare" else "普通","无词条" if names.is_empty() else " / ".join(names)]


static func effect_description(item: Dictionary) -> String:
	match combat_affix(item):
		PIERCE: return "穿透弹 · 首次命中后，同一发可再命中射线上的一个敌人，伤害为首击的 50%。墙体仍会挡弹。"
		REFUND: return "击倒补弹 · 这把枪实际击倒敌人时，自身弹匣补 1 发。每发最多一次，受弹匣容量限制。"
	return ""
