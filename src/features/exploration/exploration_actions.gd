class_name ExplorationActions
extends RefCounted
## V9 authenticates the new full description, never claims new geometry is old V3.
static var _checked: Dictionary = {}
static var _origins: Dictionary = {}

static func origin(value: Dictionary) -> Dictionary:
	# Reconstruct the original frozen reward/capability source without storing a
	# duplicate obsolete map in every new receipt. Validate it before projection.
	var source_type: String = "airdrop" if value.type == EventSortieV1.TYPE else value.type
	var key: String=SurvivalContracts.fingerprint({"seed":value.seed,"day":value.day,"slot":value.slot,"type":source_type,"size":value.layout["size"],"topology":value.layout.topology,"recruit":value.recruit,"campaign":value.campaign,"build":value.build,"powers":value.powers,"persona":value.persona})
	if _origins.has(key): return _origins[key].duplicate(true)
	var task: Dictionary=TaskActions._make(value.seed,int(value.day),int(value.slot),source_type,value.layout.topology,value.layout["size"],int(value.recruit))
	var source: Dictionary=source_from_task(task,value)
	if source.is_empty(): return {}
	if not PersonaActions.problem(source).is_empty(): return {}
	if _origins.size()>=64: _origins.clear()
	_origins[key]=source.duplicate(true)
	return source

static func source_from_task(task: Dictionary, context: Dictionary) -> Dictionary:
	if task.is_empty():
		return {}
	var source: Dictionary = CampaignActions._upgrade(WeaponActions._upgrade(task), context.campaign.run_id, int(context.campaign.preparations))
	source = CombatActions.upgrade(BuildActions.upgrade(source, context.build.owned, context.build.slots, int(context.build.get("version", 1))))
	source = PowerActions.upgrade(source, context.powers.owned, PowerState.loadout(context.powers))
	return PersonaActions.upgrade(source, context.persona.facts)

static func upgrade(source: Dictionary, worldgen: bool = false, level: bool = false,
		mission_policy: int = 0, industrial: bool = false, residential_rescue: bool = false,
		rare_policy: int = 0) -> Dictionary:
	if mission_policy != 0 and (mission_policy != 1 or not worldgen or not level):
		return {}
	if industrial and (mission_policy != 1 or source.type != "airdrop" or source.layout.topology != "industrial"):
		return {}
	if residential_rescue and (mission_policy != 1 or source.type != "rescue" or source.layout.topology != "residential"):
		return {}
	var value: Dictionary=source.duplicate(true)
	value.version=9
	if rare_policy != 0:
		if rare_policy != RareSortie.VERSION or mission_policy != 1 or source.recruit != 0 \
				or RareSortie.selection(source.seed, int(source.day), int(source.slot)) != source.type:
			return {}
		var required_topology: String = "industrial" if industrial else "commercial"
		var required_size: String = "medium" if industrial else "large"
		if industrial != (source.type == "airdrop") or source.layout.topology != required_topology or source.layout["size"] != required_size:
			return {}
		value.rare_policy = rare_policy
		value.id = ("rare-sortie:%d:%s:%s" % [rare_policy, source.id, source.type]).sha256_text()
	if mission_policy == 1:
		value.mission_policy = mission_policy
		if value.type == "equipment" or (rare_policy != 0 and value.type == "supply"):
			value.weapons = 0
	var content: Dictionary = {}
	if level:
		for attempt: int in range(4):
			value.layout = WorldgenLayout._assemble("BH_LEVEL_V1:" + value.id, source.layout["size"],
				source.layout.topology, mini(attempt, 2), attempt == 3, source.type, industrial, residential_rescue)
			if value.layout.is_empty():
				continue
			content=ExplorationSites.generate(value.layout,value.type,int(source.cash),int(source.food),int(source.weapons),value.id,mission_policy,rare_policy)
			if not content.is_empty():
				var extra: String = "" if rare_policy == 0 else "food_2" if value.type == "supply" else "cash_2"
				content.level=LevelSummary.freeze(value.layout,content.sites,content.objective,value.type,extra)
				if not content.level.is_empty() and (extra != "food_2" or RareSortie.cold_route_fits(content.level)):
					break
				content={}
	else:
		value.layout=WorldgenLayout.generate("BH_WORLDGEN_V1:"+source.id,source.layout["size"],source.layout.topology) if worldgen else ExplorationLayout.generate("BH_EXPLORATION_V1:"+source.id,source.layout["size"],source.layout.topology)
		if value.layout.is_empty():
			return {}
		content=ExplorationSites.generate(value.layout,value.type,int(source.cash),int(source.food),int(source.weapons),value.id)
	if content.is_empty(): return {}
	value.sites=content.sites
	value.objective=content.objective
	value.objective.member_id=value.recruit
	value.cash=0
	value.food=0
	for site: Dictionary in value.sites:
		if site.weapon:
			for original: Dictionary in source.sites:
				if original.id=="cash": site.drop=original.drop.duplicate(true)
		if site.kind=="cash": value.cash+=int(site.amount)
		else: value.food+=int(site.amount)
	value.route_length=0
	for metric: Dictionary in content.metrics.routes.values(): value.route_length=maxi(value.route_length,int(metric.length))
	value.exploration={"version":1,"policy":ExplorationLayout.policy(),"primary":{"cash":source.cash,"food":source.food,"weapons":value.weapons},"optional_objectives":content.optional_objectives,"metrics":content.metrics}
	if level:
		value.exploration.level=content.level
	if worldgen: value.worldgen = WorldgenLayout.policy(level, industrial, residential_rescue)
	return value

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for source: Dictionary in PersonaActions.offers(base):
		result.append(source if source.campaign.is_finale else upgrade(source,WorldgenState.enabled(base),WorldgenState.level_enabled(base)))
	return result

