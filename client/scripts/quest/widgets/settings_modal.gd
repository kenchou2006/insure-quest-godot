extends Control
## SettingsModal (右上角設定): 背景音樂 / 音效 / 秘書語音 volume, 全部靜音, 字幕, 文字顯示速度,
## 減少動態效果, 全螢幕 (where supported), 暫停／繼續 and 離開培訓 (in a game: the 繼續 / 儲存並返回 / 放棄 dialog;
## after the game: 返回主畫面). Real controls, saved at once. While it is open (and
## while paused) the meeting clock holds. Warnings never depend on sound: muted play keeps icons,
## words and colours.

signal leave_requested

const Fullscreen := preload("res://scripts/fullscreen.gd")

## Label of the leave button: 離開培訓 during a game, 返回主畫面 once it has ended
var home_label := "離開培訓"

var _panel: PanelContainer
var _paused := false
var _pause_btn: Button
var _mute: CheckButton
var _full: CheckButton
var _sliders: Dictionary = {}
var _pause_card: PanelContainer


func _init() -> void:
	name = "SettingsModal"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(QuestUI.INK, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and not _paused:
			close()
	)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", QuestUI.card_box(1.0, Color(QuestUI.GOLD, 0.5)))
	_panel.custom_minimum_size = Vector2(minf(460.0, get_viewport_rect().size.x - 32.0), 0)
	center.add_child(_panel)
	var v := QuestUI.vbox(12)
	_panel.add_child(v)
	var head := QuestUI.header("gear", "設定")
	var close_btn: Button = QuestUI.button("關閉", close, "quiet", "close")
	close_btn.name = "SettingsClose"
	head.add_child(close_btn)
	v.add_child(head)
	for spec in [["Music", "背景音樂"], ["UI", "音效"], ["Voice", "秘書語音"]]:
		v.add_child(_slider_row(spec[0], spec[1]))
	_mute = CheckButton.new()
	_mute.text = "全部靜音"
	_mute.add_theme_font_size_override("font_size", QuestUI.fs(15))
	_mute.button_pressed = MusicManager.muted
	_mute.toggled.connect(func(on: bool): MusicManager.set_muted(on))
	v.add_child(_mute)
	var subs := CheckButton.new()
	subs.text = "秘書字幕"
	subs.add_theme_font_size_override("font_size", QuestUI.fs(15))
	subs.button_pressed = GameState.subtitles
	subs.toggled.connect(func(on: bool): GameState.set_subtitles(on))
	v.add_child(subs)
	var speed_row := QuestUI.hbox(8)
	speed_row.add_child(QuestUI.label("文字顯示速度", 15))
	speed_row.add_child(QuestUI.spacer())
	var group := ButtonGroup.new()
	for k: String in GameState.TEXT_SPEEDS:
		var b := Button.new()
		b.text = k
		b.toggle_mode = true
		b.button_group = group
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", QuestUI.fs(14))
		b.button_pressed = is_equal_approx(float(GameState.TEXT_SPEEDS[k]), GameState.text_speed)
		var val: float = GameState.TEXT_SPEEDS[k]
		b.pressed.connect(func(): GameState.set_text_speed(val))
		speed_row.add_child(b)
	v.add_child(speed_row)
	var motion := CheckButton.new()
	motion.text = "減少動態效果"
	motion.add_theme_font_size_override("font_size", QuestUI.fs(15))
	motion.button_pressed = UI.reduce_motion
	motion.toggled.connect(func(on: bool): UI.set_reduce_motion(on))
	v.add_child(motion)
	if Fullscreen.is_supported():
		_full = CheckButton.new()
		_full.name = "FullscreenToggle"
		_full.text = "全螢幕"
		_full.add_theme_font_size_override("font_size", QuestUI.fs(15))
		_full.button_pressed = Fullscreen.is_on()
		_full.toggled.connect(func(on: bool): Fullscreen.set_on(on))
		v.add_child(_full)
		# Esc or the browser can leave fullscreen: the switch shows the real state
		get_viewport().size_changed.connect(func():
			if is_instance_valid(_full):
				_full.set_pressed_no_signal(Fullscreen.is_on())
		)
	v.add_child(QuestUI.divider())
	var row := QuestUI.hbox(10)
	v.add_child(row)
	_pause_btn = QuestUI.button("暫停", _toggle_pause, "secondary", "pause")
	_pause_btn.name = "PauseButton"
	_pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_pause_btn)
	var home: Button = QuestUI.button(home_label, _ask_leave, "danger", "door")
	home.name = "HomeButton"
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(home)
	_build_pause_card(center)


