extends SceneTree
## Actual sprite alpha/scale and dispatch, without a played journey or reward claim.
class PickingWorld extends Expedition:
	var picked: StringName
	func _ready() -> void: pass
	func request_search(id: StringName = &"cash") -> void: picked=id
var checks: int=0
var failures: int=0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("WORLDGEN_PICK_FAIL "+label)
func prop(type: String,at: Vector2,variant: int=0) -> FieldProp:
	var definition: Dictionary=WorldgenArt.definition({"archetype":type,"variant":variant})
	var value: FieldProp=FieldProp.new()
	value.world_asset=true;value.calibrated=true;value.facade=definition.texture
	value.front_width=WorldgenScale.WIDTH[type];value.roof_cut=definition.roof_split
	value.position=at;value.door_offset=(WorldgenScale.door_x(type,variant)-256.0)*value.front_width/448.0
	value.searchable=false
	root.add_child(value)
	return value
func run() -> void:
	for type: String in ["eatery","convenience_store","warehouse","small_apartment"]:
		var building: FieldProp=prop(type,Vector2(400,400))
		expect(not building.scaled_hit_contains(Vector2(400,110)),"empty courtyard above compact "+type+" never starts or cancels work")
		expect(building.scaled_hit_contains(building.position+Vector2(building.door_offset,48)),"exact visible entrance remains clickable "+type)
		var height_limit: float=370.0 if type=="small_apartment" else 340.0
		expect(building.scaled_hit_bounds().size.y<height_limit,"compact art has a bounded hit region including the entrance "+type)
		building.free()
	var home: FieldProp=prop("detached_home",Vector2(400,400),3)
	expect(home.facade==WorldgenArt.HOME and home.door_offset<0 and home.scaled_hit_contains(home.position+Vector2(home.door_offset,48)),"new courtyard house uses its own left entrance and actual alpha")
	expect(not home.scaled_hit_contains(home.position+Vector2(0,-280)),"new courtyard house does not claim the empty rear court")
	home.free()
	var world: PickingWorld=PickingWorld.new()
	world.layout=StreetLayout.new();world.layout.world_data={"version":5}
	world.supply=MissionSupply.new();world.supply.generated={"version":9}
	var back: FieldProp=prop("eatery",Vector2(400,350))
	var front: FieldProp=prop("eatery",Vector2(400,400))
	for pair: Array in [["back",back],["front",front]]:
		var site: Expedition.SearchSite=Expedition.SearchSite.new(&"cash",pair[1].position+Vector2(0,48))
		site.id=StringName(pair[0]);site.prop=pair[1];site.hit=pair[1].scaled_hit_bounds();world.sites.append(site)
	expect(world._clicked_site(Vector2(400,330)) and world.picked==&"front","overlapping real facades select the front footpoint first")
	world.picked=&""
	expect(not world._clicked_site(Vector2(400,120)) and world.picked==&"","empty space never reaches request_search")
	back.free();front.free();world.free()
	print(JSON.stringify({"suite":"worldgen_picking","checks":checks,"failures":failures}))
	quit(1 if failures else 0)
