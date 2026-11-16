extends "res://tests/run_feel.gd"
## Authored texture lines and repeated shading need checks beyond alpha coverage.

class LineControl extends Node2D:
	var regions: Dictionary = {}
	var ground_transform: Transform2D

	func _draw() -> void:
		for key: String in regions:
			var polygon: PackedVector2Array = regions[key]
			if key == "grass":
				# Reintroduce actual 32-unit ground boundaries over the formal lawn.
				for y: int in range(48):
					for x: int in range(60):
						var p: Vector2 = ground_transform * IsoSpace.to_view(Vector2(x,y) * 32.0)
						for offset: Vector2 in [Vector2(32,0), Vector2(0,32)]:
							var end: Vector2 = ground_transform * IsoSpace.to_view(Vector2(x,y) * 32.0 + offset)
							if Geometry2D.is_point_in_polygon(p, polygon) and Geometry2D.is_point_in_polygon(end, polygon):
								draw_line(p, end, Color(0.15,0.22,0.16), 1.0)
			else:
				var bounds: Rect2 = IsoSpace._aabb(polygon)
				for y: int in range(int(bounds.position.y), int(bounds.end.y), 8):
					for x: int in range(int(bounds.position.x), int(bounds.end.x), 16):
						var p: Vector2 = Vector2(x,y)
						for offset: Vector2 in [Vector2(8,4), Vector2(-8,4)]:
							if Geometry2D.is_point_in_polygon(p, polygon) and Geometry2D.is_point_in_polygon(p+offset, polygon):
								draw_line(p, p+offset, Color(0.8,0.85,0.8,0.6), 1.0)


func run() -> void:
	_source_pixels()
	if DisplayServer.get_name() == "headless":
		print("BH_SURFACE_RENDER skipped: Dummy; native gl_compatibility required for formal scene pixels")
	else:
		for width: int in [1024, 1600]:
			await _formal_pixels(width)
	print("BH_SURFACE_LINES " + JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)


func _source_image(path: String) -> Image:
	var image: Image = Image.new()
	var error: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	expect(error == OK, "read original PNG bytes: " + path)
	return image


func _source_pixels() -> void:
	for rel: String in ["road", "sidewalk", "canal", "bank"]:
		var image: Image = _source_image("res://assets/iso/tiles/%s.png" % rel)
		var low: Vector3 = Vector3.ONE
		var high: Vector3 = Vector3.ZERO
		var opaque: bool = true
		for y: int in range(48,80):
			for x: int in range(80,176):
				var colour: Color = image.get_pixel(x,y)
				var value: Vector3 = Vector3(colour.r,colour.g,colour.b)
				low = low.min(value)
				high = high.max(value)
				opaque = opaque and colour.a > 0.99
		expect(opaque and (high-low).length() < 0.035,
			"source %s has opaque fine grain without X/ripple strokes or restarted lighting" % rel)
	var roof: Image = _source_image("res://assets/iso/buildings/convenience.png")
	var detail: Dictionary = _line_pixels(roof, _quad(Rect2(400,210,150,80)))
	expect(detail.samples > 9000 and detail.ratio < 0.01,
		"source green roof has broad light without intersecting dotted courses: %s" % detail)


func _formal_pixels(width: int) -> void:
	var base: Dictionary = _feel_camp()
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(width, width * 9 / 16)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: Expedition = Expedition.new()
	world.supply = DailyActions.supply(DailyActions.offers(base)[0])
	world.field_departure = base
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.sortie_id = base.profile_id + ":1"
	world.growth_binding = {"run_id":base.profile_id,"root_id":base.journey.root_id,"transaction_id":world.sortie_id,
		"base_hash":SurvivalContracts.fingerprint(base),"rules_hash":SurvivalContracts.fingerprint(FrozenSettlement.pool_rules(base,world.supply))}
	world.ui_theme = preload("res://assets/ui/c1/hud_theme.tres")
	viewport.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.bus_view.skip()
	var food: Expedition.SearchSite = world.search_site(&"food")
	world.command_move(food.door)
	world.request_search(food.id)
	for tick: int in range(240):
		world.step(1.0/30.0)
	world.camera.pan_by(IsoSpace.to_view(food.door)-world.camera.position)
	expect(SeasideTown.is_layout(world.layout) and not debug_collisions_hint and not debug_navigation_hint,
		"real seaside offer, original geometry and normal rendering at %d" % width)
	for frame: int in range(3):
		await process_frame
	RenderingServer.force_draw()
	var image: Image = viewport.get_texture().get_image()
	var regions: Dictionary = _regions(viewport.size)
	var transform: Transform2D = world.get_global_transform_with_canvas()
	var actual: Dictionary = _measure(image, regions, transform)
	for key: String in actual:
		var value: Dictionary = actual[key]
		if key == "grass":
			expect(value.samples > 4000 and value.ratio > 0.03 and value.phase_span < 3.0/255.0,
				"formal lawn has no coherent 32-unit lattice at %d: %s" % [width,value])
		else:
			expect(value.samples > 700 and value.ratio < (0.05 if key == "pitched_roof" else 0.01),
				"formal %s has no dense lines at %d: %s" % [key,width,value])
	# Sensitivity control uses the same viewport, camera, clipping and full scene.
	var control: LineControl = LineControl.new()
	control.regions = regions
	control.ground_transform = transform
	var overlay: CanvasLayer = CanvasLayer.new()
	viewport.add_child(overlay)
	overlay.add_child(control)
	await process_frame
	RenderingServer.force_draw()
	var negative: Dictionary = _measure(viewport.get_texture().get_image(), regions, transform)
	for key: String in negative:
		expect(negative[key].phase_span > 6.0/255.0 if key == "grass" else negative[key].ratio > 0.10,
			"same detector rejects reintroduced %s grid at %d: %s" % [key,width,negative[key]])
	print("BH_SURFACE_PIXELS " + JSON.stringify({"width":width,"actual":actual,"negative":negative}))
	viewport.free()
	await process_frame


