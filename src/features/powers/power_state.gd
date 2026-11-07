class_name PowerState
extends RefCounted
## Camp inventory facts are published only by CampEdit / FrozenSettlement.
static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey") is Dictionary and camp.journey.get("build") is Dictionary and (camp.journey.build.get("version")==3 or camp.journey.build.get("version")==4 or camp.journey.build.get("version")==5 or camp.journey.build.get("version")==6)

static func initial_build() -> Dictionary:
	var build: Dictionary=CombatActions.initial()
	build.version=3
	build.powers={"version":1,"owned":[],"slot":"","sources":[],"uses":[]}
	return build

static func inventory_valid(owned: Variant, slot: Variant) -> bool:
	if not owned is Array or owned.size()>2 or not slot is String or (slot!="" and slot not in owned): return false
	var seen: Array[String]=[]
	for id: Variant in owned:
		if not id is String or not SpecialPowers.POLICY.has(id) or id in seen: return false
		seen.append(id)
	return true

static func problem(camp: Dictionary) -> String:
	if not camp.get("journey") is Dictionary or not camp.journey.get("build") is Dictionary or not camp.get("profile_id") is String or not camp.journey.get("seed") is String or not camp.journey.get("root_id") is String or not SurvivalContracts.integer(camp.get("settled_sorties"),0,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(camp.get("day"),2,RunSave.MAX_COUNTER): return "POWER_CAMP_CONTEXT"
	var value: Variant=camp.journey.build.get("powers")
	if not value is Dictionary or value.size()!=5 or not value.has_all(["version","owned","slot","sources","uses"]) or value.version!=1 or not inventory_valid(value.owned,value.slot) or not value.sources is Array or value.sources.size()!=value.owned.size() or not value.uses is Array or value.uses.size()>camp.settled_sorties: return "POWER_CAMP_FIELDS"
	var prior: Array=[]
	var ordinal: int=0
	for source: Variant in value.sources:
		if not source is Dictionary or source.size()!=3 or not source.has_all(["ability_id","transaction_id","generated"]) or not source.transaction_id is String or source.ability_id!=value.owned[prior.size()] or not _source_problem(camp,source.generated).is_empty(): return "POWER_SOURCE_FIELDS"
		var number: int=int(source.transaction_id.get_slice(":",1))
		var generated: Dictionary=source.generated
		if number<=ordinal or number>camp.settled_sorties or source.transaction_id!="%s:%d"%[camp.profile_id,number] or generated.campaign.run_id!=camp.profile_id or generated.seed!=camp.journey.seed or generated.day!=number+1 or generated.powers.sample!=source.ability_id or not TransactionReceipt.same({"v":prior},{"v":generated.powers.owned}): return "POWER_SOURCE_BINDING"
		ordinal=number
		prior.append(source.ability_id)
	ordinal=0
	for used: Variant in value.uses:
		if not used is Dictionary or used.size()!=3 or not used.has_all(["day","binding","event"]) or not SurvivalContracts.integer(used.day,2,camp.day-1) or used.day<=ordinal or not used.binding is Dictionary or not used.event is Dictionary: return "POWER_USE_FIELDS"
		if used.binding.get("root_id")!=camp.journey.root_id or used.binding.get("run_id")!=camp.profile_id or used.binding.get("transaction_id")!="%s:%d"%[camp.profile_id,int(used.day)-1]: return "POWER_USE_BINDING"
		if not used.event.get("ability_id") is String or not SurvivalContracts.number(used.event.get("until")): return "POWER_USE_FACT"
		if not value.sources.any(func(source:Dictionary)->bool:return source.ability_id==used.event.ability_id and source.generated.day<used.day): return "POWER_USE_BEFORE_ACQUISITION"
		var state: Dictionary=SpecialPowers.initial(used.binding,used.event.ability_id)
		if state.is_empty(): return "POWER_USE_FACT"
		state.accepted=[used.event]
		if not SpecialPowers.problem(state,used.binding,state.equipped,float(used.event.get("until",-1))).is_empty(): return "POWER_USE_FACT"
		ordinal=int(used.day)
	return ""

static func equip(before: Dictionary, ability: String) -> Dictionary:
	if not enabled(before): return {}
	var after: Dictionary=before.duplicate(true)
	after.journey.build.powers.slot=ability
	return after if problem(after).is_empty() else {}

static func settled(before: Dictionary, report: Dictionary, generated: Dictionary) -> Dictionary:
	var value: Dictionary=before.journey.build.powers.duplicate(true)
	if report.evacuated and report.site_facts.get("cash",{}).get("searched",false) and not generated.powers.sample.is_empty():
		value.owned.append(generated.powers.sample)
		value.sources.append({"ability_id":generated.powers.sample,"transaction_id":report.sortie_id,"generated":generated.duplicate(true)})
	for event: Dictionary in report.powers.accepted:
		value.uses.append({"day":before.day,"binding":report.powers.binding.duplicate(true),"event":event.duplicate(true)})
	return value


static func _source_problem(camp: Dictionary, generated: Variant) -> String:
	if not PersonaState.enabled(camp): return PowerActions.problem(generated)
	var issue: String=ExplorationActions.problem(generated, true) if ExplorationState.enabled(camp) else PersonaActions.problem(generated)
	if not issue.is_empty(): return issue
	var campaign: Variant = camp.journey.get("campaign")
	if generated.has("investigation") and (not CampaignRules.is_investigation(campaign) or generated.investigation.version != campaign.version):
		return "INVESTIGATION_POWER_SOURCE_MODE"
	if ExplorationState.enabled(camp) and WorldgenState.enabled(camp)!=generated.has("worldgen"): return "WORLDGEN_POWER_SOURCE_MODE"
	if WorldgenState.enabled(camp) and WorldgenState.level_enabled(camp)!=(generated.get("worldgen",{}).get("version")==2): return "LEVEL_POWER_SOURCE_MODE"
	if not camp.journey.build.get("persona") is Dictionary or not TransactionReceipt.same(generated.persona.facts,camp.journey.build.persona): return "PERSONA_POWER_SOURCE"
	return ""
