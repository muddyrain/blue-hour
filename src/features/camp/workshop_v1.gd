class_name WorkshopV1
extends RefCounted
## PROJECT_TEMP. Each settled tool can be spent on exactly one inventory instance.

const VERSION: int = 1
const COST: int = 8
const EXTENDED: String = "extended_mag"
const QUICK: String = "quick_mag"
const ENTRY_KEYS: Array[String] = ["sortie", "action_id", "site_id", "size", "yard", "instance_id", "mod"]


static func initial() -> Dictionary:
	return {"version":VERSION, "tools":[]}


static func enabled(camp: Dictionary) -> bool:
	var value: Variant = camp.get("journey", {}).get("campaign", {}).get("workshop")
	return value is Dictionary and SurvivalContracts.integer(value.get("version"), VERSION, VERSION)


static func marker_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 2 or not value.has_all(["version", "tools"]) \
			or not SurvivalContracts.integer(value.version, VERSION, VERSION) or not value.tools is Array:
		return "WORKSHOP_POLICY_FIELDS"
	return ""


static func problem(camp: Dictionary) -> String:
	if EconomyBuildV1.enabled(camp): return "" if TransactionReceipt.same(camp.journey.campaign.workshop, initial()) else "ECONOMY_LEGACY_WORKSHOP_CHANGED"
	var campaign: Dictionary = camp.get("journey", {}).get("campaign", {})
	if not campaign.has("workshop"):
		return ""
	if not NightHoundV1.campaign_enabled(campaign) or not marker_problem(campaign.workshop).is_empty():
		return "WORKSHOP_CAMP_POLICY"
	var ledger: Array = campaign.workshop.tools
	if ledger.is_empty():
		return ""
	if CampFacilities.selected(camp) != CampFacilities.WORKSHOP:
		return "WORKSHOP_TOOL_FACILITY"
	var first_sortie: int = int(campaign.midgame.built_day) - 1
	var previous: int = first_sortie - 1
	var installed: Dictionary[String, bool] = {}
	for entry: Variant in ledger:
		if not entry is Dictionary or entry.size() != ENTRY_KEYS.size() or not entry.has_all(ENTRY_KEYS) \
				or not SurvivalContracts.integer(entry.sortie, previous + 1, int(camp.settled_sorties)) \
				or not entry.action_id is String or not entry.site_id is String \
				or not entry.size is String or not entry.yard is bool \
				or not entry.instance_id is String or not entry.mod is String:
			return "WORKSHOP_TOOL_FIELDS"
		var source_issue: String = WorkshopSiteV1.source_problem(camp, entry)
		if not source_issue.is_empty():
			return source_issue
		previous = int(entry.sortie)
		if entry.instance_id.is_empty():
			if not entry.mod.is_empty():
				return "WORKSHOP_MOD_FIELDS"
			continue
		var item: Dictionary = WeaponInventory.find(camp, entry.instance_id)
		if not _supported_instance(camp, item) or item.get("condition") != "ready" \
				or entry.mod not in [EXTENDED, QUICK] or installed.has(entry.instance_id):
			return "WORKSHOP_MOD_SOURCE"
		installed[entry.instance_id] = true
	return ""


static func tools(camp: Dictionary) -> int:
	if EconomyBuildV1.enabled(camp): return EconomyBuildV1.tools(camp)
	if not enabled(camp):
		return 0
	var available: int = 0
	for entry: Dictionary in camp.journey.campaign.workshop.tools:
		available += int(entry.instance_id.is_empty())
	return available


static func mod_for(camp: Dictionary, instance_id: String) -> String:
	if EconomyBuildV1.enabled(camp): return String(WeaponInventory.find(camp, instance_id).get("economy", {}).get("magazine", ""))
	if enabled(camp) and not instance_id.is_empty():
		for entry: Dictionary in camp.journey.campaign.workshop.tools:
			if entry.instance_id == instance_id:
				return entry.mod
	return ""


static func name_for(mod: String) -> String:
	return "扩容弹匣" if mod == EXTENDED else "快拆弹匣" if mod == QUICK else "原装弹匣"


