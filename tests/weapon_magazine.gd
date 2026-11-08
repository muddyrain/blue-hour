extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("WEAPON_V1_FAIL "+label)
func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").begins_with(ProjectSettings.globalize_path("res://.local/")):quit(2);return
	_affix_sources()
	var app: Node=load("res://src/app/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app.playable_entry=false # Explicit historical fixture; normal new journeys use short V1.
	app._new_game()
	var base: Dictionary=app.camp_snapshot()
	var types: Dictionary={}
	var examples: Array=[]
	for seed: String in ["task-v4-0","task-v4-1","task-v4-2","task-v4-3"]:
		var fixture: Dictionary=base.duplicate(true);fixture.journey.seed=seed.md5_text()
		var offers: Array[Dictionary]=WeaponActions.offers(fixture)
		expect(TransactionReceipt.same({"v":offers},{"v":WeaponActions.offers(fixture)}),"new candidates stable")
		for offer: Dictionary in offers:
			expect(DailyActions.problem(offer).is_empty(),"V5 action/drop authenticates")
			var rules: Dictionary=FrozenSettlement.pool_rules(fixture,DailyActions.supply(offer))
			expect(rules.data_version==6 and FrozenSettlement._rules_problem(rules).is_empty(),"V6 rules bind V5 action")
			for site: Dictionary in offer.sites:
				if not site.weapon:continue
				var item: Dictionary=WeaponInventory.site_reward(base.profile_id+":1",offer,site,true)
				types[item.weapon_id]=true
				examples.append({"seed":seed,"type":offer.type,"gun":item.weapon_id})
				expect(item.weapon_id==WeaponInventory.drop_weapon(offer.seed,offer.id,site.id) and TransactionReceipt.same(item,WeaponInventory.instance_reward(fixture,item)),"carried drop agrees with durable camp provenance")
				var altered: Dictionary=offer.duplicate(true)
				for row: Dictionary in altered.sites:
					if row.weapon:row.drop.weapon_id="long_rifle" if item.weapon_id=="carbine" else "carbine"
				expect(not DailyActions.problem(altered).is_empty(),"changed frozen gun rejected")
	expect(types.has_all(["carbine","long_rifle"]),"fixed seed fixtures cover both guns")
	expect(WeaponInventory.reward(base.profile_id+":1",true).weapon_id=="long_rifle","historical reward stays fixed")
	for gun: String in ["carbine","long_rifle"]:
		var magazine: WeaponMagazine=WeaponMagazine.new("instance",gun)
		expect(magazine.rounds==magazine.capacity(),"fresh full "+gun)
		for shot: int in range(magazine.capacity()):magazine.commit_shot()
		expect(not magazine.can_fire() and magazine.rounds==0 and magazine.remaining==magazine.seconds(),"last shot starts full timer "+gun)
		magazine.advance(magazine.seconds()*0.5)
		var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(magazine.snapshot()))).payload
		expect(WeaponMagazine.problem(exact,"instance",gun).is_empty(),"exact half reload authenticates "+gun)
		var copy: WeaponMagazine=WeaponMagazine.new("instance",gun);copy.restore(exact)
		expect(copy.rounds==0 and copy.remaining==magazine.remaining,"restore cannot refill "+gun)
		copy.advance(copy.remaining-0.01)
		expect(not copy.can_fire(),"no early finish "+gun)
		copy.advance(0.01)
		expect(copy.can_fire() and copy.rounds==copy.capacity(),"finish fills exactly once "+gun)
		for change: String in ["identity","negative","overflow","fraction","time","nan","phase","unknown","version"]:
			var bad: Dictionary=exact.duplicate(true)
			match change:
				"identity":bad.instance_id="other"
				"negative":bad.rounds=-1
				"overflow":bad.rounds=magazine.capacity()+1
				"fraction":bad.rounds=0.5
				"time":bad.remaining=magazine.seconds()+1
				"nan":bad.remaining=NAN
				"phase":bad.reloading=false
				"unknown":bad.extra=0
				"version":bad.version=2
			expect(not WeaponMagazine.problem(bad,"instance",gun).is_empty(),"reject "+gun+change)
	var refund: WeaponMagazine = WeaponMagazine.new("m33-fixture", "long_rifle")
	expect(refund.commit_shot(true) == 1 and refund.rounds == refund.capacity(), "M33 refund replaces one fired round within capacity")
	for shot: int in range(refund.capacity() - 1):
		refund.commit_shot()
	expect(refund.commit_shot(true) == 1 and refund.rounds == 1 and not refund.reloading and refund.remaining == 0.0,
		"M33 last-round defeat leaves one round and no reload")
	var restored: WeaponMagazine = WeaponMagazine.new("m33-fixture", "long_rifle")
	restored.restore(refund.snapshot())
	expect(WeaponMagazine.problem(restored.snapshot(), "m33-fixture", "long_rifle").is_empty() and restored.rounds == 1,
		"M33 refunded rounds retain the existing magazine snapshot")
	expect(restored.commit_shot() == 0 and restored.rounds == 0 and restored.reloading and restored.remaining == restored.seconds(),
		"M33 next non-refunding last shot still starts normal reload")
	print(JSON.stringify({"checks":checks,"failures":failures,"types":types,"examples":examples,"parameters":WeaponDefinition.MAGAZINES}))
	app.audio.shutdown();app.queue_free();await process_frame
	quit(0 if failures==0 else 1)


