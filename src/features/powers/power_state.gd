class_name PowerState
extends RefCounted
## Camp inventory facts are published only by CampEdit / FrozenSettlement.
const SECOND_SLOT: String = "second_slot"
const FREEZE: String = "freeze"
const INVESTMENT_COST: int = 24

static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey") is Dictionary and camp.journey.get("build") is Dictionary and (camp.journey.build.get("version")==3 or camp.journey.build.get("version")==4 or camp.journey.build.get("version")==5 or camp.journey.build.get("version")==6)

static func initial_build() -> Dictionary:
	var build: Dictionary=CombatActions.initial()
	build.version=3
	build.powers={"version":1,"owned":[],"slot":"","sources":[],"uses":[]}
	return build

static func initial_progression() -> Dictionary:
	return {"version":SpecialPowers.PROGRESSION_VERSION, "owned":[], "slots":[""],
		"investments":{SECOND_SLOT:0, FREEZE:0}, "sources":[], "uses":[]}

static func progression(inventory: Dictionary) -> bool:
	return inventory.get("version") == SpecialPowers.PROGRESSION_VERSION

static func loadout(inventory: Dictionary) -> Variant:
	if progression(inventory):
		return {"version":inventory.version, "slots":inventory.get("slots"), "investments":inventory.get("investments")}
	return inventory.get("slot")

static func action_inventory_valid(owned: Variant, equipment: Variant, day: int) -> bool:
	if not equipment is Dictionary:
		return inventory_valid(owned, equipment)
	if not inventory_valid(owned, "") or not SpecialPowers.loadout_valid(equipment):
		return false
	for id: String in equipment.slots:
		if id != "" and id not in owned:
			return false
	return equipment.investments.second_slot <= day and equipment.investments.freeze <= day \
		and (equipment.investments.freeze == 0 or SpecialPowers.FREEZE in owned)

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
	if value is Dictionary and progression(value):
		return _progression_problem(camp, value)
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

static func equip_progression(before: Dictionary, slot: int, ability: String) -> Dictionary:
	if not enabled(before) or not progression(before.journey.build.powers):
		return {}
	var after: Dictionary = before.duplicate(true)
	var slots: Array = after.journey.build.powers.slots
	if slot < 0 or slot >= slots.size():
		return {}
	slots[slot] = ability
	return after if problem(after).is_empty() else {}

static func investment_problem(camp: Dictionary, choice: String) -> String:
	if not enabled(camp) or choice not in [SECOND_SLOT, FREEZE]:
		return "当前旅程不可购买"
	var value: Dictionary = camp.journey.build.powers
	if not progression(value) or camp.journey.state != "ACTIVE":
		return "当前旅程不可购买"
	if value.investments[choice] != 0:
		return "已解锁" if choice == SECOND_SLOT else "已强化"
	if choice == FREEZE and SpecialPowers.FREEZE not in value.owned:
		return "先带回全域冻结"
	if camp.cash < INVESTMENT_COST:
		return "还差 %d 币" % (INVESTMENT_COST - int(camp.cash))
	return ""

static func invest(before: Dictionary, choice: String) -> Dictionary:
	if not investment_problem(before, choice).is_empty():
		return {}
	var after: Dictionary = before.duplicate(true)
	var value: Dictionary = after.journey.build.powers
	value.investments[choice] = int(before.day)
	if choice == SECOND_SLOT:
		value.slots.append("")
	after.cash = int(before.cash) - INVESTMENT_COST
	after.camp_spending = int(before.camp_spending) + INVESTMENT_COST
	return after

static func registration_problem(camp: Dictionary) -> String:
	if not enabled(camp) or not progression(camp.journey.build.powers):
		return ""
	return "" if TransactionReceipt.same(camp.journey.build.powers, initial_progression()) else "POWER_PROGRESSION_REGISTRATION"

static func opening_spend_valid(camp: Dictionary) -> bool:
	var value: Dictionary = camp.journey.get("build", {}).get("powers", {})
	return progression(value) and camp.day == 2 and camp.settled_sorties == 0 and camp.last_day.is_empty() \
		and value.investments.second_slot == 2 and camp.camp_spending == INVESTMENT_COST \
		and camp.cash == CampRules.INITIAL_CASH - INVESTMENT_COST

