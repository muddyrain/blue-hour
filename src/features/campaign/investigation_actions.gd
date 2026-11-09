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
	var mission: bool = CampaignRules.is_mission(base.journey.campaign)
	var industrial: bool = mission and WorldgenState.industrial_yard_enabled(base)
	var action_choices: bool = CampaignRules.action_choices_enabled(base.journey.campaign)
	var midgame: bool = CampaignRules.midgame_enabled(base.journey.campaign)
	var gear_build: bool = base.journey.build.has("opening")
	var sortie_risk: bool = CampaignRules.sortie_risk_enabled(base.journey.campaign)
	var clue: String = CampaignRules.next_clue(base.journey.campaign)
	var result: Array[Dictionary] = []
	if clue.is_empty():
		projected.journey.campaign.preparations = CampaignRules.PREPARATIONS
		var finale: Array[Dictionary] = ExplorationActions.offers(projected)
		projected.journey.campaign.preparations = 0
		if not finale.is_empty():
			var selected: Dictionary = PumpStationAction.freeze(finale[0]) if CampaignRules.pump_station_enabled(base.journey.campaign) else finale[0]
			if not selected.is_empty():
				result = _day(projected, clue, mission, industrial, action_choices, midgame, selected, "", gear_build, sortie_risk)
	else:
		var rare_type: String = RareSortie.selection(base.journey.seed, int(base.day), RareSortie.SLOT) if CampaignRules.rare_sorties_enabled(base.journey.campaign) else ""
		result = _day(projected, clue, mission, industrial, action_choices, midgame, {}, rare_type, gear_build, sortie_risk)
	if result.is_empty():
		return {}
	var fingerprints: Dictionary[String, String] = {}
	var screamer: bool = CampaignRules.screamer_enabled(base.journey.campaign)
	var weapon_affixes: bool = CampaignRules.weapon_affix_enabled(base.journey.campaign)
	var first_aid: bool = CampaignRules.first_aid_enabled(base.journey.campaign) and FirstAidV1.qualified(base)
	var campaign_pressure: bool = CampaignRules.campaign_pressure_enabled(base.journey.campaign)
	var content_wave: bool = ContentWaveV1.enabled(base)
	var night_hound: bool = NightHoundV1.campaign_enabled(base.journey.campaign)
	var workshop: bool = WorkshopV1.enabled(base) and CampFacilities.selected(base) == CampFacilities.WORKSHOP
	for index: int in range(result.size()):
		var candidate: Dictionary = result[index]
		if screamer and ScreamerPolicyV1.eligible(candidate):
			candidate.screamer_policy = ScreamerPolicyV1.VERSION
		if first_aid and candidate.get("version") == 9:
			candidate.first_aid_policy = FirstAidV1.VERSION
		if campaign_pressure and candidate.get("version") == 9:
			candidate.campaign_pressure = CampaignPressureV1.marker(int(base.settled_sorties))
		if content_wave and candidate.get("version") == 9:
			candidate = ContentWaveV1.freeze_action(candidate)
		if night_hound and ContentWaveV1.eligible(candidate):
			candidate.night_hound_policy = NightHoundV1.VERSION
		if workshop:
			candidate = WorkshopSiteV1.freeze(candidate)
		if weapon_affixes and not ContentWaveV1.eligible(candidate) and WeaponInventory.affix_eligible(candidate):
			candidate.weapon_affix_policy = WeaponInventory.AFFIX_POLICY_VERSION
		result[index] = candidate
		fingerprints[candidate.id] = RecordEncoding.fingerprint(candidate)
	var frozen: Dictionary = {"offers":result, "fingerprints":fingerprints}
	if _days.size() >= MAX_DAYS_CACHED:
		_days.erase(_days.keys()[0])
	_days[identity] = frozen
	return frozen


static func marker_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 3 or not value.has_all(["version", "clue_id", "site_id"]):
		return "INVESTIGATION_ACTION_FIELDS"
	if not SurvivalContracts.integer(value.version, CampaignRules.INVESTIGATION_VERSION, CampaignRules.MISSION_VERSION):
		return "INVESTIGATION_ACTION_VERSION"
	if not value.clue_id is String or value.clue_id not in CampaignRules.CLUE_IDS or value.site_id != SITE_ID:
		return "INVESTIGATION_ACTION_CLUE"
	return ""


static func site_problem(value: Dictionary) -> String:
	if value.slot != INVESTIGATION_SLOT or value.type != "equipment" or value.campaign.preparations != 0 or value.get("worldgen", {}).get("version") != 2:
		return "INVESTIGATION_ACTION_CONTEXT"
	var version: int = CampaignRules.MISSION_VERSION if value.get("mission_policy") == 1 else CampaignRules.INVESTIGATION_VERSION
	if value.investigation.version != version:
		return "INVESTIGATION_ACTION_POLICY"
	if value.objective.site_ids != [SITE_ID]:
		return "INVESTIGATION_ACTION_OBJECTIVE"
	for site: Dictionary in value.sites:
		if site.id == SITE_ID and site.work_mode == "indoor" and not site.building.is_empty():
			return ""
	return "INVESTIGATION_ACTION_SITE"


