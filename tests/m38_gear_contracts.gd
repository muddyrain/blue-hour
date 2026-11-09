extends SceneTree
## Pure contract fixtures. Ordinary acquisition and recovery use the isolated full-flow drivers.

const RUN: String = "0123456789abcdef0123456789abcdef"
const SEED: String = "fedcba9876543210fedcba9876543210"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	_check_melee()
	var action: Dictionary = _action()
	_check_liner(action)
	_check_inventory(action)
	print(JSON.stringify({"suite":"m38_gear_contracts", "checks":checks, "failures":failures}))
	quit(0 if failures == 0 else 1)


func _expect(pass_check: bool, label: String) -> void:
	checks += 1
	if not pass_check:
		failures += 1
		printerr("M38_GEAR_FAIL " + label)


func _action() -> Dictionary:
	var id: String = ("daily-v4:%s:3:2" % SEED).sha256_text()
	var context: Dictionary = {"version":1, "run_id":RUN, "seed":SEED, "day":3, "action_id":id, "site_id":"cash"}
	var site: Dictionary = {"id":"cash", "kind":"cash", "weapon":true, "work_mode":"outdoor",
		"drop":{"version":2, "weapon_id":"long_rifle"}}
	return ContentWaveV1.freeze_action({"id":id, "version":9, "slot":2, "day":3, "type":"airdrop",
		"seed":SEED, "mission_policy":1, "layout":{"topology":"industrial"},
		"campaign":{"run_id":RUN, "is_finale":false}, "powers":{"version":SpecialPowers.WAVE_VERSION},
		"objective":{"site_ids":["cash"]}, "sites":[site],
		"build":{"version":BuildItems.WAVE_POOL, "owned":[], "drop_context":context}})


func _check_liner(action: Dictionary) -> void:
	var context: Dictionary = action.build.drop_context
	var liner: String = BuildItems.LINER
	var pool: int = BuildItems.WAVE_POOL
	var drops: Array[String] = BuildItems.drop(context, [], pool)
	_expect(drops.size() == 2 and drops.front() == liner and drops == action.build.drops,
		"eligible action reserves one of two gear drops for the liner")
	_expect(liner not in BuildItems.drop(context, [liner], pool), "already owned liner is never repeated")
	var ordinary: Dictionary = context.duplicate(true)
	ordinary.erase("liner")
	_expect(liner not in BuildItems.drop(ordinary, [], pool), "ordinary wave gear without the source marker cannot roll a liner")
	var legacy: Dictionary = context.duplicate(true)
	legacy.version = BuildItems.CATALOG_POOL
	_expect(BuildItems.drop(legacy, [], BuildItems.CATALOG_POOL).is_empty(), "legacy drop rejects liner marker")
	_expect(BuildItems.problem([liner], [liner, ""], BuildItems.CATALOG_POOL) != ""
		and BuildItems.problem([liner], [liner, ""], pool) == "", "legacy inventories cannot equip the wave liner")
	_expect(BuildItems.FILTER not in BuildItems.ids(pool) and BuildItems.FILTER in BuildItems.ids(BuildItems.WAVE_CATALOG_POOL),
		"wave inventory still requires a separate filter unlock")
	var factors: Dictionary = BuildItems.frozen_factors({"version":pool, "slots":[liner, ""]})
	_expect(is_equal_approx(20.0 * float(factors.get("burst", 1.0)), 13.0), "liner converts 20 burst damage to 13")
	factors.erase("burst")
	_expect(factors == BuildItems.BASE_FACTORS, "liner retains other original factors")


