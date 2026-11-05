class_name CampaignActions
extends RefCounted
## V6 freezes the phase and one reachable boss identity on the unchanged V5 offers.
const VERSION: int=6

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not CampaignRules.can_depart(base.journey.campaign): return result
	var context: Dictionary=CampaignRules.context(base.journey.campaign)
	for old: Dictionary in WeaponActions.offers(base):
		if context.is_finale and old.type=="rescue": continue
		result.append(_upgrade(old,base.profile_id,int(base.journey.campaign.preparations)))
		if context.is_finale: break
	return result

static func legacy(value: Dictionary) -> Dictionary:
	var old: Dictionary=value.duplicate(true)
	old.version=5;old.erase("campaign");old.erase("encounter")
	return old

static func _upgrade(old: Dictionary, run_id: String, preparations: int) -> Dictionary:
	var value: Dictionary=old.duplicate(true);value.version=VERSION
	var mode: Dictionary=CampaignRules.initial(run_id);mode.preparations=preparations
	value.campaign=CampaignRules.context(mode).merged({"run_id":run_id,"preparations":preparations})
	value.encounter={}
	if value.campaign.is_finale:
		var layout: StreetLayout=WeaponActions.supply(old).layout
		value.encounter={"version":1,"boss_id":"%s:%d:breacher" % [run_id,int(old.day)-1],"actor_id":0,"position":_spawn(layout),"policy":BossDefinition.POLICY.duplicate(true)}
	return value

static func _spawn(layout: StreetLayout) -> Array:
	var navigation: FieldNavigation=FieldNavigation.new()
	navigation.configure(layout.blockers(),layout.world_bounds)
	var start: Vector2=layout.arrivals[0]
	var candidates: Array[Vector2]=[]
	for point: Vector2 in layout.enemy_points: candidates.append(point)
	# Layout-derived grid fallback is also navigated; never a separate arena.
	for y: int in range(96,int(layout.world_bounds.end.y)-64,96):
		for x: int in range(96,int(layout.world_bounds.end.x)-64,96): candidates.append(Vector2(x,y))
	candidates.sort_custom(func(a:Vector2,b:Vector2)->bool:return absf(a.distance_to(start)-520.0)<absf(b.distance_to(start)-520.0))
	for point: Vector2 in candidates:
		if point.distance_to(start)>=360.0 and navigation.is_clear(point) and navigation.path_between(start,point).size()>=2: return [point.x,point.y]
	return []

static func problem(value: Variant) -> String:
	if not value is Dictionary or value.get("version")!=VERSION or not value.get("campaign") is Dictionary or not value.get("encounter") is Dictionary: return "CAMPAIGN_ACTION_FIELDS"
	var old: Dictionary=legacy(value)
	var issue: String=WeaponActions.problem(old)
	if not issue.is_empty(): return issue
	var context: Dictionary=value.campaign
	if not context.get("run_id") is String or context.run_id.length()!=32 or not context.run_id.is_valid_hex_number(false) or not SurvivalContracts.integer(context.get("preparations"),0,4): return "CAMPAIGN_ACTION_CONTEXT"
	var mode: Dictionary=CampaignRules.initial(context.run_id);mode.preparations=int(context.preparations)
	if not CampaignRules.problem(mode).is_empty(): return "CAMPAIGN_ACTION_IDENTITY"
	return "" if TransactionReceipt.same(value,_upgrade(old,context.run_id,int(context.preparations))) and (not context.is_finale or value.encounter.position.size()==2) else "CAMPAIGN_ACTION_BINDING"

static func matches(base: Dictionary,value: Variant) -> bool:
	if not CampaignState.is_short(base) or not problem(value).is_empty(): return false
	for offer: Dictionary in offers(base):
		if TransactionReceipt.same(value,offer): return true
	return false

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply=WeaponActions.supply(legacy(value));result.generated=value.duplicate(true)
	var mode: Dictionary=CampaignRules.initial(value.campaign.run_id);mode.preparations=int(value.campaign.preparations)
	var display: Dictionary=CampaignRules.display(mode)
	result.description=display.title+" · "+display.progress+"\n"+display.detail+"\n"+result.description
	if value.campaign.is_finale:
		result.display_name="突破封锁"
		result.description="终局 · 突破封锁\n击败破阵者，再让至少一名队员经巴士归航并确认。\n可提前撤离，下次首领重新开始；此行仍需口粮。"
	return result

static func mission_problem(mission: Dictionary) -> String:
	var issue: String=problem(mission.get("generated"))
	if not issue.is_empty(): return issue
	var old: Dictionary=mission.duplicate(true);old.generated=legacy(mission.generated)
	return WeaponActions.mission_problem(old)
