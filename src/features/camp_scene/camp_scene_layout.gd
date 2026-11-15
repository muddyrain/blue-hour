class_name CampSceneLayout
extends RefCounted
## Presentation map only; none of these coordinates enter campaign state.

const SIZE: Vector2 = Vector2(1280, 720)
const BOUNDS: Rect2 = Rect2(0, 0, 736, 608)
const FACILITIES: Dictionary[String, Rect2] = {
	"supply": Rect2(160, 64, 128, 96),
	"workshop": Rect2(416, 80, 144, 112),
	"planning": Rect2(528, 240, 128, 96),
}
const AREAS: Dictionary[StringName, Rect2] = {
	&"bus": Rect2(118, 512, 108, 32),
	&"crew": Rect2(48, 224, 104, 64),
	&"weapons": Rect2(400, 288, 64, 40),
	&"training": Rect2(260, 328, 64, 64),
}
const FIRE: Vector2 = Vector2(292, 360)
const LAMPS: Array[Vector2] = [Vector2(112, 344), Vector2(352, 160), Vector2(688, 480)]
const LOOP: Array[Vector2] = [
	Vector2(208, 208), Vector2(352, 208), Vector2(472, 240),
	Vector2(472, 320), Vector2(472, 400), Vector2(352, 416),
	Vector2(208, 416), Vector2(176, 336), Vector2(176, 208),
]
const PATHS: Array[Rect2] = [
	Rect2(160, 192, 352, 32), Rect2(464, 192, 32, 240),
	Rect2(176, 400, 320, 32), Rect2(160, 192, 32, 224),
	Rect2(208, 144, 32, 80), Rect2(464, 176, 32, 64),
	Rect2(480, 344, 128, 32), Rect2(240, 320, 96, 80),
	Rect2(384, 288, 96, 64), Rect2(160, 416, 96, 64),
]
# Side yards hold daily-life clusters; door approaches and the walking loop stay open.
const DRESSING: Array[Dictionary] = [
	{"kind":"clothesline", "at":Vector2(352, 72), "size":Vector2(80, 16)},
	{"kind":"bucket", "at":Vector2(316, 106), "size":Vector2(20, 20)},
	{"kind":"crate", "at":Vector2(344, 152), "size":Vector2(32, 26)},
	{"kind":"crate", "at":Vector2(624, 112), "size":Vector2(32, 26)},
	{"kind":"planter", "at":Vector2(600, 164), "size":Vector2(28, 24)},
	{"kind":"planter", "at":Vector2(112, 112), "size":Vector2(28, 24)},
	{"kind":"bicycle", "at":Vector2(96, 374), "size":Vector2(60, 20)},
	{"kind":"bucket", "at":Vector2(126, 408), "size":Vector2(20, 20)},
	{"kind":"blackboard", "at":Vector2(536, 384), "size":Vector2(44, 20)},
	{"kind":"bench", "at":Vector2(536, 424), "size":Vector2(64, 22)},
	{"kind":"planter", "at":Vector2(656, 416), "size":Vector2(28, 24)},
	{"kind":"crate", "at":Vector2(680, 376), "size":Vector2(32, 26)},
	{"kind":"planter", "at":Vector2(680, 192), "size":Vector2(28, 24)},
	{"kind":"bench", "at":Vector2(320, 272), "size":Vector2(64, 22)},
	{"kind":"crate", "at":Vector2(384, 272), "size":Vector2(32, 26)},
	{"kind":"planter", "at":Vector2(224, 304), "size":Vector2(28, 24)},
]


static func facility_level(camp: Dictionary, id: String) -> int:
	if EconomyBuildV1.enabled(camp):
		return EconomyBuildV1.level(camp, id)
	if CampFacilities.selected(camp) == id:
		return 2 if CampFacilities.upgraded(camp) else 1
	return 0


static func facility_door(id: String) -> Vector2:
	return IsoSpace.foot(FACILITIES[id]) + Vector2(0, 20)


static func member_position(member_id: int) -> Vector2:
	var index: int = posmod((member_id - 1) * 2, LOOP.size())
	return LOOP[index].lerp(LOOP[(index + 1) % LOOP.size()], 0.5) if member_id > LOOP.size() else LOOP[index]


static func isolated(path: String) -> bool:
	var normalized: String = path.replace("\\", "/").simplify_path().to_lower()
	var user: String = OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	return path.is_absolute_path() and "/.local/" in normalized and "/.local/" in user and normalized.get_slice("/.local/", 0) == user.get_slice("/.local/", 0)
