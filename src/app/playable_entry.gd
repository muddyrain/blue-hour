class_name PlayableEntry
extends RefCounted
## One entry configuration; the existing feature chain and business owners run it.

const DIRECTORY: String = "user://playable-v1"
const FEATURE_ARGUMENTS: Array[String] = ["--bh-enemy-trial","--bh-safe-suspend","--bh-camp-prototype"]
const LEGACY_ARGUMENTS: Array[String] = ["--bh-legacy-entry","--bh-transactional","--bh-battle-survival","--bh-survival","--bh-survival-pilot","--bh-hunger-trial","--bh-rescue-trial","--bh-growth-trial","--bh-field-join-trial","--bh-trait-trial","--bh-training-trial","--bh-rescue-pool-trial","--bh-roster-trial","--bh-weapon-quality-trial","--bh-enemy-trial","--bh-camp-prototype"]


static func progress_path() -> String:
	return ProjectSettings.globalize_path(DIRECTORY+"/run.enemy-v1.json").replace("\\","/").simplify_path()


static func owns_path(path: String) -> bool:
	return path.is_absolute_path() and path.replace("\\","/").simplify_path()==progress_path()


static func resolve(arguments: PackedStringArray) -> Dictionary:
	var playable: bool = true
	for flag: String in LEGACY_ARGUMENTS:
		if flag in arguments: playable = false
	var effective: Array[String] = []
	if playable: effective.assign(FEATURE_ARGUMENTS)
	for argument: String in arguments: effective.append(argument)
	return {"playable":playable,"arguments":effective,"progress":progress_path() if playable else "user://saves/run.json","audio":DIRECTORY+"/audio.json" if playable else "user://settings/audio.json"}
