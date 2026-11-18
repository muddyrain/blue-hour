extends "res://tests/persona_rules.gd"
## Pure generation fixtures; no fabricated earned progress or disk verification marks.

var builds: int = 0
var build_mutex: Mutex = Mutex.new()


func run() -> void:
	_memo_contract()
	var base: Dictionary = _camp_fixture()
	base.journey.build = WorldgenState.initial_build(base.journey.seed, true, true)
	base.journey.campaign = CampaignRules.initial_mission(base.profile_id, true, true, true)
	var offers: Array[Dictionary] = DailyActions.offers(base)
	expect(offers.size() == 3, "all three canonical slots are generated before publishing a day proof")
	InvestigationActions._days.clear()
	FreezeProfile.enabled = true
	FreezeProfile.start({"scope":"compact-day-proof-after-full-description-eviction"})
	for action: Dictionary in offers:
		expect(DailyActions.matches(base, action), "compact proof authenticates every original signed slot")
	FreezeProfile.finish()
	expect(int(FreezeProfile.latest.metadata.get("action_day_builds", 0)) == 0
		and int(FreezeProfile.latest.metadata.get("action_map_builds", 0)) == 0
		and int(FreezeProfile.latest.metadata.get("action_day_proof_hits", 0)) == 3,
		"evicting large descriptions does not repeat any map or day proof")
	if not offers.is_empty():
		var action: Dictionary = offers[0]
		var altered: Dictionary = action.duplicate(true)
		altered.cash += 1
		expect(not DailyActions.matches(base, altered), "warm proof rejects changed rewards with the same action id")
		altered = action.duplicate(true)
		altered.layout.entities[0].door[0] += 16
		expect(not DailyActions.problem(altered).is_empty() and not DailyActions.matches(base, altered),
			"warm navigation and action proofs reject a changed door with the same layout id")
		var changed: Dictionary = base.duplicate(true)
		changed.journey.seed = "different-generation-context".md5_text()
		expect(not DailyActions.matches(changed, action), "a different seed cannot reuse the prior camp proof")
		changed = base.duplicate(true)
		changed.journey.campaign.clues = [{"id":CampaignRules.CLUE_IDS[0],
			"transaction_id":base.profile_id + ":1", "action_id":offers.back().id, "site_id":"cash"}]
		expect(CampaignRules.problem(changed.journey.campaign, base.profile_id).is_empty(),
			"changed-prefix fixture has a well-formed next-clue context")
		expect(not DailyActions.matches(changed, offers.back()), "a changed campaign prefix cannot reuse the earlier clue offer")
	print("BH_ACTION_GENERATION_CACHE ", JSON.stringify({"suite":"action_generation_cache", "checks":checks, "failures":failures}))
	quit(1 if failures else 0)


func _memo_contract() -> void:
	var memo: ActionGenerationMemo = ActionGenerationMemo.new()
	var context: Dictionary = {"scope":"test-rule-v1", "seed":"fixture", "id":"map",
		"layout":{"size":"small", "topology":"commercial"}, "prefix":{"root":"a", "sequence":1}}
	var threads: Array[Thread] = []
	for index: int in range(3):
		var thread: Thread = Thread.new()
		thread.start(func() -> Dictionary: return memo.resolve(context, _generate))
		threads.append(thread)
	for thread: Thread in threads:
		expect(thread.wait_to_finish() == {"nested":{"proof":1}}, "concurrent callers receive the same complete result")
	expect(builds == 1 and memo._pending.is_empty(), "same-input workers compute once and release all gates")
	var exposed: Dictionary = memo.resolve(context, _generate)
	exposed.nested.proof = 999
	expect(memo.resolve(context, _generate).nested.proof == 1, "returned objects cannot mutate the private proof")
	for field: String in ["scope", "seed", "id", "layout", "prefix"]:
		var changed: Dictionary = context.duplicate(true)
		if field == "layout": changed.layout.topology = "residential"
		elif field == "prefix": changed.prefix.sequence = 2
		else: changed[field] += "-changed"
		memo.resolve(changed, _generate)
	expect(builds == 6, "every changed rule, source, geometry or prefix input recomputes")
	var failed: Dictionary = {"scope":"failed-attempt", "input":7}
	var attempt: Callable = func() -> Dictionary: return {"value":{}, "trace":["door:blocked"]}
	expect(memo.resolve(failed, attempt) == memo.resolve(failed, attempt),
		"deterministic failures retain their complete rejection diagnostics")
	expect(memo._bytes <= ActionGenerationMemo.MAX_BYTES and memo._entries.size() <= ActionGenerationMemo.MAX_ENTRIES,
		"generation proofs remain byte and entry bounded")


func _generate() -> Dictionary:
	build_mutex.lock()
	builds += 1
	build_mutex.unlock()
	return {"nested":{"proof":1}}