func _slider_row(bus: String, title: String) -> Control:
	var h := QuestUI.hbox(10)
	var t := QuestUI.label(title, 15)
	t.custom_minimum_size.x = 84
	h.add_child(t)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.set_value_no_signal(MusicManager.get_slider(bus))
	# Brand track: dark rail, green fill, ivory grabber area
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(1, 1, 1, 0.12)
	rail.set_corner_radius_all(4)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", rail)
	var fill := StyleBoxFlat.new()
	fill.bg_color = QuestUI.GREEN
	fill.set_corner_radius_all(4)
	s.add_theme_stylebox_override("grabber_area", fill)
	var fill_h := fill.duplicate() as StyleBoxFlat
	fill_h.bg_color = QuestUI.GREEN.lightened(0.15)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_h)
	h.add_child(s)
	var val := QuestUI.label(str(int(s.value)), 13, QuestUI.MUTED)
	val.custom_minimum_size.x = 34
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	s.value_changed.connect(func(x: float):
		MusicManager.set_slider(bus, x)
		val.text = str(int(x))
	)
	if bus == "UI":
		s.drag_ended.connect(func(_c: bool): AudioManager.play("ui_click"))
	_sliders[bus] = s
	return h


func _build_pause_card(parent: Control) -> void:
	_pause_card = PanelContainer.new()
	_pause_card.add_theme_stylebox_override("panel", QuestUI.card_box(1.0, Color(QuestUI.GOLD, 0.6)))
	_pause_card.visible = false
	parent.add_child(_pause_card)
	var v := QuestUI.vbox(14)
	_pause_card.add_child(v)
	var t := QuestUI.title("已暫停", 26, QuestUI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := QuestUI.label("會談計時已停止。準備好後按「繼續」。", 15, QuestUI.MUTED, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 300
	v.add_child(l)
	var resume: Button = QuestUI.button("繼續", _toggle_pause, "primary", "play")
	resume.name = "ResumeButton"
	v.add_child(resume)
	var settings: Button = QuestUI.button("設定", func(): _pause_card.visible = false; _panel.visible = true, "secondary", "gear")
	v.add_child(settings)


func open() -> void:
	visible = true
	_panel.visible = true
	_pause_card.visible = false
	_mute.set_pressed_no_signal(MusicManager.muted)
	if is_instance_valid(_full):
		_full.set_pressed_no_signal(Fullscreen.is_on())
	for bus in _sliders:
		(_sliders[bus] as HSlider).set_value_no_signal(MusicManager.get_slider(bus))
	GameState.hold("settings", true)
	QuestUI.fade_in(_panel, 0.0, 0.2, 0.0)


func close() -> void:
	visible = false
	_paused = false
	GameState.hold("settings", false)
	GameState.hold("paused", false)
	_pause_btn.call("set_label", "暫停")


func is_paused() -> bool:
	return _paused


func _toggle_pause() -> void:
	_paused = not _paused
	GameState.hold("paused", _paused)
	if _paused:
		_panel.visible = false
		_pause_card.visible = true
		visible = true
	else:
		close()


func _ask_leave() -> void:
	# The receiver decides: in a game the 離開培訓 dialog, after it straight to the main screen
	close()
	leave_requested.emit()
