class_name WorldgenDressing
extends RefCounted
## Solid scenery is frozen before interactive props and the final navigation certificate.
## It never supplies loot or a search identity. Rendering cannot invent blockers.

static func freeze(data: Dictionary) -> void:
	var occupied: Array[Rect2]=[]
	for entity: Dictionary in data.entities: occupied.append(WorldLayout.rect(entity.rect).grow(22))
	for wall: Array in data.barriers: occupied.append(WorldLayout.rect(wall).grow(20))
	var reserved: Array[Rect2]=ExplorationLayout._reserved(data)
	for parcel: Dictionary in data.parcels:
		parcel.dressing=[]
		var count: int=0
		for court: Dictionary in parcel.courtyards:
			if count>=4:break
			var area: Rect2=WorldLayout.rect(court.rect)
			var kind: String="scrap" if court.kind=="parking" else "cargo" if court.kind=="loading" else "hedge"
			var width: float=132 if kind=="scrap" else 112 if kind=="cargo" else 144
			if area.size.x<width+24 or area.size.y<84:continue
			# Place at a court boundary, leaving its entrance and orthogonal footways clear.
			for point: Vector2 in [Vector2(area.position.x+width/2+12,area.position.y+52),Vector2(area.end.x-width/2-12,area.end.y-14),Vector2(area.get_center().x,area.position.y+52)]:
				var block: Rect2=Rect2(point-Vector2(width*0.44,24),Vector2(width*0.88,24))
				var clear: bool=area.encloses(block) and not WorldLayout.rect(data.bus.sweep).grow(24).intersects(block)
				for other: Rect2 in occupied+reserved:clear=clear and not block.grow(20).intersects(other)
				for road: Array in data.roads:clear=clear and not block.grow(24).intersects(WorldLayout.rect(road))
				for walk: Array in parcel.walks:clear=clear and not block.grow(12).intersects(WorldLayout.rect(walk))
				if not clear:continue
				parcel.dressing.append({"kind":kind,"point":[point.x,point.y],"width":width,"collision":[block.position.x,block.position.y,block.size.x,block.size.y]})
				occupied.append(block.grow(20));count+=1
				break
