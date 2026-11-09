class_name SortieSnapshot
extends RefCounted
## Whitelisted simulation values. No resource paths or object deserialization.

const EXPLORATION_VERSION: int = 15
const EXPLORATION_BUILD: String = "M13-EXPLORE-01-1"
const PERSONA_VERSION: int = 14
const PERSONA_BUILD: String = "M12-SURVIVOR-01-1"
const POWER_VERSION: int = 13
const POWER_BUILD: String = "M11-POWER-01-1"
const SEARCH_VERSION: int = 12
const SEARCH_BUILD: String = "M10-SEARCH-01-1"
const COMBAT_VERSION: int = 11
const COMBAT_BUILD: String = "M9-COMBAT-01-1"
const BUILD_VERSION: int = 10
const BUILD_BUILD: String = "M8-BUILD-01-WIN-R1-1"
const CAMPAIGN_VERSION: int = 9
const CAMPAIGN_BUILD: String = "M8-RUN-01-1"
const WEAPON_VERSION: int = 8
const WEAPON_BUILD: String = "M7-WEAPON-01-1"
const OUTDOOR_VERSION: int = 7
const OUTDOOR_BUILD: String = "M6-ROGUE-02-R1-1"
const TASK_VERSION: int = 6
const TASK_BUILD: String = "M6-ROGUE-02-1"
const NEIGHBORHOOD_VERSION: int = 5
const NEIGHBORHOOD_BUILD: String = "M6-WORLD-02-1"
const WORLD_VERSION: int = 4
const WORLD_BUILD: String = "M6-WORLD-01-1"
const ROGUE_VERSION: int = 3
const ROGUE_BUILD: String = "M6-ROGUE-01-1"
const VERSION: int = 1
const ENEMY_VERSION: int = 2
const ENEMY_BUILD: String = "M5-ENEMY-02-1"
const BUILD: String = "P0-FINAL-SAFETY-01-1"
const GROWTH_BUILD: String = "M5-GROWTH-01-1"
const FIELD_BUILD: String = "M5-RESCUE-01B-1"
const TRAIT_BUILD: String = "M5-TRAIT-01-1"
const QUALITY_BUILD: String = "M5-WEAPON-03A-1"
const ROSTER_BUILD: String = "M5-ROSTER-UX-01-1"
const POOL_BUILD: String = "M5-RESCUE-02-1"
const TRAINING_BUILD: String = "M5-TRAINING-01-1"
const Supplies: Array[MissionSupply] = [preload("res://src/features/camp/scavenge.tres"), preload("res://src/features/camp/supermarket.tres"), preload("res://src/features/camp/rescue.tres")]
const SIM: Dictionary = {"phase":TYPE_INT,"elapsed":TYPE_FLOAT,"loot":TYPE_INT,"food_loot":TYPE_INT,"kills":TYPE_INT,"goal":TYPE_VECTOR2,"_spawn_clock":TYPE_FLOAT,"_ai_clock":TYPE_FLOAT,"_engine_clock":TYPE_FLOAT,"_spawn_count":TYPE_INT,"_spawn_attempts":TYPE_INT}
const ACTOR: Dictionary = {"actor_id":TYPE_INT,"member_id":TYPE_INT,"definition_id":TYPE_STRING_NAME,"is_enemy":TYPE_BOOL,"health":TYPE_FLOAT,"max_health":TYPE_FLOAT,"speed":TYPE_FLOAT,"cooldown":TYPE_FLOAT,"weapon_instance_id":TYPE_STRING,"call_sign":TYPE_STRING,"confirmed_kills":TYPE_INT,"damage_received":TYPE_FLOAT,"permanent_death":TYPE_BOOL,"permanent_death_enabled":TYPE_BOOL,"activity":TYPE_INT,"position":TYPE_VECTOR2,"path":TYPE_PACKED_VECTOR2_ARRAY,"aim":TYPE_VECTOR2,"_path_index":TYPE_INT,"visible":TYPE_BOOL}
const VISUAL: Dictionary = {"_clock":TYPE_FLOAT,"_walk_clock":TYPE_FLOAT,"_hit_clock":TYPE_FLOAT,"_fire_clock":TYPE_FLOAT,"_attack_clock":TYPE_FLOAT,"_defeat_clock":TYPE_FLOAT,"_is_defeated":TYPE_BOOL,"_facing":TYPE_VECTOR2,"_movement":TYPE_VECTOR2,"_aim":TYPE_VECTOR2,"_hit_direction":TYPE_VECTOR2,"_attack_direction":TYPE_VECTOR2,"position":TYPE_VECTOR2}
const CONTACT_VISUAL: Dictionary = {"_walk_rest":TYPE_FLOAT,"_contact_display":TYPE_VECTOR2,"_contact_initialized":TYPE_BOOL}
const KEYS: Array[String] = ["version","build","compatibility","map","sim","sites","worker","active_site","survivors","enemies","weapons","threat","growth","camera","viewport","hunger","drill"]


static func duration_matches(elapsed: float, duration_ms: Variant) -> bool:
	if not SurvivalContracts.integer(duration_ms,0,SurvivalContracts.MAX_ID):
		return false
	# JSON may cross an exact millisecond boundary by a few double ULPs.
	# Preserve the captured integer, accepting only its original floor interval.
	var milliseconds: float = elapsed * 1000.0
	return milliseconds >= float(duration_ms) - 0.000001 and milliseconds < float(duration_ms) + 1.000001


static func supply_for(identity: String) -> MissionSupply:
	for item: MissionSupply in Supplies:
		if String(item.layout.id) == identity:
			return item
	return null


static func supply_for_world(value: Dictionary) -> MissionSupply:
	if (value.get("version")==ROGUE_VERSION or value.get("version")==WORLD_VERSION or value.get("version")==NEIGHBORHOOD_VERSION or task_version(value.get("version"))):
		return DailyActions.supply(value.generated) if DailyActions.problem(value.get("generated")).is_empty() else null
	if value.get("rescue_mission") == "rescue": return Supplies[2]
	return supply_for(value.map)


