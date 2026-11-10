class_name SpecializationProgress
extends RefCounted
## M47 projections are derived from acknowledged receipts under the catalog writer.

const VERSION: int = 1
const OWN_THRESHOLD: int = 2
const SHARED_THRESHOLD: int = 4
const RECORD_PREFIX: String = "specialty-"
const ARCHIVE_PREFIX: String = ".txn.previous-m47-"
const MAX_VERIFIED_SETTLEMENTS: int = 128

static var _verified_settlements: Dictionary[String, bool] = {}


static func initial() -> Dictionary:
	return {"scavenge":0, "firepower":0, "support":0}


static func eligible_for(experience: Dictionary, plan: String) -> Array[String]:
	var result: Array[String] = []
	if not OpeningBuild.PLANS.has(plan):
		return result
	for source: String in OpeningBuild.PLANS:
		var threshold: int = OWN_THRESHOLD if source == plan else SHARED_THRESHOLD
		if int(experience.get(source, 0)) >= threshold:
			result.append(OpeningBuild.PLANS[source].unlock_id)
	result.sort()
	return result


static func derive(history: Dictionary, slot_hash: String) -> Dictionary:
	var event: Dictionary = {}
	var discoveries: Dictionary = {}
	var returns: Array[Dictionary] = []
	var journal: ReceiptJournal = history.journal
	var opening: Dictionary = history.opening
	var plan: String = opening.plan
	var eligible: Array[String] = []
	eligible.assign(opening.specialty.eligible)
	for revision: int in range(1, int(history.through) + 1):
		var row: Dictionary = journal._read_record(journal.directory.path_join("%08d/record.json" % revision), false)
		if row.error != OK or row.hash != history.hashes[revision]:
			return {"reason":"CATALOG_HISTORY_CHANGED"}
		var receipt: Dictionary = row.receipt
		if not _same_opening(receipt.base, opening, int(history.open_streets)):
			return {"reason":"CATALOG_SPECIALTY_OPENING_CHANGED"}
		if receipt.phase != "COMMITTED":
			continue
		var ref: Dictionary = {"transaction_id":receipt.transaction_id, "revision":revision, "hash":row.hash}
		var report: Variant = receipt.envelope.result.get("battle")
		if not report is Dictionary:
			return {"reason":"CATALOG_SPECIALTY_SETTLEMENT"}
		var battle: Dictionary = report
		var camp: Dictionary = TransactionReceipt.camp(receipt)
		if not _same_opening(camp, opening, int(history.open_streets)):
			return {"reason":"CATALOG_SPECIALTY_OPENING_CHANGED"}
		var campaign: Dictionary = camp.journey.campaign
		var returned: bool = battle.get("evacuated") == true and battle.get("mission_outcome") == "EXTRACTED"
		if campaign.outcome != "ACTIVE":
			if not event.is_empty() or not _verified_settlement(receipt, battle, row.hash):
				return {"reason":"CATALOG_SPECIALTY_SETTLEMENT"}
			var outcome: String = _terminal_outcome(receipt, camp, battle)
			if outcome.is_empty():
				return {"reason":"CATALOG_SPECIALTY_TERMINAL_SOURCE"}
			var delta: int = 0
			if returns.size() == CatalogProgress.REQUIRED_RETURNS:
				delta = 2 if outcome == "VICTORY" else 1
			event = {"version":VERSION, "slot":slot_hash, "kind":RECORD_PREFIX + history.run_id,
				"run_id":history.run_id, "root_id":history.root_id, "plan":plan,
				"outcome":outcome, "delta":delta, "receipt":ref, "returns":returns.duplicate(true)}
		elif returned and returns.size() < CatalogProgress.REQUIRED_RETURNS:
			if returns.any(func(prior: Dictionary) -> bool: return prior.transaction_id == ref.transaction_id) \
					or not _verified_settlement(receipt, battle, row.hash):
				return {"reason":"CATALOG_SPECIALTY_RETURN_SOURCE"}
			returns.append(ref)
		if returned and not _record_discoveries(discoveries, eligible, receipt, camp, ref, battle):
			return {"reason":"CATALOG_SPECIALTY_DISCOVERY_SOURCE"}
	return {"event":event, "discoveries":discoveries}


