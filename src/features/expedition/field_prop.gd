class_name FieldProp
extends Node2D
## Front edge is the sort anchor. Only the roof fades for a friend behind it.

const ShopTexture: Texture2D = preload("res://assets/candidates/shop_02.png")
const LootTheme: Theme = preload("res://assets/ui/c1/hud_theme.tres")
var primary_target: bool = false
var calibrated: bool = false
var fixed_roof: bool = false
var roof_cut: int = 512
var body_depth: float = 112
var door_offset: float = 0
var native_size: Vector2 = Vector2(512,640)
var render_anchor: Vector2 = Vector2(256,608)
var reference_width: float = 448.0
var street_sign: String = ""
var sign_rect: Rect2
var soft_contact: bool = false
var roof_tint: Color = Color.WHITE
var facade_tint: Color = Color.WHITE
var _alpha: Image
var world_asset: bool = false
var facade: Texture2D = ShopTexture
var iso_art: String = ""
var is_market: bool = false
var is_residence: bool = false
var front_width: float = 368.0
var searched: bool = false
var searchable: bool = true
var title: String = "旧街补给店"
var reward_hint: String = "货币 +4"
var ui_theme: Theme
var loot_category: String = ""
var loot_landmark: String = ""
var _loot_anchor: Vector2
var _work: Label
var _bar: ProgressBar
var _roof: Sprite2D
var _wall: Sprite2D


func _ready() -> void:
	if not iso_art.is_empty():
		IsoAtlas.attach(self, iso_art)
		_roof = Sprite2D.new()
		_wall = Sprite2D.new()
		_roof.visible = false
		_wall.visible = false
		add_child(_roof)
		add_child(_wall)
		_work = _label("", Vector2(-72, 10), 16, 144)
		_bar = ProgressBar.new()
		_bar.position = Vector2(-48, 32)
		_bar.size = Vector2(96, 7)
		_bar.show_percentage = false
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = Color("86ccb7")
		_bar.add_theme_stylebox_override("fill", fill)
		var background: StyleBoxFlat = StyleBoxFlat.new()
		background.bg_color = Color("25454d")
		_bar.add_theme_stylebox_override("background", background)
		add_child(_bar)
		update_work(-1, 0.0, false)
		return
	var factor: float = front_width / reference_width
	_roof = _part(Rect2(0,0,native_size.x,roof_cut) if world_asset else Rect2(0,0,512,320),(-render_anchor if world_asset else Vector2(-256,-416))*factor,factor)
	_wall = _part(Rect2(0,roof_cut,native_size.x,native_size.y-roof_cut) if world_asset else Rect2(0,320,512,128),(Vector2(0,roof_cut)-render_anchor if calibrated else Vector2(-256,-96))*factor,factor)
	_roof.self_modulate = roof_tint
	_wall.self_modulate = facade_tint
	if not street_sign.is_empty():
		var sign_label: Label = _label(street_sign,(sign_rect.position-render_anchor)*factor,12,sign_rect.size.x*factor)
		sign_label.add_theme_color_override("font_color",Color("e2d7b9"))
		sign_label.add_theme_constant_override("outline_size",1)
	if not world_asset and not is_market and not is_residence:
		var props: ShopFurniture = ShopFurniture.new()
		props.scale = Vector2.ONE * front_width / 368.0
		add_child(props)
	if calibrated: _alpha=facade.get_image()
	if searchable and not calibrated:
		var sign: Polygon2D = Polygon2D.new()
		sign.polygon = PackedVector2Array([Vector2(-front_width * 0.44, -80), Vector2(30, -80), Vector2(30, -44), Vector2(-front_width * 0.44, -44)])
		sign.color = Color("74542f") if is_market else Color("244852")
		add_child(sign)
		_label(title, Vector2(-front_width * 0.44, -77), 18, front_width * 0.44 + 30)
	_work = _label("", Vector2(-front_width / 2, 22), 18, front_width)
	if calibrated:
		_work.position=Vector2(door_offset-104,10);_work.size.x=208
		_work.add_theme_font_size_override("font_size",14)
	_work.add_theme_constant_override("outline_size", 5)
	_bar = ProgressBar.new()
	_bar.position = Vector2(-front_width / 2 + 8, 52)
	_bar.size = Vector2(front_width * 0.55, 8)
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color("86ccb7")
	_bar.add_theme_stylebox_override("fill", fill)
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color("25454d")
	_bar.add_theme_stylebox_override("background", background)
	add_child(_bar)
	_roof.visible = false
	_wall.visible = false
	for child: Node in get_children():
		if child is ShopFurniture or child is Polygon2D:
			child.visible = false
	_work.position = Vector2(-72, 10)
	_work.size = Vector2(144, 22)
	_bar.position = Vector2(-48, 32)
	_bar.size = Vector2(96, 7)
	update_work(-1, 0.0, false)


func _part(region: Rect2, point: Vector2, factor: float) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = facade
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.position = point
	sprite.scale = Vector2.ONE * factor
	add_child(sprite)
	return sprite


