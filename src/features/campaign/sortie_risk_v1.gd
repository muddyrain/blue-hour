class_name SortieRiskV1
extends RefCounted
## PROJECT_TEMP ordinary equipment size policy. Authenticates the original action identity.

const VERSION: int = 1
const SLOT: int = 2
const ROUTINE: String = "routine"
const DEEP: String = "deep"
const MIN_DEEP_ADDED_SECONDS: float = 10.0
const MIN_DEEP_MULTIPLIER: float = 1.2
const MARKER_KEYS: Array[String] = ["version", "tier", "fallback", "topology", "yard"]


static func selection(seed: String, day: int, slot: int) -> String:
	if day < 3 or slot != SLOT:
		return ""
	var key: String = "sortie-risk:%d:%s:%d:%d" % [VERSION, seed, day, slot]
	return ROUTINE if key.sha256_text().left(1).hex_to_int() % 2 == 0 else DEEP


static func enabled(action: Dictionary) -> bool:
	var marker: Variant = action.get("sortie_risk")
	var layout: Variant = action.get("layout")
	var campaign: Variant = action.get("campaign")
	if (not marker is Dictionary or marker.size() != MARKER_KEYS.size() or not marker.has_all(MARKER_KEYS)
			or not SurvivalContracts.integer(marker.version, VERSION, VERSION)
			or not marker.tier is String or marker.tier not in [ROUTINE, DEEP]
			or not marker.fallback is bool or not marker.topology is String
			or marker.topology not in NeighborhoodLayout.TOPOLOGIES or not marker.yard is bool
			or (marker.yard and marker.topology != "industrial")):
		return false
	if (action.get("version") != 9 or action.get("mission_policy") != 1 or action.get("type") != "airdrop"
			or action.get("recruit") != 0 or action.has("rare_policy") or action.has("investigation")
			or action.has("finale_policy") or not campaign is Dictionary or campaign.get("is_finale") != false
			or not action.get("seed") is String or not SurvivalContracts.integer(action.get("day"), 3, RunSave.MAX_COUNTER)
			or not SurvivalContracts.integer(action.get("slot"), SLOT, SLOT) or not layout is Dictionary):
		return false
	var requested: String = selection(action.seed, int(action.day), int(action.slot))
	if marker.tier == DEEP:
		return requested == DEEP and not marker.fallback and layout.get("size") == "large"
	return marker.fallback == (requested == DEEP) and layout.get("size") == "medium"


static func freeze(source: Dictionary, topology: String, yard: bool) -> Dictionary:
	var requested: String = selection(source.seed, int(source.day), int(source.slot))
	if requested.is_empty():
		return {}
	var routine: Dictionary = _map(source, "medium", topology, yard)
	if routine.is_empty() and yard:
		routine = _map(source, "medium", topology, false)
	if routine.is_empty():
		for alternate: String in NeighborhoodLayout.TOPOLOGIES:
			if alternate == topology:
				continue
			routine = _map(source, "medium", alternate, false)
			if not routine.is_empty():
				break
	if routine.is_empty():
		return {}
	if requested == DEEP:
		var deep: Dictionary = _map(source, "large", routine.layout.topology, routine.layout.has("loading_yard"))
		if not deep.is_empty() and _deep_fits(routine, deep):
			return _marked(deep, DEEP, false, topology, yard)
	return _marked(routine, ROUTINE, requested == DEEP, topology, yard)


static func round_trip_seconds(level: Dictionary) -> float:
	var routes: Dictionary = level.routes
	return (float(routes["bus>cash"].length) + float(routes["cash>bus"].length)) / float(level.assumptions.speed)


static func _map(source: Dictionary, size: String, topology: String, yard: bool) -> Dictionary:
	var task: Dictionary = TaskActions._make(source.seed, int(source.day), int(source.slot), "airdrop", topology, size, 0)
	var original: Dictionary = ExplorationActions.source_from_task(task, source)
	return {} if original.is_empty() else ExplorationActions.upgrade(original, true, true, 1, yard)


static func _deep_fits(routine: Dictionary, deep: Dictionary) -> bool:
	var level: Dictionary = deep.exploration.level
	var baseline: float = round_trip_seconds(routine.exploration.level)
	var distance_seconds: float = round_trip_seconds(level)
	if distance_seconds < maxf(baseline + MIN_DEEP_ADDED_SECONDS, baseline * MIN_DEEP_MULTIPLIER):
		return false
	if level.optional.added_team_seconds <= 0.0 or level.optional.added_serial_length <= 0.0:
		return false
	for site: Dictionary in deep.sites:
		if site.id == level.optional.site_id:
			return site.amount > 0 and not site.weapon
	return false


static func _marked(offer: Dictionary, tier: String, fallback: bool, topology: String, yard: bool) -> Dictionary:
	offer.sortie_risk = {"version":VERSION, "tier":tier, "fallback":fallback, "topology":topology, "yard":yard}
	return offer
