class_name EconomyBuildV1
extends RefCounted
## PROJECT_TEMP M48. Pure proposals; CampEdit and FrozenSettlement own durable writes.

const VERSION: int = 1
const SOURCE_ENCODING: String = "BH_M48_ACTION_GZIP_EXACT_V1"
const SOURCE_KEYS: Array[String] = ["encoding", "sha256", "unpacked_bytes", "compressed_sha256", "compressed_bytes", "data"]
static var _decoded_sources: Dictionary = {}
const FACILITIES: Array[String] = ["supply", "workshop", "planning"]
const GUNS: Array[String] = ["carbine", "long_rifle", "shotgun_v1"]
const BASIC: Array[String] = ["quick_v1", "reach_v1"]
const COMBAT: Array[String] = ["pierce_v1", "defeat_refund_v1"]
const OPS: Array[String] = ["build", "upgrade_facility", "sell", "craft", "upgrade_weapon", "basic_component", "combat_component", "magazine"]


static func initial() -> Dictionary:
	var facilities: Dictionary = {}
	for id: String in FACILITIES:
		facilities[id] = {"level":0, "built_sortie":0, "upgraded_sortie":0}
	return {"version":VERSION, "tools":[], "edits":[], "facilities":facilities, "sold":[], "sources":[], "returns":[]}


static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey", {}).get("campaign", {}).has("economy")


static func state(camp: Dictionary) -> Dictionary:
	var value: Variant = camp.get("journey", {}).get("campaign", {}).get("economy", {})
	return value if value is Dictionary else {}


static func facility_name(id: String) -> String:
	return String({"supply":"补给设施", "workshop":"工坊", "planning":"规划室"}.get(id, id))


static func operation_name(id: String) -> String:
	return String({"build":"建设", "upgrade_facility":"设施升级", "sell":"出售", "craft":"制作", "upgrade_weapon":"武器升级", "basic_component":"安装基本组件", "combat_component":"安装战斗组件", "magazine":"更换弹匣"}.get(id, id))


static func level(camp: Dictionary, facility: String) -> int:
	return int(state(camp).get("facilities", {}).get(facility, {}).get("level", 0))


static func tools(camp: Dictionary) -> int:
	var count: int = 0
	for unit: Dictionary in state(camp).get("tools", []):
		count += int(unit.get("spent", "").is_empty())
	return count


static func sale_price(item: Dictionary) -> int:
	var base: int = 3 if item.get("weapon_id") in ["carbine", "fire_axe_v1"] else 4
	var quote: int = base + 2 * (int(item.get("weapon_level", 1)) - 1) + int({"enhanced":2, "rare":4}.get(item.get("quality"), 0))
	return maxi(1, quote / 2) if item.get("condition") == "damaged" else quote


static func offer(camp: Dictionary, op: String, target: String = "", choice: String = "") -> Dictionary:
	var quote: Dictionary = {"available":false, "reason":"", "cost":0, "tools":0, "summary":""}
	var reason: String = ""
	var item: Dictionary = WeaponInventory.find(camp, target) if camp.get("weapons") is Array else {}
	if not enabled(camp) or op not in OPS:
		reason = "当前旅程不支持此项投资"
	elif camp.get("journey", {}).get("state") != "ACTIVE" or CampaignState.ended(camp):
		reason = "旅程已结束，仅可查看历史"
	else:
		match op:
			"build", "upgrade_facility":
				if target not in FACILITIES:
					reason = "设施类型无效"
				elif op == "build":
					quote.cost = 16 if target == "planning" else 12
					quote.tools = 2 if target == "planning" else 1
					if level(camp, target) > 0: reason = "该设施已建成"
					elif camp.get("last_day", {}).get("evacuated") != true: reason = "先完成一次成功归航并确认"
				else:
					quote.cost = 10
					quote.tools = 1
					if level(camp, target) != 1: reason = "需要一级设施，二级已是上限"
					elif int(camp.settled_sorties) <= int(state(camp).facilities[target].built_sortie) or camp.get("last_day", {}).get("evacuated") != true:
						reason = "建成后须再完成一次成功归航并确认"
				quote.summary = "%s %d → %d 级" % [facility_name(target), level(camp, target), level(camp, target) + 1]
			"sell":
				if item.is_empty(): reason = "该实例已出售或不存在"
				elif WeaponInventory.owner(camp, target) > 0: reason = "请先在装备仓换下这件武器"
				elif camp.weapons.filter(func(row: Dictionary) -> bool: return row.instance_id != target and row.condition == "ready").is_empty():
					reason = "必须保留至少一件就绪武器"
				else:
					quote.cost = -sale_price(item)
					quote.summary = "出售 %s · #%s\n组件：%s · 弹匣：%s · 成交 %d 币" % [WeaponInventory.loot_description(item), WeaponInventory.short_id(item), WeaponModifiers.description(item), WorkshopV1.name_for(WorkshopV1.mod_for(camp, target)), -int(quote.cost)]
			"craft":
				quote.cost = 12
				quote.tools = 1
				if target not in GUNS: reason = "请选择三种枪械基础型"
				elif level(camp, "workshop") < 1: reason = "需要一级工坊"
				quote.summary = "制作自制%s Lv1 · 就绪 · 原装弹匣" % (WeaponInventory.definition(target).display_name if target in GUNS else target)
				if target in GUNS: quote.summary += "\n实例基础直伤 %.2f · 空基本组件／空战斗组件" % WeaponInventory.definition(target).damage
			"upgrade_weapon", "basic_component", "combat_component", "magazine":
				quote.cost = 8
				quote.tools = 1
				if item.is_empty(): reason = "该实例已出售或不存在"
				elif item.condition != "ready": reason = "先维修这件武器"
				elif level(camp, "workshop") < 1: reason = "需要一级工坊"
				elif op == "upgrade_weapon":
					var old_level: int = int(item.get("weapon_level", 1))
					if not crafted(item): reason = "普通掉落等级由来源冻结，仅自制枪可升级"
					elif old_level >= 5: reason = "已达五级"
					elif old_level >= 3 and level(camp, "workshop") < 2: reason = "四、五级升级需要二级工坊"
					quote.cost = int({1:8, 2:10, 3:12, 4:16}.get(old_level, 0))
					quote.tools = 2 if old_level == 4 else 1
					quote.summary = "Lv%d → Lv%d · 基础直伤 %.2f → %.2f" % [old_level, mini(5, old_level + 1), WeaponModifiers.effective(item).damage, WeaponInventory.definition(item.weapon_id).damage * (1.0 + 0.1 * old_level)]
					if old_level < 5:
						var upgraded: Dictionary = item.duplicate(true)
						upgraded.weapon_level = old_level + 1
						quote.summary += holder_preview(camp, item, upgraded)
				elif op == "magazine":
					if item.weapon_id not in GUNS or choice not in [WorkshopV1.EXTENDED, WorkshopV1.QUICK]: reason = "枪型或弹匣方案无效"
					elif item.weapon_id != "carbine" and level(camp, "workshop") < 2: reason = "长管和霰弹弹匣需要二级工坊"
					elif item.get("economy", {}).get("magazine", "") == choice: reason = "已安装该弹匣"
					quote.summary = "弹匣 %s → %s" % [WorkshopV1.name_for(WorkshopV1.mod_for(camp, target)), WorkshopV1.name_for(choice)]
					if item.weapon_id in GUNS and choice in [WorkshopV1.EXTENDED,WorkshopV1.QUICK]:
						var current_mag: Dictionary = WeaponMagazine.parameters(item.weapon_id,WorkshopV1.mod_for(camp,target))
						var next_mag: Dictionary = WeaponMagazine.parameters(item.weapon_id,choice)
						quote.summary += "\n容量 %d → %d 发 · 基础换弹 %.2f → %.2f 秒" % [current_mag.capacity,next_mag.capacity,current_mag.seconds,next_mag.seconds]
				else:
					if not crafted(item): reason = "组件位置只对自制枪开放"
					elif choice not in (BASIC if op == "basic_component" else COMBAT): reason = "组件位置与效果不兼容"
					elif item.get("economy", {}).get("basic" if op == "basic_component" else "combat", "") == choice: reason = "已安装该组件"
					var name: String = {"quick_v1":"轻快机件 · 攻击间隔 ×0.90","reach_v1":"延伸瞄具 · 射程 ×1.15","pierce_v1":"穿透弹 · 同射线第二目标伤害 50%","defeat_refund_v1":"击倒补弹 · 每次开火实际击倒后最多补 1 发"}.get(choice,choice)
					quote.summary = "%s → %s" % ["基本组件" if op == "basic_component" else "战斗组件", name]
	if reason.is_empty() and int(camp.get("cash", 0)) < int(quote.cost): reason = "还差 %d 币" % (int(quote.cost) - int(camp.get("cash", 0)))
	if reason.is_empty() and tools(camp) < int(quote.tools): reason = "还差工具 ×%d" % (int(quote.tools) - tools(camp))
	quote.reason = reason
	quote.available = reason.is_empty()
	quote.summary += "\n花费 %d 币＋%d 工具 · 余额 %d 币／%d 工具 → %d 币／%d 工具" % [int(quote.cost), int(quote.tools), int(camp.get("cash", 0)), tools(camp), int(camp.get("cash", 0)) - int(quote.cost), tools(camp) - int(quote.tools)]
	return quote


