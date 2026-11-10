class_name WorldgenDressing
extends RefCounted
## Solid scenery is frozen before interactive props and the final navigation certificate.
## It never supplies loot or a search identity. Rendering cannot invent blockers.

static func freeze(data: Dictionary) -> void:
	var occupied: Array[Rect2]=[]
	for entity: Dictionary in data.entities: occupied.append(WorldLayout.rect(entity.rect).grow(22))
	for wall: Array in data.barriers: occupied.append(WorldLayout.rect(wall).grow(20))
	var reserved: Array[Rect2]=ExplorationLayout._reserved(data)
	var edge_placed: bool=false
	for parcel: Dictionary in data.parcels:
		parcel.dressing=[]
	var ordered: Array=data.parcels.duplicate()
	var bus_point: Vector2=WorldLayout.point(data.bus.door)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return WorldLayout.point(a.entrance).distance_squared_to(bus_point)<WorldLayout.point(b.entrance).distance_squared_to(bus_point))
	for parcel: Dictionary in ordered:
		if data.get("art_revision")==3 and not edge_placed:
			edge_placed=_courtyard_edge(data,parcel,occupied,reserved)
		var count: int=0
		for court: Dictionary in parcel.courtyards:
			if count>=4:break
			var area: Rect2=WorldLayout.rect(court.rect)
			var kind: String="scrap" if court.kind=="parking" else "cargo" if court.kind=="loading" else "hedge"
			var width: float=132 if kind=="scrap" else 112 if kind=="cargo" else 144
			if area.size.x<width+24 or area.size.y<84:continue
			# Place at a court boundary, leaving its entrance and orthogonal footways clear.
			var candidates: Array[Vector2] = [Vector2(area.position.x+width/2+12,area.position.y+52),Vector2(area.end.x-width/2-12,area.end.y-14),Vector2(area.get_center().x,area.position.y+52)]
			if data.has("warehouse_district") and kind == "cargo":
				candidates.append(Vector2(area.position.x + width * 0.5 + 72.0, area.get_center().y + 14.0))
			for point: Vector2 in candidates:
				var block: Rect2=Rect2(point-Vector2(width*0.44,24),Vector2(width*0.88,24))
				var route_clear: bool = not (OpenStreetsV1.intersects_sweep(data.bus, block, 24) if data.has("open_streets")
					else WorldLayout.rect(data.bus.sweep).grow(24).intersects(block))
				var clear: bool = area.encloses(block) and route_clear
				for other: Rect2 in occupied+reserved:clear=clear and not block.grow(20).intersects(other)
				for road: Array in data.roads:clear=clear and not block.grow(24).intersects(WorldLayout.rect(road))
				for walk: Array in parcel.walks:clear=clear and not block.grow(12).intersects(WorldLayout.rect(walk))
				if not clear:continue
				parcel.dressing.append({"kind":kind,"point":[point.x,point.y],"width":width,"collision":[block.position.x,block.position.y,block.size.x,block.size.y]})
				occupied.append(block.grow(20));count+=1
				break

static func _courtyard_edge(data: Dictionary, parcel: Dictionary, occupied: Array[Rect2], reserved: Array[Rect2]) -> bool:
	for court: Dictionary in parcel.courtyards:
		if court.kind not in ["garden","court"]:
			continue
		var area: Rect2=WorldLayout.rect(court.rect)
		var width: float=180.0
		if area.size.x<width+64 or area.size.y<136:
			continue
		var point: Vector2=Vector2(area.position.x+48,area.end.y-12)
		var collisions: Array=StreetModuleArt.courtyard_collisions(point,width)
		var clear: bool=true
		for value: Array in collisions:
			var block: Rect2=WorldLayout.rect(value)
			clear=clear and area.encloses(block)
			for other: Rect2 in occupied+reserved:
				clear=clear and not block.grow(22).intersects(other)
			for walk: Array in parcel.walks:
				clear=clear and not block.grow(16).intersects(WorldLayout.rect(walk))
			clear=clear and not block.grow(48).has_point(WorldLayout.point(court.entrance))
		if not clear:
			continue
		parcel.dressing.append({"kind":"courtyard_edge","point":[point.x,point.y],"width":width,"collisions":collisions})
		for value: Array in collisions:
			occupied.append(WorldLayout.rect(value).grow(22))
		return true
	return false
