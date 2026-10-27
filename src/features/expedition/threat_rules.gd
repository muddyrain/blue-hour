class_name ThreatRules
extends Resource
## PROJECT_TEMP TMP-126..129. Calibration candidates, never Deadly Days constants.

const LATE_FRACTION: float = 2.0 / 3.0
const DEEP_FRACTION: float = 4.0 / 3.0
const INTERVAL_FACTORS: Array[float] = [1.0, 5.0 / 7.0, 0.5, 2.5 / 7.0]
const ENEMY_CAP: int = 24
const SCREEN_MARGIN: float = 32.0
const PARTY_DISTANCE: float = 280.0
const ENEMY_SEPARATION: float = 32.0
const EDGE_MARGIN: float = 32.0
const REHEARSAL_DAYLIGHT: float = 21.0

@export var late_fraction: float = LATE_FRACTION
@export var deep_fraction: float = DEEP_FRACTION
@export var interval_factors: Array[float] = INTERVAL_FACTORS.duplicate()
@export var enemy_cap: int = ENEMY_CAP
@export var screen_margin: float = SCREEN_MARGIN
@export var party_distance: float = PARTY_DISTANCE
@export var enemy_separation: float = ENEMY_SEPARATION

