extends SceneTree
## Pure policy boundaries. No camp/day/save/actor fixture is edited by these tests.

var checks: int = 0
var failures: int = 0
const RUN: String = "0123456789abcdef0123456789abcdef"


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("CAMPAIGN_RULES_FAIL "+label)


func run() -> void:
	var original: Dictionary = CampaignRules.initial(RUN)
	expect(CampaignRules.problem(original,RUN).is_empty(),"fresh short run is valid")
	expect(original.preparations==0 and original.outcome=="ACTIVE" and original.result_transaction.is_empty(),"fresh identity has no credited return or result")
	for count: int in range(5):
		var value: Dictionary = original.duplicate(true)
		value.preparations=count
		var before: Dictionary = value.duplicate(true)
		var context: Dictionary = CampaignRules.context(value)
		var view: Dictionary = CampaignRules.display(value)
		expect(CampaignRules.can_depart(value),"active departure allowed after %d confirmed preparations" % count)
		expect(context.stage==("preparation" if count<2 else "breakout" if count<4 else "finale"),"phase follows confirmed count %d" % count)
		expect(context.is_finale==(count==4),"finale requires four confirmed preparations %d" % count)
		expect(context.pressure==(0.90 if count in [2,3] else 1.0),"one base interval multiplier %d" % count)
		expect(view.has_all(["title","detail","progress"]) and ("%d/4" % count) in view.progress,"read-only display reflects exact count %d" % count)
		expect(value==before,"browsing/context/departure checks do not advance count %d" % count)
		expect(CampaignRules.context(value)==context,"same authority produces stable action context %d" % count)
		var decoded: Variant = JSON.parse_string(JSON.stringify(value))
		expect(CampaignRules.problem(decoded,RUN).is_empty(),"JSON integral numbers accepted %d" % count)
	expect("×0.90" in CampaignRules.display(_state(2)).detail,"breakout explains interval pressure")
	expect("提前撤离" in CampaignRules.display(_state(0)).detail,"preparation card explains consumed early return")
	expect("提前撤离" in CampaignRules.display(_state(4)).detail,"finale card explains retry")
	for outcome: String in ["VICTORY","DEFEAT"]:
		var ended: Dictionary = _state(4)
		ended.outcome=outcome
		ended.result_transaction=RUN+":5"
		expect(CampaignRules.problem(ended,RUN).is_empty(),"bound terminal outcome "+outcome)
		expect(not CampaignRules.can_depart(ended),"ended journey rejects further action "+outcome)
		expect(CampaignRules.display(ended).title==("旅程胜利" if outcome=="VICTORY" else "旅程失败"),"terminal display "+outcome)
	var first_failure: Dictionary = original.duplicate(true)
	first_failure.outcome="DEFEAT"
	first_failure.result_transaction=RUN+":1"
	expect(CampaignRules.problem(first_failure).is_empty(),"first action failure does not require a credited preparation")
	var hunger_failure: Dictionary = _state(4)
	hunger_failure.outcome="DEFEAT"
	hunger_failure.result_transaction=RUN+":4"
	expect(CampaignRules.problem(hunger_failure).is_empty(),"confirmed fourth return may credit preparation before same-settlement hunger defeat")
	hunger_failure.result_transaction=RUN+":3"
	expect(not CampaignRules.problem(hunger_failure).is_empty(),"defeat cannot predate confirmed preparations")
	var retry_win: Dictionary = _state(4)
	retry_win.outcome="VICTORY"
	retry_win.result_transaction=RUN+":8"
	expect(CampaignRules.problem(retry_win).is_empty(),"finale retry can bind later transaction")
	for change: String in ["field","missing","version","mode","identity","foreign","negative","overflow","fraction","nan","boolean","outcome","result_type","active_result"]:
		var bad: Dictionary = original.duplicate(true)
		match change:
			"field":bad.extra=true
			"missing":bad.erase("mode")
			"version":bad.version=2
			"mode":bad.mode="legacy"
			"identity":bad.run_id="wrong"
			"foreign":bad.run_id="fedcba9876543210fedcba9876543210"
			"negative":bad.preparations=-1
			"overflow":bad.preparations=5
			"fraction":bad.preparations=1.5
			"nan":bad.preparations=NAN
			"boolean":bad.preparations=true
			"outcome":bad.outcome="UNKNOWN"
			"result_type":bad.result_transaction=1
			"active_result":bad.result_transaction=RUN+":1"
		expect(not CampaignRules.problem(bad,RUN).is_empty(),"reject bad "+change)
		if change!="foreign":
			expect(not CampaignRules.can_depart(bad),"invalid policy cannot authorize departure "+change)
	for result: String in ["",RUN+":4",RUN+":0",RUN+":-1",RUN+":05",RUN+":+5",RUN+":5.0",RUN+":5:extra","fedcba9876543210fedcba9876543210:5"]:
		var bad: Dictionary = retry_win.duplicate(true)
		bad.result_transaction=result
		expect(not CampaignRules.problem(bad).is_empty(),"reject unbound or noncanonical result "+result)
	var early_win: Dictionary = _state(3)
	early_win.outcome="VICTORY"
	early_win.result_transaction=RUN+":5"
	expect(not CampaignRules.problem(early_win).is_empty(),"victory cannot skip the fourth preparation")
	expect(not CampaignRules.problem([]).is_empty(),"non-dictionary rejected")
	expect(original==CampaignRules.initial(RUN),"all pure queries preserve original input")
	_test_investigation()
	print(JSON.stringify({"checks":checks,"failures":failures,"policy":"PROJECT_TEMP_SHORT_V1","owner_boundary":"A commits actual count, terminal evidence, and durable result"}))
	quit(0 if failures==0 else 1)