static func capture(world: Expedition) -> Dictionary:
	if not world.field_join_error.is_empty() or not world.is_paused or not world.battle_survival or world.is_practice or world.los_setup != null or world.threat_rehearsal or world._practice_manual_waves or world.phase == Expedition.Phase.FINISHED:
		return {}
	if world.bus_view != null and world.bus_view.stage in ["arriving","disembarking"]: world.bus_view.skip()
	var rows: Array = []
	var foes: Array = []
	for actor: FieldActor in world.survivors:
		rows.append(_actor(actor))
	for actor: FieldActor in world.enemies:
		foes.append(_actor(actor))
	var captured: Dictionary = {"version":ENEMY_VERSION if world.enemy_mode else VERSION,"build":ENEMY_BUILD if world.enemy_mode else QUALITY_BUILD if WeaponState.is_state(world.field_departure) else ROSTER_BUILD if RosterState.is_family(world.field_departure) else POOL_BUILD if world.pool_mode else TRAINING_BUILD if world.training_mode else TRAIT_BUILD if world.trait_mode else FIELD_BUILD if world.field_join_mode else (GROWTH_BUILD if world.growth_mode else BUILD),"compatibility":compatibility(world),"map":String(world.layout.id),
		"sim":_fields(world,SIM),"sites":{"cash":{"searched":world.searched,"progress":world.search_progress},"food":{"searched":world._food_site.searched,"progress":world._food_site.progress}},
		"worker":world.search_actor.member_id if world.search_actor != null else 0,"active_site":String(world._active_site.kind) if world._active_site != null else "",
		"survivors":rows,"enemies":foes,"weapons":world.weapon_loot.duplicate(true),
		"threat":_fields(world.threat,{"stage":TYPE_INT,"interval":TYPE_FLOAT,"transitions":TYPE_INT}),
		"growth":world.growth_inputs.snapshot(world.sortie_id,world.layout.id,world.elapsed),
		"camera":_fields(world.camera,{"position":TYPE_VECTOR2,"zoom":TYPE_VECTOR2}),"viewport":_encode(world.get_viewport_rect().size),"hunger":world.hunger_trial,
		"drill":{"enabled":world.battle_drill,"deployed":world.drill_panel._deployed.duplicate()}}
	if world.rescue_mode:
		captured.rescue_mission = String(world.supply.id)
		captured.rescue = world.rescue_target.snapshot() if world.rescue_target != null else {}
	if world.growth_mode:
		captured.xp_inputs = world.xp_inputs.snapshot(world)
	if world.trait_mode:
		captured.trait_inputs = world.trait_inputs.snapshot(world)
	if world.field_join_mode:
		captured.field_joins = world.field_joins.duplicate(true)
	captured.build = String(captured.build) + "+" + FieldContacts.BUILD
	if not world.supply.generated.is_empty():
		captured.version = EXPLORATION_VERSION if world.exploration_mode() else PERSONA_VERSION if world.persona_mode() else POWER_VERSION if world.power_mode() else SEARCH_VERSION if world.parallel_search else COMBAT_VERSION if world.combat_mode() else BUILD_VERSION if (world.supply.generated.get("version")==7 or (world.supply.generated.get("version")==8 or world.supply.generated.get("version")==9)) else CAMPAIGN_VERSION if world.supply.generated.get("version")==6 else WEAPON_VERSION if world.supply.generated.get("version")==5 else (OUTDOOR_VERSION if TaskActions.outdoor_site(world.supply.generated,&"cash") else TASK_VERSION) if world.supply.generated.get("version")==4 else NEIGHBORHOOD_VERSION if world.supply.generated.get("version")==3 else WORLD_VERSION if world.supply.generated.get("version")==2 else ROGUE_VERSION
		captured.build += "+"+_daily_build(captured.version)
		captured.generated = world.supply.generated.duplicate(true)
	if captured.version==WORLD_VERSION or captured.version==NEIGHBORHOOD_VERSION or task_version(captured.version):
		captured.sites=WorldSites.facts(world)
		captured.active_site=String(world._active_site.id) if world._active_site!=null else ""
	if task_version(captured.version): captured.task_event=world.task_event.duplicate(true)
	if (captured.version==CAMPAIGN_VERSION or (captured.version==BUILD_VERSION or combat_version(captured.version))): captured.encounter=world.encounter.snapshot()
	if (captured.version==BUILD_VERSION or combat_version(captured.version)): captured.support=world.basic_support.snapshot()
	if world.combat_mode(): captured.combat=world.combat.snapshot()
	if world.parallel_search:
		captured.worker=0
		captured.active_site=""
		captured.jobs=world.search_assignments.snapshot()
	if world.power_mode(): captured.powers=world.powers.duplicate(true)
	return captured


