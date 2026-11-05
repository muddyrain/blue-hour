class_name BossDefinition
extends RefCounted
## PROJECT_TEMP V1. Separate policy so historical ordinary enemies keep their values.

const KIND: String = "breacher_v1"
const DISPLAY_NAME: String = "破阵者"
const POLICY: Dictionary = {"id":"BH_BREACHER_V1","health":960.0,"speed":26.0,
	"melee_range":28.0,"melee_damage":24.0,"melee_windup":0.9,"melee_cooldown":2.2,
	"slam_range":340.0,"slam_radius":60.0,"slam_damage":32.0,"slam_windup":1.2,
	"slam_cooldown":4.0,"thresholds":[60,30],"summon_count":2}