static func crafted(item: Dictionary) -> bool:
	return item.get("economy", {}).get("crafted") == true


static func request(camp: Dictionary, op: String, target: String, choice: String, edit_id: String) -> Dictionary:
	return {"kind":"economy", "member_id":0, "value":JSON.stringify({"op":op, "target":target, "choice":choice, "edit_id":edit_id, "before_hash":SurvivalContracts.fingerprint(camp)})}


static func intent(request_value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(request_value.get("value", ""))
	return parsed if parsed is Dictionary else {}


static func propose(before: Dictionary, request_value: Dictionary) -> Dictionary:
	if not enabled(before) or not before.get("profile_id") is String or not state(before).get("edits") is Array: return {}
	var value: Dictionary = intent(request_value)
	if request_value.size() != 3 or request_value.get("kind") != "economy" or request_value.get("member_id") != 0 \
			or value.size() != 5 or not value.has_all(["op", "target", "choice", "edit_id", "before_hash"]): return {}
	for key: String in value:
		if not value[key] is String: return {}
	if not TrainingRules.edit_identity(value.edit_id, before.profile_id) or value.before_hash != SurvivalContracts.fingerprint(before): return {}
	if state(before).edits.any(func(row: Dictionary) -> bool: return row.id == value.edit_id): return {}
	var quote: Dictionary = offer(before, value.op, value.target, value.choice)
	if not quote.available: return {}
	var after: Dictionary = before.duplicate(true)
	var ledger: Dictionary = state(after)
	var spent: Array[String] = []
	for unit: Dictionary in ledger.tools:
		if spent.size() >= int(quote.tools): break
		if unit.spent.is_empty():
			unit.spent = value.edit_id
			spent.append(unit.id)
	var prior: Dictionary = WeaponInventory.find(before, value.target).duplicate(true)
	var changed: Dictionary = {}
	match value.op:
		"build", "upgrade_facility":
			var facility: Dictionary = ledger.facilities[value.target]
			facility.level += 1
			facility["built_sortie" if value.op == "build" else "upgraded_sortie"] = int(before.settled_sorties)
		"sell":
			for index: int in range(after.weapons.size()):
				if after.weapons[index].instance_id == value.target:
					after.weapons.remove_at(index)
					break
			ledger.sold.append({"instance":prior.duplicate(true), "edit_id":value.edit_id, "price":-int(quote.cost)})
		"craft":
			changed = craft_instance(value.edit_id, value.target)
			after.weapons.append(changed)
		"upgrade_weapon", "basic_component", "combat_component", "magazine":
			changed = WeaponInventory.find(after, value.target)
			if not changed.has("economy"): changed.economy = configuration(false, "")
			match value.op:
				"upgrade_weapon": changed.weapon_level += 1
				"basic_component": changed.economy.basic = value.choice
				"combat_component": changed.economy.combat = value.choice
				"magazine": changed.economy.magazine = value.choice
			if crafted(changed): changed.affixes = components(changed.economy)
	after.cash -= int(quote.cost)
	if int(quote.cost) > 0: after.camp_spending += int(quote.cost)
	ledger.edits.append({"id":value.edit_id, "day":int(before.day), "sortie":int(before.settled_sorties), "op":value.op, "target":value.target, "choice":value.choice, "cost":int(quote.cost), "tools":spent, "before":prior, "after":changed.duplicate(true), "before_hash":value.before_hash})
	return after


static func configuration(is_crafted: bool, edit_id: String) -> Dictionary:
	return {"version":VERSION, "crafted":is_crafted, "edit_id":edit_id, "basic":"", "combat":"", "magazine":""}


static func components(config: Dictionary) -> Array:
	var result: Array = []
	for key: String in ["basic", "combat"]:
		if not config[key].is_empty(): result.append(config[key])
	return result


static func craft_instance(edit_id: String, gun: String) -> Dictionary:
	return {"instance_id":edit_id + ":crafted", "weapon_id":gun, "condition":"ready", "origin":"m48-crafted", "acquired_sortie":"", "weapon_level":1, "quality":"crafted", "affixes":[], "economy":configuration(true, edit_id)}


static func level_at(camp: Dictionary, facility: String, sortie: int) -> int:
	var result: int = 0
	for edit: Dictionary in state(camp).get("edits", []):
		if int(edit.sortie) < sortie and edit.target == facility and edit.op in ["build", "upgrade_facility"]: result += 1
	return result


static func current_sales(camp: Dictionary) -> int:
	var result: int = 0
	for edit: Dictionary in state(camp).get("edits", []):
		if edit.day == camp.day and edit.op == "sell": result -= int(edit.cost)
	return result


static func planning_credit(camp: Dictionary, member_id: int, before_day: int = RunSave.MAX_COUNTER) -> int:
	var total: int = 0
	for row: Dictionary in state(camp).get("returns", []):
		var award: Dictionary = row.get("planning", {})
		if award.get("member_id") == member_id and int(row.sortie) + 2 <= before_day: total += int(award.points)
	return total


static func settled(before: Dictionary, after: Dictionary, report: Dictionary, action: Dictionary) -> void:
	if not enabled(before): return
	var ledger: Dictionary = state(after)
	var sortie: int = int(before.settled_sorties) + 1
	var transaction: String = report.sortie_id
	if not report.evacuated: return
	var completed: Array[String] = []
	for definition: Dictionary in action.get("sites", []):
		if report.get("site_facts", {}).get(definition.id, {}).get("searched") == true: completed.append(definition.id)
	var need_source: bool = false
	for source: Dictionary in EconomyActions.tool_sources(action):
		if source.site_id not in completed: continue
		need_source = true
		for index: int in range(int(source.count)):
			ledger.tools.append({"id":"%s:tool:%s:%d" % [transaction, source.site_id, index], "transaction_id":transaction, "action_id":action.id, "site_id":source.site_id, "ordinal":index, "spent":""})
	for definition: Dictionary in action.get("sites", []):
		if definition.get("weapon") == true and definition.id in completed: need_source = true
	if need_source: ledger.sources.append({"sortie":sortie, "transaction_id":transaction, "action":compact_action(action), "completed":completed})
	var repairs: Array[String] = []
	var workshop: int = level(before, "workshop")
	if workshop > 0:
		var candidates: Array = before.weapons.filter(func(item: Dictionary) -> bool: return item.condition == "damaged" and WeaponInventory.owner(before, item.instance_id) == 0)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var aa: int = int(String(a.acquired_sortie).get_slice(":", 1))
			var bb: int = int(String(b.acquired_sortie).get_slice(":", 1))
			return a.instance_id < b.instance_id if aa == bb else aa < bb)
		for index: int in range(mini(workshop, candidates.size())):
			var item: Dictionary = WeaponInventory.find(after, candidates[index].instance_id)
			if not item.is_empty():
				item.condition = "ready"
				repairs.append(item.instance_id)
	var planning: Dictionary = {}
	var candidates: Array[Dictionary] = []
	var planning_level: int = level(before, "planning")
	if planning_level > 0:
		for member: Dictionary in after.crew:
			if member.health <= 0 or not member.get("growth", {}).get("trait") is Dictionary or int(member.growth.trait.level) >= 5: continue
			if int(member.id) > 2 and not after.recruits.any(func(row: Dictionary) -> bool: return row.member_id == member.id and row.field_status == "RETURNED"): continue
			candidates.append({"member_id":int(member.id), "trait":member.growth.trait.duplicate(true)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.trait.level != b.trait.level: return a.trait.level < b.trait.level
			return a.member_id < b.member_id if a.trait.progress == b.trait.progress else a.trait.progress < b.trait.progress)
		if not candidates.is_empty():
			var target: Dictionary = SurvivorRoster.member(after.crew, candidates[0].member_id)
			planning = {"member_id":int(target.id), "points":planning_level, "before":target.growth.trait.duplicate(true)}
			target.growth.trait.progress += planning_level
			target.growth.trait.level = TraitRules.level_for(int(target.growth.trait.progress))
			planning.after = target.growth.trait.duplicate(true)
	ledger.returns.append({"sortie":sortie, "transaction_id":transaction, "facilities":state(before).facilities.duplicate(true), "repairs":repairs, "planning":planning, "planning_candidates":candidates, "food":CampFacilities.offered_food(before, int(before.day), true)})


static func marker_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 7 or not value.has_all(["version", "tools", "edits", "facilities", "sold", "sources", "returns"]) or not SurvivalContracts.integer(value.version, VERSION, VERSION): return "ECONOMY_POLICY_FIELDS"
	for key: String in ["tools", "edits", "sold", "sources", "returns"]:
		if not value[key] is Array: return "ECONOMY_POLICY_LISTS"
	if not value.facilities is Dictionary or value.facilities.size() != 3 or not value.facilities.has_all(FACILITIES): return "ECONOMY_FACILITIES"
	for id: String in FACILITIES:
		var row: Variant = value.facilities[id]
		if not row is Dictionary or row.size() != 3 or not row.has_all(["level", "built_sortie", "upgraded_sortie"]) or not SurvivalContracts.integer(row.level, 0, 2) or not SurvivalContracts.integer(row.built_sortie, 0, RunSave.MAX_COUNTER) or not SurvivalContracts.integer(row.upgraded_sortie, 0, RunSave.MAX_COUNTER): return "ECONOMY_FACILITY_FIELDS"
	return ""


static func problem(camp: Dictionary) -> String:
	if not enabled(camp): return ""
	var ledger: Dictionary = state(camp)
	var issue: String = marker_problem(ledger)
	if not issue.is_empty(): return issue
	if not TransactionReceipt.same(camp.journey.campaign.get("midgame", {}), CampFacilities.initial_tier_two()) or not TransactionReceipt.same(camp.journey.campaign.get("workshop", {}), WorkshopV1.initial()): return "ECONOMY_LEGACY_POLICY_CHANGED"
	var expected_tools: Dictionary = {}
	var previous: int = 0
	for source: Variant in ledger.sources:
		if not source is Dictionary or source.size() != 4 or not source.has_all(["sortie", "transaction_id", "action", "completed"]) or not SurvivalContracts.integer(source.sortie, previous + 1, int(camp.settled_sorties)) or source.transaction_id != "%s:%d" % [camp.profile_id, int(source.sortie)] or not source.action is Dictionary or not source.completed is Array: return "ECONOMY_SOURCE_FIELDS"
		var action: Dictionary = source_action(source)
		if not action.has("economy_source") or not EconomyActions.problem(action, true).is_empty() or action.seed != camp.journey.seed or action.day != int(source.sortie) + 1 or action.campaign.run_id != camp.profile_id: return "ECONOMY_ACTION_SOURCE"
		var seen_sites: Array[String] = []
		for id: Variant in source.completed:
			if not id is String or id in seen_sites or not action.sites.any(func(site: Dictionary) -> bool: return site.id == id): return "ECONOMY_COMPLETED_SITE"
			seen_sites.append(id)
		for units: Dictionary in EconomyActions.tool_sources(action):
			if units.site_id not in source.completed: continue
			for index: int in range(int(units.count)):
				var identity: String = "%s:tool:%s:%d" % [source.transaction_id, units.site_id, index]
				expected_tools[identity] = {"id":identity, "transaction_id":source.transaction_id, "action_id":action.id, "site_id":units.site_id, "ordinal":index, "spent":""}
		previous = int(source.sortie)
	if ledger.tools.size() != expected_tools.size(): return "ECONOMY_TOOL_COUNT"
	var tool_ids: Array[String] = []
	for unit: Variant in ledger.tools:
		if not unit is Dictionary or unit.size() != 6 or not unit.get("id") is String or not unit.get("spent") is String or unit.id in tool_ids or not expected_tools.has(unit.id): return "ECONOMY_TOOL_SOURCE"
		var expected: Dictionary = expected_tools[unit.id].duplicate(true)
		expected.spent = unit.spent
		if not TransactionReceipt.same(expected, unit): return "ECONOMY_TOOL_SOURCE"
		tool_ids.append(unit.id)
	var facilities: Dictionary = initial().facilities
	var spent: Dictionary = {}
	var edit_ids: Array[String] = []
	previous = 0
	for edit: Variant in ledger.edits:
		if not edit is Dictionary or edit.size() != 11 or not edit.has_all(["id", "day", "sortie", "op", "target", "choice", "cost", "tools", "before", "after", "before_hash"]) or not edit.get("id") is String or not TrainingRules.edit_identity(edit.id, camp.profile_id) or edit.id in edit_ids or not SurvivalContracts.integer(edit.sortie, previous, int(camp.settled_sorties)) or edit.day != int(edit.sortie) + 2 or edit.op not in OPS or not edit.target is String or not edit.choice is String or not edit.tools is Array or not edit.before is Dictionary or not edit.after is Dictionary or not edit.before_hash is String or edit.before_hash.length() != 64 or not edit.before_hash.is_valid_hex_number(false): return "ECONOMY_EDIT_FIELDS"
		var cost: int = 8
		var units: int = 1
		match edit.op:
			"build", "upgrade_facility":
				if edit.target not in FACILITIES: return "ECONOMY_FACILITY_ID"
				var row: Dictionary = facilities[edit.target]
				if edit.op == "build":
					if row.level != 0 or int(edit.sortie) < 1: return "ECONOMY_BUILD_SOURCE"
					cost = 16 if edit.target == "planning" else 12
					units = 2 if edit.target == "planning" else 1
					row.built_sortie = int(edit.sortie)
				else:
					if row.level != 1 or int(edit.sortie) <= int(row.built_sortie): return "ECONOMY_UPGRADE_SOURCE"
					cost = 10
					row.upgraded_sortie = int(edit.sortie)
				row.level += 1
			"craft":
				cost = 12
				if edit.target not in GUNS or facilities.workshop.level < 1: return "ECONOMY_CRAFT_SOURCE"
			"upgrade_weapon":
				if not SurvivalContracts.integer(edit.before.get("weapon_level"), 1, 4) or not crafted(edit.before): return "ECONOMY_WEAPON_UPGRADE_SOURCE"
				var old_level: int = int(edit.before.weapon_level)
				if facilities.workshop.level < (2 if old_level >= 3 else 1): return "ECONOMY_WEAPON_UPGRADE_SOURCE"
				cost = int({1:8, 2:10, 3:12, 4:16}[old_level])
				units = 2 if old_level == 4 else 1
			"basic_component", "combat_component":
				if facilities.workshop.level < 1 or not crafted(edit.before) or edit.choice not in (BASIC if edit.op == "basic_component" else COMBAT): return "ECONOMY_COMPONENT_SOURCE"
			"magazine":
				if edit.before.get("weapon_id") not in GUNS or edit.choice not in [WorkshopV1.EXTENDED, WorkshopV1.QUICK] or facilities.workshop.level < (1 if edit.before.weapon_id == "carbine" else 2): return "ECONOMY_MAGAZINE_SOURCE"
			"sell":
				cost = -sale_price(edit.before)
				units = 0
		if edit.cost != cost or edit.tools.size() != units: return "ECONOMY_EDIT_PRICE"
		for id: Variant in edit.tools:
			if not id is String or spent.has(id) or not expected_tools.has(id) or int(String(expected_tools[id].transaction_id).get_slice(":", 1)) > int(edit.sortie): return "ECONOMY_TOOL_DOUBLE_SPEND"
			spent[id] = edit.id
		edit_ids.append(edit.id)
		previous = int(edit.sortie)
	if not TransactionReceipt.same(facilities, ledger.facilities): return "ECONOMY_FACILITY_HISTORY"
	for unit: Dictionary in ledger.tools:
		if unit.spent != spent.get(unit.id, ""): return "ECONOMY_TOOL_CONSUMPTION"
	previous = 0
	for row: Variant in ledger.returns:
		if not row is Dictionary or row.size() != 7 or not row.has_all(["sortie", "transaction_id", "facilities", "repairs", "planning", "planning_candidates", "food"]) or not SurvivalContracts.integer(row.sortie, previous + 1, int(camp.settled_sorties)) or row.transaction_id != "%s:%d" % [camp.profile_id, int(row.sortie)] or not row.facilities is Dictionary or not row.repairs is Array or not row.planning is Dictionary or not row.planning_candidates is Array: return "ECONOMY_RETURN_FIELDS"
		var supply: int = level_at(camp, "supply", int(row.sortie))
		var workshop: int = level_at(camp, "workshop", int(row.sortie))
		var planning: int = level_at(camp, "planning", int(row.sortie))
		for id: String in FACILITIES:
			if row.facilities.get(id, {}).get("level") != level_at(camp, id, int(row.sortie)): return "ECONOMY_RETURN_FACILITY"
		if row.food != (supply + 1 if supply > 0 else 0) or row.repairs.size() > workshop: return "ECONOMY_UNEARNED_AUTO_EFFECT"
		var ids: Array[String] = []
		for identity: Variant in row.repairs:
			if not identity is String or identity in ids: return "ECONOMY_AUTO_REPAIR_ID"
			var item: Dictionary = historical_find(camp, identity)
			if item.is_empty() or int(String(item.acquired_sortie).get_slice(":", 1)) >= int(row.sortie): return "ECONOMY_AUTO_REPAIR_SOURCE"
			ids.append(identity)
		var last_candidate: Dictionary = {}
		var candidate_ids: Array[int] = []
		for candidate: Variant in row.planning_candidates:
			if not candidate is Dictionary or candidate.size() != 2 or not candidate.has_all(["member_id", "trait"]) or not SurvivalContracts.integer(candidate.member_id, 1, 5) or int(candidate.member_id) in candidate_ids or not candidate.trait is Dictionary: return "ECONOMY_PLANNING_CANDIDATE"
			if not planning_eligible(camp, int(candidate.member_id), int(row.sortie)): return "ECONOMY_PLANNING_UNREGISTERED_TARGET"
			var trait_value: Dictionary = candidate.trait
			if trait_value.size() != 3 or not trait_value.has_all(["id", "level", "progress"]) or trait_value.id != TraitRules.IDS[TraitRules.role({"id":candidate.member_id}) - 1] or not SurvivalContracts.integer(trait_value.progress, 0, RunSave.MAX_COUNTER) or not SurvivalContracts.integer(trait_value.level, 1, 4) or trait_value.level != TraitRules.level_for(int(trait_value.progress)): return "ECONOMY_PLANNING_CANDIDATE_TRAIT"
			if not last_candidate.is_empty() and (trait_value.level < last_candidate.trait.level or (trait_value.level == last_candidate.trait.level and (trait_value.progress < last_candidate.trait.progress or (trait_value.progress == last_candidate.trait.progress and candidate.member_id < last_candidate.member_id)))): return "ECONOMY_PLANNING_TARGET_ORDER"
			candidate_ids.append(int(candidate.member_id))
			last_candidate = candidate
		if not row.planning.is_empty():
			var award: Dictionary = row.planning
			if planning == 0 or award.size() != 4 or not award.has_all(["member_id", "points", "before", "after"]) or award.points != planning or not award.before is Dictionary or not award.after is Dictionary or not SurvivalContracts.integer(award.get("member_id"), 1, 5) or row.planning_candidates.is_empty() or row.planning_candidates[0].get("member_id") != award.member_id or not TransactionReceipt.same(row.planning_candidates[0].get("trait", {}), award.before) or award.before.get("level", 5) >= 5: return "ECONOMY_PLANNING_SOURCE"
			if not planning_eligible(camp, int(award.member_id), int(row.sortie)): return "ECONOMY_PLANNING_UNREGISTERED_TARGET"
			var expected: Dictionary = award.before.duplicate(true)
			expected.progress += planning
			expected.level = TraitRules.level_for(int(expected.progress))
			if not TransactionReceipt.same(expected, award.after): return "ECONOMY_PLANNING_AMOUNT"
			for death: Dictionary in camp.journey.deaths:
				if death.member_id == award.member_id and int(String(death.transaction_id).get_slice(":", 1)) <= int(row.sortie): return "ECONOMY_PLANNING_DEAD_TARGET"
		elif not row.planning_candidates.is_empty(): return "ECONOMY_PLANNING_MISSING"
		previous = int(row.sortie)
	return weapon_problem(camp)


static func historical_find(camp: Dictionary, identity: String) -> Dictionary:
	var current: Dictionary = WeaponInventory.find(camp, identity)
	if not current.is_empty(): return current
	for row: Dictionary in state(camp).get("sold", []):
		if row.get("instance", {}).get("instance_id") == identity: return row.instance
	return {}


static func site_reward(sortie_id: String, action: Dictionary, site: Dictionary) -> Dictionary:
	var origin: Dictionary = EconomyActions.origin(action)
	var original_site: Dictionary = {}
	for row: Dictionary in origin.get("sites", []):
		if row.id == site.id: original_site = row
	if original_site.is_empty() or not original_site.get("weapon", false): return {}
	var item: Dictionary = WeaponInventory.site_reward(sortie_id, origin, original_site, true)
	if item.is_empty(): return {}
	var grade: int = EconomyActions.grade(action)
	var entropy: String = ("BH_M48_WEAPON:%s:%s:%s:0" % [action.seed, action.id, site.id]).sha256_text()
	var roll: int = entropy.substr(0, 8).hex_to_int() % 100
	var common: int = [60, 45, 25][grade - 1]
	var enhanced: int = [30, 35, 40][grade - 1]
	item.weapon_level = clampi(1 + floori((float(action.day) - 2.0) / 3.0) + int(grade >= 3), 1, 5)
	item.quality = "common" if roll < common else "enhanced" if roll < common + enhanced else "rare"
	item.affixes = []
	var basic: String = BASIC[entropy.substr(8, 2).hex_to_int() % BASIC.size()]
	if item.quality != "common": item.affixes.append(basic)
	if item.quality == "rare":
		item.affixes.append(BASIC[1 - BASIC.find(basic)] if CombatEquipment.melee(item.weapon_id) else COMBAT[entropy.substr(10, 2).hex_to_int() % COMBAT.size()])
	item.drop = {"version":5, "slot":int(action.slot), "site_id":site.id, "action_id":action.id, "day":int(action.day), "loot_grade":grade}
	item.economy = configuration(false, "")
	return item


static func weapon_problem(camp: Dictionary) -> String:
	var ledger: Dictionary = state(camp)
	var expected: Dictionary = {}
	var all: Array = camp.weapons.duplicate(true)
	for row: Variant in ledger.sold:
		if not row is Dictionary or row.size() != 3 or not row.has_all(["instance", "edit_id", "price"]) or not row.instance is Dictionary: return "ECONOMY_SOLD_FIELDS"
		all.append(row.instance)
	for item: Variant in all:
		if not item is Dictionary or not item.get("instance_id") is String or not WeaponModifiers.problem(item).is_empty(): return "ECONOMY_WEAPON_FIELDS"
		if not crafted(item) and item.get("drop", {}).get("version") != 5:
			var base: Dictionary = item.duplicate(true)
			base.erase("economy")
			expected[item.instance_id] = base
	for source: Dictionary in ledger.sources:
		var action: Dictionary = source_action(source)
		if action.is_empty(): return "ECONOMY_ACTION_CODEC"
		for site: Dictionary in action.sites:
			if site.get("weapon") != true or site.id not in source.completed: continue
			var item: Dictionary = site_reward(source.transaction_id, action, site)
			if item.is_empty() or expected.has(item.instance_id): return "ECONOMY_WEAPON_SOURCE_DUPLICATE"
			expected[item.instance_id] = item
	var sold: Array = []
	for edit: Dictionary in ledger.edits:
		if edit.op in ["build", "upgrade_facility"]:
			if not edit.before.is_empty() or not edit.after.is_empty(): return "ECONOMY_FACILITY_WEAPON_CHANGE"
			continue
		if edit.op == "craft":
			var created: Dictionary = craft_instance(edit.id, edit.target)
			if not edit.before.is_empty() or not TransactionReceipt.same(created, edit.after) or expected.has(created.instance_id): return "ECONOMY_CRAFT_IDENTITY"
			expected[created.instance_id] = created
			continue
		if not expected.has(edit.target): return "ECONOMY_SOLD_OR_UNKNOWN_INSTANCE"
		var old: Dictionary = expected[edit.target].duplicate(true)
		if edit.before.get("condition") not in ["ready", "damaged"] or (crafted(old) and edit.before.condition != "ready"): return "ECONOMY_WEAPON_CONDITION"
		old.condition = edit.before.condition
		if not TransactionReceipt.same(old, edit.before): return "ECONOMY_WEAPON_EDIT_PRESTATE"
		if edit.op == "sell":
			if not edit.after.is_empty(): return "ECONOMY_SALE_RESULT"
			sold.append({"instance":old.duplicate(true), "edit_id":edit.id, "price":-int(edit.cost)})
			expected.erase(edit.target)
			continue
		if old.condition != "ready": return "ECONOMY_DAMAGED_UPGRADE"
		if not old.has("economy"): old.economy = configuration(false, "")
		match edit.op:
			"upgrade_weapon": old.weapon_level += 1
			"basic_component": old.economy.basic = edit.choice
			"combat_component": old.economy.combat = edit.choice
			"magazine": old.economy.magazine = edit.choice
		if crafted(old): old.affixes = components(old.economy)
		if not TransactionReceipt.same(old, edit.after): return "ECONOMY_WEAPON_EDIT_RESULT"
		expected[edit.target] = old
	if not TransactionReceipt.same({"v":sold}, {"v":ledger.sold}): return "ECONOMY_SOLD_HISTORY"
	if expected.size() != camp.weapons.size(): return "ECONOMY_ACTIVE_INVENTORY_COUNT"
	var seen: Array[String] = []
	for item: Dictionary in camp.weapons:
		if item.instance_id in seen or not expected.has(item.instance_id): return "ECONOMY_INVENTORY_IDENTITY"
		var proposed: Dictionary = expected[item.instance_id].duplicate(true)
		if item.condition == "ready": proposed.condition = "ready"
		if not TransactionReceipt.same(item, proposed): return "ECONOMY_WEAPON_PROVENANCE"
		seen.append(item.instance_id)
	var owners: Array[int] = []
	var equipped: Array[String] = []
	for row: Variant in camp.loadout:
		if not row is Dictionary or row.size() != 2 or not SurvivalContracts.integer(row.get("member_id"), 1, 5) or not row.get("instance_id") is String or int(row.member_id) in owners or row.instance_id in equipped or not WeaponInventory._living(camp, int(row.member_id)) or WeaponInventory.find(camp, row.instance_id).get("condition") != "ready": return "ECONOMY_LOADOUT"
		owners.append(int(row.member_id))
		equipped.append(row.instance_id)
	for member: Dictionary in camp.crew:
		if member.health > 0 and int(member.id) not in owners: return "ECONOMY_MEMBER_WITHOUT_WEAPON"
	return ""


static func legacy_projection(camp: Dictionary) -> Dictionary:
	# Authenticate the new policy first. This view is never saved or used in play.
	var projected: Dictionary = camp.duplicate(true)
	var originals: Array = camp.weapons.duplicate(true)
	for row: Dictionary in state(camp).sold: originals.append(row.instance.duplicate(true))
	projected.weapons = []
	var mapping: Dictionary = {}
	for item: Dictionary in originals:
		if crafted(item): continue
		var old: Dictionary = item.duplicate(true)
		old.erase("economy")
		if old.get("drop", {}).get("version") == 5:
			var source_action_id: String = old.drop.action_id
			var source_site_id: String = old.drop.site_id
			var found: bool = false
			for source: Dictionary in state(camp).sources:
				var original_action: Dictionary = source_action(source)
				if original_action.is_empty(): return {}
				if original_action.id != source_action_id: continue
				var action: Dictionary = EconomyActions.origin(original_action)
				for site: Dictionary in action.sites:
					if site.id == source_site_id:
						old = WeaponInventory.site_reward(source.transaction_id, action, site, true)
						if old.is_empty(): return {}
						old.condition = item.condition
						found = true
						break
				if found: break
			if not found: return {}
		projected.weapons.append(old)
		mapping[item.instance_id] = {"instance_id":old.instance_id, "weapon_id":old.weapon_id}
	var starter: String = "%s:starter:1" % camp.profile_id
	for item: Dictionary in originals:
		if crafted(item): mapping[item.instance_id] = {"instance_id":starter, "weapon_id":"carbine"}
	var used: Array[String] = []
	for row: Dictionary in projected.loadout:
		var original: Dictionary = WeaponInventory.find(projected, row.instance_id)
		if original.is_empty() or row.instance_id in used:
			for candidate: Dictionary in projected.weapons:
				if candidate.condition == "ready" and candidate.instance_id not in used:
					row.instance_id = candidate.instance_id
					break
		used.append(row.instance_id)
	for member: Dictionary in projected.crew:
		for receipt: Dictionary in member.get("growth", {}).get("last_action", {}).get("recent", []):
			if BuildAuthority.ability(receipt): continue
			var actual: Dictionary = historical_find(camp, receipt.get("instance_id", ""))
			if actual.is_empty() or receipt.get("weapon_id") != actual.weapon_id or not mapping.has(actual.instance_id): return {}
			receipt.instance_id = mapping[actual.instance_id].instance_id
			receipt.weapon_id = mapping[actual.instance_id].weapon_id
		var credit: int = planning_credit(camp, int(member.id))
		if credit > 0:
			if int(member.growth.trait.progress) < credit: return {}
			member.growth.trait.progress -= credit
			member.growth.trait.level = TraitRules.level_for(int(member.growth.trait.progress))
	for row: Dictionary in projected.get("training", []):
		row.progress_before -= planning_credit(camp, int(row.member_id), int(row.day))
		if row.progress_before < 0: return {}
	var revenue: int = current_sales(camp)
	if revenue > 0:
		projected.last_day.cash_gained += revenue
		projected.last_day.cash_after += revenue
	return projected


static func ledger_text(camp: Dictionary) -> String:
	if not enabled(camp): return "旧旅程沿原设施与工具规则"
	var lines: PackedStringArray = ["工具余额 %d · 回收 %d 单位 · 每单位仅可消费一次" % [tools(camp), state(camp).tools.size()]]
	for unit: Dictionary in state(camp).tools:
		lines.append("%s · 站点 %s · 第%d份 · %s" % [unit.transaction_id, unit.site_id, int(unit.ordinal) + 1, "未消费" if unit.spent.is_empty() else "已用于 " + unit.spent])
	for edit: Dictionary in state(camp).edits:
		lines.append("第%d天 · %s %s %s · %d币／%d工具 · %s" % [int(edit.day), operation_name(edit.op), facility_name(edit.target) if edit.target in FACILITIES else edit.target, edit.choice, int(edit.cost), edit.tools.size(), edit.id])
	for row: Dictionary in state(camp).returns:
		lines.append("归航 %s · 设施应发%d粮 · 自动维修%d件" % [row.transaction_id, int(row.food), row.repairs.size()])
		for identity: String in row.repairs:
			var item: Dictionary = historical_find(camp, identity)
			lines.append("  已修复 %s · %s" % [WeaponInventory.definition(item.weapon_id).display_name if not item.is_empty() else "武器", identity])
		if row.repairs.is_empty(): lines.append("  工坊未建或没有出发前损坏的闲置武器")
		if row.planning.is_empty(): lines.append("  规划未建或没有存活、已登记且未满级的目标")
		else:
			var member: Dictionary = SurvivorRoster.member(camp.crew, int(row.planning.member_id))
			lines.append("  规划：%s #%d · 特长进度 %d → %d" % [String(member.get("call_sign", "队员")), int(row.planning.member_id), int(row.planning.before.progress), int(row.planning.after.progress)])
	return "\n".join(lines)


static func result_problem(receipt: Dictionary) -> String:
	var before: Dictionary = receipt.base
	var actual: Dictionary = receipt.envelope.result.camp
	if enabled(before) != enabled(actual): return "ECONOMY_RESULT_POLICY"
	if not enabled(before): return ""
	var report: Dictionary = receipt.envelope.result.battle
	var expected: Dictionary = actual.duplicate(true)
	var last: Dictionary = {}
	for row: Dictionary in state(actual).returns:
		if row.transaction_id == receipt.transaction_id: last = row
	if report.evacuated:
		if last.is_empty(): return "ECONOMY_RETURN_MISSING"
		var award: Dictionary = last.planning
		if not award.is_empty():
			var target: Dictionary = SurvivorRoster.member(expected.crew, int(award.member_id))
			if target.is_empty() or not TransactionReceipt.same(target.growth.trait, award.after): return "ECONOMY_PLANNING_RESULT"
			target.growth.trait = award.before.duplicate(true)
	expected.journey.campaign.economy = state(before).duplicate(true)
	# Restore precisely the old condition before recomputing the automatic queue.
	for item: Dictionary in expected.weapons:
		var original: Dictionary = WeaponInventory.find(before, item.instance_id)
		if not original.is_empty(): item.condition = original.condition
	settled(before, expected, report, receipt.rules.mission.generated)
	var expected_sources: Dictionary = source_comparison(state(expected))
	var actual_sources: Dictionary = source_comparison(state(actual))
	if expected_sources.is_empty() or actual_sources.is_empty() or not TransactionReceipt.same(expected_sources, actual_sources) or not TransactionReceipt.same({"v":expected.weapons}, {"v":actual.weapons}): return "ECONOMY_RESULT_TRANSITION"
	for member: Dictionary in expected.crew:
		if not TransactionReceipt.same(member.growth.trait, SurvivorRoster.member(actual.crew, int(member.id)).growth.trait): return "ECONOMY_PLANNING_RESULT"
	return ""


static func apply_planning_result(expected: Dictionary, receipt: Dictionary) -> String:
	if not enabled(receipt.base): return ""
	var actual: Dictionary = receipt.envelope.result.camp
	for row: Dictionary in state(actual).returns:
		if row.transaction_id != receipt.transaction_id or row.planning.is_empty(): continue
		var target: Dictionary = SurvivorRoster.member(expected.crew, int(row.planning.member_id))
		if target.is_empty() or not TransactionReceipt.same(target.growth.trait, row.planning.before): return "ECONOMY_PLANNING_NATURAL_SOURCE"
		target.growth.trait = row.planning.after.duplicate(true)
	return ""


static func holder_preview(camp: Dictionary, before: Dictionary, after: Dictionary) -> String:
	var owner: int = WeaponInventory.owner(camp, before.instance_id)
	if owner == 0: return "\n当前未配装；持有人加成在装备后显示"
	var member: Dictionary = SurvivorRoster.member(camp.crew, owner)
	var personal: Dictionary = {}
	if PersonaState.enabled(camp):
		personal = SurvivorPersona.factors(SurvivorPersona.member(camp.journey.build.persona, owner, member.definition_id))
	var factor: float = float(personal.get("melee" if CombatEquipment.melee(before.weapon_id) else "ranged", 1.0))
	if not CombatEquipment.melee(before.weapon_id): factor *= float(BuildItems.camp_factors(camp).get("damage", 1.0))
	return "\n%s #%d 当前有效直伤 %.2f → %.2f" % [member.call_sign, owner, WeaponModifiers.effective(before).damage * factor, WeaponModifiers.effective(after).damage * factor]


static func planning_eligible(camp: Dictionary, member_id: int, sortie: int) -> bool:
	# Eligibility belongs to that return, so a later death does not erase earned credit.
	if member_id < 1 or member_id > 5 or sortie < 1 or SurvivorRoster.member(camp.get("crew", []), member_id).is_empty(): return false
	if member_id > 2:
		var registered: bool = false
		for recruit: Variant in camp.get("recruits", []):
			if not recruit is Dictionary or not SurvivalContracts.integer(recruit.get("member_id"), member_id, member_id) or recruit.get("field_status") != "RETURNED" or not recruit.get("settlement_id") is String: continue
			var parts: PackedStringArray = String(recruit.settlement_id).split(":")
			if parts.size() == 2 and parts[0] == camp.get("profile_id") and parts[1].is_valid_int() and parts[1] == str(int(parts[1])) and int(parts[1]) >= 1 and int(parts[1]) <= sortie: registered = true
		if not registered: return false
	for death: Variant in camp.get("journey", {}).get("deaths", []):
		if not death is Dictionary or not SurvivalContracts.integer(death.get("member_id"), member_id, member_id) or not death.get("transaction_id") is String: continue
		var parts: PackedStringArray = String(death.transaction_id).split(":")
		if parts.size() == 2 and parts[1].is_valid_int() and int(parts[1]) <= sortie: return false
	return true


static func compact_action(action: Dictionary) -> Dictionary:
	# Only this M48 source field is compacted; the journal and save transports stay unchanged.
	if not SurvivalContracts.integer(action.get("version"), 9, 9) or not action.get("economy_source") is Dictionary: return {}
	var exact: String = RecordEncoding.stringify(action)
	var raw: PackedByteArray = exact.to_utf8_buffer()
	if raw.is_empty() or raw.size() > RunSave.MAX_BYTES: return {}
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)
	if compressed.is_empty() or compressed.size() > RunSave.MAX_BYTES: return {}
	return {"encoding":SOURCE_ENCODING, "sha256":exact.sha256_text(), "unpacked_bytes":raw.size(), "compressed_sha256":_source_bytes_hash(compressed), "compressed_bytes":compressed.size(), "data":Marshalls.raw_to_base64(compressed)}