func _quad(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x,rect.position.y), rect.end, Vector2(rect.position.x,rect.end.y)])


func _regions(size: Vector2i) -> Dictionary:
	# Visible interiors in the unchanged food-door camera at zoom 0.82; exclude
	# HVAC units, labels, curbs and the legitimate center dashed line.
	var regions: Dictionary = {
		"roof":_quad(Rect2(576,154,90,28)),
		"pitched_roof":_quad(Rect2(313,304,90,18)),
		"water":PackedVector2Array([Vector2(394,98),Vector2(433,117),Vector2(351,159),Vector2(312,139)]),
		"road":PackedVector2Array([Vector2(850,490),Vector2(948,539),Vector2(935,546),Vector2(837,497)]),
		"sidewalk":PackedVector2Array([Vector2(891,469),Vector2(989,518),Vector2(976,525),Vector2(878,476)]),
		"grass":_quad(Rect2(949,310,65,86)),
	}
	var offset: Vector2 = (Vector2(size)-Vector2(1024,576))*0.5
	for key: String in regions:
		var polygon: PackedVector2Array = regions[key]
		for index: int in range(polygon.size()):
			polygon[index] += offset
		regions[key] = polygon
	return regions


func _measure(image: Image, regions: Dictionary, transform: Transform2D) -> Dictionary:
	var result: Dictionary = {}
	for key: String in regions:
		result[key] = _line_pixels(image, regions[key])
	result.grass.phase_span = _phase_span(image, regions.grass, transform)
	return result


func _line_pixels(image: Image, polygon: PackedVector2Array) -> Dictionary:
	var bounds: Rect2i = Rect2i(IsoSpace._aabb(polygon))
	var count: int = 0
	var lines: int = 0
	for y: int in range(bounds.position.y+2,bounds.end.y-2):
		for x: int in range(bounds.position.x+2,bounds.end.x-2):
			var p: Vector2i = Vector2i(x,y)
			var around: Color = Color(0,0,0,0)
			var inside: bool = true
			for offset: Vector2i in [Vector2i(-2,0),Vector2i(2,0),Vector2i(0,-2),Vector2i(0,2)]:
				inside = inside and Geometry2D.is_point_in_polygon(Vector2(p+offset),polygon)
				around += image.get_pixelv(p+offset)*0.25
			if not inside:
				continue
			var delta: Color = image.get_pixelv(p)-around
			count += 1
			if maxf(absf(delta.r),maxf(absf(delta.g),absf(delta.b))) > 3.0/255.0:
				lines += 1
	return {"samples":count,"line_pixels":lines,"ratio":float(lines)/maxi(count,1)}


func _phase_span(image: Image, polygon: PackedVector2Array, transform: Transform2D) -> float:
	var inverse: Transform2D = transform.affine_inverse()
	var bounds: Rect2i = Rect2i(IsoSpace._aabb(polygon))
	var span: float = 0.0
	for axis: int in range(2):
		var sums: Array[Vector3] = []
		var counts: Array[int] = []
		sums.resize(32)
		counts.resize(32)
		for y: int in range(bounds.position.y,bounds.end.y):
			for x: int in range(bounds.position.x,bounds.end.x):
				if not Geometry2D.is_point_in_polygon(Vector2(x,y),polygon):
					continue
				var map: Vector2 = IsoSpace.to_map(inverse*Vector2(x,y))
				var bin: int = posmod(int(floorf(map[axis])),32)
				var colour: Color = image.get_pixel(x,y)
				sums[bin] += Vector3(colour.r,colour.g,colour.b)
				counts[bin] += 1
		var low: Vector3 = Vector3.ONE
		var high: Vector3 = Vector3.ZERO
		for index: int in range(32):
			if counts[index] == 0:
				continue
			var average: Vector3 = sums[index]/counts[index]
			low = low.min(average)
			high = high.max(average)
		span = maxf(span,maxf(high.x-low.x,maxf(high.y-low.y,high.z-low.z)))
	return span
