class_name CrewAppearance
extends RefCounted
## Stable ID maps original parts only; edited call signs never choose an appearance.
## AMBER constants retain the historical rig API; ID2 is now Xia Zhiyao, not a saved-name lookup.

const AMBER_LEGS: Texture2D = preload("res://assets/m403/xia_lower.png")
const AMBER_UPPER: Texture2D = preload("res://assets/m403/xia_upper.png")
const AMBER_FULL: Texture2D = preload("res://assets/m403/xia_full.png")
const AMBER_HANDS: Array[Vector2] = [Vector2(150, 127), Vector2(169, 111), Vector2(135, 138)]
