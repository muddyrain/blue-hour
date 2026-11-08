class_name ScreamerPolicyV1
extends RefCounted
## An explicit extension of the ordinary industrial gear offer.

const VERSION: int = 1
const KIND: String = "screamer_zombie_v1"
const RANGE: float = 220.0
const WINDUP: float = 2.0
const MAX_REINFORCEMENTS: int = 2


static func enabled(generated: Dictionary) -> bool:
	return SurvivalContracts.integer(generated.get("screamer_policy"), VERSION, VERSION) and eligible(generated)


static func eligible(generated: Dictionary) -> bool:
	var worldgen: Variant = generated.get("worldgen")
	var layout: Variant = generated.get("layout")
	var campaign: Variant = generated.get("campaign")
	return generated.get("version") == 9 and generated.get("type") == "airdrop" \
		and SurvivalContracts.integer(generated.get("day"), 3, RunSave.MAX_COUNTER) \
		and SurvivalContracts.integer(generated.get("mission_policy"), 1, 1) \
		and SurvivalContracts.integer(generated.get("gear_build_policy"), BuildItems.VERSION, BuildItems.CATALOG_POOL) \
		and not generated.has("rare_policy") and not generated.has("investigation") \
		and not generated.has("finale_policy") and campaign is Dictionary and campaign.get("is_finale") == false \
		and worldgen is Dictionary and worldgen.get("version") == 2 and worldgen.get("revision") == 2 \
		and layout is Dictionary and layout.get("topology") == "industrial"
