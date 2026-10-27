class_name LosPracticeSetup
extends RefCounted
## Initialization-only practice arrangement on actual map geometry; no stat overrides.

var starts: Array[Vector2] = []
var blocked_spawn: Vector2
var visible_spawn: Vector2
var clear_goal: Vector2
var camera_center: Vector2


static func for_layout(layout: StreetLayout, range_case: bool) -> LosPracticeSetup:
	var setup: LosPracticeSetup = LosPracticeSetup.new()
	if range_case:
		setup.starts.assign(layout.arrivals)
		setup.blocked_spawn = setup.starts[0] + Vector2.RIGHT * 350
		setup.visible_spawn = setup.blocked_spawn
		setup.clear_goal = setup.starts[0] + Vector2(160,48)
		setup.camera_center = setup.starts[0] + Vector2(160,-96)
		return setup
	var market: bool = layout.id == &"market_loop"
	var corner: Vector2 = layout.cash_block.end if market else Vector2(layout.cash_block.position.x,layout.cash_block.end.y)
	var side: float = 1.0 if market else -1.0
	setup.starts.assign([corner + Vector2(side * 32,-128),corner + Vector2(side * 32,-80)])
	setup.blocked_spawn = corner + Vector2(-side * 48,32)
	setup.visible_spawn = corner + Vector2(side * 192,-16)
	setup.clear_goal = corner + Vector2(side * 64,104)
	setup.camera_center = corner + Vector2(side * 80,-80)
	return setup
