extends PanelContainer
## TimerBadge: 剩餘 mm:ss for the current client.
## > 60 s calm · ≤ 60 s gold frame · ≤ 30 s warning red · last 10 s the number swells once a second ·
## 0 → 時間到 (play continues, overtime is counted). Shows 計時暫停 while the clock is held, so the
## state reads without sound. Sounds play once, from TensionManager / the mark signal owner.

var _icon: Control
var _label: Label
var _state_label: Label
var _last_mark := 999
var _frame := ""
var compact := false


func _init(is_compact := false) -> void:
	compact = is_compact
	name = "TimerBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := QuestUI.hbox(6)
	add_child(h)
	_icon = QuestUI.icon("clock", 18.0 if not compact else 15.0, QuestUI.TEXT)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_icon)
	_label = QuestUI.label("剩餘 10:00", 16 if not compact else 13, QuestUI.TEXT, false, true)
	h.add_child(_label)
	_state_label = QuestUI.label("", 11, QuestUI.MUTED)
	_state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_state_label)
	_set_frame("calm")


func _ready() -> void:
	GameState.timer_tick.connect(_on_tick)
	GameState.timer_mark.connect(_on_mark)
	GameState.client_changed.connect(func(_id): _last_mark = 999; _refresh())
	# Warning / Danger from any cause (trust, budget, compliance, events): gold / red, one pulse
	TensionManager.state_changed.connect(func(st: int, _why: Array):
		_refresh()
		if st == TensionManager.WARNING or st == TensionManager.DANGER:
			QuestUI.pulse_once(self, 1.06)
	)
	_refresh()


func _set_frame(kind: String) -> void:
	if kind == _frame:
		return
	_frame = kind
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(999)
	s.content_margin_left = 12 if not compact else 8
	s.content_margin_right = 12 if not compact else 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.set_border_width_all(1)
	match kind:
		"gold":
			s.bg_color = Color(QuestUI.GOLD, 0.12)
			s.border_color = QuestUI.GOLD
		"red":
			s.bg_color = Color(QuestUI.RED, 0.14)
			s.border_color = QuestUI.RED
		_:
			s.bg_color = Color(QuestUI.INK, 0.6)
			s.border_color = Color(1, 1, 1, 0.16)
	add_theme_stylebox_override("panel", s)


func _process(_delta: float) -> void:
	# Pause note follows the live clock state (secretary, tutorial, settings, AI wait, map)
	var running := GameState.clock_running()
	var txt := ""
	if not GameState.record.is_empty() and not running:
		if not GameState.timed_page:
			txt = "地圖上不計時"
		elif TutorialManager.blocking():
			txt = "秘書說明中・計時暫停"
		elif GameState.holds.has("paused"):
			txt = "已暫停"
		elif not Net.is_my_turn():
			txt = "等待中"
		else:
			txt = "計時暫停"
	if _state_label.text != txt:
		_state_label.text = txt


func _refresh() -> void:
	_on_tick(GameState.remaining_time(), GameState.total_time())


func _on_tick(rem: float, _total: float) -> void:
	if rem <= 0.0:
		_label.text = "時間到" + ("（超時 %s）" % QuestUI.mmss(GameState.overtime()) if GameState.overtime() >= 1.0 and not compact else "")
	else:
		_label.text = ("剩餘 " if not compact else "") + QuestUI.mmss(rem)
	var col := QuestUI.TEXT
	var tension: int = TensionManager.state
	if rem <= 30.0 or tension == TensionManager.DANGER:
		_set_frame("red")
		col = QuestUI.RED.lightened(0.15)
	elif rem <= 60.0 or tension == TensionManager.WARNING:
		_set_frame("gold")
		col = QuestUI.GOLD.lightened(0.1)
	else:
		_set_frame("calm")
	_label.add_theme_color_override("font_color", col)
	if _icon.has_method("set_color"):
		_icon.call("set_color", col)


func _on_mark(m: int) -> void:
	if m > 10 or m <= 0:
		if m == 60 or m == 30:
			QuestUI.pulse_once(self, 1.06)
		return
	# Last ten seconds: the number swells and settles once per second, never blinks
	if m < _last_mark:
		_last_mark = m
		QuestUI.pulse_once(self, 1.1 if m <= 3 else 1.06)
