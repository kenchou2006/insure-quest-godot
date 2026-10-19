extends PanelContainer
## StatMeter：訪談畫面的一項數值（圖示、名稱、進度條、數字）。數值改變時進度條補間、數字短暫
## 跳動，旁邊浮出 +n／−n。inverted 的數值（預算壓力、合規風險）越高越要注意，顏色跟著轉紅。
## 只是顯示：數值一律來自後端的會談指標。

var key := ""
var caption := ""
var inverted := false
var color := Color("#00A86B")
var value := -1
var _bar: ProgressBar
var _num: Label
var _delta: Label
var _fill: StyleBoxFlat
var _tween: Tween


func _init(k: String, cap: String, icon_kind: String, col: Color, is_inverted := false) -> void:
	key = k
	caption = cap
	color = col
	inverted = is_inverted
	name = "Meter_" + k
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0D4038", 0.92)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	var v := QuestUI.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var head := QuestUI.hbox(6)
	head.add_child(QuestUI.icon(icon_kind, 16.0, col))
	var cl := QuestUI.label(cap, 13, QuestUI.TEXT)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cl)
	_delta = QuestUI.label("", 12, QuestUI.GREEN)
	_delta.name = "Delta"
	_delta.modulate.a = 0.0
	head.add_child(_delta)
	v.add_child(head)
	var row := QuestUI.hbox(8)
	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(60, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.1)
	back.set_corner_radius_all(4)
	_fill = StyleBoxFlat.new()
	_fill.bg_color = col
	_fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", _fill)
	row.add_child(_bar)
	_num = QuestUI.label("—", 16, QuestUI.TEXT, false, true)
	_num.name = "Value"
	_num.custom_minimum_size = Vector2(30, 0)
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_num.pivot_offset = Vector2(15, 10)
	row.add_child(_num)
	v.add_child(row)


## v < 0：尚未評估（顯示「待評估」）
func set_value(v: int, animate := true) -> void:
	if v < 0:
		value = -1
		_bar.value = 0
		_num.text = "—"
		tooltip_text = caption + "：待評估"
		return
	v = clampi(v, 0, 100)
	var old := value
	value = v
	tooltip_text = "%s：%d" % [caption, v]
	var col := color
	if inverted and v >= 60:
		col = QuestUI.RED
	_fill.bg_color = col
	if old < 0 or not animate or QuestUI.motion_off():
		_bar.value = v
		_num.text = str(v)
		return
	var d := v - old
	if d == 0:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_bar, "value", float(v), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(x: float): _num.text = str(int(round(x))), float(old), float(v), 0.45)
	# 數字短暫跳動
	_num.scale = Vector2.ONE * 1.25
	_tween.tween_property(_num, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# +n／−n：好的變化綠色，壞的變化紅色（反向數值上升算壞）
	var good := (d > 0) != inverted
	_delta.text = ("+%d" % d) if d > 0 else ("−%d" % absi(d))
	_delta.add_theme_color_override("font_color", QuestUI.GREEN if good else QuestUI.RED)
	_delta.modulate.a = 1.0
	var fade := create_tween()
	fade.tween_interval(1.4)
	fade.tween_property(_delta, "modulate:a", 0.0, 0.4)
