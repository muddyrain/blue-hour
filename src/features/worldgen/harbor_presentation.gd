class_name HarborPresentation
extends RefCounted
## Exterior work points and closed-roof props; no second search or reward system.


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
		prop.name = detail.kind
		IsoAtlas.attach(prop, detail.art)
		prop.set_meta("iso_kind", detail.kind)
		if detail.kind == "lamp":
			prop.set_meta("light_color", Color("d8e5df") if float(detail.point[0]) >= 990.0 else Color("ffa64a"))
		prop.position = WorldLayout.point(detail.point)
		world._sort.add_child(prop)
	for definition: Dictionary in world.supply.generated.sites:
		var binding: Dictionary = bindings[definition.id]
		var entity: Dictionary = binding.entity
		var prop: FieldProp = binding.prop
		var site: Expedition.SearchSite = Expedition.SearchSite.new(StringName(definition.kind), WorldLayout.point(entity.door))
		site.id = StringName(definition.id)
		site.reward = int(definition.amount)
		site.weapon = definition.weapon
		site.seconds = float(definition.seconds)
		site.prop = prop
		site.hit = prop.scaled_hit_bounds()
		prop.primary_target = definition.id in world.supply.generated.objective.site_ids
		prop.reward_hint = ("废料回收" if site.kind == &"cash" else "冷藏补给") + " +%d" % site.reward
		if site.weapon:
			prop.reward_hint += " · 武器 ×1"
		var tools: int = world._tools_at(String(site.id))
		if tools > 0:
			prop.reward_hint += " · 工具 ×%d" % tools
		prop.loot_landmark = prop.title
		var work_anchor: Vector2 = IsoSpace.to_view(site.door - prop.position)
		prop.configure_loot_badge("货台" if site.id == &"cash" else "仓储", work_anchor + Vector2(0, 12))
		world.sites.append(site)
		if site.id == &"cash":
			world._cash_site = site
			world._shop = prop
		elif site.id == &"food":
			world._food_site = site


static func card_text(supply: MissionSupply) -> String:
	var action: Dictionary = supply.generated
	var main: Dictionary = {}
	for site: Dictionary in action.sites:
		if site.id == "cash":
			main = site
	var tools: int = EconomyActions.count_at(action, "cash")
	var reward: String = "工具 ×%d" % tools if tools > 0 else "武器 ×1" if bool(main.get("weapon", false)) else "器材回收"
	return "%s\n远端货台 · %s · 基础作业 %d 秒\n港口作业耗时 ×1.5；仓储点基础 27–45 秒。\n废料按货币结算，首次货台开工引来增援。\n%s" % [HarborWarehouse.TITLE, reward, ceili(float(main.get("seconds", 12)) * HarborWarehouse.WORK_FACTOR), supply.layout.route_hint]