static func problem(value: Variant, receipt: Dictionary) -> String:
	var enemy_mode: bool = EnemyState.is_state(receipt.base)
	var generated: bool = value is Dictionary and (value.get("version")==ROGUE_VERSION or value.get("version")==WORLD_VERSION or value.get("version")==NEIGHBORHOOD_VERSION or task_version(value.get("version")))
	if not value is Dictionary or value.size() != int(search_version(value.get("version"))) + int(power_version(value.get("version"))) + int(combat_version(value.get("version"))) + KEYS.size() + (2 if RescueState.is_family(receipt.base) else 0) + (1 if GrowthState.is_family(receipt.base) else 0) + int(FieldJoinState.is_family(receipt.base)) + int(TraitState.is_family(receipt.base)) + int(generated) + int(task_version(value.get("version"))) + int((value.get("version")==CAMPAIGN_VERSION or (value.get("version")==BUILD_VERSION or combat_version(value.get("version")))))+int((value.get("version")==BUILD_VERSION or combat_version(value.get("version")))) or not value.has_all(KEYS) or not SurvivalContracts.json_value(value):
		return "WORLD_FIELDS"
	var base_build: String = ENEMY_BUILD if enemy_mode else QUALITY_BUILD if WeaponState.is_state(receipt.base) else ROSTER_BUILD if RosterState.is_family(receipt.base) else POOL_BUILD if RescuePoolState.is_family(receipt.base) else TRAINING_BUILD if TrainingState.is_state(receipt.base) else TRAIT_BUILD if TraitState.is_family(receipt.base) else FIELD_BUILD if FieldJoinState.is_family(receipt.base) else (GROWTH_BUILD if GrowthState.is_family(receipt.base) else BUILD)
	if generated:
		if not enemy_mode or receipt.rules.get("data_version")!=(10 if value.version==EXPLORATION_VERSION else 9 if combat_version(value.version) else 8 if value.version==BUILD_VERSION else 7 if value.version==CAMPAIGN_VERSION else 6 if value.version==WEAPON_VERSION else 5 if task_version(value.version) else 4 if value.version==NEIGHBORHOOD_VERSION else 3 if value.version==WORLD_VERSION else 2) or not value.get("generated") is Dictionary or not TransactionReceipt.same(value.generated,receipt.rules.mission.generated) or not DailyActions.problem(value.generated).is_empty():
			return "WORLD_DAILY_BINDING"
		if value.version==OUTDOOR_VERSION and not TaskActions.outdoor_site(value.generated,&"cash"): return "WORLD_OUTDOOR_SOURCE"
		if value.generated.version != (9 if value.version==EXPLORATION_VERSION else 8 if combat_version(value.version) else 7 if value.version==BUILD_VERSION else 6 if value.version==CAMPAIGN_VERSION else 5 if value.version==WEAPON_VERSION else 4 if task_version(value.version) else 3 if value.version==NEIGHBORHOOD_VERSION else 2 if value.version==WORLD_VERSION else 1): return "WORLD_GENERATION_VERSION"
	elif (receipt.rules.get("data_version")==2 or receipt.rules.get("data_version")==3 or receipt.rules.get("data_version")==4 or receipt.rules.get("data_version")==5 or (receipt.rules.get("data_version")==6 or (receipt.rules.get("data_version")==7 or (receipt.rules.get("data_version")==8 or (receipt.rules.get("data_version")==9 or receipt.rules.get("data_version")==10))))):
		return "WORLD_DAILY_VERSION"
	var contact_build: bool = value.build == base_build + "+" + FieldContacts.BUILD + ("+"+_daily_build(value.version) if generated else "")
	# Legacy snapshots remain strictly authenticatable in completed receipt history.
	# Resuming their different motion semantics is separately rejected by apply().
	if value.version != (int(value.version) if task_version(value.get("version")) else NEIGHBORHOOD_VERSION if value.get("version")==NEIGHBORHOOD_VERSION else WORLD_VERSION if value.get("version")==WORLD_VERSION else ROGUE_VERSION if generated else ENEMY_VERSION if enemy_mode else VERSION) or ((generated or value.build != base_build) and not contact_build) or not value.map is String or (value.map!=value.generated.layout.id if generated else supply_for(value.map)==null) or not value.hunger is bool:
		return "WORLD_VERSION_OR_MAP"
	if not value.compatibility is String or value.compatibility.length() != 64 or not value.compatibility.is_valid_hex_number(false):
		return "WORLD_COMPATIBILITY"
	if not value.drill is Dictionary or value.drill.size() != 2 or not value.drill.has_all(["enabled","deployed"]) or not value.drill.enabled is bool or not value.drill.deployed is Array or value.drill.deployed.size() > FieldJoinRules.participants(receipt).size():
		return "WORLD_DRILL_FIELDS"
	var deployed: Array[int] = []
	for id: Variant in value.drill.deployed:
		if not SurvivalContracts.integer(id,1,SurvivalContracts.MAX_ID) or int(id) in deployed or SurvivorRoster.member(FieldJoinRules.participants(receipt),int(id)).is_empty() or not value.drill.enabled:
			return "WORLD_DRILL_SOURCE"
		deployed.append(int(id))
	if not _shape(value.sim,SIM) or not _shape(value.camera,{"position":TYPE_VECTOR2,"zoom":TYPE_VECTOR2}) or not _vector(value.viewport):
		return "WORLD_SIM_FIELDS"
	var sim: Dictionary = value.sim
	if int(sim.phase) not in [0,1,2] or sim.elapsed < 0 or sim.loot < 0 or sim.food_loot < 0 or sim.kills < 0 or sim._spawn_count < 0:
		return "WORLD_SIM_RANGE"
	if (sim.phase == 1 and (sim.elapsed + 0.0001 < 20 or sim._engine_clock <= 0 or sim._engine_clock > 3)) or (sim.phase == 2 and (sim.elapsed + 0.0001 < 23 or sim._engine_clock > 0)):
		return "WORLD_BUS_CLOCK"
	var supply: MissionSupply = supply_for_world(value)
	if (value.version==WORLD_VERSION or value.version==NEIGHBORHOOD_VERSION or task_version(value.version)):
		var issue: String = WorldSites.problem(value.generated.sites,value.sites,value.version==EXPLORATION_VERSION)
		if not issue.is_empty(): return issue
		var carry: Dictionary = WorldSites.carry(value.generated.sites,value.sites,receipt.transaction_id,true,value.generated)
		if sim.loot!=carry.loot or sim.food_loot!=carry.food or not TransactionReceipt.same({"v":value.weapons},{"v":carry.weapons}): return "WORLD_SITE_CARRY"
	else:
		if not value.sites is Dictionary or value.sites.size() != 2 or not value.sites.has_all(["cash","food"]):
			return "WORLD_SITES"
		for kind: String in ["cash","food"]:
			var site: Variant = value.sites[kind]
			if not _shape(site,{"searched":TYPE_BOOL,"progress":TYPE_FLOAT}) or site.progress < 0 or site.progress > 31 or (not supply.supports(StringName(kind)) and (site.searched or site.progress != 0)):
				return "WORLD_SITE_PROGRESS"
			if site.searched != (site.progress >= 30):
				return "WORLD_SITE_COMPLETION"
		if sim.loot != (supply.cash_reward if value.sites.cash.searched else 0) or sim.food_loot != (supply.food_reward if value.sites.food.searched else 0):
			return "WORLD_CARRY_SOURCE"
		var expected_weapons: Array = [WeaponInventory.reward(receipt.transaction_id,WeaponState.is_family(receipt.base))] if value.sites.cash.searched and supply.has_weapon_sample else []
		if not value.weapons is Array or not _same({"v":value.weapons},{"v":expected_weapons}):
			return "WORLD_WEAPON_SOURCE"
	if task_version(value.version):
		var event_issue: String = TaskActions.event_problem(value.generated,value.sites,value.get("task_event"),int(sim._spawn_count))
		if not event_issue.is_empty(): return event_issue
	if not value.survivors is Array or value.survivors.size() != FieldJoinRules.participants(receipt).size() or not value.enemies is Array or value.enemies.size() > ThreatRules.ENEMY_CAP:
		return "WORLD_ACTOR_COUNTS"
	if (value.version==BUILD_VERSION or combat_version(value.version)):
		var support_issue: String=BuildAuthority.world_problem(value,receipt)
		if not support_issue.is_empty(): return support_issue
	if generated and (power_version(value.version)!=value.generated.has("powers")): return "POWER_MODE_BINDING"
	if generated and ((value.version==PERSONA_VERSION or value.version==EXPLORATION_VERSION)!=value.generated.has("persona")): return "PERSONA_MODE_BINDING"
	if generated and ((value.version==EXPLORATION_VERSION)!=(value.generated.get("version")==9)): return "EXPLORATION_MODE_BINDING"
	if power_version(value.version):
		var power_issue: String=PowerAuthority.world_problem(value,receipt)
		if not power_issue.is_empty(): return power_issue
	if not value.active_site is String: return "WORLD_WORKER_FIELDS"
	var ids: Array[int] = []
	var workers: int = 0
	for row: Variant in value.survivors:
		if not row is Dictionary:
			return "WORLD_SURVIVOR_FIELDS"
		if not _actor_shape(row,false,contact_build,value.version==OUTDOOR_VERSION or magazine_version(value.version),magazine_version(value.version) and not (combat_version(value.version) and not row.has("magazine"))) or row.state.is_enemy:
			return "WORLD_SURVIVOR_FIELDS"
		var state: Dictionary = row.state
		var id: int = int(state.member_id)
		var participant: Dictionary = SurvivorRoster.member(FieldJoinRules.participants(receipt),id)
		var checkpoint: Dictionary = SurvivorRoster.member(receipt.health,id)
		var member: Dictionary = SurvivorRoster.member(FieldJoinRules.context(receipt).crew,id)
		if participant.is_empty() or id in ids or checkpoint.is_empty() or member.is_empty():
			return "WORLD_MEMBER_ID"
		ids.append(id)
		if state.definition_id != member.definition_id or state.call_sign != member.call_sign or state.health != checkpoint.health or state.weapon_instance_id != participant.weapon_instance_id or state.max_health != SurvivorGrowth.maximum(receipt.base,member) or not state.permanent_death_enabled or state.speed != 125.0 * (TraitRules.factor(member,"move") if TraitState.is_family(receipt.base) else 1.0) * PersonaState.factor(value.get("generated",{}),id,"move") * BuildAuthority.factor(value,"move"):
			return "WORLD_MEMBER_CHECKPOINT"
		var is_axe: bool=combat_version(value.version) and CombatEquipment.melee(WeaponInventory.for_member(FieldJoinRules.context(receipt),id).weapon_id)
		if magazine_version(value.version) and row.has("magazine")==is_axe: return "WORLD_ATTACK_MODE_FIELDS"
		if magazine_version(value.version) and not is_axe:
			var magazine_issue: String=WeaponMagazine.problem(row.magazine,state.weapon_instance_id,WeaponInventory.for_member(FieldJoinRules.context(receipt),id).weapon_id,PersonaState.factor(value.get("generated",{}),id,"reload")*BuildAuthority.factor(value,"reload"))
			if not magazine_issue.is_empty():return magazine_issue
		if (state.health == 0) != state.permanent_death or (state.health == 0) != (state.activity == FieldActor.Activity.DOWN) or state.health + state.damage_received != participant.health_before + BuildAuthority.healed(receipt.get("support",[]),id):
			return "WORLD_DEATH_OR_DAMAGE"
		if (value.version==OUTDOOR_VERSION or magazine_version(value.version)) and state.health>0 and state.activity!=FieldActor.Activity.SEARCHING and not state.visible: return "WORLD_WORKER_VISIBILITY"
		if int(state.activity) in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]:
			workers += 1
			if not search_version(value.version):
				if id != value.worker or state.visible != (state.activity==FieldActor.Activity.RECOVERING):
					return "WORLD_WORKER_ID"
				if value.version==OUTDOOR_VERSION or magazine_version(value.version):
					var outdoor: bool = TaskActions.outdoor_site(value.generated,StringName(value.active_site))
					if (state.activity==FieldActor.Activity.RECOVERING)!=outdoor: return "WORLD_WORKER_POLICY"
					if outdoor and _vec(state.position).distance_to(_work_point(value.generated,String(value.active_site)))>14.0: return "WORLD_WORKER_DISTANCE"
	if not SurvivalContracts.integer(value.worker,0,SurvivalContracts.MAX_ID) or not value.active_site is String or value.active_site not in ([""]+value.sites.keys() if (value.version==WORLD_VERSION or value.version==NEIGHBORHOOD_VERSION or task_version(value.version)) else ["","cash","food"]) or (not search_version(value.version) and workers > 1):
		return "WORLD_WORKER_FIELDS"
	var participant_order: Array = []
	for row: Dictionary in FieldJoinRules.participants(receipt):
		participant_order.append(int(row.id))
	if not _same({"v":ids},{"v":participant_order}):
		return "WORLD_EXECUTION_ORDER"
	if (value.worker == 0) != value.active_site.is_empty() or (value.worker != 0 and (int(value.worker) not in ids or value.sites[value.active_site].searched)):
		return "WORLD_WORKER_SOURCE"
	if value.worker != 0 and int(_member(value.survivors,int(value.worker)).state.activity) not in ([1,2,4] if value.version==OUTDOOR_VERSION or magazine_version(value.version) else [1,2]):
		return "WORLD_WORKER_ACTIVITY"
	if search_version(value.version):
		var jobs_issue: String = _jobs_problem(value,ids)
		if not jobs_issue.is_empty():
			return jobs_issue
	var enemy_ids: Array[int] = []
	for row: Variant in value.enemies:
		if not _actor_shape(row,enemy_mode,contact_build) or not row.state.is_enemy or row.state.health <= 0 or int(row.state.activity) not in [0,1] or row.state.member_id != 0 or (row.state.actor_id >= sim._spawn_count and int(row.state.actor_id)-10000 not in deployed) or int(row.state.actor_id) in enemy_ids or (not enemy_mode and (row.state.max_health != 54 or row.state.speed != 34)):
			return "WORLD_ENEMY_ID_OR_STATE"
		enemy_ids.append(int(row.state.actor_id))
	if not _shape(value.threat,{"stage":TYPE_INT,"interval":TYPE_FLOAT,"transitions":TYPE_INT}) or int(value.threat.stage) not in [0,1,2,3] or value.threat.transitions < 0 or value.threat.transitions > 3:
		return "WORLD_THREAT"
	if combat_version(value.get("version")):
		var issue: String=CombatRuntime.problem(value.get("combat"),value,receipt)
		if not issue.is_empty(): return issue
	var director: ThreatDirector = ThreatDirector.new()
	var spawn_factor: float = CampaignPressureV1.spawn_factor(value.generated) if (
		value.version == CAMPAIGN_VERSION or value.version == BUILD_VERSION or combat_version(value.version)) else 1.0
	director.update(float(sim.elapsed), 105, 7.0 * spawn_factor)
	if value.threat.stage != director.stage or value.threat.interval != director.interval:
		return "WORLD_THREAT_CLOCK"
	if (value.version==CAMPAIGN_VERSION or (value.version==BUILD_VERSION or combat_version(value.version))):
		var encounter_issue: String=EncounterRuntime.facts_problem(value.get("encounter"),value.generated,value.get("xp_inputs",{}),value.sites)
		if not encounter_issue.is_empty(): return encounter_issue
		var boss_rows: int=0
		for row: Dictionary in value.enemies:
			if row.state.actor_id==0: boss_rows+=1
		if not value.generated.encounter.is_empty() and boss_rows!=int(value.encounter.health>0): return "WORLD_BOSS_ACCOUNTING"
	if enemy_mode:
		for row: Dictionary in value.enemies:
			var issue: String = _boss_actor_problem(row,value) if (value.version==CAMPAIGN_VERSION or (value.version==BUILD_VERSION or combat_version(value.version))) and not value.generated.encounter.is_empty() and row.state.actor_id==0 else CombatEnemyRules.snapshot_problem(row,value,receipt,(value.version==CAMPAIGN_VERSION or (value.version==BUILD_VERSION or combat_version(value.version))) and not value.generated.encounter.is_empty() and int(row.state.actor_id) in EncounterRuntime.summon_ids(value.encounter))
			if not issue.is_empty():
				return issue
	if not value.growth is Dictionary or not value.growth.get("members") is Array or value.growth.members.size() != ids.size() or value.growth.get("sortie_id") != receipt.transaction_id or value.growth.get("map_id") != value.map or not duration_matches(sim.elapsed,value.growth.get("duration_ms")):
		return "WORLD_GROWTH"
	var total: int = 0
	if RescueState.is_family(receipt.base):
		if not value.get("rescue") is Dictionary or value.get("rescue_mission") not in ["rescue","scavenge","supermarket"] or value.rescue_mission != receipt.rules.mission.mission_id or supply.layout.id != StringName(value.map):
			return "RESCUE_WORLD_REQUIRED"
		var expected_target: bool = supply.id == &"rescue" and (not RescuePoolState.available(receipt.base).is_empty() if RescuePoolState.is_family(receipt.base) else receipt.base.recruits.is_empty())
		if expected_target:
			var rescue_issue: String = RescueTarget.snapshot_problem(value.rescue,ids,FieldJoinState.is_family(receipt.base),RescuePoolState.choice(receipt.base,receipt.transaction_id) if RescuePoolState.is_family(receipt.base) else 3,5 if RescuePoolState.is_family(receipt.base) else 3,supply.layout.world_bounds)
			if not rescue_issue.is_empty(): return rescue_issue
		elif not value.rescue.is_empty(): return "RESCUE_WORLD_UNEXPECTED"
	if FieldJoinState.is_family(receipt.base):
		if not value.get("field_joins") is Array or not TransactionReceipt.same({"v":value.field_joins},{"v":receipt.joins}):
			return "FIELD_JOIN_WORLD_FACT"
		if not receipt.joins.is_empty():
			if value.rescue.get("status") != "IN_FIELD_JOINED" or sim.elapsed*1000.0+0.000001 < receipt.joins[0].at_ms:
				return "FIELD_JOIN_WORLD_TARGET"
		elif value.rescue.get("status") == "IN_FIELD_JOINED":
			return "FIELD_JOIN_NOT_DURABLE"
	if GrowthState.is_family(receipt.base):
		var xp_issue: String = GrowthRules.inputs_problem(value.get("xp_inputs"),RunTransaction.token_for(receipt),value.growth,FieldJoinRules.participants(receipt),FieldJoinRules.context(receipt),value.get("support",{}).get("accepted",[]))
		if not xp_issue.is_empty():
			return xp_issue
		if value.xp_inputs.spawn_count != sim._spawn_count or value.xp_inputs.diagnostic != value.drill.enabled:
			return "XP_WORLD_SOURCE"
		for event: Dictionary in value.xp_inputs.events:
			if FieldJoinState.is_family(receipt.base) and not receipt.joins.is_empty() and event.member_id == receipt.joins[0].member_id and event.at_ms < receipt.joins[0].at_ms:
				return "FIELD_JOIN_EARLY_XP"
			if int(event.enemy_id) in enemy_ids:
				return "XP_ENEMY_STILL_ACTIVE"
	if TraitState.is_family(receipt.base):
		var report: Dictionary = {"participants":FieldJoinRules.participants(receipt),"growth_inputs":value.growth,"xp_inputs":value.xp_inputs,"field_joins":receipt.joins,"searched":WorldSites.completed(value.generated.sites,value.sites,"cash")>0 if (value.version==WORLD_VERSION or value.version==NEIGHBORHOOD_VERSION or task_version(value.version)) else value.sites.cash.searched,"food_searched":WorldSites.completed(value.generated.sites,value.sites,"food")>0 if (value.version==WORLD_VERSION or value.version==NEIGHBORHOOD_VERSION or task_version(value.version)) else value.sites.food.searched}
		if value.version==PERSONA_VERSION or value.version==EXPLORATION_VERSION: report.site_facts=value.sites
		var trait_issue: String = TraitRules.inputs_problem(value.get("trait_inputs"),RunTransaction.token_for(receipt),report,FieldJoinRules.context(receipt),value.get("generated",{}))
		if not trait_issue.is_empty():
			return trait_issue
	var growth_ids: Array[int] = []
	var defeated_ids: Array[int] = []
	for row: Variant in value.growth.members:
		if not row is Dictionary or row.size() != 3 or not row.has_all(["member_id","total","recent"]) or int(row.member_id) not in ids or int(row.member_id) in growth_ids or not SurvivalContracts.integer(row.total,0,SurvivalContracts.MAX_ID) or not row.recent is Array or row.recent.size() > SurvivorGrowth.RECENT_LIMIT or row.recent.size() > row.total:
			return "WORLD_GROWTH_MEMBER"
		growth_ids.append(int(row.member_id))
		var actor_row: Dictionary = _member(value.survivors,int(row.member_id))
		if row.total != actor_row.state.confirmed_kills:
			return "WORLD_GROWTH_COUNT"
		var previous_at: int = -1
		var item: Dictionary = WeaponInventory.for_member(FieldJoinRules.context(receipt),int(row.member_id))
		for event: Variant in row.recent:
			if not event is Dictionary or (event.size() != 5 or not event.has_all(["kind","enemy_id","at_ms","weapon_id","instance_id"])) and not ((value.version==BUILD_VERSION or combat_version(value.version)) and BuildAuthority.ability(event) and BuildAuthority.ability_problem(event,receipt.transaction_id,false).is_empty()):
				return "WORLD_GROWTH_EVENT_FIELDS"
			if event.kind != "defeat" or not SurvivalContracts.integer(event.enemy_id,0,SurvivalContracts.MAX_ID) or int(event.enemy_id) in defeated_ids or int(event.enemy_id) in enemy_ids or (event.enemy_id >= sim._spawn_count and int(event.enemy_id)-10000 not in deployed):
				return "WORLD_GROWTH_DEFEAT"
			if not SurvivalContracts.integer(event.at_ms,0,int(value.growth.duration_ms)) or event.at_ms < previous_at or (not BuildAuthority.ability(event) and (event.instance_id != item.instance_id or event.weapon_id != item.weapon_id)):
				return "WORLD_GROWTH_EVENT_SOURCE"
			previous_at = int(event.at_ms)
			defeated_ids.append(int(event.enemy_id))
		total += int(row.total)
	if total != sim.kills or sim.kills + value.enemies.size() != sim._spawn_count + deployed.size():
		return "WORLD_ENEMY_ACCOUNTING"
	if task_version(value.version):
		for resolution: Dictionary in value.task_event.resolutions:
			for enemy: Dictionary in value.enemies:
				if enemy.state.actor_id==resolution.enemy_id and enemy.behavior.kind!=EnemyRules.NORMAL: return "TASK_EVENT_ENEMY_KIND"
	if (value.version==CAMPAIGN_VERSION or (value.version==BUILD_VERSION or combat_version(value.version))) and not value.generated.encounter.is_empty():
		var summons: Array[int]=EncounterRuntime.summon_ids(value.encounter)
		var seen_summons: Array[int]=[]
		for id:int in summons:
			if id<=0 or id>=sim._spawn_count or id in seen_summons: return "WORLD_BOSS_SUMMON_SOURCE"
			seen_summons.append(id)
			if id not in enemy_ids and not value.xp_inputs.events.any(func(event:Dictionary)->bool:return event.enemy_id==id): return "WORLD_BOSS_SUMMON_MISSING"
			for resolution:Dictionary in value.task_event.resolutions:
				if resolution.reason=="spawned" and resolution.enemy_id==id: return "WORLD_BOSS_SUMMON_DUPLICATE"
	if value.camera.zoom[0] != value.camera.zoom[1] or value.camera.zoom[0] < 0.7 or value.camera.zoom[0] > 1.25 or value.viewport[0] <= 0 or value.viewport[1] <= 0:
		return "WORLD_CAMERA"
	return ""


