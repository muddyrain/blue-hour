extends "res://tests/persona_rules.gd"
## Native pixels at shared tile edges; Dummy runs validate the formal ground path.

class LegacyTiles extends IsoTiles:
	func _draw() -> void:
		for cell: Vector2i in cells:
			var rel: String = "tiles/%s.png" % _art_name(cell, String(cells[cell]))
			var p: Vector2 = IsoSpace.to_view(Vector2(cell) * TILE)
			draw_texture_rect(IsoAtlas.texture(rel), Rect2(p - Vector2(TILE, 0), Vector2(TILE * 2, TILE)), false)


func run() -> void:
	var base: Dictionary = _camp_fixture()
	base.journey.build = WorldgenState.initial_build(base.journey.seed, true, true)
	var action: Dictionary = DailyActions.offers(base)[0]
	var layout: StreetLayout = DailyActions.supply(action).layout
	expect(SeasideTown.is_layout(layout), "formal day-two offer selects seaside ground")
	var block: StreetBlock = StreetBlock.new()
	block.layout = layout
	root.add_child(block)
	expect(block.get_child_count() == 1 and block.get_child(0) is IsoTiles,
		"formal seaside ground has one tile layer and skips procedural grid")
	expect(not debug_collisions_hint and not debug_navigation_hint, "normal game has no physics/navigation debug overlay")
	block.free()
	if DisplayServer.get_name() == "headless":
		print("BH_GROUND_RENDER skipped: Dummy; run with native gl_compatibility for pixels")
	else:
		for width: int in [1024, 1600]:
			await _pixels(width)
	print("BH_GROUND_SEAMS " + JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)


func _pixels(width: int) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(width, width * 9 / 16)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var factor: float = float(width) / 1280.0
	var layer: IsoTiles = IsoTiles.new()
	layer.position = Vector2(width * 0.5 + 0.3, -100.0 * factor + 0.2)
	layer.scale = Vector2.ONE * factor
	for y: int in range(40):
		for x: int in range(40):
			layer.cells[Vector2i(x,y)] = "road" if x < 13 else "grass" if x < 26 else "canal"
	viewport.add_child(layer)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var actual: Image = viewport.get_texture().get_image()
	var coverage: Dictionary = _edge_coverage(actual, layer)
	expect(coverage.samples > 500 and coverage.holes == 0,
		"real road/grass/canal shared edges remain opaque at %d: %s" % [width, coverage])
	var road: Image = IsoAtlas.ground_texture("tiles/road_ew.png").get_image()
	var sidewalk: Image = IsoAtlas.ground_texture("tiles/sidewalk.png").get_image()
	expect(road.get_pixel(128,64).r > road.get_pixel(80,64).r + 0.1
		and sidewalk.get_pixel(128,64) != sidewalk.get_pixel(110,64),
		"road center paint and authored sidewalk seams keep their interior detail")
	# Replace only texture data with a constant transparent diamond. This removes
	# authored lines/gradients; any lattice must come from coverage and compositing.
	var saved: Dictionary = IsoAtlas._textures.duplicate()
	var solid: Color = Color("405060")
	var image: Image = Image.create(256,128,false,Image.FORMAT_RGBA8)
	image.fill(solid)
	for y: int in range(128):
		for x: int in range(256):
			if absf(x - 128.0) / 128.0 + absf(y - 64.0) / 64.0 > 1.0:
				image.set_pixel(x,y,Color.TRANSPARENT)
	for rel: String in saved:
		if rel.begins_with("tiles/"):
			IsoAtlas._textures[rel] = ImageTexture.create_from_image(image)
	IsoAtlas._ground_textures.clear()
	layer.queue_redraw()
	await process_frame
	RenderingServer.force_draw()
	var fixed: Dictionary = _edge_coverage(viewport.get_texture().get_image(), layer, solid)
	expect(fixed.holes == 0 and fixed.colour_errors == 0,
		"constant diamonds produce no lattice across shared edges at %d: %s" % [width, fixed])
	var legacy: LegacyTiles = LegacyTiles.new()
	legacy.cells = layer.cells.duplicate()
	legacy.position = layer.position
	legacy.scale = layer.scale
	layer.hide()
	viewport.add_child(legacy)
	await process_frame
	RenderingServer.force_draw()
	var control: Dictionary = _edge_coverage(viewport.get_texture().get_image(), legacy, solid)
	expect(control.colour_errors > 100,
		"negative control reproduces old transparent-rectangle seams at %d: %s" % [width, control])
	print("BH_GROUND_PIXELS " + JSON.stringify({"width":width,"real":coverage,"fixed":fixed,"old":control}))
	IsoAtlas._textures = saved
	IsoAtlas._ground_textures.clear()
	viewport.free()
	await process_frame


func _edge_coverage(image: Image, layer: IsoTiles, solid: Color = Color.TRANSPARENT) -> Dictionary:
	var samples: int = 0
	var holes: int = 0
	var colour_errors: int = 0
	for y: int in range(2,35):
		for x: int in range(2,35):
			for offset: Vector2 in [Vector2(0,0.25),Vector2(0.25,0)]:
				var point: Vector2i = Vector2i(layer.transform * IsoSpace.to_view((Vector2(x,y) + offset) * IsoTiles.TILE))
				if point.x < 4 or point.y < 4 or point.x >= image.get_width()-4 or point.y >= image.get_height()-4:
					continue
				for dy: int in range(-1,2):
					for dx: int in range(-1,2):
						var colour: Color = image.get_pixelv(point + Vector2i(dx,dy))
						samples += 1
						if colour.a < 0.99: holes += 1
						if solid.a > 0.0 and (absf(colour.r-solid.r) > 0.008 or absf(colour.g-solid.g) > 0.008 or absf(colour.b-solid.b) > 0.008 or colour.a < 0.99):
							colour_errors += 1
	return {"samples":samples,"holes":holes,"colour_errors":colour_errors}
