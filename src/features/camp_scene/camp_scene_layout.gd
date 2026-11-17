class_name CampSceneLayout
extends RefCounted
## Camp-only presentation coordinates. Never used by navigation or saved state.

const SIZE: Vector2 = Vector2(1280, 720)
const SCENE_SIZE: Vector2 = Vector2(976, 612)
const BOUNDS: Rect2 = Rect2(Vector2.ZERO, SCENE_SIZE)
const FACILITIES: Dictionary[String, Rect2] = {
	"supply": Rect2(380, 75, 250, 180),
	"workshop": Rect2(650, 185, 325, 310),
	"planning": Rect2(475, 405, 180, 105),
}
const DOORS: Dictionary[String, Vector2] = {
	"supply": Vector2(490, 246), "workshop": Vector2(766, 430), "planning": Vector2(554, 494),
}
const AREAS: Dictionary[StringName, Rect2] = {
	&"bus": Rect2(42, 364, 168, 126),
	&"crew": Rect2(34, 78, 320, 216),
	&"weapons": Rect2(805, 390, 104, 70),
	&"training": Rect2(430, 328, 72, 72),
}
const FIRE: Vector2 = Vector2(466, 372)
# Short local strolls keep all eight people readable and clear of the baked furniture.
const STOPS: Array[Vector2] = [
	Vector2(350, 352), Vector2(440, 292), Vector2(585, 350), Vector2(409, 425),
	Vector2(300, 310), Vector2(540, 285), Vector2(300, 418), Vector2(525, 395),
]
const STROLLS: Array[Vector2] = [
	Vector2(370, 345), Vector2(465, 292), Vector2(610, 365), Vector2(390, 410),
	Vector2(320, 323), Vector2(565, 305), Vector2(320, 400), Vector2(545, 384),
]

static func facility_level(camp: Dictionary, id: String) -> int:
	if EconomyBuildV1.enabled(camp):
		return EconomyBuildV1.level(camp, id)
	if CampFacilities.selected(camp) == id:
		return 2 if CampFacilities.upgraded(camp) else 1
	return 0


static func facility_door(id: String) -> Vector2:
	return DOORS[id]


static func member_position(member_id: int) -> Vector2:
	return resident_route(member_id)[0]


static func resident_route(member_id: int) -> Array[Vector2]:
	var index: int = 7 if member_id == 9 else 5 if member_id == 10 else clampi(member_id - 1, 0, 7)
	return [STOPS[index], STROLLS[index]]


static func isolated(path: String) -> bool:
	var normalized: String = path.replace("\\", "/").simplify_path().to_lower()
	var user: String = OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	return path.is_absolute_path() and "/.local/" in normalized and "/.local/" in user and normalized.get_slice("/.local/", 0) == user.get_slice("/.local/", 0)
