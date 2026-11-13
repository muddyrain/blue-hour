class_name WorldgenState
extends RefCounted
## Only a new journey opts into new geometry; world/reward owners stay unchanged.

static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey") is Dictionary and camp.journey.get("build") is Dictionary and camp.journey.build.get("version")==6

static func initial_build(seed: String, _level: bool = false, _industrial: bool = false) -> Dictionary:
	var value: Dictionary=ExplorationState.initial_build(seed)
	value.version=6
	value.worldgen={"version":2,"policy_id":"BH_LEVEL_V1"}
	value.worldgen.industrial_yard = 1
	return value

static func level_enabled(camp: Dictionary) -> bool:
	return enabled(camp) and camp.journey.build.get("worldgen",{}).get("version")==2

static func industrial_yard_enabled(camp: Dictionary) -> bool:
	return level_enabled(camp) and camp.journey.build.worldgen.get("industrial_yard") == 1


static func problem(camp: Dictionary) -> String:
	var value: Variant = camp.journey.build.get("worldgen")
	if value is Dictionary:
		for supported: Dictionary in [
			{"version":2,"policy_id":"BH_LEVEL_V1"},
			{"version":2,"policy_id":"BH_LEVEL_V1","industrial_yard":1},
		]:
			if TransactionReceipt.same(value, supported):
				return ""
	return "WORLDGEN_CAMP_CAPABILITY"
