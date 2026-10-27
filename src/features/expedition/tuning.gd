class_name ExpeditionTuning
extends Resource
## Prototype values, not measured Deadly Days constants (TMP-101).

@export var survivor_speed: float = 125.0
@export var squad_spacing: float = 48.0
@export var enemy_speed: float = 34.0
@export var survivor_health: float = 200.0
@export var enemy_health: float = 54.0
@export var enemy_damage: float = 4.0
@export var enemy_interval: float = 1.1
@export var search_seconds: float = 30.0
# TMP-105: arbitrary demo payout, independent of the observed whole-sortie income.
@export var search_reward: int = 4
@export var bus_ready_seconds: float = 20.0
@export var engine_seconds: float = 3.0
@export var boarding_radius: float = 88.0
@export var daylight_seconds: float = 105.0
@export var spawn_seconds: float = 7.0
@export var camera_pan_speed: float = 480.0
@export var camera_min_zoom: float = 0.70
@export var camera_max_zoom: float = 1.25
@export var camera_zoom_step: float = 1.10
