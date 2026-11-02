class_name CampSceneLayout
extends RefCounted
## PROJECT_TEMP spatial presentation; these coordinates never enter a save.

const SIZE: Vector2 = Vector2(1280, 720)
const AREAS: Dictionary[StringName, Rect2] = {
	&"bus": Rect2(130, 346, 294, 226),
	&"crew": Rect2(434, 124, 388, 260),
	&"weapons": Rect2(896, 124, 310, 350),
	&"supplies": Rect2(890, 510, 310, 114),
	&"training": Rect2(140, 180, 260, 134),
}


static func member_position(member_id: int) -> Vector2:
	return Vector2(494 + (member_id - 1) * 144, 476)


static func isolated(path: String) -> bool:
	var normalized: String = path.replace("\\", "/").simplify_path().to_lower()
	var user: String = OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	return path.is_absolute_path() and "/.local/" in normalized and "/.local/" in user and normalized.get_slice("/.local/", 0) == user.get_slice("/.local/", 0)
