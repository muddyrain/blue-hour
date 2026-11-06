class_name WorldSites
extends RefCounted
## Bounded authoritative budgets. No per-building copy of the task reward.
const WORK_SECONDS: float = 30.0

static func definitions(layout: Dictionary, cash: int, food: int, weapons: int) -> Array:
	if layout.get("version")==3: return _neighborhood_definitions(layout,cash,food,weapons)
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

static func problem(defs: Array, facts: Variant, exploration: bool = false) -> String:
	if not facts is Dictionary or facts.size()!=defs.size(): return "SITE_FIELDS"
	for def: Dictionary in defs:
		if not facts.has(def.id): return "SITE_ID"
		var state: Variant = facts[def.id]
		if not state is Dictionary or state.size()!=2 or not state.get("searched") is bool or not SurvivalContracts.number(state.get("progress")) or state.progress<0 or state.progress>(float(def.seconds) if exploration else 31.0) or state.searched!=(state.progress>=def.seconds): return "SITE_PROGRESS"
	return ""

static func carry(defs: Array, facts: Dictionary, transaction: String, quality: bool, generated: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"loot":0,"food":0,"weapons":[]}
	for def: Dictionary in defs:
		if facts[def.id].searched:
			result["loot" if def.kind=="cash" else "food"]+=int(def.amount)
			if def.weapon: result.weapons.append(WeaponInventory.site_reward(transaction,generated,def,quality))
	return result

static func completed(defs: Array, facts: Dictionary, kind: String = "") -> int:
	var count: int = 0
	for def: Dictionary in defs:
		if facts[def.id].searched and (kind.is_empty() or def.kind==kind): count+=1
	return count

static func _neighborhood_definitions(layout: Dictionary, cash: int, food: int, weapons: int) -> Array:
	var rank: int = NeighborhoodLayout.SIZES.find(layout["size"])
	var defs: Array = []
	var used: Array[String] = []
	var start: Vector2 = WorldLayout.point(layout.bus.door)
	for kind: String in ["cash","food"]:
		var budget: int = cash if kind=="cash" else food
		var count: int = mini(budget, (3+rank if food==0 else rank+1) if kind=="cash" else (2 if rank==0 else 3))
		var candidates: Array = layout.entities.filter(func(e: Dictionary) -> bool: return e.id not in used)
		var preferred: Array = ["warehouse","garage","small_apartment","row_house"] if kind=="cash" else ["supermarket","convenience_store","eatery","detached_home"]
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			var ad: float = start.distance_to(WorldLayout.point(a.door))
			var bd: float = start.distance_to(WorldLayout.point(b.door))
			return ad+(0 if a.archetype in preferred else 400)<bd+(0 if b.archetype in preferred else 400))
		for i: int in range(count):
			# Main sources stay near; remaining sources span the block rather than rewarding decorative outskirts.
			var index: int = 0 if i==0 else candidates.size()-1 if i==1 else candidates.size()/2
			var entity: Dictionary = candidates.pop_at(index)
			used.append(entity.id)
			defs.append({"id":kind if i==0 else kind+"_%d"%(i+1),"building":entity.id,"kind":kind,"amount":budget/count+int(i<budget%count),"weapon":kind=="cash" and i==0 and weapons==1,"seconds":WORK_SECONDS})
	return defs
