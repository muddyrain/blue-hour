class_name ExplorationActions
extends RefCounted
## V9 authenticates the new full description, never claims new geometry is old V3.
static var _checked: Dictionary = {}
static var _origins: Dictionary = {}

static func origin(value: Dictionary) -> Dictionary:
	# Reconstruct the original frozen reward/capability source without storing a
	# duplicate obsolete map in every new receipt. Validate it before projection.
	var key: String=SurvivalContracts.fingerprint({"seed":value.seed,"day":value.day,"slot":value.slot,"type":value.type,"size":value.layout["size"],"topology":value.layout.topology,"recruit":value.recruit,"campaign":value.campaign,"build":value.build,"powers":value.powers,"persona":value.persona})
	if _origins.has(key): return _origins[key].duplicate(true)
	var task: Dictionary=TaskActions._make(value.seed,int(value.day),int(value.slot),value.type,value.layout.topology,value.layout["size"],int(value.recruit))
	if task.is_empty(): return {}
	var source: Dictionary=CampaignActions._upgrade(WeaponActions._upgrade(task),value.campaign.run_id,int(value.campaign.preparations))
	source=CombatActions.upgrade(BuildActions.upgrade(source,value.build.owned,value.build.slots))
	source=PowerActions.upgrade(source,value.powers.owned,value.powers.slot)
	source=PersonaActions.upgrade(source,value.persona.facts)
	if not PersonaActions.problem(source).is_empty(): return {}
	if _origins.size()>=64: _origins.clear()
	_origins[key]=source.duplicate(true)
	return source

static func upgrade(source: Dictionary, worldgen: bool = false, level: bool = false) -> Dictionary:
	var value: Dictionary=source.duplicate(true)
	value.version=9
	var content: Dictionary = {}
	if level:
		for attempt: int in range(4):
			value.layout=WorldgenLayout._assemble("BH_LEVEL_V1:"+source.id,source.layout["size"],source.layout.topology,mini(attempt,2),attempt==3,source.type)
			if value.layout.is_empty():
				continue
			content=ExplorationSites.generate(value.layout,value.type,int(source.cash),int(source.food),int(source.weapons),value.id)
			if not content.is_empty():
				content.level=LevelSummary.freeze(value.layout,content.sites,content.objective,value.type)
				if not content.level.is_empty():
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
	value.exploration={"version":1,"policy":ExplorationLayout.policy(),"primary":{"cash":source.cash,"food":source.food,"weapons":source.weapons},"optional_objectives":content.optional_objectives,"metrics":content.metrics}
	if level:
		value.exploration.level=content.level
	if worldgen: value.worldgen=WorldgenLayout.policy(level)
	return value

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for source: Dictionary in PersonaActions.offers(base):
		result.append(source if source.campaign.is_finale else upgrade(source,WorldgenState.enabled(base),WorldgenState.level_enabled(base)))
	return result

static func problem(value: Variant) -> String:
	var worldgen: bool=value is Dictionary and value.has("worldgen")
	var level: bool=worldgen and value.worldgen is Dictionary and value.worldgen.get("version")==2
	if worldgen and (not value.worldgen is Dictionary or not TransactionReceipt.same(value.worldgen,WorldgenLayout.policy(level))): return "WORLDGEN_ACTION_POLICY"
	if not value is Dictionary or not SurvivalContracts.json_value(value) or value.size()!=(24 if worldgen else 23) or value.get("version")!=9 or not value.get("layout") is Dictionary or not value.get("exploration") is Dictionary or not value.get("build") is Dictionary or not value.get("powers") is Dictionary or not value.get("persona") is Dictionary or not value.get("campaign") is Dictionary: return "EXPLORATION_ACTION_FIELDS"
	if not value.get("seed") is String or value.seed.length()!=32 or value.seed.to_lower()!=value.seed or not value.seed.is_valid_hex_number(false) or not SurvivalContracts.integer(value.get("day"),2,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(value.get("slot"),0,2) or value.get("type") not in TaskActions.TYPES or value.layout.get("size") not in NeighborhoodLayout.SIZES or value.layout.get("topology") not in NeighborhoodLayout.TOPOLOGIES or not SurvivalContracts.integer(value.get("recruit"),0,5) or not value.build.get("owned") is Array or not value.build.get("slots") is Array or not value.powers.get("owned") is Array or not value.powers.get("slot") is String or not value.persona.get("facts") is Dictionary or not value.campaign.get("run_id") is String or value.campaign.run_id.length()!=32 or not value.campaign.run_id.is_valid_hex_number(false) or not SurvivalContracts.integer(value.campaign.get("preparations"),0,3): return "EXPLORATION_ACTION_CONTEXT"
	var signature: String=SurvivalContracts.fingerprint(value)
	if _checked.has(signature): return ""
	var source: Dictionary=origin(value)
	if source.is_empty(): return "EXPLORATION_ORIGINAL_SOURCE"
	var expected: Dictionary=upgrade(source,worldgen,level)
	if expected.is_empty() or not TransactionReceipt.same(value,expected): return "EXPLORATION_ACTION_CANONICAL"
	if _checked.size()>=64: _checked.clear()
	_checked[signature]=true
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
	var source: Dictionary=origin(value)
	var result: MissionSupply=PersonaActions.supply(source)
	result.generated=value.duplicate(true)
	result.layout=ExplorationLayout.resource(value.layout)
	result.cash_reward=int(value.cash)
	result.food_reward=int(value.food)
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
	return "" if mission.map_id==value.layout.id and mission.mission_id==TaskActions.CONFIG[value.type].mission and mission.cash_reward==value.cash and mission.food_reward==value.food and mission.has_weapon_sample==(value.weapons==1) else "EXPLORATION_MISSION_BINDING"
