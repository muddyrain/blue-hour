class_name RescuePoolState
extends RefCounted
## Explicit108 adapter. Existing transactions own every join, result, edit and suspend.

const SCHEMA: int = 108
const FORMAT: String = "BH_RESCUE_POOL_V1"
const SCOPE: String = "RESCUE_POOL_PILOT"
const MAX_ROSTER: int = 4 # PROJECT_TEMP, includes permanent history; five actors not enabled.
const CANDIDATES: Array[int] = [3,4,5]


static func is_state(data: Dictionary) -> bool:
	return SurvivalContracts.integer(data.get("schema_version"),SCHEMA,SCHEMA)


static func is_family(data: Dictionary) -> bool:
	return is_state(data) or RosterState.is_family(data)


static func initial(seed: String = "") -> Dictionary:
	var value: Dictionary = TrainingState.initial()
	value.format = FORMAT
	value.seed = RunSave.new_profile_id() if seed.is_empty() else seed.md5_text()
	return value


static func snapshot(camp: Dictionary, journey: Dictionary, recruits: Array, history: Array = []) -> Dictionary:
	var value: Dictionary = TrainingState.snapshot(camp,journey,recruits,history)
	value.schema_version = SCHEMA
	return value


static func available(base: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	if (base.crew.size()>=RosterState.MAX_HISTORY or RosterState.living_count(base)>=RosterState.MAX_LIVING) if RosterState.is_family(base) else base.crew.size()>=MAX_ROSTER:
		return ids
	for id: int in CANDIDATES:
		if SurvivorRoster.member(base.crew,id).is_empty():
			ids.append(id)
	return ids


static func choice(base: Dictionary, identity: String) -> int:
	var ids: Array[int] = available(base)
	if ids.is_empty():
		return 0
	# Entropy is reproducible; the original base/rules hashes bind it to run/root/sortie.
	var seed: String = String(base.journey.seed)+":"+identity.get_slice(":",1)+":rescue"
	return ids[seed.sha256_text().substr(0,8).hex_to_int() % ids.size()]


static func offer(base: Dictionary, identity: String, mission: String) -> Dictionary:
	var id: int = choice(base,identity) if mission=="rescue" else 0
	return {} if id==0 else {"member_id":id,"definition_id":"crew_%d" % id,"weapon_id":"long_rifle" if id==4 else "carbine"}


static func weapon(profile: String, id: int) -> Dictionary:
	var kind: String = "long_rifle" if id==4 else "carbine"
	return {"instance_id":"%s:recruit:%d:%s" % [profile,id,kind],"weapon_id":kind,"condition":"ready","origin":"rescue-first-contact","acquired_sortie":""}


static func grant(value: Dictionary, id: int) -> void:
	var members: Array[Dictionary] = [{"id":id,"health":200.0}]
	SurvivorRoster.initialize(members)
	GrowthRules.initialize(members)
	TraitRules.initialize(members)
	TrainingState.initialize(members)
	value.crew.append(members[0])
	var gun: Dictionary = weapon(value.profile_id,id)
	if WeaponState.is_family(value):
		gun = WeaponModifiers.baseline(gun)
	value.weapons.append(gun)
	value.loadout.append({"member_id":id,"instance_id":gun.instance_id})


static func problem(data: Dictionary) -> String:
	return EnemyState.problem(data) if EnemyState.is_state(data) else WeaponState.problem(data) if WeaponState.is_state(data) else RosterState.problem(data) if RosterState.is_family(data) else TrainingState.family_problem(data,true) if is_state(data) else "POOL_FORMAT"


static func natural_problem(data: Dictionary, roster: bool = false, generated_maps: bool = false, build_context: Dictionary = {}) -> String:
	if data.size()!=15 or not data.has_all(FrozenSettlement.STATE_KEYS) or not data.get("origin") is Dictionary or not data.origin.is_empty() or not SurvivalContracts.integer(data.get("settled_sorties"),0,RunSave.MAX_COUNTER) or not data.get("crew") is Array or data.crew.size()<2 or data.crew.size()>(RosterState.MAX_HISTORY if roster else MAX_ROSTER) or not data.get("recruits") is Array or data.recruits.size()>(3 if roster else 2) or not data.get("journey") is Dictionary:
		return "POOL_FIELDS"
	var meta: Dictionary = data.journey
	for key: String in ["format","state"]:
		if not meta.get(key) is String:
			return "POOL_JOURNEY_TYPES"
	if meta.size()!=7 or not meta.has_all(["format","transaction_version","root_id","seed","deaths","active_member_ids","state"]) or meta.format!=(RosterState.FORMAT if roster else FORMAT) or not SurvivalContracts.integer(meta.transaction_version,TransactionReceipt.VERSION,TransactionReceipt.VERSION) or not meta.root_id is String or meta.root_id.length()!=32 or not meta.root_id.is_valid_hex_number(false) or not meta.seed is String or meta.seed.length()!=32 or not meta.seed.is_valid_hex_number(false) or not meta.deaths is Array or not meta.active_member_ids is Array:
		return "POOL_JOURNEY"
	var ids: Array[int] = []
	for member: Variant in data.crew:
		if not member is Dictionary or not SurvivalContracts.integer(member.get("id"),1,5) or int(member.id) in ids or not member.get("definition_id") is String or member.definition_id!="crew_%d" % int(member.id) or not TraitRules.member_problem(member,0,true).is_empty() or not SurvivalContracts.number(member.get("health")) or member.health<0 or member.health>GrowthRules.maximum(member) or not member.get("condition") is String or member.condition!=("active" if member.health>0 else "dead"):
			return "POOL_MEMBER"
		ids.append(int(member.id))
	if 1 not in ids or 2 not in ids or ids.size()!=2+data.recruits.size():
		return "POOL_INITIAL_IDENTITIES"
	# These containers are used by recruit provenance before common_problem below.
	if not data.get("weapons") is Array or not data.get("loadout") is Array:
		return "POOL_INVENTORY_TYPES"
	for item: Variant in data.weapons:
		if not item is Dictionary or not item.get("instance_id") is String:
			return "POOL_WEAPON_TYPES"
	var seen: Array[int] = []
	var previous_sortie: int = 0
	for record: Variant in data.recruits:
		if not record is Dictionary or record.size()!=6 or not record.has_all(["rescue_id","member_id","recruit_id","settlement_id","joined_at_ms","field_status"]):
			return "POOL_RECRUIT_FIELDS"
		for key: String in ["rescue_id","recruit_id","settlement_id","field_status"]:
			if not record[key] is String:
				return "POOL_RECRUIT_TYPES"
		if not SurvivalContracts.integer(record.member_id,3,5) or int(record.member_id) in seen or int(record.member_id) not in ids or record.rescue_id!=RescueState.TARGET or record.recruit_id!="%s:recruit:%d" % [data.profile_id,int(record.member_id)] or record.field_status not in ["RETURNED","LOST"] or not SurvivalContracts.integer(record.joined_at_ms,10000,RunSave.MAX_COUNTER):
			return "POOL_RECRUIT_RECORD"
		var index: String = record.settlement_id.get_slice(":",1)
		if not index.is_valid_int() or not SurvivalContracts.integer(int(index),previous_sortie+1,int(data.settled_sorties)) or record.settlement_id!="%s:%d" % [data.profile_id,int(index)] or WeaponInventory.find(data,weapon(data.profile_id,int(record.member_id)).instance_id).is_empty():
			return "POOL_RECRUIT_SOURCE"
		previous_sortie = int(index)
		seen.append(int(record.member_id))
		if record.field_status=="LOST" and not meta.deaths.any(func(death: Variant) -> bool: return death is Dictionary and death.get("member_id")==record.member_id and death.get("transaction_id")==record.settlement_id and death.get("cause")=="BATTLE"):
			return "POOL_LOST_HISTORY"
	for death: Variant in meta.deaths:
		if not death is Dictionary or not DeathRules.problem(death,data.profile_id).is_empty() or death.get("cause") not in ["BATTLE","STARVATION"] or int(death.transaction_id.get_slice(":",1))>int(data.settled_sorties) or int(death.member_id) not in ids:
			return "POOL_DEATH"
		if int(death.member_id)>2:
			for record: Dictionary in data.recruits:
				if record.member_id==death.member_id and (int(death.transaction_id.get_slice(":",1))<int(record.settlement_id.get_slice(":",1)) or (death.transaction_id==record.settlement_id and record.field_status!="LOST")):
					return "POOL_DEATH_BEFORE_JOIN"
	var life_state: String = DeathRules.journey(data.crew,meta.deaths,data.profile_id,true)
	if life_state=="REVIEW_REQUIRED" or meta.state!=life_state:
		return "POOL_LIFE_HISTORY"
	var active: Array[int] = []
	for member: Dictionary in data.crew:
		if member.health>0:
			active.append(int(member.id))
	active.sort()
	if roster and active.size()>RosterState.MAX_LIVING:
		return "ROSTER_LIVING_LIMIT"
	if not TransactionReceipt.same({"v":active},{"v":meta.active_member_ids}):
		return "POOL_ACTIVE_IDENTITIES"
	var common: Dictionary = data.duplicate(true)
	for member: Dictionary in common.crew:
		member.condition = "active" if member.health>0 else "down"
	return FrozenSettlement.common_problem(common,generated_maps,build_context)