static func apply(world: Expedition, value: Dictionary) -> String:
	# Older reviewed in-flight worlds retain their exact format/compatibility until return.
	world.parallel_search = search_version(value.get("version"))
	if old_outdoor(value): return "WORLD_OUTDOOR_BUILD_MISMATCH"
	if not String(value.get("build","")).ends_with("+" + FieldContacts.BUILD + ("+"+_daily_build(value.get("version")) if (value.get("version")==ROGUE_VERSION or value.get("version")==WORLD_VERSION or value.get("version")==NEIGHBORHOOD_VERSION or task_version(value.get("version"))) else "")):
		return "WORLD_CONTACT_BUILD_MISMATCH"
	if not world.setup_problem.is_empty() or world.survivors.size() != value.survivors.size() or not world.enemies.is_empty():
		return "WORLD_RECONSTRUCTION_SETUP"
	if compatibility(world) != value.compatibility or _encode(world.get_viewport_rect().size) != value.viewport or world.hunger_trial != value.hunger or world.battle_drill != value.drill.enabled:
		return "WORLD_BUILD_DATA_VIEWPORT_MISMATCH"
	if world.bus_view != null: world.bus_view.skip()
	_restore(world,value.sim,SIM)
	world.drill_panel._deployed.assign(value.drill.deployed)
	if task_version(value.version): world.task_event=value.task_event.duplicate(true)
	world.weapon_loot.assign(value.weapons.duplicate(true))
	for kind: String in value.sites:
		var site: Expedition.SearchSite = world.search_site(StringName(kind))
		site.progress = value.sites[kind].progress
		site.searched = value.sites[kind].searched
	for actor: FieldActor in world.survivors:
		var row: Dictionary = _member(value.survivors,actor.member_id)
		_restore(actor,row.state,ACTOR)
		if magazine_version(value.version) and actor.magazine!=null:actor.magazine.restore(row.magazine)
		_restore(actor.visual,row.visual,_visual_spec(true))
		actor.visual._apply_pose()
	world.search_assignments = SearchAssignments.new()
	if search_version(value.version):
		world.search_assignments.restore(value.jobs)
	elif value.worker != 0:
		world.search_assignments.assign(int(value.worker),String(value.active_site))
		var old_actor: FieldActor = world.search_member(int(value.worker))
		if old_actor.activity in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING]:
			world.search_assignments.begin(old_actor.member_id)
	for row: Dictionary in value.enemies:
		var actor: FieldActor = world._make_actor(true,int(row.state.actor_id),_vec(row.state.position),{},String(row.behavior.kind) if world.enemy_mode else "")
		_restore(actor,row.state,ACTOR)
		_restore(actor.visual,row.visual,_visual_spec(true))
		if world.enemy_mode:
			actor.enemy_behavior.restore(row.behavior)
			actor.sync_enemy_visual()
		actor.visual._apply_pose()
		world.enemies.append(actor)
	if (value.version==CAMPAIGN_VERSION or (value.version==BUILD_VERSION or combat_version(value.version))): world.encounter.restore(value.encounter)
	if (value.version==BUILD_VERSION or combat_version(value.version)):
		world.basic_support.restore(value.support, FirstAidV1.enabled(value.generated))
	if combat_version(value.version):
		world.combat.restore(value.combat)
		world.combat.refresh_toxic(world)
		if world.combat.screamer != null:
			world.combat.screamer.present(world)
		for actor: FieldActor in world.survivors: world.combat.present(actor)
	if power_version(value.version): world.powers=value.powers.duplicate(true)
	world.refresh_power_factors()
	_restore(world.threat,value.threat,{"stage":TYPE_INT,"interval":TYPE_FLOAT,"transitions":TYPE_INT})
	if world.rescue_mode and world.rescue_target != null:
		world.rescue_target.restore(value.rescue)
	if world.growth_mode:
		world.xp_inputs.restore(value.xp_inputs)
	if world.trait_mode:
		world.trait_inputs.restore(value.trait_inputs)
	world.growth_inputs._counts.clear()
	world.growth_inputs._recent.clear()
	for row: Dictionary in value.growth.members:
		world.growth_inputs._counts[int(row.member_id)] = int(row.total)
		world.growth_inputs._recent[int(row.member_id)] = row.recent.duplicate(true)
	_restore(world.camera,value.camera,{"position":TYPE_VECTOR2,"zoom":TYPE_VECTOR2})
	world.camera.force_update_scroll()
	world.is_paused = true
	world._update_ui()
	world.queue_redraw()
	return ""


