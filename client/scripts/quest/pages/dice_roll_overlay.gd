extends Control
## DiceRollOverlay（擲骰與地圖前進）：骰子在地圖下方的骰盤滾動 1.0 秒（擲骰與落定音效），
## 落定後顯示「移動中…　骰出 N，前進 N 站」，骰盤一直留到棋子到站才淡出。
## 只顯示點數，不透露站點事件。整個圖層不攔截滑鼠，只有「跳過動畫」按鈕可按：
## 跳過時棋子直接到站、縮短等待（點數與站點仍由後端決定）。

const ROLL_TIME := 1.0
const SHOW_TIME := 0.55

signal skip_requested

var _tray: PanelContainer
var _die: Die
var _caption: Label
var _title: Label
var _skip: Button
var _seq: Tween
var _tick := 0.0
var _rolling := false


func _init() -> void:
	name = "DiceRollOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_tray = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(QuestUI.INK, 0.92)
	s.set_corner_radius_all(18)
	s.set_border_width_all(1)
	s.border_color = Color(QuestUI.GOLD, 0.6)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 16
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	_tray.add_theme_stylebox_override("panel", s)
	_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tray)
	var h := QuestUI.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	_tray.add_child(h)
	var tv := QuestUI.vbox(4)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title = QuestUI.title("擲骰中…", 24 if not UI.is_phone() else 18, QuestUI.TEXT)
	_title.name = "DiceTitle"
	tv.add_child(_title)
	_caption = QuestUI.label("正在安排下一段行程", 15, QuestUI.TEXT, false, true)
	_caption.name = "DiceCaption"
	tv.add_child(_caption)
	h.add_child(tv)
	_die = Die.new()
	_die.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_die)
	_skip = QuestUI.button("跳過動畫", _on_skip, "quiet", "next")
	_skip.name = "SkipAnimation"
	_skip.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(_skip)


## Plays the roll; returns seconds until the die has landed and its number shown
func play(roller: String, value: int, mine: bool) -> float:
	if _seq and _seq.is_valid():
		_seq.kill()
	visible = true
	modulate.a = 1.0
	_skip.visible = true
	_skip.disabled = false
	_title.text = "擲骰中…"
	_caption.text = "正在安排下一段行程" if mine else "%s 擲骰中" % roller
	_caption.add_theme_color_override("font_color", QuestUI.TEXT)
	_tray.reset_size()
	_place()
	_rolling = true
	_die.value = randi() % 6 + 1
	AudioManager.play("dice_roll")
	var quick := QuestUI.motion_off()
	var roll_t := 0.35 if quick else ROLL_TIME
	_seq = create_tween()
	_seq.tween_interval(roll_t)
	_seq.tween_callback(func():
		_rolling = false
		_die.value = value
		_die.rotation = 0.0
		AudioManager.play("dice_land")
		_title.text = "移動中…"
		_caption.text = "骰出 %d，前進 %d 站" % [value, value]
		_caption.add_theme_color_override("font_color", QuestUI.GOLD)
		if not quick:
			_die.pivot_offset = _die.size * 0.5
			_die.scale = Vector2.ONE * 1.25
			var b := _die.create_tween()
			b.tween_property(_die, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	# 骰盤留到棋子到站（QuestFlow 離開擲骰／移動狀態）才淡出
	return roll_t + 0.15


func _ready() -> void:
	if not Engine.is_editor_hint():
		QuestFlow.state_changed.connect(_on_flow)


func _on_flow(_from: String, to: String) -> void:
	if to in [QuestFlow.DICE_ROLLING, QuestFlow.PLAYER_MOVING] or not visible:
		return
	hide_tray()


func hide_tray() -> void:
	if _seq and _seq.is_valid():
		_seq.kill()
	_rolling = false
	if QuestUI.motion_off():
		visible = false
		return
	_seq = create_tween()
	_seq.tween_property(self, "modulate:a", 0.0, 0.3)
	_seq.tween_callback(func(): visible = false)


## 跳過動畫：骰子立即落定，棋子直接到站
func _on_skip() -> void:
	_skip.disabled = true
	AudioManager.play("ui_click")
	skip_requested.emit()


func _process(delta: float) -> void:
	if not _rolling:
		return
	_tick += delta
	if _tick >= 0.07:
		_tick = 0.0
		_die.value = randi() % 6 + 1
		_die.pivot_offset = _die.size * 0.5
		_die.rotation = randf_range(-0.3, 0.3)


func _place() -> void:
	var sz := _tray.get_combined_minimum_size()
	_tray.size = sz
	var map_w := size.x
	# Over the map, not the side panel (the side panel takes about 30% on wide screens)
	if not UI.is_portrait() and not UI.is_phone_landscape():
		map_w = size.x * 0.7
	_tray.position = Vector2((map_w - sz.x) * 0.5, size.y - sz.y - (24.0 if not UI.is_phone() else 12.0))


func is_playing() -> bool:
	return visible


## Rounded die with pips (gold frame, ivory pips)
class Die extends Control:
	var value := 1:
		set(v):
			value = v
			queue_redraw()

	func _init() -> void:
		var sz := 84.0 if not UI.is_phone() else 60.0
		custom_minimum_size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-3)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#F3F0E7")
		sb.set_corner_radius_all(int(size.x * 0.18))
		sb.set_border_width_all(2)
		sb.border_color = QuestUI.GOLD
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		draw_style_box(sb, r)
		var c := size * 0.5
		var o := size.x * 0.24
		var rad := size.x * 0.075
		var pts: Array = []
		match value:
			1: pts = [c]
			2: pts = [c + Vector2(-o, -o), c + Vector2(o, o)]
			3: pts = [c + Vector2(-o, -o), c, c + Vector2(o, o)]
			4: pts = [c + Vector2(-o, -o), c + Vector2(o, -o), c + Vector2(-o, o), c + Vector2(o, o)]
			5: pts = [c + Vector2(-o, -o), c + Vector2(o, -o), c, c + Vector2(-o, o), c + Vector2(o, o)]
			_: pts = [c + Vector2(-o, -o), c + Vector2(o, -o), c + Vector2(-o, 0), c + Vector2(o, 0), c + Vector2(-o, o), c + Vector2(o, o)]
		for p in pts:
			draw_circle(p, rad, QuestUI.INK if value != 1 else Color("#8E2B24"))
