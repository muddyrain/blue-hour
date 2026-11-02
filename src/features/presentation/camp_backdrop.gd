class_name CampBackdrop
extends Control

const ART: Texture2D = preload("res://assets/m403/camp_blue_hour.png")

var visible_member_ids: Array[int] = []
var _roster: Control
var _portraits: Array[TextureRect] = []
var _names: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture: TextureRect = TextureRect.new()
	picture.texture = ART
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0.025,0.065,0.09,0.97))
	gradient.set_color(1, Color(0.025,0.065,0.09,0.0))
	gradient.add_point(0.35, Color(0.025,0.065,0.09,0.80))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0,0)
	texture.fill_to = Vector2(0.75,0)
	var shade: TextureRect = TextureRect.new()
	shade.texture = texture
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_roster = Control.new()
	_roster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roster)
	var neutral: ColorRect = ColorRect.new()
	neutral.color = CampStyle.INK
	neutral.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	neutral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster.add_child(neutral)
	# ART contains baked people; only its skyline is reused for a stateful camp.
	var skyline: TextureRect = TextureRect.new()
	var crop: AtlasTexture = AtlasTexture.new()
	crop.atlas = ART
	crop.region = Rect2(0, 0, 1280, 220)
	skyline.texture = crop
	skyline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skyline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CampStyle.place(skyline, Rect2(0, 0, 1280, 220))
	_roster.add_child(skyline)
	var veil: ColorRect = ColorRect.new()
	veil.color = Color(0.02, 0.05, 0.08, 0.55)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CampStyle.place(veil, Rect2(0, 0, 1280, 220))
	_roster.add_child(veil)
	for member_id: int in [1, 2, 3]:
		var portrait: TextureRect = TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		CampStyle.place(portrait, Rect2(848 + (member_id - 1) * 126, 212, 120, 120))
		_roster.add_child(portrait)
		_portraits.append(portrait)
	_names = CampStyle.label("", 16)
	_names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CampStyle.place(_names, Rect2(848, 338, 390, 100))
	_roster.add_child(_names)
	_roster.hide()


func show_roster(enabled: bool, members: Array, active_ids: Array) -> void:
	_roster.visible = enabled
	visible_member_ids.clear()
	if not enabled:
		return
	_names.text = "在营 %d 人 · 同行者\n" % active_ids.size()
	if members.is_empty():
		_names.text = "名册尚未载入"
	elif active_ids.is_empty():
		_names.text = "已无在营成员 · 阵亡档案保留"
	for member_id: int in [1, 2, 3]:
		var portrait: TextureRect = _portraits[member_id - 1]
		portrait.hide()
		var member: Dictionary = SurvivorRoster.member(members, member_id)
		if member.is_empty():
			continue
		if member_id in active_ids:
			portrait.texture = SurvivorRoster.definition_for(member).portrait
			portrait.show()
			visible_member_ids.append(member_id)
			_names.text += "%02d %s · 存活\n" % [member_id, member.call_sign]
