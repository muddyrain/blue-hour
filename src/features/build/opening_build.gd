class_name OpeningBuild
extends RefCounted
## One immutable origin in the registered camp. Camp edits still own the slots.

const VERSION: int = 1
const PLANS: Dictionary = {
	"scavenge": {"title":"搜集型", "item_id":"field_tools_v1", "advice":"先拿口粮，或用省下的时间再搜一处。"},
	"firepower": {"title":"火力型", "item_id":"pressure_rounds_v1", "advice":"有装备行动时，先清理来敌，再做露天回收。"},
}


static func source(plan: String, run_id: String, root_id: String, seed: String) -> Dictionary:
	if not PLANS.has(plan):
		return {}
	return {"version":VERSION, "plan":plan, "item_id":PLANS[plan].item_id,
		"run_id":run_id, "root_id":root_id, "seed":seed}


static func problem(camp: Dictionary) -> String:
	var marker: Variant = camp.journey.build.opening
	if not WorldgenState.level_enabled(camp) or not CampaignRules.rare_sorties_enabled(camp.journey.get("campaign")):
		return "OPENING_BUILD_MODE"
	if not marker is Dictionary or not marker.get("plan") is String or not PLANS.has(marker.plan):
		return "OPENING_BUILD_PLAN"
	for identity: Variant in [camp.get("profile_id"), camp.journey.get("root_id"), camp.journey.get("seed")]:
		if not identity is String or identity.length() != 32 or not identity.is_valid_hex_number(false):
			return "OPENING_BUILD_IDENTITY"
	if not TransactionReceipt.same(marker, source(marker.plan, camp.profile_id, camp.journey.root_id, camp.journey.seed)):
		return "OPENING_BUILD_SOURCE"
	var owned: Variant = camp.journey.build.get("owned")
	return "" if owned is Array and not owned.is_empty() and owned[0] == marker.item_id else "OPENING_BUILD_OWNED"


static func registration_problem(camp: Dictionary) -> String:
	var build: Variant = camp.get("journey", {}).get("build")
	if not build is Dictionary or not build.has("opening"):
		return ""
	return "" if camp.settled_sorties == 0 and build.owned == [build.opening.item_id] \
		and build.slots == [build.opening.item_id, ""] else "OPENING_BUILD_REGISTRATION"
