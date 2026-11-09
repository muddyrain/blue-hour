class_name EventSortieV1
extends RefCounted
## PROJECT_TEMP event offer, derived from a certified ordinary equipment action.

const VERSION: int = 1
const TYPE: String = "event"
const TITLE: String = "应急补给站"
const QUIET: String = "quiet"
const FORCE: String = "force"
const QUIET_TITLE: String = "安静取粮"
const FORCE_TITLE: String = "强开物资柜"
const SECONDS: float = 12.0
const REQUESTS: int = 2
const CHOICES: Dictionary = {QUIET: {"food":3, "cash":0}, FORCE: {"food":0, "cash":6}}
const SITE: String = "cash"
const MARKER_KEYS: Array[String] = ["version", "source_id", "source_risk", "site_id", "choices", "seconds", "requests"]


static func selected(seed: String, day: int, slot: int) -> bool:
	if day < 3 or slot != SortieRiskV1.SLOT:
		return false
	var key: String = "event-sortie:%d:%s:%d:%d" % [VERSION, seed, day, slot]
	return key.sha256_text().left(1).hex_to_int() % 4 == 0


static func site_id(action: Dictionary) -> String:
	var marker: Variant = action.get("event_sortie")
	return SITE if action.get("type") == TYPE and marker is Dictionary and marker.get("site_id") == SITE else ""


static func reward(action: Dictionary, branch: String) -> Dictionary:
	if site_id(action).is_empty():
		return {}
	var choices: Variant = action.event_sortie.get("choices")
	var offer: Variant = choices.get(branch) if choices is Dictionary else null
	return offer.duplicate() if offer is Dictionary else {}


static func marker_problem(marker: Variant) -> String:
	if not marker is Dictionary or marker.size() != MARKER_KEYS.size() or not marker.has_all(MARKER_KEYS):
		return "EVENT_SORTIE_FIELDS"
	if not SurvivalContracts.integer(marker.version, VERSION, VERSION) or not marker.site_id is String or marker.site_id != SITE \
			or not marker.source_id is String or marker.source_id.length() != 64 \
			or not marker.source_id.is_valid_hex_number(false) or not marker.source_risk is Dictionary \
			or not SurvivalContracts.number(marker.seconds) or marker.seconds != SECONDS \
			or not SurvivalContracts.integer(marker.requests, REQUESTS, REQUESTS) \
			or not marker.choices is Dictionary or not TransactionReceipt.same(marker.choices, CHOICES):
		return "EVENT_SORTIE_CONFIG"
	var risk: Dictionary = marker.source_risk
	if not risk.is_empty() and (risk.size() != SortieRiskV1.MARKER_KEYS.size() or not risk.has_all(SortieRiskV1.MARKER_KEYS) \
			or not risk.topology is String or risk.topology not in NeighborhoodLayout.TOPOLOGIES \
			or not risk.yard is bool or (risk.yard and risk.topology != "industrial")):
		return "EVENT_SORTIE_SOURCE"
	return ""


static func freeze(source: Dictionary) -> Dictionary:
	if source.get("version") != 9 or source.get("mission_policy") != 1 or source.get("type") != "airdrop" \
			or source.has("rare_policy") or source.has("investigation") or source.has("finale_policy") \
			or source.get("recruit") != 0 or source.get("campaign", {}).get("is_finale") != false \
			or not selected(source.seed, int(source.day), int(source.slot)) or source.objective.site_ids != [SITE]:
		return {}
	var result: Dictionary = source.duplicate(true)
	var station: Dictionary = {}
	for site: Dictionary in result.sites:
		if site.id == SITE:
			station = site
			break
	var point: Variant = station.get("point")
	if station.get("source") != "primary" or station.get("kind") != "cash" or station.get("work_mode") != "outdoor" \
			or station.get("building") != "" or station.get("weapon") != true or not point is Array or point.size() != 2 \
			or not SurvivalContracts.number(point[0]) or not SurvivalContracts.number(point[1]) \
			or not WorldLayout.rect(result.layout.bounds).has_point(WorldLayout.point(point)):
		return {}
	result.event_sortie = {"version":VERSION, "source_id":source.id, "source_risk":source.get("sortie_risk", {}).duplicate(),
		"site_id":SITE, "choices":CHOICES.duplicate(true), "seconds":SECONDS, "requests":REQUESTS}
	result.erase("sortie_risk")
	result.type = TYPE
	result.id = ("event-sortie:%s:%s" % [source.layout.id, RecordEncoding.fingerprint(result.event_sortie)]).sha256_text()
	result.objective.task_id = result.id
	result.parameters = {"event_seconds":SECONDS, "source":"PROJECT_TEMP"}
	result.cash -= station.amount
	result.exploration.primary.cash -= station.amount
	result.exploration.primary.weapons = 0
	result.weapons = 0
	station.amount = 0
	station.weapon = false
	station.seconds = SECONDS
	station.erase("drop")
	result.powers.sample = ""
	result.build.drops = []
	result.exploration.level = LevelSummary.freeze(result.layout, result.sites, result.objective, TYPE)
	return {} if result.exploration.level.is_empty() else result
