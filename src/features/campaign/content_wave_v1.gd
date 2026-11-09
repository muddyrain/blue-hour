class_name ContentWaveV1
extends RefCounted
## Explicit M38 scope. Legacy camps and frozen actions retain their previous catalogs.

const VERSION: int = 1


static func enabled(camp: Dictionary) -> bool:
	return campaign_enabled(camp.get("journey", {}).get("campaign"))


static func campaign_enabled(campaign: Variant) -> bool:
	return CampaignRules.is_mission(campaign) \
		and SurvivalContracts.integer(campaign.get("content_wave_policy"), VERSION, VERSION)


static func marked(action: Dictionary) -> bool:
	var powers: Variant = action.get("powers")
	return action.get("version") == 9 and action.get("mission_policy") == 1 \
		and SurvivalContracts.integer(action.get("content_wave_policy"), VERSION, VERSION) \
		and powers is Dictionary and powers.get("version") == SpecialPowers.WAVE_VERSION


static func eligible(action: Dictionary) -> bool:
	var campaign: Variant = action.get("campaign")
	var layout: Variant = action.get("layout")
	var sites: Variant = action.get("sites")
	if not marked(action) or action.get("type") != "airdrop" or action.has("rare_policy") \
			or action.has("investigation") or action.has("finale_policy") \
			or not SurvivalContracts.integer(action.get("slot"), 2, 2) \
			or not campaign is Dictionary or campaign.get("is_finale") != false \
			or not layout is Dictionary or layout.get("topology") != "industrial" or not sites is Array \
			or not SurvivalContracts.integer(action.get("day"), 3, RunSave.MAX_COUNTER):
		return false
	for site: Variant in sites:
		if site is Dictionary and site.get("id") == "cash" and site.get("weapon") == true:
			return true
	return false


static func freeze_action(action: Dictionary) -> Dictionary:
	var result: Dictionary = action.duplicate(true)
	result.content_wave_policy = VERSION
	if result.has("rare_policy"):
		result.powers.sample = ""
	if not eligible(result):
		return result
	for site: Dictionary in result.sites:
		if site.id == "cash" and site.weapon:
			site.drop = WeaponInventory.hammer_site_drop(result, site)
			break
	var context: Dictionary = result.build.drop_context
	var pool: int = int(result.build.version)
	result.gear_build_policy = pool
	context.version = pool
	context.liner = true
	result.build.drops = BuildItems.drop(context, result.build.owned, pool)
	return result