static func compatibility(world: Expedition) -> String:
	var weapons: Array = []
	for definition: WeaponDefinition in WeaponInventory.Definitions:
		weapons.append(_resource(definition))
	var data: Dictionary = {"build":ENEMY_BUILD if world.enemy_mode else QUALITY_BUILD if WeaponState.is_state(world.field_departure) else ROSTER_BUILD if RosterState.is_family(world.field_departure) else POOL_BUILD if world.pool_mode else TRAINING_BUILD if world.training_mode else TRAIT_BUILD if world.trait_mode else FIELD_BUILD if world.field_join_mode else (GROWTH_BUILD if world.growth_mode else BUILD),"tuning":_resource(world.tuning),"threat":_resource(world.threat.rules),"supply":_resource(world.supply),"weapons":weapons}
	if world.enemy_mode:
		data.enemy_rules = EnemyRules.POLICY
	data.build = String(data.build) + "+" + FieldContacts.BUILD
	if not world.supply.generated.is_empty():
		data.build += "+"+(EXPLORATION_BUILD if world.exploration_mode() else PERSONA_BUILD if world.persona_mode() else POWER_BUILD if world.power_mode() else SEARCH_BUILD if world.parallel_search else COMBAT_BUILD if world.combat_mode() else BUILD_BUILD if (world.supply.generated.get("version")==7 or (world.supply.generated.get("version")==8 or world.supply.generated.get("version")==9)) else CAMPAIGN_BUILD if world.supply.generated.get("version")==6 else WEAPON_BUILD if world.supply.generated.get("version")==5 else (OUTDOOR_BUILD if TaskActions.outdoor_site(world.supply.generated,&"cash") else TASK_BUILD) if world.supply.generated.get("version")==4 else NEIGHBORHOOD_BUILD if world.supply.generated.get("version")==3 else WORLD_BUILD if world.supply.generated.get("version")==2 else ROGUE_BUILD)
		data.generated = world.supply.generated.duplicate(true)
	if (world.supply.generated.get("version")==5 or (world.supply.generated.get("version")==6 or (world.supply.generated.get("version")==7 or (world.supply.generated.get("version")==8 or world.supply.generated.get("version")==9)))):data.magazines=WeaponDefinition.MAGAZINES
	if (world.supply.generated.get("version")==6 or (world.supply.generated.get("version")==7 or (world.supply.generated.get("version")==8 or world.supply.generated.get("version")==9))): data.campaign_policy={"version":CampaignRules.VERSION,"preparations":CampaignRules.PREPARATIONS,"pressure":CampaignRules.BREAKOUT_INTERVAL,"boss":BossDefinition.POLICY}
	if (world.supply.generated.get("version")==7 or (world.supply.generated.get("version")==8 or world.supply.generated.get("version")==9)): data.build_policy=world.supply.generated.build.policy.duplicate(true)
	data.contact = {"distance":FieldContacts.DISTANCE,"approach":FieldContacts.APPROACH,"rechase":FieldContacts.RECHASE,"step":FieldContacts.STEP_DISTANCE,"steps":FieldContacts.MAX_STEPS,"path_parts":FieldContacts.MAX_PATH_PARTS,"pass_dot":FieldContacts.PASS_DOT,"recovery_speed":FieldContacts.RECOVERY_SPEED,"recovery_cap":FieldContacts.MAX_RECOVERY,"recovery_passes":FieldContacts.RECOVERY_PASSES,"yield_speed":FieldContacts.YIELD_SPEED}
	if world.combat_mode(): data.combat_policy={"weapons":CombatEquipment.policy(),"definitions":[_resource(CombatEquipment.definition("fire_axe_v1")),_resource(CombatEquipment.definition("shotgun_v1"))],"toxic":ToxicV1.POLICY}
	if ContentWaveV1.marked(world.supply.generated):
		data.combat_policy.hammer = {"pattern":CombatEquipment.melee_policy(CombatEquipment.HAMMER_ID),
			"definition":_resource(CombatEquipment.definition(CombatEquipment.HAMMER_ID))}
	if ContentWaveV1.eligible(world.supply.generated):
		data.burst_policy = BurstRuntimeV1.POLICY
	if ScreamerPolicyV1.enabled(world.supply.generated):
		data.screamer_policy = {"version":ScreamerPolicyV1.VERSION, "range":ScreamerPolicyV1.RANGE,
			"windup":ScreamerPolicyV1.WINDUP, "max_reinforcements":ScreamerPolicyV1.MAX_REINFORCEMENTS}
	var campaign: Dictionary = world.field_departure.get("journey", {}).get("campaign", {})
	if CampaignRules.weapon_affix_enabled(campaign):
		data.weapon_affix_policy = {"version":campaign.weapon_affix_policy,
			"pierce_factor":AttackRules.PIERCE_DAMAGE_FACTOR, "pierce_radius":AttackRules.PIERCE_HIT_RADIUS,
			"defeat_refund_rounds":WeaponMagazine.DEFEAT_REFUND_ROUNDS}
	if FirstAidV1.enabled(world.supply.generated):
		data.first_aid_policy = {"version":FirstAidV1.VERSION, "source":FirstAidV1.SOURCE_ID,
			"range":FirstAidV1.RANGE, "health_ratio":FirstAidV1.HEALTH_RATIO, "amount":FirstAidV1.HEAL_AMOUNT}
	if world.parallel_search:
		data.search_policy={"version":SearchAssignments.VERSION,"occupancy":"one_member_one_site","order":"site_id"}
	if world.power_mode(): data.power_policy=SpecialPowers.policy(int(world.supply.generated.powers.version))
	if world.persona_mode(): data.persona_policy=SurvivorPersona.policy()
	if world.exploration_mode(): data.exploration_policy=ExplorationLayout.policy()
	return SurvivalContracts.fingerprint(data)


