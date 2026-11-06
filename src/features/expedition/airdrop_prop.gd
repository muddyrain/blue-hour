class_name AirdropProp
extends FieldProp
## Small original vector crate/beacon, read-only projection of the real search site.
func _ready() -> void:
	_work=_label("空投 · 主目标",Vector2(-104,18),14,208)
	_bar=ProgressBar.new(); _bar.position=Vector2(-36,48); _bar.size=Vector2(72,6); _bar.show_percentage=false
	_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(_bar)
	update_work(-1,0,false)

func _draw() -> void:
	draw_crate(self,searched)


static func draw_crate(canvas: CanvasItem, recovered: bool) -> void:
	canvas.draw_set_transform(Vector2.ZERO,0,Vector2(1,0.3))
	canvas.draw_circle(Vector2.ZERO,32,Color(0.05,0.10,0.12,0.35))
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_rect(Rect2(-22,-32,44,32),Color("6f7960"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-22,-32),Vector2(-12,-40),Vector2(30,-40),Vector2(22,-32)]),Color("9ba285"))
	canvas.draw_rect(Rect2(-4,-32,8,32),Color("dfbd73"))
	canvas.draw_line(Vector2(30,0),Vector2(30,-82),Color("7f969b"),3)
	canvas.draw_circle(Vector2(30,-84),5,Color("9aebd6") if recovered else Color("ffd385"))
	canvas.draw_arc(Vector2.ZERO,35,0,TAU,32,Color("9aebd6") if recovered else Color("ffd385"),2,true)


func update_work(actor_id: int, fraction: float, inside: bool, call_sign: String = "", work_text: String = "") -> void:
	super.update_work(actor_id,fraction,inside,call_sign,work_text)
	if _work!=null:
		_work.text=work_text if not work_text.is_empty() else "空投 · 已回收" if searched else "空投 · 回收中 %d%%"%roundi(fraction*100) if inside else "空投 · 主目标 · 左键回收"
	queue_redraw()
