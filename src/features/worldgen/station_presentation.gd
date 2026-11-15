class_name StationPresentation
extends RefCounted
## Closed exterior buildings and original signed work; never creates a reward.


static func populate(world: Expedition) -> void:
	var bindings: Dictionary = {}
	for entity: Dictionary in world.layout.world_data.entities:
		var body: Rect2 = WorldLayout.rect(entity.rect)
		var prop: FieldProp = FieldProp.new()
		prop.iso_art = entity.art
		prop.world_asset = true
		prop.title = entity.title
		prop.front_width = body.size.x
		prop.body_depth = body.size.y
		prop.door_offset = WorldLayout.point(entity.door).x - body.get_center().x
		prop.position = Vector2(body.get_center().x, body.end.y)
		prop.ui_theme = world.ui_theme
		prop.searchable = not String(entity.site_id).is_empty()
		world._sort.add_child(prop)
		world._buildings.append(prop)
		if prop.searchable:
			bindings[entity.site_id] = {"entity":entity, "prop":prop}
	for detail: Dictionary in world.layout.world_data.props:
		var prop: Node2D = Node2D.new()
		IsoAtlas.attach(prop, detail.art)
		prop.set_meta("iso_kind", detail.kind)
		prop.position = WorldLayout.point(detail.point)
		world._sort.add_child(prop)
	for point: Vector2 in [Vector2(784, 432), Vector2(1600, 432), Vector2(784, 1008)]:
		var bench: Node2D = Node2D.new()
		IsoAtlas.attach(bench, "station/bench.svg")
		bench.position = point
		world._sort.add_child(bench)
	for definition: Dictionary in world.supply.generated.sites:
		var binding: Dictionary = bindings[definition.id]
		var prop: FieldProp = binding.prop
		var site: Expedition.SearchSite = Expedition.SearchSite.new(StringName(definition.kind), WorldLayout.point(binding.entity.door))
		site.id = StringName(definition.id)
		site.reward = int(definition.amount)
		site.weapon = definition.weapon
		site.seconds = float(definition.seconds)
		site.prop = prop
		site.hit = prop.scaled_hit_bounds()
		prop.primary_target = definition.id in world.supply.generated.objective.site_ids
		prop.reward_hint = ("食品" if site.kind == &"food" else "货币") + " +%d" % site.reward
		if site.weapon:
			prop.reward_hint += " · 武器 ×1"
		var tools: int = world._tools_at(String(site.id))
		if tools > 0:
			prop.reward_hint += " · 工具 ×%d" % tools
		prop.loot_landmark = prop.title
		prop.configure_loot_badge("食品" if site.kind == &"food" else "寄存", IsoSpace.to_view(site.door - prop.position) + Vector2(0, 12))
		world.sites.append(site)
		if site.id == &"cash":
			world._cash_site = site
			world._shop = prop
		elif site.id == &"food":
			world._food_site = site


static func card_text(supply: MissionSupply) -> String:
	var names: PackedStringArray = []
	for entity: Dictionary in supply.layout.world_data.entities:
		if entity.site_id in supply.generated.objective.site_ids:
			names.append(entity.title)
	return "%s\n主目标 · %s\n可搜获上限：食品 %d · 货币 %d · 武器 %d\n%s" % [CapeStation.TITLE, "、".join(names), supply.food_reward, supply.cash_reward, int(supply.generated.weapons), CapeStation.ROUTE_HINT]