func _draw() -> void:
	if not iso_art.is_empty():
		if primary_target and loot_category.is_empty():
			IsoDraw.marker(self, Vector2(door_offset, 0), Color("a8ebd4") if searched else IsoDraw.AMBER)
		return
	var depth: float = maxf(body_depth, 64.0)
	var height: float = 96.0 if is_market else (72.0 if is_residence else 88.0)
	var roof: Color = IsoDraw.SHOP_ROOF if is_market else (IsoDraw.ROOF if is_residence else IsoDraw.WARE_ROOF)
	var left: Color = IsoDraw.SHOP_LEFT if is_market else (IsoDraw.WALL_LEFT if is_residence else IsoDraw.WARE_LEFT)
	var right: Color = IsoDraw.SHOP_RIGHT if is_market else (IsoDraw.WALL_RIGHT if is_residence else IsoDraw.WARE_RIGHT)
	if world_asset and not is_market and not is_residence:
		if "仓" in title or "厂" in title or "库" in title:
			roof = IsoDraw.WARE_ROOF
			left = IsoDraw.WARE_LEFT
			right = IsoDraw.WARE_RIGHT
			height = 100.0
		elif "店" in title or "超" in title or "市" in title:
			roof = IsoDraw.SHOP_ROOF
			left = IsoDraw.SHOP_LEFT
			right = IsoDraw.SHOP_RIGHT
			height = 96.0
		else:
			height = clampf(56.0 + front_width * 0.08, 64.0, 120.0)
	var roof_alpha: float = 1.0
	IsoDraw.box(self, Vector2(front_width, depth), height, roof, left, right, roof_alpha)
	if is_market or "店" in title or "超" in title:
		IsoDraw.shop_stripe(self, Vector2(front_width, depth), height, Color("c45c4a"))
	if primary_target and loot_category.is_empty():
		IsoDraw.marker(self, Vector2(door_offset, 0), Color("a8ebd4") if searched else IsoDraw.AMBER)


func obscures(world_point: Vector2) -> bool:
	# Gameplay still tests this in map space. Closed-roof presentation does not fade.
	var foot: Vector2 = _map_foot()
	if calibrated:
		if world_point.y >= foot.y - 16:
			return false
		for height: float in [0.0, 32.0, 64.0]:
			var pixel: Vector2 = (world_point - foot - Vector2(0, height)) / (front_width / reference_width) + render_anchor
			if fixed_roof:
				if Rect2(Vector2.ZERO, Vector2(native_size.x, roof_cut)).has_point(pixel):
					return true
				continue
			if pixel.x >= 0 and pixel.x < native_size.x and pixel.y >= 0 and pixel.y < roof_cut and _alpha != null and _alpha.get_pixel(int(pixel.x), int(pixel.y)).a > 0.15:
				return true
		return false
	var factor: float = front_width / 448.0
	return Rect2(foot + Vector2(-front_width / 2, (-576 if world_asset else -384) * factor), Vector2(front_width, (480 if world_asset else 288) * factor)).has_point(world_point)


func show_behind_roof(friend_behind: bool) -> void:
	_roof.modulate.a = 0.40 if friend_behind else 1.0


func _map_foot() -> Vector2:
	return IsoSpace.map_of(self)


func scaled_hit_bounds() -> Rect2:
	var foot: Vector2 = _map_foot()
	var depth: float = maxf(body_depth, 80.0)
	var body: Rect2 = Rect2(Vector2(foot.x - front_width * 0.5, foot.y - depth), Vector2(front_width, depth + 40.0))
	return body.merge(Rect2(foot + Vector2(door_offset - 28, 0), Vector2(56, 64)))


func scaled_hit_contains(point: Vector2) -> bool:
	return scaled_hit_bounds().has_point(point)


func update_work(actor_id: int, fraction: float, inside: bool, call_sign: String = "", work_text: String = "") -> void:
	if _work != null:
		_work.visible = searchable
		_work.text = "已搜集" if searched else reward_hint + " · 左键"
		if calibrated: _work.text=("主目标 · " if primary_target else "")+("已搜集" if searched else title+" · "+reward_hint)
		if actor_id >= 0:
			_work.text = "%s · %s · 再点取消" % [call_sign if not call_sign.is_empty() else "队员%d" % (actor_id + 1), "搜集中" if inside else "前往中"]
		if not work_text.is_empty():
			_work.text = work_text
		_work.add_theme_color_override("font_color", Color("a8ebd4") if searched else Color("ffe0a4"))
	if _bar != null:
		_bar.visible = searchable and not searched and fraction > 0.0
		_bar.value = fraction * 100.0


func configure_loot_badge(category: String, anchor: Vector2) -> void:
	loot_category = category
	_loot_anchor = anchor
	_work.theme = LootTheme
	_work.clip_text = false
	_work.add_theme_font_size_override("font_size", 15)
	_work.add_theme_constant_override("outline_size", 0)
	var panel: StyleBoxFlat = LootTheme.get_stylebox("panel", "PanelContainer").duplicate() as StyleBoxFlat
	panel.content_margin_left = 6.0
	panel.content_margin_right = 6.0
	panel.content_margin_top = 2.0
	panel.content_margin_bottom = 2.0
	_work.add_theme_stylebox_override("normal", panel)
	_work.tooltip_text = title + "\n" + reward_hint
	_bar.position = anchor + Vector2(-36, 3)
	_bar.size = Vector2(72, 5)
	present_loot(0, "", "", 0.0)
	queue_redraw()


func present_loot(member_id: int, call_sign: String, phase: String, fraction: float) -> void:
	var text: String = SearchWorkView.loot_badge_text(loot_category, primary_target, searched, reward_hint, member_id, call_sign, phase, loot_landmark)
	if text != _work.text:
		_work.text = text
		_work.reset_size()
		_work.position = _loot_anchor - Vector2(_work.size.x * 0.5, _work.size.y)
		_work.add_theme_color_override("font_color", C1ExpeditionHud.TONES["info"] if searched else
			C1ExpeditionHud.TONES["warning"] if primary_target else C1ExpeditionHud.TONES["normal"])
	_work.visible = searchable
	_bar.visible = searchable and not searched and fraction > 0.0
	_bar.value = fraction * 100.0


func _label(value: String, point: Vector2, size: int, width: float) -> Label:
	var label: Label = Label.new()
	label.theme = ui_theme
	label.text = value
	label.position = point
	label.size = Vector2(width, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("edf0db"))
	label.add_theme_color_override("font_outline_color", Color("18333c"))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
