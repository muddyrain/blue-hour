class_name WorldgenGround
extends Node2D
## Flat materials read the frozen roads/parcels; no independent collision geometry.
var layout: StreetLayout

func _draw() -> void:
	draw_rect(layout.world_bounds,Color("586b60"))
	draw_texture_rect(StreetBlock.GrassTexture,layout.world_bounds,true,Color(0.77,0.88,0.76,0.42))
	for parcel: Dictionary in layout.world_data.parcels:
		var area: Rect2=WorldLayout.rect(parcel.rect)
		draw_rect(area,Color("56664e"))
		draw_texture_rect(StreetBlock.GrassTexture,area,true,Color(0.7,0.84,0.66,0.5))
		for court: Dictionary in parcel.courtyards:
			_court(court)
		# Authored orthogonal shared paths join frontages and courts; no nav debug lines.
		for walk: Array in parcel.walks:
			var paving: Rect2=WorldLayout.rect(walk).intersection(area)
			draw_rect(paving.grow(3).intersection(area),Color("676e62"))
			draw_rect(paving,Color("909384"))
			draw_texture_rect(StreetBlock.PavingTexture,paving,true,Color(0.83,0.89,0.81,0.65))
	# One continuous verge on each street, cut by all actual connections.
	for road: Rect2 in layout.roads:
		var paving: Rect2=road.grow(28).intersection(layout.world_bounds)
		draw_rect(paving,Color("93998a"))
		draw_texture_rect(StreetBlock.PavingTexture,paving,true,Color(0.88,0.91,0.86,0.52))
	for entity: Dictionary in layout.world_data.entities:
		var block: Rect2=WorldLayout.rect(entity.rect)
		var door: Vector2=WorldLayout.point(entity.door)
		var apron: Rect2=Rect2(block.position.x-8,block.end.y-3,block.size.x+16,64)
		draw_rect(apron,Color("969b8c"))
		draw_texture_rect(StreetBlock.PavingTexture,apron,true,Color(0.9,0.94,0.87,0.56))
		draw_rect(Rect2(block.position.x-5,block.end.y-5,block.size.x+10,10),Color("434e48"))
		draw_rect(Rect2(door-Vector2(29,48),Vector2(58,8)),Color("c1bdac"))
		draw_rect(Rect2(door-Vector2(32,40),Vector2(64,7)),Color("7a8177"))
	for road: Rect2 in layout.roads:
		draw_rect(road,Color("34434b"))
		draw_texture_rect(StreetBlock.AsphaltTexture,road,true,Color(0.73,0.8,0.82,0.45))
	for road: Rect2 in layout.roads:
		var horizontal: bool=road.size.x>road.size.y
		var length: int=int(road.size.x if horizontal else road.size.y)
		for step: int in range(12,length-12,32):
			for side: int in [-1,1]:
				var p: Vector2=road.position+(Vector2(step,-3 if side<0 else road.size.y+1) if horizontal else Vector2(-3 if side<0 else road.size.x+1,step))
				if _junction(p,road): continue
				draw_line(p,p+(Vector2(26,0) if horizontal else Vector2(0,26)),Color("b6b6a4"),3)
				if step%160==12: draw_rect(Rect2(p+Vector2(1,5),Vector2(18,4)),Color("28363a"))
		for step: int in range(32,length-32,88):
			var p: Vector2=Vector2(road.position.x+step,road.get_center().y) if horizontal else Vector2(road.get_center().x,road.position.y+step)
			if not _junction(p,road): draw_line(p,p+(Vector2(32,0) if horizontal else Vector2(0,32)),Color("c3b27d"),2)
	# Crossings mark the actual perpendicular road connections, never a collision.
	for a: Rect2 in layout.roads:
		if a.size.x<=a.size.y: continue
		for b: Rect2 in layout.roads:
			if b.size.x>=b.size.y or not a.intersects(b): continue
			for stripe: int in range(8,int(b.size.x)-8,17):
				var y: float=a.position.y-25 if b.position.y<a.position.y else a.end.y+8
				draw_rect(Rect2(b.position.x+stripe,y,9,18),Color("b9bca9"))

func _court(court: Dictionary) -> void:
	var area: Rect2=WorldLayout.rect(court.rect)
	var garden: bool=court.kind=="garden"
	var parking: bool=court.kind=="parking"
	var loading: bool=court.kind=="loading"
	draw_rect(area.grow(3),Color("46574d") if garden else Color("535f5f"))
	draw_rect(area,Color("506b49") if garden else Color("5b6869") if parking or loading else Color("858c7c"))
	draw_texture_rect(StreetBlock.GrassTexture if garden else StreetBlock.ConcreteTexture if parking or loading else StreetBlock.PavingTexture,area,true,Color(0.82,0.87,0.78,0.55))
	if garden:
		# Low planting and soil remain traversable; raised hedges have frozen collisions.
		var bed: Rect2=Rect2(area.position+Vector2(8,8),Vector2(maxf(8,area.size.x-16),minf(38,area.size.y*0.22)))
		draw_rect(bed,Color("4c5440"))
		for x: int in range(int(bed.position.x)+8,int(bed.end.x)-4,19):
			draw_circle(Vector2(x,bed.get_center().y),5,Color("79945b"))
			if x%3==0:draw_circle(Vector2(x-2,bed.get_center().y-2),1.8,Color("cec277"))
	elif parking or loading:
		for x: int in range(int(area.position.x)+20,int(area.end.x)-132,164):
			var y: float=area.position.y+8
			var depth: float=minf(86,area.size.y-16)
			draw_line(Vector2(x,y),Vector2(x,y+depth),Color("c2c1a5"),2)
			draw_line(Vector2(x,y+depth),Vector2(x+132,y+depth),Color("c2c1a5"),2)
		if loading:
			for x: int in range(int(area.position.x)+12,int(area.end.x)-16,24):
				draw_line(Vector2(x,area.end.y-8),Vector2(x+12,area.end.y-20),Color("b8a877"),3)

func _junction(point: Vector2,current: Rect2) -> bool:
	for other: Rect2 in layout.roads:
		if other!=current and other.grow(5).has_point(point): return true
	return false