static func _progression_problem(camp: Dictionary, value: Dictionary) -> String:
	if value.size() != 6 or not value.has_all(["version", "owned", "slots", "investments", "sources", "uses"]) \
			or not action_inventory_valid(value.owned, loadout(value), int(camp.day)) \
			or not value.sources is Array or value.sources.size() != value.owned.size() \
			or not value.uses is Array or value.uses.size() > camp.settled_sorties:
		return "POWER_CAMP_FIELDS"
	var acquired: Dictionary = {}
	var previous_day: int = 1
	var prior: Array = []
	for source: Variant in value.sources:
		if not source is Dictionary or source.size() != 3 or not source.has_all(["ability_id", "transaction_id", "generated"]) \
				or source.ability_id != value.owned[prior.size()] or not _source_problem(camp, source.generated).is_empty():
			return "POWER_SOURCE_FIELDS"
		var generated: Dictionary = source.generated
		var day: int = int(generated.day)
		if day <= previous_day or day >= camp.day or source.transaction_id != "%s:%d" % [camp.profile_id, day - 1] \
				or generated.campaign.run_id != camp.profile_id or generated.seed != camp.journey.seed \
				or generated.powers.sample != source.ability_id or generated.powers.owned != prior \
				or not _historical_loadout(generated.powers, value, day, acquired):
			return "POWER_SOURCE_BINDING"
		previous_day = day
		acquired[source.ability_id] = day
		prior.append(source.ability_id)
	if value.investments.freeze != 0 and value.investments.freeze <= acquired.get(SpecialPowers.FREEZE, camp.day):
		return "POWER_UPGRADE_BEFORE_ACQUISITION"
	var purchases_today: int = int(value.investments.freeze == camp.day) + int(value.investments.second_slot == camp.day)
	if purchases_today > 0 and not SurvivalContracts.integer(camp.get("camp_spending"), purchases_today * INVESTMENT_COST, RunSave.MAX_COUNTER):
		return "POWER_INVESTMENT_SPENDING"
	previous_day = 1
	for used: Variant in value.uses:
		if not used is Dictionary or used.size() != 4 or not used.has_all(["day", "binding", "loadout", "event_record"]) \
				or not SurvivalContracts.integer(used.day, previous_day + 1, int(camp.day) - 1) \
				or not used.binding is Dictionary or not used.loadout is Dictionary or not used.event_record is Dictionary:
			return "POWER_USE_FIELDS"
		var day: int = int(used.day)
		if used.binding.get("root_id") != camp.journey.root_id or used.binding.get("run_id") != camp.profile_id \
				or used.binding.get("transaction_id") != "%s:%d" % [camp.profile_id, day - 1]:
			return "POWER_USE_BINDING"
		if not SpecialPowers.loadout_valid(used.loadout) or not _historical_loadout(used.loadout, value, day, acquired):
			return "POWER_USE_LOADOUT"
		var state: Dictionary = SpecialPowers.initial(used.binding, used.loadout)
		if state.is_empty():
			return "POWER_USE_FACT"
		var decoded: Dictionary = RecordEncoding.unpack(used.event_record)
		if decoded.error != OK or decoded.payload.size() != 1 \
				or not decoded.payload.get("events") is Array or decoded.payload.events.is_empty():
			return "POWER_USE_RECORD"
		state.accepted = decoded.payload.events
		var final: Variant = state.accepted.back()
		if not final is Dictionary or not SurvivalContracts.number(final.get("at")) \
				or not SpecialPowers.problem(state, used.binding, used.loadout, float(final.at)).is_empty():
			return "POWER_USE_FACT"
		previous_day = day
	return ""

static func _historical_loadout(equipment: Dictionary, inventory: Dictionary, day: int, acquired: Dictionary) -> bool:
	if not progression(equipment):
		return false
	for choice: String in [SECOND_SLOT, FREEZE]:
		var purchase_day: int = int(inventory.investments[choice])
		if equipment.investments[choice] != (purchase_day if purchase_day <= day else 0):
			return false
	for id: String in equipment.slots:
		if not id.is_empty() and acquired.get(id, day) >= day:
			return false
	return true

static func settled(before: Dictionary, report: Dictionary, generated: Dictionary) -> Dictionary:
	var value: Dictionary=before.journey.build.powers.duplicate(true)
	if report.evacuated and report.site_facts.get("cash",{}).get("searched",false) and not generated.powers.sample.is_empty():
		value.owned.append(generated.powers.sample)
		value.sources.append({"ability_id":generated.powers.sample,"transaction_id":report.sortie_id,"generated":generated.duplicate(true)})
	if progression(value):
		if not report.powers.accepted.is_empty():
			# Camp JSON uses the original decimal transport. Keep V2 effect clocks exact.
			var event_record: Dictionary = JSON.parse_string(RecordEncoding.stringify({"events":report.powers.accepted}))
			value.uses.append({"day":before.day, "binding":report.powers.binding.duplicate(true),
				"loadout":report.powers.loadout.duplicate(true), "event_record":event_record})
	else:
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
	if generated.get("layout", {}).has("loading_yard") and not WorldgenState.industrial_yard_enabled(camp):
		return "INDUSTRIAL_POWER_SOURCE_MODE"
	if generated.get("layout", {}).has("rescue_court") and not CampaignRules.midgame_enabled(campaign):
		return "RESCUE_COURT_POWER_SOURCE_MODE"
	if not camp.journey.build.get("persona") is Dictionary or not TransactionReceipt.same(generated.persona.facts,camp.journey.build.persona): return "PERSONA_POWER_SOURCE"
	return ""