static func problem(value: Variant, camp_source: bool = false) -> String:
	if value is Dictionary:
		if value.has("event_sortie") != (value.get("type") == EventSortieV1.TYPE):
			return "EVENT_SORTIE_TYPE"
		var powers: Variant = value.get("powers")
		var wave_power: bool = powers is Dictionary and powers.get("version") == SpecialPowers.WAVE_VERSION
		if (value.has("content_wave_policy") and not ContentWaveV1.marked(value)) \
				or value.has("content_wave_policy") != wave_power:
			return "CONTENT_WAVE_ACTION_POLICY"
		if value.has("night_hound_policy") and not NightHoundV1.enabled(value):
			return "HOUND_ACTION_POLICY"
		if value.has("workshop_tool") and WorkshopSiteV1.site_id(value).is_empty():
			return "WORKSHOP_TOOL_ACTION"
	if value is Dictionary and value.has("screamer_policy") and not ScreamerPolicyV1.enabled(value):
		return "SCREAMER_ACTION_POLICY"
	if value is Dictionary and value.has("weapon_affix_policy") and not WeaponInventory.affix_enabled(value):
		return "WEAPON_AFFIX_ACTION_POLICY"
	if value is Dictionary and value.has("first_aid_policy") and not FirstAidV1.enabled(value):
		return "FIRST_AID_ACTION_POLICY"
	if value is Dictionary and value.has("sortie_risk") and not SortieRiskV1.enabled(value):
		return "SORTIE_RISK_ACTION_POLICY"
	if value is Dictionary and value.has("campaign_pressure") and not CampaignPressureV1.enabled(value):
		return "CAMPAIGN_PRESSURE_ACTION_POLICY"
	if value is Dictionary and value.has("recon") and not ReconActionV1.enabled(value):
		return "RECON_ACTION_POLICY"
	if value is Dictionary and value.has("finale_policy"):
		return PumpStationAction.problem(value)
	if value is Dictionary and value.has("investigation"):
		var issue: String = InvestigationActions.marker_problem(value.investigation)
		if not issue.is_empty():
			return issue
		var projected: Dictionary = value.duplicate(false)
		projected.erase("investigation")
		issue = _problem(projected, camp_source)
		return InvestigationActions.site_problem(value) if issue.is_empty() else issue
	if value is Dictionary and value.has("mission_policy") and value.get("type") == "equipment":
		return "MISSION_INVESTIGATION_REQUIRED"
	return _problem(value, camp_source)

