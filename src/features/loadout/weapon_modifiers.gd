class_name WeaponModifiers
extends RefCounted
## PROJECT_TEMP instance policy. No random global state, ownership or persistence.

const KEYS: Array[String] = ["weapon_level","quality","affixes"]
const RULESET: String = "BH_WEAPON_MODIFIERS_V1"


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


static func problem(item: Dictionary) -> String:
	if item.size()!=8 or not item.has_all(KEYS) or not SurvivalContracts.integer(item.weapon_level,1,2) or not item.quality is String or item.quality not in ["common","rare"] or not item.affixes is Array:
		return "WEAPON_MODIFIER_FIELDS"
	for key: String in ["instance_id","weapon_id","condition","origin","acquired_sortie"]:
		if not item.get(key) is String:
			return "WEAPON_INSTANCE_STRINGS"
	if item.affixes.size()!=(0 if item.quality=="common" else 1):
		return "WEAPON_MODIFIER_COUNT"
	for id: Variant in item.affixes:
		if not id is String or id not in ["reach_v1","quick_v1"]:
			return "WEAPON_MODIFIER_ID"
	return ""


static func effective(item: Dictionary, personal_factor: float = 1.0) -> Dictionary:
	var base: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	var level_factor: float = 1.10 if item.get("weapon_level",1)==2 else 1.0
	var affixes: Array = item.get("affixes",[])
	return {"damage":base.damage*level_factor,"interval":base.interval*(0.90 if "quick_v1" in affixes else 1.0)*personal_factor,"range":base.shot_range*(1.15 if "reach_v1" in affixes else 1.0)}


static func combat_definition(item: Dictionary) -> WeaponDefinition:
	var value: WeaponDefinition = WeaponInventory.definition(item.weapon_id).duplicate() as WeaponDefinition
	var stats: Dictionary = effective(item)
	value.damage = stats.damage
	value.interval = stats.interval
	value.shot_range = stats.range
	return value


static func description(item: Dictionary) -> String:
	var names: PackedStringArray = []
	for id: String in item.get("affixes",[]):
		names.append("延伸瞄具：射程×1.15" if id=="reach_v1" else "轻快机件：间隔×0.90")
	return "武器Lv%d · %s · %s" % [int(item.get("weapon_level",1)),"稀有" if item.get("quality","")=="rare" else "普通","无词条" if names.is_empty() else " / ".join(names)]
