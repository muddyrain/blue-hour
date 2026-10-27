class_name SquadReadouts
extends Node2D
## Screen-space readouts stay readable at crossings without changing actor navigation.

var entries: Array[Dictionary] = []


func update_members(members: Array[FieldActor], world_to_screen: Transform2D, viewport_size: Vector2) -> void:
	entries.clear()
	for actor: FieldActor in members:
		if not actor.visible or actor.activity == FieldActor.Activity.DOWN:
			continue
		var head: Vector2 = world_to_screen * (actor.position + actor.visual.position + Vector2(0, -72))
		# Leave the north-facing long barrel and the face clear, with stable team-side placement.
		var rect: Rect2 = Rect2(head + Vector2(-96 if actor.actor_id == 0 else 20, -25), Vector2(76, 27))
		entries.append({"id": actor.actor_id, "health": actor.health, "max": actor.max_health,
			"head": head, "rect": rect, "colour": ActorVisual.COLOURS[actor.actor_id % 2]})
	if entries.size() == 2 and entries[0]["rect"].grow(8.0).intersects(entries[1]["rect"]):
		var centre: float = (entries[0]["head"].x + entries[1]["head"].x) * 0.5
		entries[0]["rect"].position.x = centre - 82.0
		entries[1]["rect"].position.x = centre + 6.0
	for entry: Dictionary in entries:
		entry["rect"].position.x = clampf(entry["rect"].position.x, 4.0, viewport_size.x - 80.0)
		entry["rect"].position.y = clampf(entry["rect"].position.y, 80.0, viewport_size.y - 105.0)
	if entries.size() == 2 and entries[0]["rect"].intersects(entries[1]["rect"]):
		entries[1]["rect"].position.y = minf(entries[0]["rect"].end.y + 6.0, viewport_size.y - 105.0)
		if entries[0]["rect"].intersects(entries[1]["rect"]):
			entries[0]["rect"].position.y = entries[1]["rect"].position.y - 33.0
	queue_redraw()


func _draw() -> void:
	for entry: Dictionary in entries:
		var rect: Rect2 = entry["rect"]
		var colour: Color = entry["colour"]
		draw_line(rect.get_center() + Vector2(0, 13), entry["head"], Color(colour, 0.70), 1.0, true)
		draw_rect(rect, Color("102b36"))
		draw_rect(rect, colour, false, 1.5)
		draw_rect(Rect2(rect.position, Vector2(22, 27)), colour)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(7, 19), str(entry["id"] + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("102b36"))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(28, 16), str(ceili(entry["health"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f3f1dc"))
		draw_rect(Rect2(rect.position + Vector2(28, 21), Vector2(40, 3)), Color("344d54"))
		draw_rect(Rect2(rect.position + Vector2(28, 21), Vector2(40 * entry["health"] / entry["max"], 3)), colour)
