class_name InvestigationActions
extends RefCounted
## M18 selects three original task slots and marks one real equipment entrance.

const INVESTIGATION_SLOT: int = 1
const SITE_ID: String = "cash"
const MAX_DAYS_CACHED: int = 8
static var _days: Dictionary[String, Dictionary] = {}


static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_frozen_day(base).get("offers", []).duplicate(true))
	return result


static func matches(base: Dictionary, value: Variant) -> bool:
	if not value is Dictionary or not value.get("id") is String:
		return false
	var expected: String = _frozen_day(base).get("fingerprints", {}).get(value.id, "")
	return not expected.is_empty() and expected == RecordEncoding.fingerprint(value)


static func _frozen_day(base: Dictionary) -> Dictionary:
	if not WorldgenState.level_enabled(base) or not CampaignRules.can_depart(base.journey.campaign):
		return {}
	# Journal replay revisits prior days. Bound these expensive map proofs separately
	# from transient receipt proofs, and key them by the entire exact camp value.
	var identity: String = RecordEncoding.fingerprint(base)
	if identity.is_empty():
		return {}
	if _days.has(identity):
		return _days[identity]
	# The original task/boss generators consume their original frozen phase format.
	var projected: Dictionary = base.duplicate(false)
	projected.journey = base.journey.duplicate(false)
	projected.journey.campaign = CampaignRules.initial(base.profile_id)
	var clue: String = CampaignRules.next_clue(base.journey.campaign)
	var result: Array[Dictionary] = []
	if clue.is_empty():
		projected.journey.campaign.preparations = CampaignRules.PREPARATIONS
		var finale: Array[Dictionary] = ExplorationActions.offers(projected)
		projected.journey.campaign.preparations = 0
		if not finale.is_empty():
			result = _day(projected, clue, finale[0])
	else:
		result = _day(projected, clue)
	if result.is_empty():
		return {}
	var fingerprints: Dictionary[String, String] = {}
	for candidate: Dictionary in result:
		fingerprints[candidate.id] = RecordEncoding.fingerprint(candidate)
	var frozen: Dictionary = {"offers":result, "fingerprints":fingerprints}
	if _days.size() >= MAX_DAYS_CACHED:
		_days.erase(_days.keys()[0])
	_days[identity] = frozen
	return frozen


static func marker_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 3 or not value.has_all(["version", "clue_id", "site_id"]):
		return "INVESTIGATION_ACTION_FIELDS"
	if not SurvivalContracts.integer(value.version, CampaignRules.INVESTIGATION_VERSION, CampaignRules.INVESTIGATION_VERSION):
		return "INVESTIGATION_ACTION_VERSION"
	if not value.clue_id is String or value.clue_id not in CampaignRules.CLUE_IDS or value.site_id != SITE_ID:
		return "INVESTIGATION_ACTION_CLUE"
	return ""


static func site_problem(value: Dictionary) -> String:
	if value.slot != INVESTIGATION_SLOT or value.type != "equipment" or value.campaign.preparations != 0 or value.get("worldgen", {}).get("version") != 2:
		return "INVESTIGATION_ACTION_CONTEXT"
	if value.objective.site_ids != [SITE_ID]:
		return "INVESTIGATION_ACTION_OBJECTIVE"
	for site: Dictionary in value.sites:
		if site.id == SITE_ID and site.work_mode == "indoor" and not site.building.is_empty():
			return ""
	return "INVESTIGATION_ACTION_SITE"


static func _day(projected: Dictionary, clue: String, finale: Dictionary = {}) -> Array[Dictionary]:
	var original: Array[Dictionary] = PersonaActions.offers(projected)
	if original.size() != 3:
		return []
	var recruit: int = 0
	for action: Dictionary in original:
		if action.type == "rescue":
			recruit = int(action.recruit)
			break
	var slots: Array[int] = [0, INVESTIGATION_SLOT, 2]
	var result: Array[Dictionary] = []
	if not finale.is_empty():
		slots.erase(int(finale.slot))
		result.append(finale)
	var extra: Dictionary = original[slots.back()]
	var optional_type: String = "rescue" if recruit > 0 else String(extra.type)
	if optional_type == "supply":
		optional_type = "airdrop"
	for slot: int in slots:
		var investigation: bool = not clue.is_empty() and slot == INVESTIGATION_SLOT
		var task_type: String = "supply" if slot == slots[0] else "equipment" if investigation else optional_type
		var source: Dictionary = _with_type(original[slot], task_type, recruit if task_type == "rescue" else 0)
		if source.is_empty():
			return []
		var offer: Dictionary = ExplorationActions.upgrade(source, true, true)
		if offer.is_empty():
			return []
		if investigation:
			if not site_problem(offer).is_empty():
				return []
			offer.investigation = {"version":CampaignRules.INVESTIGATION_VERSION, "clue_id":clue, "site_id":SITE_ID}
		result.append(offer)
	return result


static func _with_type(source: Dictionary, type: String, recruit: int) -> Dictionary:
	if source.type == type:
		return source
	var topology: String = "industrial" if type == "equipment" and source.layout.topology == "residential" else source.layout.topology
	var task: Dictionary = TaskActions._make(source.seed, int(source.day), int(source.slot), type, topology, source.layout["size"], recruit)
	return ExplorationActions.source_from_task(task, source)
