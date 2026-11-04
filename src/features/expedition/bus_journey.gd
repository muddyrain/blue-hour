class_name BusJourney
extends Node
## Presentation clock only. Frozen result is published by Main before departure begins.
signal departed()
const DRIVE_IN: float = 2.4
const DISEMBARK: float = 1.0
const EMBARK: float = 0.9
const DRIVE_OUT: float = 2.8
var stage: String = "arriving"
var clock: float = 0.0
var world: Expedition
var sprite: Sprite2D
var route: Dictionary
var stop: Vector2
var starts: Array[Vector2] = []
var boarding_starts: Array[Vector2] = []
var skip_button: Button

func configure(owner_world: Expedition, bus: Sprite2D, data: Dictionary) -> void:
	world=owner_world; sprite=bus; route=data.duplicate(true); stop=world.layout.bus_foot()
	for actor: FieldActor in world.survivors:
		starts.append(actor.position)
		actor.hide()
	sprite.position=WorldLayout.point(route.entry)

func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer=12; add_child(layer)
	skip_button=Button.new(); skip_button.position=Vector2(20,158); skip_button.size=Vector2(240,40)
	skip_button.text="巴士驶入 · 跳过演出"; skip_button.pressed.connect(skip)
	layer.add_child(skip_button)

func running() -> bool:
	return stage in ["arriving","disembarking","embarking","departing"]

func advance(delta: float) -> void:
	if not running(): return
	if world.rescue_target!=null: world.rescue_target.refresh()
	clock+=delta
	match stage:
		"arriving":
			sprite.position=WorldLayout.point(route.entry).lerp(stop,smoothstep(0,1,minf(clock/DRIVE_IN,1)))
			if clock>=DRIVE_IN: stage="disembarking"; clock=0; skip_button.text="队员下车 · 跳过演出"
		"disembarking":
			for i: int in range(world.survivors.size()):
				var actor: FieldActor = world.survivors[i]
				actor.show(); actor.position=WorldLayout.point(route.passenger_door).lerp(starts[i],minf(clock/DISEMBARK,1))
				actor.visual.advance(delta,Vector2.DOWN*40,Vector2.RIGHT)
			if clock>=DISEMBARK: skip()
		"embarking":
			for i: int in range(world.survivors.size()):
				var actor: FieldActor = world.survivors[i]
				if actor.health>0: actor.position=boarding_starts[i].lerp(WorldLayout.point(route.passenger_door),minf(clock/EMBARK,1))
			if clock>=EMBARK:
				for actor: FieldActor in world.survivors:
					if actor.health>0: actor.hide()
				stage="departing"; clock=0; skip_button.text="巴士驶离 · 跳过演出"
		"departing":
			sprite.position=stop.lerp(WorldLayout.point(route.exit),smoothstep(0,1,minf(clock/DRIVE_OUT,1)))
			if clock>=DRIVE_OUT: skip()

func skip() -> void:
	if stage in ["arriving","disembarking"]:
		sprite.position=stop
		for i: int in range(world.survivors.size()):
			world.survivors[i].position=starts[i]; world.survivors[i].show()
		stage="exploring"
	elif stage in ["embarking","departing"]:
		sprite.position=WorldLayout.point(route.exit)
		for actor: FieldActor in world.survivors:
			if actor.health>0: actor.hide()
		stage="done"
		departed.emit()
	if skip_button!=null: skip_button.hide()
	if world.rescue_target!=null: world.rescue_target.refresh()

func departure() -> void:
	if stage!="exploring" or world.phase!=Expedition.Phase.FINISHED: return
	for actor: FieldActor in world.survivors: boarding_starts.append(actor.position)
	stage="embarking"; clock=0; skip_button.text="队员登车 · 跳过演出"; skip_button.show()
