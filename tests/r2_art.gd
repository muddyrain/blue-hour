extends SceneTree
## Exercise the native-canvas path and real alpha, not just descriptor constants.
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R2_ART_FAIL " + label)

func run() -> void:
	for type: String in ["convenience_store", "eatery"]:
		var art: String = StreetModuleArt.for_archetype(type)
		var definition: Dictionary = WorldgenArt.definition({"archetype": type, "variant": 0, "art": art})
		var prop: FieldProp = FieldProp.new()
		prop.world_asset = true
		prop.calibrated = true
		prop.facade = definition.texture
		prop.native_size = definition.native_size
		prop.render_anchor = definition.origin
		prop.reference_width = definition.reference_width
		prop.roof_cut = definition.roof_split
		prop.front_width = WorldgenScale.WIDTH[type]
		prop.door_offset = StreetModuleArt.door_offset(art, prop.front_width)
		prop.position = Vector2(400, 400)
		prop.searchable = false
		root.add_child(prop)
		expect(prop.facade.get_size() == prop.native_size, type + " native canvas is not truncated to the legacy frame")
		expect(prop._wall.region_rect.end == prop.native_size, type + " wall includes full source foot and padding")
		expect(prop._roof.region_rect.size.y == definition.roof_split, type + " roof uses its own source split")
		expect(prop.scaled_hit_contains(prop.position + Vector2(prop.door_offset, 48)), type + " real doorway remains selectable")
		expect(not prop.scaled_hit_contains(prop.position + Vector2(0, -320)), type + " transparent sky padding cannot steal a click")
		expect(prop.obscures(prop.position + Vector2(0, -160)), type + " real roof detects a passing friend")
		prop.show_behind_roof(true)
		expect(is_equal_approx(prop._roof.modulate.a, 0.4) and is_equal_approx(prop._wall.modulate.a, 1.0), type + " only roof fades")
		prop.show_behind_roof(false)
		expect(is_equal_approx(prop._roof.modulate.a, 1.0), type + " roof opacity restores")
		prop.free()
		var legacy: Dictionary = WorldgenArt.definition({"archetype": type, "variant": 0})
		expect(not legacy.has("native_size") and legacy.origin == Vector2(256, 608), type + " legacy metadata remains unchanged")
	var point: Vector2 = Vector2(300, 300)
	var feet: Array = StreetModuleArt.courtyard_collisions(point, 200)
	expect(feet.size() == 2, "courtyard uses two solid feet")
	var interior: Vector2 = point + Vector2(90, -45)
	var open_right: Vector2 = point + Vector2(200, -45)
	for value: Array in feet:
		var foot: Rect2 = WorldLayout.rect(value)
		expect(not foot.has_point(interior) and not foot.has_point(open_right), "L-shaped wall preserves the interior and right opening")
	expect(WorldgenArt.PAVING.get_size() == Vector2(1254, 1254) and StreetModuleArt.PAVING_PATCH == 256.0, "material source pixels do not become world units")
	print(JSON.stringify({"suite": "r2_art", "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
