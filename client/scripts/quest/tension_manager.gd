extends Node
## TensionManager (autoload): Stable / Warning / Danger / Critical Decision from the meeting clock,
## client trust, compliance, the plan (budget / coverage flags set by pages) and event severity.
## Every state names its reasons in words, so the warning reads the same with sound off.
## Visuals stay restrained: Warning = one gold pulse on the timer / card (pages listen), Danger = a
## very faint static dark-red edge (never flashing), Critical = the page dims around the control.

signal state_changed(state: int, reasons: Array)
## One readable message per new reason: text, level (1 warning, 2 danger)
signal message(text: String, level: int)

enum { STABLE, WARNING, DANGER, CRITICAL }
const NAMES := ["Stable", "Warning", "Danger", "Critical"]

var state := STABLE
var reasons: Array = []
## Page flags: budget_over, coverage_gap, hesitating, event_severity (0..2), violation
var flags: Dictionary = {}
var active := false
var _critical := false
var _said: Dictionary = {}
var _acc := 0.0
var _layer: CanvasLayer
var _edge: Control
var _edge_tween: Tween
var _music_before := "map"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.name = "TensionEdge"
	_layer.layer = 30
	add_child(_layer)
	_edge = EdgeGlow.new()
	_edge.name = "DangerEdge"
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.modulate.a = 0.0
	_edge.visible = false
	_layer.add_child(_edge)
	if not Engine.is_editor_hint():
		GameState.client_changed.connect(func(_id): _said.clear(); flags.clear())
		GameState.timer_mark.connect(_on_timer_mark)


## Countdown sounds, once each: 30 s warning tone, a low beat each of the last 10 s (firmer in the
## last 3), nothing harsh at zero — the message carries it
func _on_timer_mark(m: int) -> void:
	if not GameState.timed_page:
		return
	if m == 30:
		AudioManager.play("timer_warn")
	elif m >= 4 and m <= 10:
		AudioManager.play("timer_tick")
	elif m >= 1 and m <= 3:
		AudioManager.play("timer_tick_strong")
	elif m == 0:
		AudioManager.play("timer_tick_strong", 0.8)
	_recompute()


## Mission pages switch tension on while they are up; the map and menus stay calm
func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	if not on:
		flags.clear()
		_apply(STABLE, [])


func set_flag(key: String, value: Variant) -> void:
	var off: bool = value == null or (value is bool and not value) or ((value is int or value is float) and float(value) == 0.0)
	if off:
		flags.erase(key)
	else:
		flags[key] = value
	_recompute()


func enter_critical() -> void:
	if _critical:
		return
	_critical = true
	_music_before = AudioManager.music_state()
	AudioManager.play("heartbeat")
	_apply(CRITICAL, reasons)


func exit_critical() -> void:
	if not _critical:
		return
	_critical = false
	AudioManager.set_music_state(_music_before if _music_before != "" and _music_before != "critical" else "meeting")
	_recompute(true)


func is_critical() -> bool:
	return _critical


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 0.25:
		_acc = 0.0
		_recompute()


func _recompute(force := false) -> void:
	if _critical and not force:
		return
	if not active:
		if state != STABLE:
			_apply(STABLE, [])
		return
	var warn: Array = []
	var danger: Array = []
	var ratio := GameState.time_ratio()
	var in_meeting := not GameState.my_session().is_empty()
	if GameState.remaining_time() <= 0.0:
		danger.append("會談時間結束，請完成目前決策")
	elif ratio < 0.25:
		danger.append("會談時間所剩不多")
	elif ratio < 0.5:
		warn.append("會談時間正在減少")
	if in_meeting:
		var t := GameState.trust()
		if t < 35:
			danger.append("客戶信任過低")
		elif t < 45 or flags.has("hesitating"):
			warn.append("客戶正在猶豫")
		var comp := GameState.compliance()
		if comp < 70 or flags.has("violation"):
			danger.append("出現重大合規風險")
		elif comp < 90:
			warn.append("合規表達出現瑕疵")
	elif flags.has("hesitating"):
		warn.append("客戶正在猶豫")
	if flags.has("budget_over"):
		danger.append("目前方案超出客戶每月預算")
	if flags.has("coverage_gap"):
		warn.append("目前方案仍有保障缺口")
	var sev := int(flags.get("event_severity", 0))
	if sev >= 2:
		danger.append("重大人生事件正在衝擊客戶")
	elif sev == 1:
		warn.append("客戶生活出現變化")
	var next := DANGER if not danger.is_empty() else (WARNING if not warn.is_empty() else STABLE)
	var all: Array = danger + warn
	if next != state or all != reasons:
		_apply(next, all, danger)


func _apply(next: int, why: Array, dangers: Array = []) -> void:
	var prev := state
	state = next
	reasons = why
	for r in why:
		if not _said.has(r):
			_said[r] = true
			message.emit(r, 2 if dangers.has(r) else 1)
	if prev != next:
		_sound_for(next)
		_edge_for(next)
		state_changed.emit(next, why)


func _sound_for(s: int) -> void:
	match s:
		STABLE:
			AudioManager.stop_tension_layers()
		WARNING:
			AudioManager.set_layer("tension_warn", true)
			AudioManager.set_layer("tension_danger", false)
			AudioManager.set_layer("tension_critical", false)
		DANGER:
			AudioManager.set_layer("tension_warn", false)
			AudioManager.set_layer("tension_danger", true)
			AudioManager.set_layer("tension_critical", false)
		CRITICAL:
			AudioManager.set_layer("tension_critical", true, 0.6)
			AudioManager.set_music_state("critical")


func _edge_for(s: int) -> void:
	if _edge_tween and _edge_tween.is_valid():
		_edge_tween.kill()
	var target := 1.0 if s == DANGER else 0.0
	if target > 0:
		_edge.visible = true
	if UI.is_animation_disabled():
		_edge.modulate.a = target
		_edge.visible = target > 0
		return
	_edge_tween = create_tween()
	_edge_tween.tween_property(_edge, "modulate:a", target, 0.6).set_trans(Tween.TRANS_SINE)
	if target == 0:
		_edge_tween.tween_callback(func(): _edge.visible = false)


func level_name() -> String:
	return NAMES[state]


## Static dark-red vignette at the screen edges (about 16% at the very edge, none inside)
class EdgeGlow extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var col := Color("#5A1A16")
		var band := minf(size.x, size.y) * 0.12
		for k in range(12):
			var a := 0.16 * pow(1.0 - float(k) / 12.0, 2.0)
			var inset := band * float(k) / 12.0
			var w := band / 12.0 + 0.5
			var c := Color(col, a)
			draw_rect(Rect2(inset, inset, size.x - inset * 2, w), c)
			draw_rect(Rect2(inset, size.y - inset - w, size.x - inset * 2, w), c)
			draw_rect(Rect2(inset, inset + w, w, size.y - inset * 2 - w * 2), c)
			draw_rect(Rect2(size.x - inset - w, inset + w, w, size.y - inset * 2 - w * 2), c)