func _state(count: int) -> Dictionary:
	var value: Dictionary = CampaignRules.initial(RUN)
	value.preparations=count
	return value


func _test_investigation() -> void:
	var value: Dictionary = CampaignRules.initial_investigation(RUN)
	expect(CampaignRules.problem(value, RUN).is_empty() and CampaignRules.next_clue(value) == "dispatch_log",
		"new investigation begins with its own version and first clue")
	var clue: Dictionary = {"id":"dispatch_log", "transaction_id":RUN + ":2", "action_id":"ab".repeat(32), "site_id":"cash"}
	value.clues.append(clue)
	expect(CampaignRules.problem(value, RUN).is_empty() and CampaignRules.next_clue(value) == "checkpoint_pass"
		and not CampaignRules.context(value).is_finale, "first confirmed clue leaves the finale locked")
	var early: Dictionary = value.duplicate(true)
	early.outcome = "VICTORY"
	early.result_transaction = RUN + ":3"
	expect(not CampaignRules.problem(early).is_empty(), "one clue cannot produce victory")
	value.clues.append({"id":"checkpoint_pass", "transaction_id":RUN + ":4", "action_id":"cd".repeat(32), "site_id":"cash"})
	expect(CampaignRules.problem(value, RUN).is_empty() and CampaignRules.context(value).is_finale,
		"two different bound clues open the original finale")
	for field: String in ["id", "transaction_id", "site_id", "action_id"]:
		var bad: Dictionary = value.duplicate(true)
		bad.clues[1][field] = clue[field] if field in ["id","transaction_id"] else "invalid"
		expect(not CampaignRules.problem(bad).is_empty(), "reject altered second-clue " + field)
	value.outcome = "VICTORY"
	value.result_transaction = RUN + ":4"
	expect(not CampaignRules.problem(value).is_empty(), "finale result must follow both clue transactions")
	value.result_transaction = RUN + ":6"
	expect(CampaignRules.problem(value).is_empty() and not CampaignRules.can_depart(value), "later bound victory ends the investigation")
