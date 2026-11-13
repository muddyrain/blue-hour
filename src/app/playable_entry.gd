class_name PlayableEntry
extends RefCounted
## One entry configuration; the existing feature chain and business owners run it.

const DIRECTORY: String = "user://playable-v1"


static func progress_path() -> String:
	return ProjectSettings.globalize_path(DIRECTORY+"/run.enemy-v1.json").replace("\\","/").simplify_path()


static func owns_path(path: String) -> bool:
	return path.is_absolute_path() and path.replace("\\","/").simplify_path()==progress_path()


static func resolve(arguments: PackedStringArray) -> Dictionary:
	var effective: Array[String] = []
	for argument: String in arguments: effective.append(argument)
	return {"playable":true,"arguments":effective,"progress":progress_path(),"audio":DIRECTORY+"/audio.json"}
