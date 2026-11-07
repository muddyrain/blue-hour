class_name WorldgenState
extends RefCounted
## Only a new journey opts into new geometry; world/reward owners stay unchanged.

static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey") is Dictionary and camp.journey.get("build") is Dictionary and camp.journey.build.get("version")==6

static func initial_build(seed: String) -> Dictionary:
	var value: Dictionary=ExplorationState.initial_build(seed)
	value.version=6
	value.worldgen={"version":1,"policy_id":"BH_WORLDGEN_V1"}
	return value

static func problem(camp: Dictionary) -> String:
	var value: Variant=camp.journey.build.get("worldgen")
	return "" if value is Dictionary and TransactionReceipt.same(value,{"version":1,"policy_id":"BH_WORLDGEN_V1"}) else "WORLDGEN_CAMP_CAPABILITY"
