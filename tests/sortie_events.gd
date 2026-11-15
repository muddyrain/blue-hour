extends "res://tests/maps_events.gd"
## Separate process keeps the three certified offer boards within the public timeout.


func run() -> void:
	await _visible_events()
	print("BH_SORTIE_EVENTS " + JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures == 0 else 1)
