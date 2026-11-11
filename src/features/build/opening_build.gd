class_name OpeningBuild
extends RefCounted
## One immutable origin in the registered camp. Camp edits still own the slots.

const VERSION: int = 1
const SPECIALTY_VERSION: int = 2
const POLICY_VERSION: int = 1
const PLANS: Dictionary = {
	"scavenge": {"title":"搜集型", "item_id":"field_tools_v1", "unlock_id":"stride_harness_v1", "advice":"先拿口粮，或用省下的时间再搜一处。"},
	"firepower": {"title":"火力型", "item_id":"pressure_rounds_v1", "unlock_id":"guided_mag_v1", "advice":"有装备行动时，先清理来敌，再做露天回收。"},
	"support": {"title":"支援型", "item_id":"aid_kit_v1", "unlock_id":"aid_broadcast_v1", "advice":"用 Q 支援受伤队员，注意治疗冷却。"},
}


static func source(plan: String, run_id: String, root_id: String, seed: String, m47_policy: Dictionary = {}) -> Dictionary:
	if not PLANS.has(plan) or (m47_policy.is_empty() and plan == "support"):
		return {}
	var marker: Dictionary = {"version":VERSION, "plan":plan, "item_id":PLANS[plan].item_id,
		"run_id":run_id, "root_id":root_id, "seed":seed}
	if not m47_policy.is_empty():
		if not policy_valid(m47_policy):
			return {}
		marker.version = SPECIALTY_VERSION
		marker.specialty = m47_policy.duplicate(true)
	return marker


static func policy_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 \
			or not SurvivalContracts.integer(value.get("version"), POLICY_VERSION, POLICY_VERSION) \
			or not value.get("eligible") is Array or value.eligible.size() > PLANS.size():
		return false
	var previous: String = ""
	for id: Variant in value.eligible:
		if not id is String or id <= previous or not PLANS.values().any(func(row: Dictionary) -> bool: return row.unlock_id == id):
			return false
		previous = id
	return true


static func plan(camp: Dictionary) -> String:
	return camp.get("journey", {}).get("build", {}).get("opening", {}).get("plan", "")


static func is_m47(camp: Dictionary) -> bool:
	var marker: Variant = camp.get("journey", {}).get("build", {}).get("opening", {})
	return marker is Dictionary and SurvivalContracts.integer(marker.get("version"), SPECIALTY_VERSION, SPECIALTY_VERSION)


static func eligible(camp: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if is_m47(camp):
		result.assign(camp.journey.build.opening.specialty.eligible)
	return result


static func problem(camp: Dictionary) -> String:
	var marker: Variant = camp.journey.build.opening
	if not WorldgenState.level_enabled(camp) or not CampaignRules.rare_sorties_enabled(camp.journey.get("campaign")):
		return "OPENING_BUILD_MODE"
	if not marker is Dictionary or not marker.get("plan") is String or not PLANS.has(marker.plan):
		return "OPENING_BUILD_PLAN"
	for identity: Variant in [camp.get("profile_id"), camp.journey.get("root_id"), camp.journey.get("seed")]:
		if not identity is String or identity.length() != 32 or not identity.is_valid_hex_number(false):
			return "OPENING_BUILD_IDENTITY"
	var policy: Dictionary = {}
	if is_m47(camp):
		if not policy_valid(marker.get("specialty")) or not camp.journey.build.has("catalog") \
				or not OpenStreetsV1.supported(camp.journey.campaign.get("open_streets_policy")):
			return "OPENING_SPECIALTY_POLICY"
		policy = marker.specialty
	if not TransactionReceipt.same(marker, source(marker.plan, camp.profile_id, camp.journey.root_id, camp.journey.seed, policy)):
		return "OPENING_BUILD_SOURCE"
	var owned: Variant = camp.journey.build.get("owned")
	return "" if owned is Array and not owned.is_empty() and owned[0] == marker.item_id else "OPENING_BUILD_OWNED"


static func registration_problem(camp: Dictionary) -> String:
	var build: Variant = camp.get("journey", {}).get("build")
	if not build is Dictionary or not build.has("opening"):
		return ""
	return "" if camp.settled_sorties == 0 and build.owned == [build.opening.item_id] \
		and build.slots == [build.opening.item_id, ""] else "OPENING_BUILD_REGISTRATION"
