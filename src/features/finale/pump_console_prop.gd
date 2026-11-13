class_name PumpConsoleProp
extends FieldProp
## The station art owns the cabinet. This prop exposes the existing work display.

func _ready() -> void:
	_work = _label("", Vector2(-104, 16), 15, 208)
	_bar = ProgressBar.new()
	_bar.position = Vector2(-42, 42)
	_bar.size = Vector2(84, 7)
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	update_work(-1, 0.0, false)


func update_work(actor_id: int, fraction: float, inside: bool, call_sign: String = "", work_text: String = "") -> void:
	super.update_work(actor_id, fraction, inside, call_sign, work_text)
	if searched:
		_work.text = "泵站 · 已停机"
	elif inside:
		_work.text = "正在停机 %d%% · 再点取消" % roundi(fraction * 100)
	elif actor_id >= 0:
		_work.text = "操作员前往 · 再点取消"
	else:
		_work.text = "控制柜 · 点击派工停机"


func _draw() -> void:
	IsoDraw.box(self, Vector2(48, 28), 40, Color("4d5a66"), Color("8a9098"), Color("6d757c"))
	IsoDraw.marker(self, Vector2.ZERO, Color("a8ebd4") if searched else IsoDraw.AMBER)

