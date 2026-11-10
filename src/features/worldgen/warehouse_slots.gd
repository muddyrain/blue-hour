class_name WarehouseSlots
extends RefCounted
## Frozen semantic slots and physical profiles. Texture paths belong to WarehouseDressingArt.

const RACK: String = "warehouse.storage.pallet_rack"
const CARGO: String = "warehouse.storage.cargo_stack"
const BAY: String = "warehouse.loading.bay_mark"
const DOCK: String = "warehouse.loading.dock_edge"
const NARROW: String = "warehouse.service.narrow_annex"
const END: String = "warehouse.service.end_annex"
const REPAIR: String = "warehouse.service.repair_kit"
const MAT: String = "warehouse.service.work_mat"
const PAVING: String = "warehouse.alley.paving"
const LAMP: String = "warehouse.alley.wall_lamp"
const EDGE: String = "warehouse.alley.edge_prop"

const BUILDINGS: Dictionary = {
	NARROW: {"size":Vector2(112,186), "depth":144.0, "roof":132, "door":55.0, "title":"窄检修附房"},
	END: {"size":Vector2(112,176), "depth":132.0, "roof":122, "door":63.0, "title":"仓旁工具房"},
}
const FOOTPRINTS: Dictionary = {
	RACK: Vector2(126,26),
	CARGO: Vector2(72,25),
	REPAIR: Vector2(52,22),
	LAMP: Vector2.ZERO,
	EDGE: Vector2.ZERO,
}