static func _problem(value: Variant, camp_source: bool) -> String:
	var worldgen: bool=value is Dictionary and value.has("worldgen")
	var level: bool=worldgen and value.worldgen is Dictionary and value.worldgen.get("version")==2
	var industrial: bool = level and value.worldgen.get("revision") == 2
	var residential_rescue: bool = level and value.worldgen.get("revision") == 3
	var mission: bool = value is Dictionary and value.has("mission_policy")
	var rare: bool = value is Dictionary and value.has("rare_policy")
	var gear_build: bool = value is Dictionary and value.has("gear_build_policy")
	var screamer: bool = value is Dictionary and value.has("screamer_policy")
	var weapon_affixes: bool = value is Dictionary and value.has("weapon_affix_policy")
	var first_aid: bool = value is Dictionary and value.has("first_aid_policy")
	var sortie_risk: bool = value is Dictionary and value.has("sortie_risk")
	var campaign_pressure: bool = value is Dictionary and value.has("campaign_pressure")
	var content_wave: bool = value is Dictionary and value.has("content_wave_policy")
	var night_hound: bool = value is Dictionary and value.has("night_hound_policy")
	var workshop_tool: bool = value is Dictionary and value.has("workshop_tool")
	var event_sortie: bool = value is Dictionary and value.has("event_sortie")
	var recon: bool = value is Dictionary and value.has("recon")
	if event_sortie:
		var issue: String = EventSortieV1.marker_problem(value.event_sortie)
		if not issue.is_empty():
			return issue
		if not mission or rare or gear_build or screamer or weapon_affixes or sortie_risk or night_hound or workshop_tool:
			return "EVENT_SORTIE_CONTEXT"
	if worldgen and (not value.worldgen is Dictionary or not TransactionReceipt.same(value.worldgen,WorldgenLayout.policy(level, industrial, residential_rescue))): return "WORLDGEN_ACTION_POLICY"
	if mission and (not level or not SurvivalContracts.integer(value.mission_policy, 1, 1)): return "MISSION_ACTION_POLICY"
	if rare and (not mission or not SurvivalContracts.integer(value.rare_policy, RareSortie.VERSION, RareSortie.VERSION)): return "RARE_ACTION_POLICY"
	if gear_build and (not mission or rare or value.get("type") != "airdrop" \
			or not BuildItems.valid_pool(value.gear_build_policy)):
		return "GEAR_BUILD_POLICY"
	var field_count: int = 23 + int(worldgen) + int(mission) + int(rare) + int(gear_build) \
		+ int(screamer) + int(weapon_affixes) + int(first_aid) + int(sortie_risk) + int(campaign_pressure) + int(content_wave) \
		+ int(night_hound) + int(workshop_tool) + int(event_sortie) + int(recon)
	if not value is Dictionary or not SurvivalContracts.json_value(value) or value.size()!=field_count or value.get("version")!=9 or not value.get("layout") is Dictionary or not value.get("exploration") is Dictionary or not value.get("build") is Dictionary or not value.get("powers") is Dictionary or not value.get("persona") is Dictionary or not value.get("campaign") is Dictionary: return "EXPLORATION_ACTION_FIELDS"
	if not BuildItems.valid_pool(value.build.get("version")) or content_wave != BuildItems.wave_pool(int(value.build.version)):
		return "EXPLORATION_BUILD_POOL"
	if not value.get("seed") is String or value.seed.length()!=32 or value.seed.to_lower()!=value.seed or not value.seed.is_valid_hex_number(false) or not SurvivalContracts.integer(value.get("day"),2,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(value.get("slot"),0,2) or (not event_sortie and value.get("type") not in TaskActions.TYPES) or value.layout.get("size") not in NeighborhoodLayout.SIZES or value.layout.get("topology") not in NeighborhoodLayout.TOPOLOGIES or not SurvivalContracts.integer(value.get("recruit"),0,5) or not value.build.get("owned") is Array or not value.build.get("slots") is Array or not value.powers.get("owned") is Array or not PowerState.action_inventory_valid(value.powers.owned, PowerState.loadout(value.powers), int(value.day)) or not value.persona.get("facts") is Dictionary or not value.campaign.get("run_id") is String or value.campaign.run_id.length()!=32 or not value.campaign.run_id.is_valid_hex_number(false) or not SurvivalContracts.integer(value.campaign.get("preparations"),0,3): return "EXPLORATION_ACTION_CONTEXT"
	var signature: String=RecordEncoding.fingerprint(value) if mission else SurvivalContracts.fingerprint(value)
	var proof_key: String = "camp-source:" + signature if mission and camp_source else signature
	if _checked.has(proof_key): return ""
	var source: Dictionary=origin(value)
	if source.is_empty(): return "EXPLORATION_ORIGINAL_SOURCE"
	var expected: Dictionary
	var source_risk: Dictionary = value.event_sortie.source_risk if event_sortie else value.get("sortie_risk", {})
	if not source_risk.is_empty():
		expected = SortieRiskV1.freeze(source, source_risk.topology, source_risk.yard)
	else:
		expected = upgrade(source, worldgen, level, int(mission), industrial, residential_rescue, int(value.get("rare_policy", 0)))
	if event_sortie and not expected.is_empty():
		expected = EventSortieV1.freeze(expected)
	if expected.is_empty(): return "EXPLORATION_ACTION_CANONICAL"
	if gear_build:
		expected = BuildActions.with_gear_drops(expected)
	if screamer:
		expected.screamer_policy = ScreamerPolicyV1.VERSION
	if weapon_affixes:
		expected.weapon_affix_policy = WeaponInventory.AFFIX_POLICY_VERSION
	if first_aid:
		expected.first_aid_policy = FirstAidV1.VERSION
	if campaign_pressure:
		expected.campaign_pressure = CampaignPressureV1.marker(int(value.day) - 2)
	if content_wave:
		expected = ContentWaveV1.freeze_action(expected)
	if night_hound:
		expected.night_hound_policy = NightHoundV1.VERSION
	if workshop_tool:
		expected = WorkshopSiteV1.freeze(expected)
	if recon:
		expected = ReconActionV1.freeze(expected)
		if not expected.has("recon"):
			return "RECON_ACTION_CONTEXT"
	var matches: bool = signature == RecordEncoding.fingerprint(expected) if mission else TransactionReceipt.same(value,expected)
	if not matches and mission and camp_source:
		# RunSave keeps its historical JSON camp projection. A stored ability source
		# must match that precise projection, without accepting it in receipt proof.
		var projected: Dictionary = JSON.parse_string(JSON.stringify(expected, "", true, true))
		matches = signature == RecordEncoding.fingerprint(projected)
	if not matches:
		if recon and RecordEncoding.fingerprint(value.recon) != RecordEncoding.fingerprint(expected.recon):
			return "RECON_ACTION_CANONICAL"
		return "EXPLORATION_ACTION_CANONICAL"
	if _checked.size()>=64: _checked.clear()
	_checked[proof_key]=true
	return ""

static func matches(base: Dictionary,value: Variant) -> bool:
	if not ExplorationState.enabled(base): return false
	var proof: Dictionary = {}
	if WorldgenState.level_enabled(base) and value is Dictionary:
		proof=ValueProofCache.lookup("level-matches",{"base":base,"value":value})
		if proof.hit: return true
	if value is Dictionary and value.get("version")==8:
		return value.get("campaign",{}).get("is_finale",false) and PersonaActions.matches(base,value)
	if not problem(value).is_empty(): return false
	if WorldgenState.level_enabled(base)!=(value.get("worldgen",{}).get("version")==2): return false
	for offer: Dictionary in offers(base):
		if TransactionReceipt.same(value,offer):
			if not proof.is_empty(): ValueProofCache.remember(proof,true)
			return true
	return false

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	if PumpStationAction.enabled(value):
		return PumpStationAction.supply(value)
	var source: Dictionary=origin(value)
	var result: MissionSupply=PersonaActions.supply(source)
	result.generated=value.duplicate(true)
	result.layout=ExplorationLayout.resource(value.layout)
	result.cash_reward=int(value.cash)
	result.food_reward=int(value.food)
	result.has_weapon_sample = value.weapons == 1
	if value.type == EventSortieV1.TYPE:
		result.display_name = EventSortieV1.TITLE
		result.description = LevelSummary.mission_card_text(value)
		return result
	if value.has("rare_policy"):
		result.display_name = RareSortie.title(value.type)
		result.description = RareSortie.card_text(value)
		return result
	var optional_cash: int=int(value.cash-source.cash)
	var optional_food: int=int(value.food-source.food)
	result.description="%s · %s · %d栋 / %d互动点\n主目标收益：钱%d / 粮%d / 武器%d\n可选收益上限：钱%d / 粮%d（无额外目标奖金）\n主目标位于中远区域；附近留有补给。\n按路线分工，随时可按原条件归航；夜间时钟不延长。"%[{"small":"小型","medium":"中型","large":"大型"}[value.layout["size"]],result.layout.display_name,value.layout.entities.size(),value.sites.size(),source.cash,source.food,source.weapons,optional_cash,optional_food]
	if value.exploration.has("level"):
		var main_cash: int = 0
		var main_food: int = 0
		var main_weapons: int = 0
		for site: Dictionary in value.sites:
			if site.id in value.objective.site_ids:
				if site.kind=="cash":
					main_cash+=int(site.amount)
				else:
					main_food+=int(site.amount)
				main_weapons+=int(site.weapon)
		var main_text: String = "援救后当场同行；生还归航后计入营地" if value.type=="rescue" else "主目标：钱%d / 粮%d / 武器%d" % [main_cash,main_food,main_weapons]
		result.description="%s · %s\n%s\n其余上限：钱%d / 粮%d / 武器%d（无奖金）\n%s" % [{"small":"小型","medium":"中型","large":"大型"}[value.layout["size"]],result.layout.display_name,main_text,value.cash-main_cash,value.food-main_food,value.weapons-main_weapons,LevelSummary.description(value)]
	return result

static func mission_problem(mission: Dictionary) -> String:
	if mission.size()!=6 or not mission.has_all(["map_id","mission_id","cash_reward","food_reward","has_weapon_sample","generated"]): return "EXPLORATION_MISSION_FIELDS"
	var issue: String=problem(mission.generated)
	if not issue.is_empty(): return issue
	var value: Dictionary=mission.generated
	var source_type: String = "airdrop" if value.type == EventSortieV1.TYPE else value.type
	return "" if mission.map_id==value.layout.id and mission.mission_id==TaskActions.CONFIG[source_type].mission and mission.cash_reward==value.cash and mission.food_reward==value.food and mission.has_weapon_sample==(value.weapons==1) else "EXPLORATION_MISSION_BINDING"
