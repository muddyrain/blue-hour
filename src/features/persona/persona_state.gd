class_name PersonaState
extends RefCounted
## Facts live in the original journey owner. Old journeys never acquire this extension.
static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey") is Dictionary and camp.journey.get("build") is Dictionary and (camp.journey.build.get("version")==4 or camp.journey.build.get("version")==5 or camp.journey.build.get("version")==6)

static func initial_build(seed: String) -> Dictionary:
	var build: Dictionary=PowerState.initial_build()
	build.version=4
	build.persona=SurvivorPersona.generate(seed)
	return build

static func recipe(generated: Dictionary, id: int, definition_id: String = "") -> Dictionary:
	return SurvivorPersona.member(generated.get("persona",{}).get("facts",{}),id,definition_id)

static func factor(generated: Dictionary, id: int, kind: String) -> float:
	if not generated.has("persona"): return 1.0
	return float(SurvivorPersona.factors(recipe(generated,id)).get(kind,0.0))