static func source_action(source: Dictionary) -> Dictionary:
	var stored: Variant = source.get("action")
	if not stored is Dictionary: return {}
	if not stored.has("encoding"):
		# Explicit compatibility for this task's unpublished, full debug sources.
		# They still pass the same complete EconomyActions.problem at the call site.
		return stored.duplicate(true) if SurvivalContracts.integer(stored.get("version"), 9, 9) and stored.get("economy_source") is Dictionary else {}
	if stored.size() != SOURCE_KEYS.size() or not stored.has_all(SOURCE_KEYS) or stored.encoding != SOURCE_ENCODING \
			or not SurvivalContracts.integer(stored.unpacked_bytes, 1, RunSave.MAX_BYTES) \
			or not SurvivalContracts.integer(stored.compressed_bytes, 18, RunSave.MAX_BYTES) \
			or not stored.data is String or stored.data.length() != 4 * ceili(float(stored.compressed_bytes) / 3.0): return {}
	for key: String in ["sha256", "compressed_sha256"]:
		if not stored[key] is String or stored[key].length() != 64 or not stored[key].is_valid_hex_number(false) or stored[key] != stored[key].to_lower(): return {}
	if not _source_base64(stored.data): return {}
	var compressed: PackedByteArray = Marshalls.base64_to_raw(stored.data)
	if compressed.size() != int(stored.compressed_bytes) or Marshalls.raw_to_base64(compressed) != stored.data or _source_bytes_hash(compressed) != stored.compressed_sha256: return {}
	# New sources use the engine's fixed GZIP writer (no optional header sections).
	# Check format and declared output length before invoking the bounded inflater.
	if compressed[0] != 0x1f or compressed[1] != 0x8b or compressed[2] != 8 or compressed[3] != 0 \
			or compressed.decode_u32(compressed.size() - 4) != int(stored.unpacked_bytes): return {}
	var cache_key: String = RecordEncoding.fingerprint(stored)
	var cached: Variant = ActionMemo.lookup(_decoded_sources, cache_key)
	if cached != null: return cached.duplicate(true)
	# The verified length bounds allocation; fixed inflate also terminates on suffixes.
	var raw: PackedByteArray = compressed.decompress(int(stored.unpacked_bytes), FileAccess.COMPRESSION_GZIP)
	if raw.size() != int(stored.unpacked_bytes): return {}
	if raw.compress(FileAccess.COMPRESSION_GZIP) != compressed: return {}
	var exact: String = raw.get_string_from_utf8()
	if exact.to_utf8_buffer() != raw or exact.sha256_text() != stored.sha256: return {}
	var parser: JSON = JSON.new()
	if parser.parse(exact) != OK or not parser.data is Dictionary: return {}
	var decoded: Dictionary = RecordEncoding.unpack(parser.data)
	if decoded.get("error") != OK or not decoded.get("payload") is Dictionary: return {}
	var action: Dictionary = decoded.payload
	if not SurvivalContracts.integer(action.get("version"), 9, 9) or not action.get("economy_source") is Dictionary or RecordEncoding.stringify(action) != exact: return {}
	ActionMemo.store(_decoded_sources, cache_key, action.duplicate(true), 64)
	return action


static func _source_base64(value: String) -> bool:
	if value.is_empty() or value.length() % 4 != 0: return false
	var end: int = value.length()
	var padding: int = 0
	while end > 0 and value.unicode_at(end - 1) == 61:
		padding += 1
		end -= 1
	if padding > 2: return false
	for index: int in range(end):
		var code: int = value.unicode_at(index)
		if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 43 or code == 47): return false
	return true


static func _source_bytes_hash(value: PackedByteArray) -> String:
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(value)
	return digest.finish().hex_encode()


static func source_comparison(ledger: Dictionary) -> Dictionary:
	# Full-source equality permits the unpublished raw debug representation to be read.
	# No source fields or proofs are removed from this comparison.
	var value: Dictionary = ledger.duplicate(true)
	for source: Dictionary in value.get("sources", []):
		var action: Dictionary = source_action(source)
		if action.is_empty(): return {}
		source.action = action
	return value
