class_name CampBackdrop
extends Control

const ART: Texture2D = preload("res://assets/m403/camp_blue_hour.png")


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
