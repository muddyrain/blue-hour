class_name WorldSites
extends RefCounted
## Bounded authoritative budgets. No per-building copy of the task reward.
const WORK_SECONDS: float = 30.0

static func definitions(layout: Dictionary, cash: int, food: int, weapons: int) -> Array:
	var result: Array = []
	var used: Array[String] = []
	for kind: String in ["cash","food"]:
		var budget: int = cash if kind=="cash" else food
		var count: int = mini(budget, 2 if food>=2 and kind=="cash" else 4 if kind=="cash" else 3)
		for index: int in range(count):
			var building: Dictionary = {}
			var preferred: Array = ["warehouse","garage","row_house","small_apartment"] if kind=="cash" else ["supermarket","convenience_store","eatery","detached_home"]
			for type: String in preferred:
				for entity: Dictionary in layout.entities:
					if entity.archetype==type and entity.id not in used: building=entity; break
				if not building.is_empty(): break
			used.append(building.id)
			result.append({"id":kind if index==0 else kind+"_%d"%(index+1),"building":building.id,"kind":kind,"amount":budget/count+int(index<budget%count),"weapon":kind=="cash" and index==0 and weapons==1,"seconds":WORK_SECONDS})
	return result

static func facts(world: Expedition) -> Dictionary:
	var result: Dictionary = {}
	for site: Expedition.SearchSite in world.sites:
		result[String(site.id)]={"searched":site.searched,"progress":site.progress}
	return result

static func problem(defs: Array, facts: Variant) -> String:
	if not facts is Dictionary or facts.size()!=defs.size(): return "SITE_FIELDS"
	for def: Dictionary in defs:
		if not facts.has(def.id): return "SITE_ID"
		var state: Variant = facts[def.id]
		if not state is Dictionary or state.size()!=2 or not state.get("searched") is bool or not SurvivalContracts.number(state.get("progress")) or state.progress<0 or state.progress>31 or state.searched!=(state.progress>=def.seconds): return "SITE_PROGRESS"
	return ""

static func carry(defs: Array, facts: Dictionary, transaction: String, quality: bool) -> Dictionary:
	var result: Dictionary = {"loot":0,"food":0,"weapons":[]}
	for def: Dictionary in defs:
		if facts[def.id].searched:
			result["loot" if def.kind=="cash" else "food"]+=int(def.amount)
			if def.weapon: result.weapons.append(WeaponInventory.reward(transaction,quality))
	return result

static func completed(defs: Array, facts: Dictionary, kind: String = "") -> int:
	var count: int = 0
	for def: Dictionary in defs:
		if facts[def.id].searched and (kind.is_empty() or def.kind==kind): count+=1
	return count