static func _resource(resource: Resource) -> Dictionary:
	var result: Dictionary = {}
	for prop: Dictionary in resource.get_property_list():
		if int(prop.usage) & PROPERTY_USAGE_EDITOR and int(prop.usage) & PROPERTY_USAGE_STORAGE and prop.name != "script":
			result[String(prop.name)] = _encode(resource.get(prop.name))
	return result


static func _actor(actor: FieldActor) -> Dictionary:
	var value: Dictionary = {"state":_fields(actor,ACTOR),"visual":_fields(actor.visual,_visual_spec(true))}
	if not actor.is_enemy and actor.magazine!=null:value.magazine=actor.magazine.snapshot()
	if actor.is_enemy and actor.enemy_behavior!=null:
		value.behavior = actor.enemy_behavior.snapshot()
	return value


static func _fields(object: Object, spec: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in spec:
		result[key] = _encode(object.get(key))
	return result


static func _encode(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x,value.y]
	if value is Rect2:
		return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Resource:
		return _resource(value)
	if value is StringName:
		return String(value)
	if value is Array or value is PackedVector2Array or value is PackedFloat32Array or value is PackedInt32Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_encode(item))
		return result
	if value is Color:
		return value.to_html()
	return value


static func _restore(object: Object, values: Dictionary, spec: Dictionary) -> void:
	for key: String in spec:
		var value: Variant = values[key]
		match spec[key]:
			TYPE_VECTOR2: value = _vec(value)
			TYPE_PACKED_VECTOR2_ARRAY:
				var points: PackedVector2Array = PackedVector2Array()
				for point: Array in value:
					points.append(_vec(point))
				value = points
			TYPE_INT: value = int(value)
			TYPE_FLOAT: value = float(value)
			TYPE_STRING_NAME: value = StringName(value)
		object.set(key,value)


