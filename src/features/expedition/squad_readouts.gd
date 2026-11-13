class_name SquadReadouts
extends Node2D
## Screen-space readouts stay readable at crossings without changing actor navigation.

var entries: Array[Dictionary] = []


func update_members(members: Array[FieldActor], world_to_screen: Transform2D, viewport_size: Vector2, blocked: Array[Rect2] = []) -> void:
	entries.clear()
	for actor: FieldActor in members:
		if not actor.visible or actor.activity == FieldActor.Activity.DOWN:
			continue
		var head: Vector2 = world_to_screen * (actor.position + actor.visual.position + Vector2(0, -72))
		# Leave the north-facing long barrel and the face clear, with stable team-side placement.
		var rect: Rect2 = Rect2(head + Vector2(-96 if actor.actor_id == 0 else 20, -25), Vector2(76, 27))
		var definition: SurvivorDefinition = SurvivorRoster.definition(actor.member_id)
		entries.append({"id": actor.actor_id, "member_id":actor.member_id, "health": actor.health, "max": actor.max_health,
			"head": head, "rect": rect, "alpha": 1.0, "colour": definition.colour if definition!=null else Color("80ddd8") if actor.actor_id==0 else Color("f2c37f")})
	if entries.size() == 2 and entries[0]["rect"].grow(8.0).intersects(entries[1]["rect"]):
		var centre: float = (entries[0]["head"].x + entries[1]["head"].x) * 0.5
		entries[0]["rect"].position.x = centre - 82.0
		entries[1]["rect"].position.x = centre + 6.0
	var north: float = 190.0 if entries.size() >= 3 else 80.0
	var south: float = viewport_size.y - (225.0 if entries.size() >= 3 else 105.0)
	for entry: Dictionary in entries:
		entry["rect"].position.x = clampf(entry["rect"].position.x, 4.0, viewport_size.x - 80.0)
		entry["rect"].position.y = clampf(entry["rect"].position.y, north, south)
	if entries.size() == 2 and entries[0]["rect"].intersects(entries[1]["rect"]):
		entries[1]["rect"].position.y = minf(entries[0]["rect"].end.y + 6.0, viewport_size.y - 105.0)
		if entries[0]["rect"].intersects(entries[1]["rect"]):
			entries[0]["rect"].position.y = entries[1]["rect"].position.y - 33.0
	if entries.size() >= 3:
		for index: int in range(1,entries.size()):
			var origin: Rect2 = entries[index].rect
			var placed: bool = false
			for shift: int in [0,-33,33,-66,66]:
				for side: int in [0,-82,82]:
					var candidate: Rect2 = Rect2(origin.position+Vector2(side,shift),origin.size)
					if candidate.position.x < 4 or candidate.end.x > viewport_size.x-4 or candidate.position.y < north or candidate.position.y > south:
						continue
					var overlaps: bool = false
					for previous: int in range(index):
						if candidate.grow(3).intersects(entries[previous].rect):
							overlaps = true
					if not overlaps:
						entries[index].rect = candidate
						placed = true
						break
				if placed:
					break
	_avoid_hud(blocked, viewport_size)
	queue_redraw()


func _avoid_hud(blocked: Array[Rect2], viewport_size: Vector2) -> void:
	if blocked.is_empty():
		return
	for index: int in range(entries.size()):
		if not _hits_blocked(entries[index].rect, blocked):
			continue
		var origin: Rect2 = entries[index].rect
		var placed: bool = false
		for up: int in [0, 36, 72, 108, 144, 180, 216]:
			for side: int in [0, 86, -86, 172, -172]:
				var candidate: Rect2 = Rect2(origin.position + Vector2(side, -up), origin.size)
				if candidate.position.x < 4.0 or candidate.end.x > viewport_size.x - 4.0:
					continue
				if candidate.position.y < 8.0 or candidate.end.y > viewport_size.y - 8.0:
					continue
				if _hits_blocked(candidate, blocked):
					continue
				var overlaps: bool = false
				for other: int in range(entries.size()):
					if other == index or float(entries[other].get("alpha", 1.0)) < 0.05:
						continue
					if candidate.grow(3.0).intersects(entries[other].rect):
						overlaps = true
						break
				if not overlaps:
					entries[index].rect = candidate
					placed = true
					break
			if placed:
				break
		if not placed:
			entries[index].alpha = 0.0


func _hits_blocked(rect: Rect2, blocked: Array[Rect2]) -> bool:
	for area: Rect2 in blocked:
		if rect.intersects(area):
			return true
	return false


func _draw() -> void:
	for entry: Dictionary in entries:
		var alpha: float = float(entry.get("alpha", 1.0))
		if alpha <= 0.001:
			continue
		var rect: Rect2 = entry["rect"]
		var colour: Color = entry["colour"]
		draw_line(rect.get_center() + Vector2(0, 13), entry["head"], Color(colour, 0.70 * alpha), 1.0, true)
		draw_rect(rect, Color(Color("102b36"), alpha))
		draw_rect(rect, Color(colour, alpha), false, 1.5)
		draw_rect(Rect2(rect.position, Vector2(22, 27)), Color(colour, alpha))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(7, 19), str(entry["member_id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Color("102b36"), alpha))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(28, 16), str(ceili(entry["health"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Color("f3f1dc"), alpha))
		draw_rect(Rect2(rect.position + Vector2(28, 21), Vector2(40, 3)), Color(Color("344d54"), alpha))
		draw_rect(Rect2(rect.position + Vector2(28, 21), Vector2(40 * entry["health"] / entry["max"], 3)), Color(colour, alpha))