static func _same_opening(camp: Dictionary, opening: Dictionary, streets: int) -> bool:
	var journey: Dictionary = camp.get("journey", {})
	return journey.get("campaign", {}).get("open_streets_policy") == streets \
		and TransactionReceipt.same(journey.get("build", {}).get("opening", {}), opening)


static func _verified_settlement(receipt: Dictionary, battle: Dictionary, hash_value: String) -> bool:
	# The caller has re-read and verified the exact record hash and binding revision.
	if _verified_settlements.has(hash_value):
		return true
	var generated: Dictionary = receipt.rules.get("mission", {}).get("generated", {})
	var facts: Variant = battle.get("site_facts")
	if not generated.get("sites") is Array or not facts is Dictionary \
			or not WorldSites.problem(generated.sites, facts, generated.get("version") == 9).is_empty():
		return false
	var carried: Dictionary = WorldSites.carry(generated.sites, facts, receipt.transaction_id,
		WeaponState.is_family(receipt.base), generated, battle.get("task_event", {}))
	var input: Dictionary = {"before":receipt.base, "token":RunTransaction.token_for(receipt),
		"participants":receipt.participants, "rules":receipt.rules, "report":battle, "carried":carried,
		"prior_deaths":receipt.base.journey.deaths, "completion":"COMPLETED", "searching_member_ids":[]}
	if not FrozenSettlement.validate({"input":input, "envelope":receipt.envelope}).is_empty():
		return false
	if _verified_settlements.size() == MAX_VERIFIED_SETTLEMENTS:
		_verified_settlements.erase(_verified_settlements.keys().front())
	_verified_settlements[hash_value] = true
	return true


static func _terminal_outcome(receipt: Dictionary, camp: Dictionary, battle: Dictionary) -> String:
	var result: Dictionary = receipt.envelope.result
	var campaign: Dictionary = camp.journey.campaign
	if campaign.result_transaction != receipt.transaction_id:
		return ""
	if campaign.outcome == "VICTORY" and battle.evacuated and battle.mission_outcome == "EXTRACTED" \
			and PumpStationAction.enabled(receipt.rules.mission.generated) and PumpStationAction.stopped(battle.site_facts) \
			and not battle.get("encounter", {}).get("defeat", {}).is_empty():
		return "VICTORY"
	if campaign.outcome == "DEFEAT" and result.journey_outcome == "FAILED" and camp.journey.active_member_ids.is_empty() \
			and result.deaths.any(func(death: Dictionary) -> bool:
				return death.transaction_id == receipt.transaction_id and death.cause in ["BATTLE", "STARVATION"]):
		return "DEFEAT"
	return ""


static func _record_discoveries(discoveries: Dictionary, eligible: Array[String], receipt: Dictionary, camp: Dictionary, ref: Dictionary, battle: Dictionary) -> bool:
	var before: Dictionary = receipt.base.journey.build
	var after: Dictionary = camp.journey.build
	var old_owned: Array = before.owned + before.powers.owned
	var new_owned: Array = after.owned + after.powers.owned
	for id: String in eligible:
		if id in new_owned and id not in old_owned and not discoveries.has(id):
			if not _verified_settlement(receipt, battle, ref.hash):
				return false
			discoveries[id] = {"run_id":camp.profile_id, "root_id":receipt.root_id, "receipt":ref}
	return true


static func result_for(event: Dictionary, before: int) -> Dictionary:
	if event.is_empty():
		return {}
	var amount: int = int(event.delta)
	var after: int = before + amount
	var item: String = OpeningBuild.PLANS[event.plan].unlock_id
	var unlocked: Array[String] = []
	var shared: Array[String] = []
	if before < OWN_THRESHOLD and after >= OWN_THRESHOLD:
		unlocked.append(item)
	if before < SHARED_THRESHOLD and after >= SHARED_THRESHOLD:
		shared.append(item)
	return {"run_id":event.run_id, "transaction_id":event.receipt.transaction_id, "plan":event.plan,
		"outcome":event.outcome, "delta":amount, "before":before, "after":after,
		"unlocked":unlocked, "shared":shared, "status":"CONFIRMED"}