func _affix_sources() -> void:
	var profile: String = "0123456789abcdef0123456789abcdef"
	var token: String = profile + ":2"
	var historical: Dictionary = CampaignRules.initial_mission(profile, true, true, true, true, true)
	var current: Dictionary = CampaignRules.initial_mission(profile, true, true, true, true, true, true)
	expect(CampaignRules.problem(historical).is_empty() and not CampaignRules.weapon_affix_enabled(historical)
		and CampaignRules.problem(current).is_empty() and CampaignRules.weapon_affix_enabled(current),
		"only the explicit new campaign marker enables weapon affix drops")
	var forged_campaign: Dictionary = current.duplicate(true)
	forged_campaign.erase("screamer_policy")
	expect(not CampaignRules.problem(forged_campaign).is_empty(), "weapon affix campaign cannot bypass its existing policy chain")
	var variants: Dictionary[int, String] = {4: WeaponModifiers.REFUND, 22: "quick_v1",
		31: "", 65: "reach_v1", 74: WeaponModifiers.PIERCE}
	for key: int in variants:
		var seed: String = "%032x" % key
		var action: String = ("daily-v4:%s:3:2" % seed).sha256_text()
		var affix: String = variants[key]
		var site: Dictionary = {"id":"cash", "kind":"cash", "weapon":true, "work_mode":"outdoor",
			"drop":{"version":2, "weapon_id":CombatActions.drop(seed, action, "cash", false)}}
		var generated: Dictionary = {"id":action, "seed":seed, "day":3, "slot":2, "version":9,
			"type":"airdrop", "mission_policy":1, "campaign":{"is_finale":false}, "objective":{"site_ids":["cash"]},
			"sites":[site], "weapon_affix_policy":WeaponInventory.AFFIX_POLICY_VERSION}
		var item: Dictionary = WeaponInventory.site_reward(token, generated, site, true)
		var provenance: Dictionary = {"journey":{"seed":seed}}
		var actual_affix: String = WeaponModifiers.combat_affix(item)
		expect(item.weapon_id == "long_rifle" and item.drop.version == WeaponInventory.AFFIX_DROP_VERSION
			and item.affixes == ([] if affix.is_empty() else [affix]) and item.instance_id == token + ":weapon:north-cache"
			and WeaponModifiers.problem(item).is_empty(), "frozen rifle keeps its original identity and derives one exact affix: " + affix)
		expect(TransactionReceipt.same(item, WeaponInventory.instance_reward(provenance, item, true))
			and WeaponInventory.instance_reward(provenance, item).is_empty(), "V3 provenance recomputes the source and requires the new campaign")
		expect(WeaponModifiers.combat_definition(item).combat_affix == actual_affix
			and WeaponModifiers.effect_description(item).is_empty() == (affix not in [WeaponModifiers.PIERCE, WeaponModifiers.REFUND]),
			"combat and display project only the two new effects")
		var old_action: Dictionary = generated.duplicate(true)
		old_action.erase("weapon_affix_policy")
		var old_item: Dictionary = WeaponInventory.site_reward(token, old_action, site, true)
		expect(old_item.drop.version == 2 and TransactionReceipt.same(old_item, WeaponInventory.instance_reward(provenance, old_item))
			and WeaponModifiers.combat_affix(old_item).is_empty(), "same historical frozen action keeps the legacy rifle interpretation")
		if actual_affix.is_empty():
			continue
		var forged: Dictionary = item.duplicate(true)
		forged.affixes = [WeaponModifiers.PIERCE if actual_affix == WeaponModifiers.REFUND else WeaponModifiers.REFUND]
		expect(not TransactionReceipt.same(forged, WeaponInventory.instance_reward(provenance, forged, true)),
			"alternate valid affix cannot replace the frozen source")
		var bad_slot: Dictionary = item.duplicate(true)
		bad_slot.drop.slot = 0
		expect(WeaponInventory.instance_reward(provenance, bad_slot, true).is_empty(), "V3 cannot claim the supplies slot")
		forged.affixes.append(actual_affix)
		expect(not WeaponModifiers.problem(forged).is_empty(), "V3 rare affixes are mutually exclusive")
		var rare_action: Dictionary = generated.duplicate(true)
		rare_action.rare_policy = 1
		expect(not WeaponInventory.affix_enabled(rare_action), "special rare sortie cannot use the ordinary rifle policy")
		var camp: Dictionary = {"schema_version":EnemyState.SCHEMA, "weapons":[], "loadout":[], "crew":[],
			"cash":53, "camp_spending":0}
		expect(WeaponInventory.bank(camp, [item], token, generated).is_empty()
			and not WeaponInventory.bank(camp, [item], token, generated).is_empty() and camp.weapons.size() == 1,
			"the same authentic V3 site reward enters the existing inventory exactly once")
		var repair: Dictionary = WeaponInventory.repair(camp, item.instance_id)
		var ready: Dictionary = item.duplicate(true)
		ready.condition = "ready"
		expect(repair.has("data") and TransactionReceipt.same(repair.data.weapons[0], ready),
			"repair preserves stable V3 provenance and the exact affix")