static func _supported_instance(camp: Dictionary, item: Dictionary) -> bool:
	return item.get("weapon_id") == "carbine" or (item.get("weapon_id") == "long_rifle"
		and CampFacilities.upgraded(camp) and item.get("quality") == "common" and item.get("affixes") == [])


static func mod_problem(camp: Dictionary, instance_id: String, mod: String) -> String:
	if EconomyBuildV1.enabled(camp): return String(EconomyBuildV1.offer(camp, "magazine", instance_id, mod).reason)
	if not enabled(camp) or CampFacilities.selected(camp) != CampFacilities.WORKSHOP:
		return "需要已建工坊"
	if CampaignState.ended(camp) or camp.journey.state != "ACTIVE":
		return "当前旅程无法改装"
	if mod not in [EXTENDED, QUICK]:
		return "改装方案无效"
	var item: Dictionary = WeaponInventory.find(camp, instance_id)
	if item.is_empty():
		return "该武器实例已失效"
	if item.weapon_id == "long_rifle" and CampFacilities.tier_two_enabled(camp):
		if not CampFacilities.upgraded(camp):
			return "长管步枪改装需要二级工坊的校准台"
		if not _supported_instance(camp, item):
			return "校准台仅接受无词条的普通长管步枪"
	elif item.weapon_id != "carbine":
		return "请选择卡宾枪或普通长管步枪" if CampFacilities.upgraded(camp) else "请选择一把卡宾枪"
	var owner: int = WeaponInventory.owner(camp, instance_id)
	if owner > 0 and not WeaponInventory._living(camp, owner):
		return "历史队员的配装仅供查阅"
	var gun: String = WeaponInventory.definition(item.weapon_id).display_name
	if item.get("condition") != "ready":
		return "先维修这把%s" % gun
	if not mod_for(camp, instance_id).is_empty():
		return "这把%s已改装" % gun
	if tools(camp) < 1:
		return "需要工具箱 ×1"
	if int(camp.cash) < COST:
		return "还差 %d 币" % (COST - int(camp.cash))
	return ""


static func install(before: Dictionary, instance_id: String, mod: String) -> Dictionary:
	if EconomyBuildV1.enabled(before): return {} # M48 uses an edit-bound economy intent.
	if not mod_problem(before, instance_id, mod).is_empty():
		return {}
	var after: Dictionary = before.duplicate(true)
	for entry: Dictionary in after.journey.campaign.workshop.tools:
		if entry.instance_id.is_empty():
			entry.instance_id = instance_id
			entry.mod = mod
			break
	after.cash -= COST
	after.camp_spending += COST
	return after


static func recovered(action: Dictionary, report: Dictionary) -> bool:
	var site: String = WorkshopSiteV1.site_id(action)
	var facts: Variant = report.get("site_facts")
	if site.is_empty() or report.get("evacuated") != true or not facts is Dictionary:
		return false
	var source: Variant = facts.get(site)
	return source is Dictionary and source.get("searched") == true


static func settled(before: Dictionary, action: Dictionary, report: Dictionary) -> Dictionary:
	if EconomyBuildV1.enabled(before): return before.journey.campaign.workshop.duplicate(true)
	var result: Dictionary = before.journey.campaign.workshop.duplicate(true)
	if CampFacilities.selected(before) == CampFacilities.WORKSHOP and recovered(action, report):
		result.tools.append({"sortie":int(before.settled_sorties) + 1, "action_id":action.id,
			"site_id":WorkshopSiteV1.site_id(action), "size":action.layout["size"], "yard":action.worldgen.revision == 2,
			"instance_id":"", "mod":""})
	return result


static func result_problem(before: Dictionary, after: Dictionary, generated: Dictionary, battle: Variant) -> String:
	if enabled(before) != enabled(after):
		return "WORKSHOP_RESULT_POLICY"
	if not enabled(before):
		return ""
	if not battle is Dictionary or not TransactionReceipt.same(after.journey.campaign.workshop, settled(before, generated, battle)):
		return "WORKSHOP_RESULT_SOURCE"
	return ""
