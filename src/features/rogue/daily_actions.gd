class_name DailyActions
extends RefCounted
## Dispatch by explicit version; old receipt authentication never uses the new generator.
static func offers(base: Dictionary) -> Array[Dictionary]:
	return BuildActions.offers(base) if BuildState.enabled(base) else CampaignActions.offers(base) if CampaignState.is_short(base) else WeaponActions.offers(base)
static func problem(value: Variant) -> String:
	if value is Dictionary and value.get("version")==7: return BuildActions.problem(value)
	if value is Dictionary and value.get("version")==6: return CampaignActions.problem(value)
	if value is Dictionary and value.get("version")==5: return WeaponActions.problem(value)
	if value is Dictionary and value.get("version")==4: return TaskActions.problem(value)
	if value is Dictionary and value.get("version")==3: return NeighborhoodActions.problem(value)
	return WorldActions.problem(value) if value is Dictionary and value.get("version")==2 else RogueActions.problem(value)
static func matches(base: Dictionary, value: Variant) -> bool:
	if BuildState.enabled(base): return BuildActions.matches(base,value)
	if CampaignState.is_short(base) and (not value is Dictionary or value.get("version")!=6): return false
	if value is Dictionary and value.get("version")==6: return CampaignActions.matches(base,value)
	if value is Dictionary and value.get("version")==5: return WeaponActions.matches(base,value)
	if value is Dictionary and value.get("version")==4: return TaskActions.matches(base,value)
	if value is Dictionary and value.get("version")==3: return NeighborhoodActions.matches(base,value)
	return WorldActions.matches(base,value) if value is Dictionary and value.get("version")==2 else RogueActions.matches(base,value)
static func supply(value: Dictionary) -> MissionSupply:
	if value.get("version")==7: return BuildActions.supply(value)
	if value is Dictionary and value.get("version")==6: return CampaignActions.supply(value)
	if value is Dictionary and value.get("version")==5: return WeaponActions.supply(value)
	if value is Dictionary and value.get("version")==4: return TaskActions.supply(value)
	if value is Dictionary and value.get("version")==3: return NeighborhoodActions.supply(value)
	return WorldActions.supply(value) if value.get("version")==2 else RogueActions.supply(value)
static func mission_problem(mission: Dictionary) -> String:
	if mission.get("generated",{}).get("version")==7: return BuildActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==6: return CampaignActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==5: return WeaponActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==4: return TaskActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==3: return NeighborhoodActions.mission_problem(mission)
	return WorldActions.mission_problem(mission) if mission.get("generated",{}).get("version")==2 else RogueActions.mission_problem(mission)