static func _shape(value: Variant, spec: Dictionary) -> bool:
	if not value is Dictionary or value.size() != spec.size() or not value.has_all(spec.keys()):
		return false
	for key: String in spec:
		var item: Variant = value[key]
		match spec[key]:
			TYPE_VECTOR2:
				if not _vector(item): return false
			TYPE_PACKED_VECTOR2_ARRAY:
				if not item is Array or item.size() > 512: return false
				for point: Variant in item:
					if not _vector(point): return false
			TYPE_FLOAT:
				if not _number(item): return false
			TYPE_INT:
				if not SurvivalContracts.integer(item,0,SurvivalContracts.MAX_ID): return false
			TYPE_STRING_NAME,TYPE_STRING:
				if not item is String or item.length() > 128: return false
			_:
				if typeof(item) != spec[key]: return false
	return true


static func _visual_spec(contact: bool) -> Dictionary:
	return VISUAL.merged(CONTACT_VISUAL) if contact else VISUAL


static func _actor_shape(row: Variant, enemy_mode: bool = false, contact: bool = true, outdoor: bool = false, magazines: bool = false) -> bool:
	if not row is Dictionary or row.size() != (3 if enemy_mode or magazines else 2) or (enemy_mode and not row.has("behavior")) or (magazines and not row.has("magazine")) or not _shape(row.get("state"),ACTOR) or not _shape(row.get("visual"),_visual_spec(contact)):
		return false
	if contact and row.visual._walk_rest < 0.0: return false
	var state: Dictionary = row.state
	return int(state.activity) in ([0,1,2,3,4] if outdoor else [0,1,2,3]) and state.health >= 0 and state.health <= state.max_health and state.cooldown >= 0 and state.damage_received >= 0 and (state._path_index <= state.path.size() or state.activity == 3) and row.visual._is_defeated == (state.activity == 3)


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _number(value: Variant) -> bool:
	return SurvivalContracts.number(value) and absf(float(value)) <= 100000000.0