static func _day(projected: Dictionary, clue: String, mission: bool, industrial: bool,
		action_choices: bool, midgame: bool, finale: Dictionary = {}, rare_type: String = "",
		gear_build: bool = false, sortie_risk: bool = false) -> Array[Dictionary]:
	var original: Array[Dictionary] = PersonaActions.offers(projected)
	if original.size() != 3:
		return []
	var recruit: int = 0
	for action: Dictionary in original:
		if action.type == "rescue":
			recruit = int(action.recruit)
			break
	var slots: Array[int] = [0, INVESTIGATION_SLOT, 2]
	if mission and not clue.is_empty():
		# Display supplies, the optional action, then investigation. Its signed slot stays 1.
		slots = [0, 2, INVESTIGATION_SLOT]
	var result: Array[Dictionary] = []
	if not finale.is_empty():
		slots.erase(int(finale.slot))
		result.append(finale)
	var extra: Dictionary = original[slots.back()]
	var optional_type: String = "rescue" if recruit > 0 else String(extra.type)
	if mission:
		optional_type = "rescue" if recruit > 0 and projected.day > 2 else "airdrop"
	if optional_type == "supply":
		optional_type = "airdrop"
	for slot: int in slots:
		var investigation: bool = not clue.is_empty() and slot == INVESTIGATION_SLOT
		var task_type: String = "supply" if slot == slots[0] else "equipment" if investigation else optional_type
		var offer: Dictionary
		if action_choices and slot != slots[0] and not investigation:
			if not rare_type.is_empty():
				var yard: bool = rare_type == "airdrop"
				var source: Dictionary = _with_type(original[slot], rare_type, 0,
					"industrial" if yard else "commercial", "medium" if yard else "large")
				if not source.is_empty():
					offer = ExplorationActions.upgrade(source, true, true, 1, yard, false, RareSortie.VERSION)
			if offer.is_empty():
				offer = _choice_offer(projected, original[slot], industrial, midgame, sortie_risk)
		else:
			offer = _offer(original[slot], task_type, recruit if task_type == "rescue" else 0, mission, industrial)
		if offer.is_empty():
			return []
		if gear_build and offer.type == "airdrop" and not offer.has("rare_policy"):
			offer = BuildActions.with_gear_drops(offer)
		if investigation:
			var version: int = CampaignRules.MISSION_VERSION if mission else CampaignRules.INVESTIGATION_VERSION
			offer.investigation = {"version":version, "clue_id":clue, "site_id":SITE_ID}
			if not site_problem(offer).is_empty():
				return []
		result.append(offer)
	return result


static func _choice_offer(base: Dictionary, source: Dictionary, industrial: bool, midgame: bool,
		sortie_risk: bool) -> Dictionary:
	var key: String = "m25-action-choice:%s:%d" % [base.journey.seed, int(base.day)]
	if key.sha256_text().left(1).hex_to_int() % 2 == 0:
		var transaction: String = "%s:%d" % [base.profile_id, int(base.settled_sorties) + 1]
		var recruit: int = RescuePoolState.choice(base, transaction)
		if recruit > 0:
			var rescue: Dictionary = _offer(source, "rescue", recruit, true, industrial, midgame)
			if not rescue.is_empty():
				return rescue
	if sortie_risk and not SortieRiskV1.selection(source.seed, int(source.day), int(source.slot)).is_empty():
		var topology: String = source.layout.topology
		var risk_offer: Dictionary = SortieRiskV1.freeze(source, topology, industrial and topology == "industrial")
		if not risk_offer.is_empty():
			return risk_offer
	return _offer(source, "airdrop", 0, true, industrial)


static func _offer(source: Dictionary, type: String, recruit: int, mission: bool,
		industrial: bool, residential_rescue: bool = false) -> Dictionary:
	var topology: String = "industrial" if type == "equipment" and source.layout.topology == "residential" else source.layout.topology
	if residential_rescue:
		topology = "residential"
	var size: String = source.layout["size"]
	var yard: bool = industrial and type == "airdrop" and topology == "industrial"
	var candidate: Dictionary = _with_type(source, type, recruit, topology, size)
	var offer: Dictionary = ExplorationActions.upgrade(candidate, true, true, int(mission), yard, residential_rescue) if not candidate.is_empty() else {}
	if not mission or not offer.is_empty():
		return offer
	# Keep the day and reward identity. Only retry the existing layout themes and sizes
	# when the preferred layout cannot certify all of the required work entrances.
	var sizes: Array[String] = NeighborhoodLayout.SIZES.duplicate()
	sizes.erase(size)
	sizes.push_front(size)
	for alternate_size: String in sizes:
		for alternate_theme: String in NeighborhoodLayout.TOPOLOGIES:
			if (alternate_size == size and alternate_theme == topology) or (type == "equipment" and alternate_theme == "residential"):
				continue
			if (yard or residential_rescue) and alternate_theme != topology:
				continue
			candidate = _with_type(source, type, recruit, alternate_theme, alternate_size)
			if candidate.is_empty():
				continue
			offer = ExplorationActions.upgrade(candidate, true, true, 1, yard, residential_rescue)
			if not offer.is_empty():
				return offer
	# An uncertifiable plot cannot remove the original day's playable gear offer.
	return _offer(source, type, recruit, mission, false) if yard else {}


static func _with_type(source: Dictionary, type: String, recruit: int, topology: String, size: String) -> Dictionary:
	if source.type == type and int(source.recruit) == recruit and source.layout.topology == topology and source.layout["size"] == size:
		return source
	var task: Dictionary = TaskActions._make(source.seed, int(source.day), int(source.slot), type, topology, size, recruit)
	return ExplorationActions.source_from_task(task, source)
