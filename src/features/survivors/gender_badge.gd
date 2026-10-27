class_name GenderBadge
extends HBoxContainer
## Original vector symbols avoid platform-font tofu; text does not encode gender by colour.

const MALE_ICON: Texture2D = preload("res://assets/m403/gender_male.svg")
const FEMALE_ICON: Texture2D = preload("res://assets/m403/gender_female.svg")

var definition: SurvivorDefinition
var prefix: String = ""
var _icon: TextureRect
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 5)
	if not prefix.is_empty():
		var lead: Label = Label.new()
		lead.text = prefix
		lead.add_theme_font_size_override("font_size", 18)
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lead)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(22, 26)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	set_definition(definition)


func set_definition(value: SurvivorDefinition) -> void:
	definition = value
	if _icon == null or definition == null:
		return
	_icon.texture = MALE_ICON if definition.gender == &"male" else FEMALE_ICON
	_label.text = "男" if definition.gender == &"male" else "女"
	tooltip_text = prefix + definition.gender_text()