static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))


static func _member(rows: Array, id: int) -> Dictionary:
	for row: Dictionary in rows:
		if int(row.state.member_id) == id:
			return row
	return {}


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return SurvivalContracts.fingerprint(a) == SurvivalContracts.fingerprint(b)

static func _daily_build(version: Variant) -> String:
	return EXPLORATION_BUILD if version==EXPLORATION_VERSION else PERSONA_BUILD if version==PERSONA_VERSION else POWER_BUILD if version==POWER_VERSION else SEARCH_BUILD if version==SEARCH_VERSION else COMBAT_BUILD if version==COMBAT_VERSION else BUILD_BUILD if version==BUILD_VERSION else CAMPAIGN_BUILD if version==CAMPAIGN_VERSION else WEAPON_BUILD if version==WEAPON_VERSION else OUTDOOR_BUILD if version==OUTDOOR_VERSION else TASK_BUILD if version==TASK_VERSION else NEIGHBORHOOD_BUILD if version==NEIGHBORHOOD_VERSION else WORLD_BUILD if version==WORLD_VERSION else ROGUE_BUILD


static func old_outdoor(value: Dictionary) -> bool:
	return value.get("version")==TASK_VERSION and TaskActions.outdoor_site(value.get("generated",{}),&"cash")


static func _work_point(generated: Dictionary, id: String) -> Vector2:
	for site: Dictionary in generated.sites:
		if site.id==id: return TaskActions.site_point(generated,site)
	return Vector2.INF


static func task_version(version: Variant) -> bool:
	return version==TASK_VERSION or version==OUTDOOR_VERSION or magazine_version(version)


static func magazine_version(version: Variant) -> bool:
	return version==WEAPON_VERSION or version==CAMPAIGN_VERSION or (version==BUILD_VERSION or combat_version(version))


static func _boss_actor_problem(row: Dictionary, value: Dictionary) -> String:
	if not row.get("behavior") is Dictionary or row.behavior.size()!=5 or not row.behavior.has_all(["kind","spawn_stage","target_id","state","windup_remaining"]) or not SurvivalContracts.integer(row.behavior.spawn_stage,0,0): return "WORLD_BOSS_BEHAVIOR"
	if not value.get("encounter") is Dictionary or row.state.max_health!=BossDefinition.POLICY.health or row.state.speed!=BossDefinition.POLICY.speed or row.state.health!=value.encounter.get("health") or row.behavior.kind!=EnemyRules.HEAVY or row.behavior.state!="chase" or row.behavior.windup_remaining!=0 or row.behavior.target_id!=0: return "WORLD_BOSS_ACTOR"
	if PumpStationAction.enabled(value.generated):
		var stopped: bool = PumpStationAction.stopped(value.sites)
		var lane: Dictionary = value.encounter.pump.lane
		if row.state.visible != stopped or (not stopped and _vec(row.state.position) != _vec(value.generated.encounter.position)):
			return "WORLD_PUMP_BOSS_VISIBILITY"
		if not lane.is_empty() and _vec(lane.from) != _vec(row.state.position):
			return "WORLD_PUMP_BOSS_LOCK"
	return ""


static func combat_version(version: Variant) -> bool:
	return version==COMBAT_VERSION or search_version(version)


static func _jobs_problem(value: Dictionary, ids: Array[int]) -> String:
	if value.worker != 0 or value.active_site != "":
		return "SEARCH_LEGACY_SLOT"
	var site_ids: Array[String] = []
	for id: String in value.sites:
		site_ids.append(id)
	var issue: String = SearchAssignments.problem(value.get("jobs"),ids,site_ids)
	if not issue.is_empty():
		return issue
	var owners: Dictionary = {}
	for job: Dictionary in value.jobs.assignments:
		var actor: Dictionary = _member(value.survivors,int(job.member_id)).state
		var site: Dictionary = value.sites[job.site_id]
		if actor.health <= 0 or site.searched:
			return "SEARCH_UNAVAILABLE_SOURCE"
		if value.get("rescue") is Dictionary and value.rescue.get("status")=="IN_PROGRESS" and value.rescue.get("worker")==job.member_id:
			return "SEARCH_RESCUE_OCCUPIED"
		var outdoor: bool = TaskActions.outdoor_site(value.generated,StringName(job.site_id))
		var door: Vector2 = _work_point(value.generated,job.site_id)
		if job.phase=="working":
			if actor.activity != (FieldActor.Activity.RECOVERING if outdoor else FieldActor.Activity.SEARCHING) or actor.visible != outdoor or _vec(actor.position).distance_to(door)>14.0 or not actor.path.is_empty() or actor._path_index!=0:
				return "SEARCH_WORKING_STATE"
		else:
			if actor.activity!=FieldActor.Activity.MOVING or not actor.visible or actor.path.is_empty() or actor._path_index>=actor.path.size() or _vec(actor.path.back()).distance_to(door)>14.0:
				return "SEARCH_APPROACH_STATE"
		owners[int(job.member_id)]=job.phase
	for row: Dictionary in value.survivors:
		if int(row.state.activity) in [FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING] and owners.get(int(row.state.member_id),"")!="working":
			return "SEARCH_ORPHAN_WORKER"
	return ""

static func search_version(version: Variant) -> bool:
	return version==SEARCH_VERSION or power_version(version)

static func power_version(version: Variant) -> bool:
	return version==POWER_VERSION or version==PERSONA_VERSION or version==EXPLORATION_VERSION