func _check_inventory(action: Dictionary) -> void:
	var wave: Dictionary = {"version":CampaignRules.MISSION_VERSION, "mode":CampaignRules.MISSION_MODE,
		"content_wave_policy":ContentWaveV1.VERSION, "action_policy":CampaignRules.ACTION_POLICY_VERSION,
		"midgame":CampFacilities.initial()}
	var camp: Dictionary = {"profile_id":RUN, "settled_sorties":2, "cash":31, "camp_spending":0,
		"journey":{"seed":SEED, "campaign":wave}, "crew":[{"id":5, "health":100.0}],
		"recruits":[{"member_id":5, "field_status":"RETURNED", "settlement_id":RUN + ":2"}],
		"weapons":[]}
	var item: Dictionary = WeaponInventory.site_reward(RUN + ":2", action, action.sites[0], true)
	_expect(item.get("weapon_id") == CombatEquipment.HAMMER_ID and item.get("condition") == "damaged"
		and item.get("weapon_level") == 1 and item.get("quality") == "common", "qualified site yields a damaged common hammer")
	if item.is_empty():
		return
	_expect(TransactionReceipt.same(item, WeaponInventory.instance_reward(camp, item, false, true)), "camp reconstructs the original hammer source")
	_expect(WeaponInventory.instance_reward(camp, item).is_empty(), "older weapon catalogs reject the hammer source")
	var forged: Dictionary = item.duplicate(true)
	forged.drop.action_id = "foreign"
	_expect(WeaponInventory.instance_reward(camp, forged, false, true).is_empty(), "hammer requires its original signed action ID")
	forged = action.duplicate(true)
	forged.rare_policy = 1
	_expect(WeaponInventory.site_reward(RUN + ":2", forged, forged.sites[0], true).is_empty(), "rare actions cannot claim an industrial hammer")
	var quote: Dictionary = WeaponInventory.repair_offer(camp, item)
	_expect(quote.base == 10 and quote.cost == 7 and quote.source == WeaponInventory.MECHANIC_TITLE,
		"confirmed living mechanic discounts the hammer from 10 to 7")
	camp.weapons.append(item)
	var repair: Dictionary = WeaponInventory.repair(camp, item.instance_id)
	_expect(repair.data.cash == 24 and repair.data.camp_spending == 7 and repair.data.weapons[0].condition == "ready",
		"repair uses the previewed quote and preserves the source")
	_expect(TransactionReceipt.same(repair.data.weapons[0], WeaponInventory.instance_reward(repair.data, repair.data.weapons[0], false, true)),
		"repaired hammer remains certified with its original identity")
	camp.settled_sorties = 1
	_expect(WeaponInventory.repair_quote(camp, item) == 10, "same-sortie acceptance is not a confirmed return")
	camp.settled_sorties = 2
	camp.journey.campaign.midgame = {"version":CampFacilities.VERSION, "facility":CampFacilities.WORKSHOP, "built_day":3}
	_expect(WeaponInventory.repair_quote(camp, item) == 6, "workshop takes the greater discount without stacking")
	camp.journey.campaign.midgame = CampFacilities.initial()
	camp.crew[0].health = 0.0
	_expect(WeaponInventory.repair_quote(camp, item) == 10, "dead mechanic no longer discounts repairs")


func _check_melee() -> void:
	var id: String = CombatEquipment.HAMMER_ID
	var weapon: WeaponDefinition = CombatEquipment.definition(id)
	_expect(weapon != null and weapon.damage == 48.0 and weapon.interval == 1.25
		and weapon.shot_range == 54.0 and weapon.magazine_capacity() == 0, "hammer resource has the signed gameplay parameters")
	var targets: Array[Dictionary] = [
		{"id":4, "foot":Vector2(28, 0), "alive":true, "available":true},
		{"id":1, "foot":Vector2(14, 14), "alive":true, "available":true},
		{"id":2, "foot":Vector2(32, 5), "alive":true, "available":true},
	]
	var clear: Array[ShotObstacle] = []
	_expect(CombatPatternsV1.melee_plan(id, Vector2.ZERO, Vector2.RIGHT, targets, clear, 54.0) == [{"id":4, "hits":1}],
		"hammer ignores the closer target outside its cone and only hits the first eligible target")
	_expect(CombatPatternsV1.axe_plan(Vector2.ZERO, Vector2.RIGHT, targets, clear).size() == 3,
		"historical axe still hits three targets across its wider cone")
	var wall: Array[ShotObstacle] = [ShotObstacle.new(&"wall", Rect2(10, -25, 3, 80), true)]
	_expect(CombatPatternsV1.melee_plan(id, Vector2.ZERO, Vector2.RIGHT, targets, wall, 54.0).is_empty(),
		"hammer cannot strike through a wall")
