class_name DailyActions
extends RefCounted
## Dispatch by explicit version; old receipt authentication never uses the new generator.
static func offers(base: Dictionary) -> Array[Dictionary]:
	if CampaignRules.is_investigation(base.get("journey", {}).get("campaign")):
		return InvestigationActions.offers(base)
	return ExplorationActions.offers(base) if ExplorationState.enabled(base) else PersonaActions.offers(base) if PersonaState.enabled(base) else PowerActions.offers(base) if PowerState.enabled(base) else CombatActions.offers(base) if CombatActions.enabled(base) else BuildActions.offers(base) if BuildState.enabled(base) else CampaignActions.offers(base) if CampaignState.is_short(base) else WeaponActions.offers(base)
static func problem(value: Variant) -> String:
	if value is Dictionary and value.get("version")==9: return ExplorationActions.problem(value)
	if value is Dictionary and value.has("persona"): return PersonaActions.problem(value)
	if value is Dictionary and value.has("powers"): return PowerActions.problem(value)
	if value is Dictionary and value.get("version")==8: return CombatActions.problem(value)
	if value is Dictionary and value.get("version")==7: return BuildActions.problem(value)
	if value is Dictionary and value.get("version")==6: return CampaignActions.problem(value)
	if value is Dictionary and value.get("version")==5: return WeaponActions.problem(value)
	if value is Dictionary and value.get("version")==4: return TaskActions.problem(value)
	if value is Dictionary and value.get("version")==3: return NeighborhoodActions.problem(value)
	return WorldActions.problem(value) if value is Dictionary and value.get("version")==2 else RogueActions.problem(value)
static func matches(base: Dictionary, value: Variant) -> bool:
	if CampaignRules.is_investigation(base.get("journey", {}).get("campaign")):
		return InvestigationActions.matches(base,value)
	if value is Dictionary and (value.has("investigation") or value.has("mission_policy")):
		return false
	if ExplorationState.enabled(base): return ExplorationActions.matches(base,value)
	if PersonaState.enabled(base): return PersonaActions.matches(base,value)
	if PowerState.enabled(base): return PowerActions.matches(base,value)
	if CombatActions.enabled(base): return CombatActions.matches(base,value)
	if BuildState.enabled(base): return BuildActions.matches(base,value)
	if CampaignState.is_short(base) and (not value is Dictionary or value.get("version")!=6): return false
	if value is Dictionary and value.get("version")==6: return CampaignActions.matches(base,value)
	if value is Dictionary and value.get("version")==5: return WeaponActions.matches(base,value)
	if value is Dictionary and value.get("version")==4: return TaskActions.matches(base,value)
	if value is Dictionary and value.get("version")==3: return NeighborhoodActions.matches(base,value)
	return WorldActions.matches(base,value) if value is Dictionary and value.get("version")==2 else RogueActions.matches(base,value)
static func supply(value: Dictionary) -> MissionSupply:
	if value.get("version")==9: return ExplorationActions.supply(value)
	if value.has("persona"): return PersonaActions.supply(value)
	if value.has("powers"): return PowerActions.supply(value)
	if value.get("version")==8: return CombatActions.supply(value)
	if value.get("version")==7: return BuildActions.supply(value)
	if value is Dictionary and value.get("version")==6: return CampaignActions.supply(value)
	if value is Dictionary and value.get("version")==5: return WeaponActions.supply(value)
	if value is Dictionary and value.get("version")==4: return TaskActions.supply(value)
	if value is Dictionary and value.get("version")==3: return NeighborhoodActions.supply(value)
	return WorldActions.supply(value) if value.get("version")==2 else RogueActions.supply(value)
static func mission_problem(mission: Dictionary) -> String:
	if mission.get("generated",{}).get("version")==9: return ExplorationActions.mission_problem(mission)
	if mission.get("generated",{}).has("persona"): return PersonaActions.mission_problem(mission)
	if mission.get("generated",{}).has("powers"): return PowerActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==8: return CombatActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==7: return BuildActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==6: return CampaignActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==5: return WeaponActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==4: return TaskActions.mission_problem(mission)
	if mission.get("generated",{}).get("version")==3: return NeighborhoodActions.mission_problem(mission)
	return WorldActions.mission_problem(mission) if mission.get("generated",{}).get("version")==2 else RogueActions.mission_problem(mission)
