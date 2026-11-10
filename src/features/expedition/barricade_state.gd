class_name BarricadeState
extends RefCounted
## The existing accepted airstrike history is the only source of open passage.


static func opened(action: Dictionary, accepted: Array, layout: StreetLayout) -> bool:
	if not action.has("barricade"):
		return false
	for event: Dictionary in accepted:
		if event.kind == "airstrike" and hits(action, event.payload, layout):
			return true
	return false


static func hits(action: Dictionary, plan: Dictionary, layout: StreetLayout) -> bool:
	if plan.is_empty() or not action.has("barricade"):
		return false
	var point: Vector2 = WorldLayout.point(plan.point)
	var anchor: Vector2 = WorldLayout.point(action.barricade.anchor)
	return point.distance_to(anchor) <= float(plan.radius) and BuildAuthority.line_clear(layout, point, anchor)
