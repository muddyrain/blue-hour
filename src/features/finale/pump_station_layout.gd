class_name PumpStationLayout
extends RefCounted
## Authored 2.5D footprint. All visible route guidance reads this same frozen map.

const POLICY: String = "BH_PUMP_STATION_V1"


static func freeze() -> Dictionary:
	var station: Dictionary = {
		"version": 1,
		"camera": [960, 520],
		"yard": [320, 192, 1230, 524],
		"channel": [0, 52, 1920, 122],
		"arena": [700, 384, 650, 236],
		"power_house": [530, 222, 730, 150],
		"cabinet_base": [1142, 384, 56, 24],
		"console": [1170, 436],
		"boss": [960, 452],
		"front_gate": [1236, 704],
		"side_gate": [470, 704],
		"front_path": [[1236, 742], [1236, 704], [1236, 502], [1170, 436]],
		"side_path": [[470, 742], [470, 704], [470, 424], [705, 424], [1170, 436]],
		"front_gap": 248,
		"side_gap": 112,
	}
	var value: Dictionary = {
		"version": 5,
		"seed": POLICY,
		"size": "small",
		"topology": "industrial",
		"attempt": 0,
		"fallback": false,
		"bounds": [0, 0, 1920, 1056],
		"entities": [
			{"id": "pump_house", "rect": station.power_house, "door": [784, 400]},
			{"id": "pump_cabinet", "rect": station.cabinet_base, "door": station.console},
		],
		"roads": [[0, 768, 1920, 180]],
		"barriers": [
			[320, 192, 1230, 24], [320, 216, 24, 500], [1526, 216, 24, 500],
			[344, 692, 70, 24], [526, 692, 586, 24], [1360, 692, 166, 24],
			# Anchor the vertical arm to the frontage so the service lane cannot cut
			# across its lower tip. The walkable turn is beside the pump house.
			[638, 472, 26, 220], [664, 628, 336, 26],
		],
		"gates": [station.side_gate, station.front_gate],
		"bus": {
			"rect": [850, 804, 240, 80], "door": [1016, 776], "passenger_door": [1016, 868],
			"entry": [-160, 884], "exit": [2080, 884], "sweep": [0, 784, 1920, 120],
			"facing": "right",
		},
		"arrivals": [[968, 776], [1016, 776], [1064, 776], [1112, 776]],
		"enemy_points": [[64, 790], [176, 790], [1744, 790], [1856, 790]],
		"rescue": [784, 400],
		# Water is a walking obstacle. Like existing ground props it is not a shot wall.
		"objects": [{"id": "pump_channel", "collision": station.channel}],
		"parcels": [], "graph": {}, "art_revision": 3,
		"pump_station": station,
	}
	value.id = WorldgenLayout.PREFIX + RecordEncoding.fingerprint(value).substr(0, 32)
	return value


static func problem(value: Variant) -> String:
	if not value is Dictionary:
		return "PUMP_LAYOUT_FIELDS"
	return "" if RecordEncoding.fingerprint(value) == RecordEncoding.fingerprint(freeze()) else "PUMP_LAYOUT_CANONICAL"


static func resource(value: Dictionary) -> StreetLayout:
	if not problem(value).is_empty():
		return null
	var layout: StreetLayout = NeighborhoodLayout.resource(value)
	layout.display_name = "河堤泵站"
	layout.camera_start = WorldLayout.point(value.pump_station.camera)
	layout.route_hint = "右侧装卸道较短，左侧检修道有墙体遮挡。到达控制柜后派工停机。"
	return layout
