class_name ExplorationState
extends RefCounted
## Explicit new-journey capability; the existing camp/transaction remains the owner.
const POLICY_ID: String = "BH_EXPLORATION_V1"
static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey") is Dictionary and camp.journey.get("build") is Dictionary and camp.journey.build.get("version")==5

static func initial_build(seed: String) -> Dictionary:
	var value: Dictionary=PersonaState.initial_build(seed)
	value.version=5
	value.exploration={"version":1,"policy_id":POLICY_ID}
	return value

static func problem(camp: Dictionary) -> String:
	var value: Variant=camp.journey.build.get("exploration")
	return "" if value is Dictionary and TransactionReceipt.same(value,{"version":1,"policy_id":POLICY_ID}) else "EXPLORATION_CAMP_CAPABILITY"
