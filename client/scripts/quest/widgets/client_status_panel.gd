extends PanelContainer
## ClientStatusPanel: 客戶狀態 — portrait, name, 信任 / 需求 / 預算適配 / 合規 bars, read live from
## GameState (server metrics). A change animates the bar and floats a +n / -n beside it.

var _portrait: TextureRect
var _name: Label
var _sub: Label
var _rows: VBoxContainer
var _bars: Dictionary = {}
var _values: Dictionary = {}
var compact := false
var show_header := true


func _init(is_compact := false, with_header := true) -> void:
	compact = is_compact
	show_header = with_header
	name = "ClientStatusPanel"
	add_theme_stylebox_override("panel", QuestUI.card_box())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := QuestUI.vbox(10)
	add_child(v)
	if show_header:
		v.add_child(QuestUI.header("people", "客戶狀態"))
	var h := QuestUI.hbox(12)
	v.add_child(h)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var psz := Vector2(96, 120) if not compact else Vector2(64, 80)
	_portrait.custom_minimum_size = psz
	_portrait.material = UI.get_rounded_material(0.1)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_portrait)
	var right := QuestUI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_name = QuestUI.label("本局客戶", 17 if not compact else 15, QuestUI.TEXT, false, true)
	right.add_child(_name)
	_sub = QuestUI.label("", 12, QuestUI.MUTED, true)
	right.add_child(_sub)
	_rows = QuestUI.vbox(5)
	right.add_child(_rows)
	for spec in [["trust", "信任"], ["insight", "需求"], ["fit", "預算適配"], ["risk", "合規風險"]]:
		var row := QuestUI.metric_bar(spec[1], 0)
		_rows.add_child(row)
		_bars[spec[0]] = row


func _ready() -> void:
	refresh()


func refresh() -> void:
	var c := GameState.current_client()
	_portrait.texture = GameState.client_portrait()
	_portrait.visible = _portrait.texture != null
	var nm := str(c.get("name", ""))
	_name.text = nm if nm != "" else "本局客戶"
	var bits: Array = []
	if int(c.get("age", 0)) > 0:
		bits.append("%d 歲" % int(c.age))
	if str(c.get("job", "")) != "":
		bits.append(str(c.job))
	_sub.text = "・".join(bits)
	_sub.visible = _sub.text != ""
	var m := GameState.metrics()
	var vals := {
		"trust": float(m.get("trust", 50)),
		"insight": float(m.get("insight", 20)),
		"fit": float(m.get("fit", 50)),
		"risk": 100.0 - float(m.get("compliance", 100)),
	}
	for k in vals:
		_set_bar(k, vals[k])


func _set_bar(key: String, value: float) -> void:
	var row: HBoxContainer = _bars[key]
	var bar = row.get_child(1)
	var num: Label = row.get_child(2)
	var old: float = _values.get(key, value)
	_values[key] = value
	var col := (QuestUI.RED if value >= 60.0 else Color("#C8D2CE")) if key == "risk" else QuestUI.metric_color(value)
	bar.color = col
	num.add_theme_color_override("font_color", col)
	num.text = str(int(round(value)))
	if QuestUI.motion_off() or absf(old - value) < 0.5:
		bar.value = value
		return
	var tw := bar.create_tween()
	tw.tween_property(bar, "value", value, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_float_delta(row, value - old, key == "risk")


func _float_delta(row: Control, d: float, inverted := false) -> void:
	var good := (d > 0) != inverted
	var l := QuestUI.label(("+%d" if d > 0 else "%d") % int(round(d)), 13, QuestUI.GREEN if good else QuestUI.RED, false, true)
	l.top_level = true
	add_child(l)
	l.global_position = row.global_position + Vector2(row.size.x - 20, -6)
	var tw := l.create_tween()
	tw.tween_property(l, "global_position:y", l.global_position.y - 16, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.tween_callback(l.queue_free)
