class_name CrewAppearance
extends RefCounted
## Stable ID maps original parts only; edited call signs never choose an appearance.
## AMBER constants retain the historical rig API; ID2 is now Xia Zhiyao, not a saved-name lookup.

const AMBER_LEGS: Texture2D = preload("res://assets/m403/xia_lower.png")
const AMBER_UPPER: Texture2D = preload("res://assets/m403/xia_upper.png")
const AMBER_FULL: Texture2D = preload("res://assets/m403/xia_full.png")
const AMBER_HANDS: Array[Vector2] = [Vector2(150, 127), Vector2(169, 111), Vector2(135, 138)]

const LIN_LEGS: Texture2D = preload("res://assets/m5_rescue/lin_lower.png")
const LIN_UPPER: Texture2D = preload("res://assets/m5_rescue/lin_upper.png")
const LIN_FULL: Texture2D = preload("res://assets/m5_rescue/lin_full.png")
const LIN_HANDS: Array[Vector2] = [Vector2(145,138), Vector2(160,120), Vector2(128,138)]

const SHEN_LEGS: Texture2D = preload("res://assets/m5_rescue_pool/shen_lower.png")
const SHEN_UPPER: Texture2D = preload("res://assets/m5_rescue_pool/shen_upper.png")
const SHEN_FULL: Texture2D = preload("res://assets/m5_rescue_pool/shen_full.png")
const LU_LEGS: Texture2D = preload("res://assets/m5_rescue_pool/lu_lower.png")
const LU_UPPER: Texture2D = preload("res://assets/m5_rescue_pool/lu_upper.png")
const LU_FULL: Texture2D = preload("res://assets/m5_rescue_pool/lu_full.png")
const POOL_HANDS: Array[Vector2] = [Vector2(151,140),Vector2(166,124),Vector2(128,144)]
