class_name FieldProp
extends Node2D
## Front edge is the sort anchor. Only the roof fades for a friend behind it.

const ShopTexture: Texture2D = preload("res://assets/candidates/shop_02.png")
var primary_target: bool = false
var calibrated: bool = false
var roof_cut: int = 512
var body_depth: float = 112
var door_offset: float = 0
var _alpha: Image
var world_asset: bool = false
var facade: Texture2D = ShopTexture
var is_market: bool = false
var is_residence: bool = false
var front_width: float = 368.0
var searched: bool = false
var searchable: bool = true
var title: String = "旧街补给店"
var reward_hint: String = "货币 +4"
var ui_theme: Theme
var _work: Label
var _bar: ProgressBar
var _roof: Sprite2D
var _wall: Sprite2D


func _ready() -> void:
	var factor: float = front_width / 448.0
	_roof = _part(Rect2(0,0,512,roof_cut) if world_asset else Rect2(0,0,512,320),Vector2(-256,-608 if world_asset else -416)*factor,factor)
	_wall = _part(Rect2(0,roof_cut,512,640-roof_cut) if world_asset else Rect2(0,320,512,128),Vector2(-256,roof_cut-608 if calibrated else -96)*factor,factor)
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
	if primary_target:
		draw_arc(Vector2(door_offset,20),18,0,TAU,24,Color("a8ebd4") if searched else Color("ffd385"),3,true)
		draw_colored_polygon(PackedVector2Array([Vector2(door_offset,-9),Vector2(door_offset-6,-19),Vector2(door_offset+6,-19)]),Color("ffd385"))
	if calibrated:
		var shadow: PackedVector2Array=PackedVector2Array([Vector2(-front_width/2,-body_depth),Vector2(front_width/2,-body_depth),Vector2(front_width/2+26,8),Vector2(-front_width/2+16,10)])
		draw_colored_polygon(shadow,Color(0.08,0.14,0.17,0.23))
		draw_rect(Rect2(-front_width/2,-5,front_width,9),Color(0.06,0.12,0.15,0.35))
		return
	# Soft narrow contact shadows replace the old rectangular footprint carpet.
	draw_set_transform(Vector2(front_width * 0.04, 0), 0, Vector2(1, 0.10))
	for layer: int in range(3):
		draw_circle(Vector2.ZERO, front_width * (0.44 + layer * 0.018), Color(0.08, 0.15, 0.17, 0.055))
	draw_set_transform(Vector2.ZERO)


func obscures(world_point: Vector2) -> bool:
	if calibrated:
		if world_point.y>=global_position.y-16: return false
		# A roof can cover legs while the head is already above its silhouette.
		for height: float in [0.0,32.0,64.0]:
			var pixel: Vector2=(world_point-global_position-Vector2(0,height))/(front_width/448.0)+Vector2(256,608)
			if pixel.x>=0 and pixel.x<512 and pixel.y>=0 and pixel.y<roof_cut and _alpha!=null and _alpha.get_pixel(int(pixel.x),int(pixel.y)).a>0.15:return true
		return false
	var factor: float = front_width / 448.0
	return Rect2(global_position + Vector2(-front_width / 2, (-576 if world_asset else -384) * factor), Vector2(front_width, (480 if world_asset else 288) * factor)).has_point(world_point)


func show_behind_roof(friend_behind: bool) -> void:
	_roof.modulate.a = 0.40 if friend_behind else 1.0


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
