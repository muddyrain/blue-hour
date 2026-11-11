class_name WorkshopSiteV1
extends RefCounted
## PROJECT_TEMP. A toolbox attaches to an existing certified optional route.

const VERSION: int = 1
const OPTIONAL_SOURCES: Array[String] = ["optional_building", "vehicle", "fruit_tree"]
const SOURCE_CACHE_LIMIT: int = 128
static var _sources: Dictionary[String, String] = {}


static func site_id(action: Dictionary) -> String:
	if EconomyActions.enabled(action):
		var sources: Array[Dictionary] = EconomyActions.tool_sources(action)
		return String(sources[0].site_id) if not sources.is_empty() else ""
	var marker: Variant = action.get("workshop_tool")
	if not marker is Dictionary or marker.size() != 2 or not marker.has_all(["version", "site_id"]) \
			or not SurvivalContracts.integer(marker.version, VERSION, VERSION) or not marker.site_id is String \
			or not NightHoundV1.enabled(action):
		return ""
	var optional: String = _optional_site(action)
	return optional if optional == marker.site_id else ""


static func freeze(action: Dictionary) -> Dictionary:
	if not NightHoundV1.enabled(action):
		return action
	var optional: String = _optional_site(action)
	if optional.is_empty():
		return action
	var result: Dictionary = action.duplicate(false)
	result.workshop_tool = {"version":VERSION, "site_id":optional}
	return result


static func source_problem(camp: Dictionary, entry: Dictionary) -> String:
	if not WorkshopV1.enabled(camp) or CampFacilities.selected(camp) != CampFacilities.WORKSHOP \
			or not SurvivalContracts.integer(entry.get("sortie"), 2, int(camp.get("settled_sorties", 0))) \
			or entry.get("size") not in NeighborhoodLayout.SIZES or not entry.get("yard") is bool \
			or not entry.get("site_id") is String or String(entry.site_id).is_empty():
		return "WORKSHOP_TOOL_SOURCE"
	var day: int = int(entry.sortie) + 1
	if day < int(camp.journey.campaign.midgame.built_day):
		return "WORKSHOP_TOOL_BEFORE_BUILD"
	var seed: String = camp.journey.seed
	var identity: String = ("daily-v4:%s:%d:%d" % [seed, day, SortieRiskV1.SLOT]).sha256_text()
	if entry.get("action_id") != identity:
		return "WORKSHOP_TOOL_ACTION"
	return "" if entry.site_id == _source_site(seed, day, identity, entry.size, entry.yard) else "WORKSHOP_TOOL_SITE"


static func _source_site(seed: String, day: int, identity: String, size: String, yard: bool) -> String:
	var key: String = "%s:%s:%d" % [identity, size, int(yard)]
	var cached: Variant = ActionMemo.lookup(_sources, key)
	if cached != null:
		return String(cached)
	# Existing day rewards and level geometry are independent of equipment and survivors.
	# The original departure receipt separately proves this map was offered and cleared.
	var task: Dictionary = TaskActions._make(seed, day, SortieRiskV1.SLOT, "airdrop", "industrial", size, 0)
	var action: Dictionary = ExplorationActions.upgrade(WeaponActions._upgrade(task), true, true, 1, yard)
	var optional: String = _optional_site(action)
	ActionMemo.store(_sources, key, optional, SOURCE_CACHE_LIMIT)
	return optional


static func _optional_site(action: Dictionary) -> String:
	var exploration: Variant = action.get("exploration")
	var objective: Variant = action.get("objective")
	if not exploration is Dictionary or not objective is Dictionary or not objective.get("site_ids") is Array \
			or not action.get("sites") is Array:
		return ""
	var level: Variant = exploration.get("level")
	if not level is Dictionary or not level.get("optional") is Dictionary or not level.get("primary") is Array:
		return ""
	var optional: Dictionary = level.optional
	var id: Variant = optional.get("site_id")
	if not id is String or id.is_empty() or id in objective.site_ids or id in level.primary \
			or optional.get("source") not in OPTIONAL_SOURCES or not optional.get("routes") is Dictionary \
			or not optional.routes.has_all(["bus>" + id, id + ">bus"]):
		return ""
	for site: Variant in action.sites:
		if site is Dictionary and site.get("id") == id and site.get("source") == optional.source \
				and site.get("weapon") == false and SurvivalContracts.integer(site.get("amount"), 1, RunSave.MAX_COUNTER):
			return id
	return ""
