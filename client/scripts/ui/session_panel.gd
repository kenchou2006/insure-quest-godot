@tool
extends PanelContainer
## Client interview panel: clue observation -> needs interview (with AI free questions) -> plan allocation -> objection handling (with AI scoring) -> result and stress test.
## Supports portrait stacked layout, adaptive coverage card sizing (truncation prevention), AI coach hints, and visualized stress test.

signal violation_occurred

var main: Node
var _sess: Dictionary = {}
var _actor: bool = false
var _body: VBoxContainer
var _scroll: ScrollContainer
var _header_box: Control
var _metrics: Control
var _steps: HBoxContainer
var _content: VBoxContainer
# Wait AI state uses static: panel is rebuilt when switching desktop/mobile layouts;
# if not preserved, "client thinking..." vanishes and input box reappears while AI response is still en route
static var _waiting_ai: bool = false
static var _waiting_hint: bool = false
static var _streamed_hint_text: String = ""
static var _hint_streamed: bool = false
static var _streamed_obj_text: String = ""
static var _obj_streamed: bool = false
static var _rep_body_streamed: bool = false
## Summary of last received interview state (client/step/asked count...); change signifies AI response received, clearing wait
static var _last_key: String = ""
## Client answer stream: current text and state summary at reception (state change means final answer arrived, stops showing)
static var _stream_text: String = ""
static var _stream_key: String = ""
static var _stream_answer_done: bool = false
static var _queued_talk: Dictionary = {}
var _think_label: Label = null
var _hint_label: Label = null
var _obj_think_label: Label = null
var _last_result_sound_key: String = ""
var _prev_asked_len: int = 0
var _violation_pulse_panel: Panel = null
var _flashing_hotspots: bool = false
var _hint_used_this_session: bool = false

# Spectator auto-follow state
var _last_manual_scroll_time: float = -999.0
var _scroll_step_key := ""
var _follow_hold_until: float = 0.0
var _scroll_tween: Tween = null
var _prev_observed_for_spectator: int = -1
var _prev_cards_count_for_spectator: int = -1
var _clues_observed: int = 0
var _clues_control: Control = null
var _plan_alloc_section: Control = null
var _plan_cards_section: Control = null
var _objection_section: Control = null
var _queued_row: Control = null
var _pending_row: Control = null
var _last_client_row: Control = null

# Spectator prediction floating strip
var _pred_strip_container: MarginContainer = null
var _pred_strip: PanelContainer = null
var _pred_strip_shown: bool = false

# Local cache for plan allocation
var _plan_key: String = ""
var _sess_prev_id: String = ""
var _alloc: Dictionary = {"cash": 0, "protect": 0, "growth": 0}
var _cards: Array = []
var _plan_ui: Dictionary = {}

# Batch 2 state: real-time radar, floating metric deltas, thumbnail collapse, and compliance details
var _prev_metrics: Dictionary = {}
var _scene_collapsed: bool = false
var _expanded_compliance_issues: Dictionary = {}
static var _pending_talk: Dictionary = {}
var _actor_name_cache := ""
var _fade_key := ""

const METRIC_SHORT := {
	"trust": "信任",
	"insight": "洞察",
	"fit": "適配",
	"risk": "風險",
	"compliance": "合規"
}

const STANDARD_QUESTIONS := [
	{"id": "coverage", "text": "目前遇到醫療或無法工作時，有哪些資源可以使用？"},
	{"id": "income", "text": "如果收入中斷一個月，哪些支出仍然必須支付？"},
	{"id": "goal", "text": "這個人生目標裡，哪一部分是你最不願意犧牲的？"},
	{"id": "risk", "text": "這筆目標資金在使用前，你最多能接受多少波動？"},
	{"id": "premium", "text": "在預備金、保障和投資之間，你過去是如何分配的？"}
]

const CARD_CATEGORY_COLORS := {
	"medical": Color("#e07a5f"),
	"income": Color("#e5a93c"),
	"accident": Color("#e63946"),
	"tools": Color("#4ea8de"),
	"legacy": Color("#9b72cf"),
	"care": Color("#2ed59e"),
}

const RES_COLORS := {
	"cash": Color("#e5a93c"),
	"protect": Color("#2ed59e"),
	"growth": Color("#4ea8de"),
}


func _client_portrait(c: Dictionary, size: int, is_round: bool = false) -> Control:
	var cid: String = str(c.get("id", ""))
	var cname: String = str(c.get("name", "客戶"))
	var tex: Texture2D = Portraits.get_texture(cid)
	if tex != null:
		if is_round:
			var av := UI.avatar(tex, cname, size)
			av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			return av
		return UI.RoundTex.new(tex, Vector2(size, size), 12.0, UI.ACCENT, 2.0)

	# Fallback to scene thumbnail, then initial
	if is_round:
		var scene_p := UI.client_scene_path(c)
		var sc_tex: Texture2D = load(scene_p) if scene_p != "" and ResourceLoader.exists(scene_p) else null
		var av := UI.avatar(sc_tex, cname, size)
		av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return av
	var p := UI.portrait(c, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return p


func _ready() -> void:
	UI.pop_in(self, 0.22)
	# Interview state doesn't change when server rejects action; proactively dismiss "thinking", otherwise stuck
	if not Engine.is_editor_hint() and not Net.server_error.is_connected(_on_server_error):
		Net.server_error.connect(_on_server_error)
	if not Engine.is_editor_hint() and not Net.stream_text.is_connected(_on_stream_text):
		Net.stream_text.connect(_on_stream_text)
	if not Engine.is_editor_hint() and not Net.stream_answer_done.is_connected(_on_stream_answer_done):
		Net.stream_answer_done.connect(_on_stream_answer_done)
	if not Engine.is_editor_hint() and not Net.stream_chunk.is_connected(_on_stream_chunk):
		Net.stream_chunk.connect(_on_stream_chunk)
	var pad: int = 10 if UI.is_phone_portrait() else (14 if UI.is_portrait() else 16)
	add_theme_stylebox_override("panel", UI.box(UI.PANEL, 18, UI.ACCENT, pad))
	_body = UI.vbox(10 if UI.is_phone_portrait() else 12)
	_scroll = UI.scroll(_body)
	add_child(_scroll)
	if not Engine.is_editor_hint():
		_scroll.gui_input.connect(_on_scroll_input)
		var v_bar := _scroll.get_v_scroll_bar()
		if v_bar != null:
			v_bar.gui_input.connect(_on_scroll_input)
	_build_header_container()
	_steps = UI.hbox(2 if UI.is_phone() else 6)
	_body.add_child(_steps)
	_content = UI.vbox(10 if UI.is_phone_portrait() else 12)
	_body.add_child(_content)
	_build_spectator_prediction_overlay()


func _build_spectator_prediction_overlay() -> void:
	if _pred_strip_container != null and is_instance_valid(_pred_strip_container):
		return
	_pred_strip_container = MarginContainer.new()
	_pred_strip_container.name = "SpectatorPredOverlay"
	_pred_strip_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pred_strip_container.size_flags_vertical = Control.SIZE_SHRINK_END
	_pred_strip_container.size_flags_horizontal = Control.SIZE_FILL
	_pred_strip_container.z_index = 20
	var pad_x: int = 8 if UI.is_phone_portrait() else 12
	var pad_b: int = 8 if UI.is_phone_portrait() else 10
	_pred_strip_container.add_theme_constant_override("margin_left", pad_x)
	_pred_strip_container.add_theme_constant_override("margin_right", pad_x)
	_pred_strip_container.add_theme_constant_override("margin_bottom", pad_b)
	_pred_strip_container.add_theme_constant_override("margin_top", 0)
	_pred_strip_container.visible = false
	add_child(_pred_strip_container)

	_pred_strip = PanelContainer.new()
	_pred_strip.name = "PredStrip"
	_pred_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_pred_strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pred_strip.size_flags_vertical = Control.SIZE_SHRINK_END
	_pred_strip_container.add_child(_pred_strip)


func _build_header_container() -> void:
	if _header_box != null:
		_header_box.queue_free()
	_header_box = UI.vbox(4)
	_header_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_header_box)
	_body.move_child(_header_box, 0)


func _on_stream_text(text: String) -> void:
	if text == "" or _sess.is_empty() or str(_sess.get("step", "")) != "discover":
		return
	var first: bool = _stream_text == "" or _stream_key != _last_key
	_stream_text = text
	_stream_key = _last_key
	# If bubble exists, only update text (no rebuild, no flicker); redraw on first chunk to construct bubble (visible to spectators)
	if not first and _think_label != null and is_instance_valid(_think_label):
		_think_label.text = text
		_think_label.add_theme_color_override("font_color", UI.TEXT)
		if not _actor:
			_auto_follow_deferred(_think_label)
	else:
		refresh(_sess, _actor_name_cache)


func _on_stream_answer_done() -> void:
	if _sess.is_empty() or str(_sess.get("step", "")) != "discover":
		return
	_stream_answer_done = true
	refresh(_sess, _actor_name_cache)


func _on_stream_chunk(key: String, text: String, _done: bool) -> void:
	if key == "hint":
		if text == "":
			return
		var first: bool = not _hint_streamed or _streamed_hint_text == ""
		_hint_streamed = true
		_streamed_hint_text = text
		if not first and _hint_label != null and is_instance_valid(_hint_label):
			_hint_label.text = text
			_hint_label.visible_ratio = 1.0
			_hint_label.add_theme_color_override("font_color", UI.TEXT)
		else:
			refresh(_sess, _actor_name_cache)
	elif key == "objection":
		_obj_streamed = true
		_rep_body_streamed = true
		_streamed_obj_text = text
		if _obj_think_label != null and is_instance_valid(_obj_think_label):
			_obj_think_label.text = text
			_obj_think_label.visible_ratio = 1.0
			_obj_think_label.add_theme_color_override("font_color", UI.TEXT)
		else:
			refresh(_sess, _actor_name_cache)


func _streaming() -> bool:
	return _stream_text != "" and _stream_key == _last_key


func _on_server_error(_msg: String) -> void:
	if not (_waiting_ai or _waiting_hint or not _queued_talk.is_empty()):
		return
	_waiting_ai = false
	_waiting_hint = false
	_streamed_hint_text = ""
	_hint_streamed = false
	_streamed_obj_text = ""
	_pending_talk = {}
	_queued_talk = {}
	_stream_answer_done = false
	if is_inside_tree() and not _sess.is_empty():
		refresh(_sess, _actor_name_cache)


func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] or mb.pressed:
			_last_manual_scroll_time = Time.get_ticks_msec() / 1000.0
			if _scroll_tween != null and _scroll_tween.is_valid():
				_scroll_tween.kill()
				_scroll_tween = null
	elif event is InputEventPanGesture or event is InputEventScreenDrag:
		_last_manual_scroll_time = Time.get_ticks_msec() / 1000.0
		if _scroll_tween != null and _scroll_tween.is_valid():
			_scroll_tween.kill()
			_scroll_tween = null
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_last_manual_scroll_time = Time.get_ticks_msec() / 1000.0
			if _scroll_tween != null and _scroll_tween.is_valid():
				_scroll_tween.kill()
				_scroll_tween = null


func _scroll_to_top_after_layout() -> void:
	if _scroll == null or Engine.is_editor_hint() or not is_inside_tree():
		return
	# Content is rebuilt in this refresh; reset after layout so the new step's height does not keep the old offset
	await get_tree().process_frame
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0


func _auto_follow_deferred(target: Control) -> void:
	if _actor or target == null or Engine.is_editor_hint():
		return
	await get_tree().process_frame
	var hold: float = _follow_hold_until - Time.get_ticks_msec() / 1000.0
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	if not is_instance_valid(target) or not target.is_inside_tree() or _scroll == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_manual_scroll_time < 4.0:
		return
	_smooth_scroll_to(target, 0.3)


func _get_spectator_pred_strip_height() -> float:
	if _actor or _pred_strip_container == null or not is_instance_valid(_pred_strip_container) or not _pred_strip_container.visible:
		return 0.0
	if str(_sess.get("step", "")) not in ["discover", "plan", "objection"]:
		return 0.0
	var h: float = _pred_strip_container.get_combined_minimum_size().y
	if _pred_strip_container.size.y > h:
		h = _pred_strip_container.size.y
	return h


func _smooth_scroll_to(target: Control, duration: float = 0.3) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or _scroll == null:
		return
	var s_rect := _scroll.get_global_rect()
	var t_rect := target.get_global_rect()
	if s_rect.size.y <= 0:
		return
	var strip_h: float = _get_spectator_pred_strip_height()
	var visible_viewport_h: float = maxf(s_rect.size.y - strip_h, 1.0)
	var diff_top: float = t_rect.position.y - s_rect.position.y
	var diff_bottom: float = (t_rect.position.y + t_rect.size.y) - (s_rect.position.y + visible_viewport_h)
	var current_scroll: int = _scroll.scroll_vertical
	var target_scroll: int = current_scroll

	if t_rect.size.y >= visible_viewport_h:
		if absf(diff_top) > 4.0:
			target_scroll = int(current_scroll + diff_top - 12.0)
		else:
			return
	elif diff_top < 0:
		target_scroll = int(current_scroll + diff_top - 12.0)
	elif diff_bottom > 0:
		target_scroll = int(current_scroll + diff_bottom + 20.0)
	else:
		return

	target_scroll = maxi(0, target_scroll)
	var v_bar := _scroll.get_v_scroll_bar()
	if v_bar != null:
		var max_v: int = maxi(0, int(v_bar.max_value - v_bar.page))
		target_scroll = mini(target_scroll, max_v)

	if target_scroll == current_scroll:
		return

	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", target_scroll, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _send_talk(text: String, suggested: String = "") -> void:
	var comp := Compliance.check(text)
	var talk_data := {
		"text": text,
		"suggested": suggested,
		"level": comp.level,
		"issues": comp.issues,
	}
	var is_waiting: bool = _waiting_ai or bool(_sess.get("aiBusy", false)) or _streaming()
	if is_waiting:
		_queued_talk = talk_data
		refresh(_sess, _actor_name_cache)
	else:
		_pending_talk = talk_data
		_waiting_ai = true
		var act := {"type": "talk", "text": text}
		if suggested != "":
			act["suggested"] = suggested
		Net.act(act)
		refresh(_sess, _actor_name_cache)


func _trigger_violation_juice() -> void:
	Sound.play("violation", self)
	violation_occurred.emit()

	if _violation_pulse_panel == null or not is_instance_valid(_violation_pulse_panel):
		_violation_pulse_panel = Panel.new()
		_violation_pulse_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_violation_pulse_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_violation_pulse_panel.z_index = 50
		var sb := UI.box(Color(1.0, 0.1, 0.1, 0.12), 18, Color("#ff4444"), 4, false)
		_violation_pulse_panel.add_theme_stylebox_override("panel", sb)
		add_child(_violation_pulse_panel)

	_violation_pulse_panel.visible = true
	_violation_pulse_panel.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(_violation_pulse_panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(_violation_pulse_panel, "modulate:a", 0.35, 0.25)
	tw.tween_property(_violation_pulse_panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(_violation_pulse_panel, "modulate:a", 0.0, 0.55)
	tw.tween_callback(func():
		if _violation_pulse_panel and is_instance_valid(_violation_pulse_panel):
			_violation_pulse_panel.visible = false
	)


func refresh(sess: Dictionary, actor_name: String) -> void:
	_actor_name_cache = actor_name
	var prev_key: String = _last_key
	_sess = sess
	_actor = str(sess.get("playerId", "")) == Net.player_id
	var key: String = "%s/%s/%d/%d/%s" % [sess.get("client", {}).get("id", ""), sess.get("step", ""), (sess.get("asked", []) as Array).size(), (sess.get("clues", []) as Array).filter(func(c: Dictionary): return bool(c.get("observed", false))).size(), str(sess.get("result") != null)]
	_last_key = key
	if key != prev_key:
		_waiting_ai = false
		_pending_talk = {}
		_stream_text = ""
		_stream_answer_done = false
		if str(sess.get("step", "")) != "discover":
			_queued_talk = {}
		elif not _queued_talk.is_empty() and not bool(sess.get("aiBusy", false)):
			var q: Dictionary = _queued_talk.duplicate()
			_queued_talk = {}
			_pending_talk = q
			_waiting_ai = true
			var act := {"type": "talk", "text": str(q.get("text", ""))}
			if str(q.get("suggested", "")) != "":
				act["suggested"] = str(q.get("suggested", ""))
			Net.act(act)

	# Red-light violation juice detection for newly arrived entries
	var asked_arr: Array = sess.get("asked", []) as Array if sess.get("asked") is Array else []
	var cur_client_sess_id: String = str(sess.get("client", {}).get("id", "")) + str(sess.get("playerId", ""))
	if cur_client_sess_id != str(_sess_prev_id):
		_queued_talk = {}
		_pending_talk = {}
		_waiting_ai = false
		_waiting_hint = false
		_streamed_hint_text = ""
		_hint_streamed = false
		_streamed_obj_text = ""
		_obj_streamed = false
		_rep_body_streamed = false
		_stream_answer_done = false
		_prev_asked_len = asked_arr.size()
		_hint_used_this_session = false
		_prev_observed_for_spectator = -1
		_prev_cards_count_for_spectator = -1
	else:
		if asked_arr.size() > _prev_asked_len:
			for chk_idx in range(_prev_asked_len, asked_arr.size()):
				var chk_entry: Dictionary = asked_arr[chk_idx] if asked_arr[chk_idx] is Dictionary else {}
				var comp_lvl: String = str(chk_entry.get("compliance", ""))
				if comp_lvl == "violation":
					_trigger_violation_juice()
					break
			_prev_asked_len = asked_arr.size()

	# On new interview (different client or advisor), reset scroll to top to avoid staying at previous scroll position
	if str(sess.get("client", {}).get("id", "")) + str(sess.get("playerId", "")) != str(_sess_prev_id):
		_sess_prev_id = str(sess.get("client", {}).get("id", "")) + str(sess.get("playerId", ""))
		_prev_metrics.clear()
		_pred_strip_shown = false
		if _pred_strip_container != null and is_instance_valid(_pred_strip_container):
			_pred_strip_container.visible = false
		if _scroll != null:
			_scroll.set_deferred("scroll_vertical", 0)
	# New step (線索 → 方案 → 異議 → 結果): start at the top; spectators see the top briefly before auto-follow resumes
	var step_key: String = _sess_prev_id + "/" + str(sess.get("step", ""))
	if step_key != _scroll_step_key:
		_scroll_step_key = step_key
		_follow_hold_until = Time.get_ticks_msec() / 1000.0 + 1.2
		_scroll_to_top_after_layout()
	if sess.get("hint") != null:
		_waiting_hint = false

	# Floating indicator for metric changes (e.g. "trust +8" for 1.5s)
	var m_dict: Dictionary = _sess.get("metrics", {}) if _sess.get("metrics") is Dictionary else {}
	if not _prev_metrics.is_empty():
		for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
			var old_v: float = float(_prev_metrics.get(k, 50.0))
			var new_v: float = float(m_dict.get(k, 50.0))
			var delta: int = int(round(new_v - old_v))
			if delta != 0:
				_spawn_metric_delta(METRIC_SHORT.get(k, k), delta)
	_prev_metrics = m_dict.duplicate()

	_build_header(actor_name)
	_build_steps()
	UI.clear(_content)

	# Show the AI coach hint button or hint bar
	_render_coach_hint()

	# Spectator prediction floating strip (shown when spectating other players)
	if not _actor and str(sess.get("step", "")) in ["discover", "plan", "objection"]:
		_render_spectator_prediction()
	else:
		if _pred_strip_container != null and is_instance_valid(_pred_strip_container):
			_pred_strip_container.visible = false

	match str(sess.get("step", "")):
		"discover": _build_discover()
		"plan": _build_plan()
		"objection": _build_objection()
		"result": _build_result()

	if not _actor and str(sess.get("step", "")) in ["discover", "plan", "objection"]:
		var strip_h: float = _get_spectator_pred_strip_height()
		if strip_h > 0.0:
			var pad_ctl := Control.new()
			pad_ctl.name = "PredBottomPadding"
			pad_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pad_ctl.custom_minimum_size = Vector2(0, strip_h)
			_content.add_child(pad_ctl)

	if not _actor:
		_schedule_spectator_auto_follow(str(sess.get("step", "")))

	# Only fade in on scene change (client, advisor, or step); updates within same step redraw directly to avoid flickering
	var scene_key: String = "%s/%s/%s" % [str(sess.get("client", {}).get("id", "")), str(sess.get("playerId", "")), str(sess.get("step", ""))]
	if scene_key != _fade_key:
		_fade_key = scene_key
		UI.fade_in(_content, 0.2)
	UI.pass_wheel(_body)


func _schedule_spectator_auto_follow(step: String) -> void:
	var target_node: Control = null
	match step:
		"discover":
			if _think_label != null and is_instance_valid(_think_label):
				target_node = _think_label
			elif _queued_row != null and is_instance_valid(_queued_row):
				target_node = _queued_row
			elif _pending_row != null and is_instance_valid(_pending_row):
				target_node = _pending_row
			elif _clues_observed != _prev_observed_for_spectator and _clues_control != null and is_instance_valid(_clues_control):
				target_node = _clues_control
			elif _last_client_row != null and is_instance_valid(_last_client_row):
				target_node = _last_client_row
			elif _clues_control != null and is_instance_valid(_clues_control):
				target_node = _clues_control
			_prev_observed_for_spectator = _clues_observed
		"plan":
			var card_count: int = _cards.size()
			if _sess.get("plan") != null and _sess.get("plan") is Dictionary:
				card_count = (_sess.get("plan", {}).get("cards", []) as Array).size()
			if _plan_cards_section != null and is_instance_valid(_plan_cards_section) and _prev_cards_count_for_spectator != -1 and card_count != _prev_cards_count_for_spectator:
				target_node = _plan_cards_section
			elif _plan_alloc_section != null and is_instance_valid(_plan_alloc_section):
				target_node = _plan_alloc_section
			elif _plan_cards_section != null and is_instance_valid(_plan_cards_section):
				target_node = _plan_cards_section
			_prev_cards_count_for_spectator = card_count
		"objection":
			if _objection_section != null and is_instance_valid(_objection_section):
				target_node = _objection_section
		"result":
			if _content != null and _content.get_child_count() > 0:
				target_node = _content.get_child(0) as Control
	if target_node != null:
		_auto_follow_deferred(target_node)


func _spawn_metric_delta(m_name: String, delta: int) -> void:
	if _header_box == null or not is_inside_tree():
		return
	var txt: String = "%s %s%d" % [m_name, "+" if delta > 0 else "", delta]
	var col: Color = UI.GOOD if delta > 0 else UI.BAD
	var p := UI.panel(Color(col.r, col.g, col.b, 0.2), 6, 4)
	p.add_theme_stylebox_override("panel", UI.box(Color(col.r, col.g, col.b, 0.25), 6, col, 4, false))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := UI.label(txt, 12, col)
	p.add_child(lbl)
	_header_box.add_child(p)

	if not Engine.is_editor_hint():
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "position:y", p.position.y - 18.0, 1.5).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(p.queue_free)


func _build_header(actor_name: String) -> void:
	UI.clear(_header_box)
	var is_phone: bool = UI.is_phone_portrait()
	var c: Dictionary = _sess.get("client", {})
	var referral: bool = bool(_sess.get("referral", false))
	var generated: bool = bool(c.get("generated", false))
	var twist: Dictionary = _sess.get("twist", {}) if _sess.get("twist") is Dictionary else {}
	var m_dict: Dictionary = _sess.get("metrics", {}) if _sess.get("metrics") is Dictionary else {}

	var is_phone_land: bool = UI.is_phone_landscape()

	# Client profile card frame
	var pad_val: int = 6 if is_phone_land else (8 if is_phone else 10)
	var card_panel := UI.panel(UI.PANEL, 14, pad_val)
	card_panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 14, UI.GOLD if referral else UI.ACCENT, pad_val))
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Phone landscape compact 3 rows, desktop single row, phone portrait two rows
	if is_phone_land:
		var v_all := UI.vbox(3)
		card_panel.add_child(v_all)

		# Row 1: portrait + name + age/job (ellipsized) + badges
		var row1 := UI.hbox(6)
		row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var avatar_box := _client_portrait(c, 48)
		row1.add_child(avatar_box)

		var c_name: String = str(c.get("name", "客戶"))
		row1.add_child(UI.label(c_name, 14, UI.GOLD if referral else UI.TEXT))

		var c_age: int = int(c.get("age", 30))
		var c_gender: String = str(c.get("gender", ""))
		var c_job: String = str(c.get("job", ""))
		var age_job_lbl := UI.label("｜ %d 歲・%s・%s" % [c_age, c_gender, c_job], 11, UI.MUTED)
		age_job_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		age_job_lbl.clip_text = true
		row1.add_child(age_job_lbl)

		var tag_str: String = str(c.get("tag", ""))
		if tag_str != "":
			var tag_p := UI.panel(UI.PANEL_2, 4, 2)
			tag_p.add_child(UI.label("［%s］" % tag_str, 10, UI.ACCENT_2))
			row1.add_child(tag_p)

		if not twist.is_empty() and twist.get("title") != null:
			var tw_p := UI.panel(Color("#2e2614"), 4, 2)
			tw_p.add_theme_stylebox_override("panel", UI.box(Color("#2e2614"), 4, UI.GOLD, 2, false))
			tw_p.add_child(UI.label("※ " + str(twist.get("title")), 10, UI.GOLD))
			row1.add_child(tw_p)

		var diff: String = str(c.get("difficulty", "normal"))
		var diff_stars: String = "★☆☆" if diff == "easy" else ("★★☆" if diff == "normal" else "★★★")
		var diff_p := UI.panel(Color("#262214"), 4, 2)
		diff_p.add_child(UI.label(diff_stars, 10, UI.GOLD))
		row1.add_child(diff_p)

		if referral:
			var ref_p := UI.panel(Color("#183d2a"), 4, 2)
			ref_p.add_child(UI.label("♥ 轉介紹", 10, UI.GOOD))
			row1.add_child(ref_p)

		if generated:
			var ai_p := UI.panel(UI.PANEL_2, 4, 2)
			ai_p.add_child(UI.label("AI 客戶" if Net.ai_enabled else "規則版客戶", 10, UI.INFO if Net.ai_enabled else UI.MUTED))
			row1.add_child(ai_p)

		if not _actor:
			var obs_p := UI.panel(UI.PANEL_2, 4, 2)
			obs_p.add_child(UI.label("觀摩：%s" % actor_name, 10, UI.GOLD))
			row1.add_child(obs_p)

		v_all.add_child(row1)

		# Row 2: goal (single line, ellipsized)
		var goal_str: String = str(c.get("goal", ""))
		var amount_str: String = str(c.get("amount", ""))
		var full_goal: String = "◎ 核心目標：%s（需求預算：%s）" % [goal_str, amount_str] if amount_str != "" else "◎ 核心目標：%s" % goal_str
		if goal_str == "":
			full_goal = "◎ 進行需求訪談中"
		var goal_lbl := UI.label(full_goal, 11, UI.TEXT)
		goal_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		goal_lbl.clip_text = true
		goal_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_all.add_child(goal_lbl)

		# Row 3: the five metric bars in one row
		_metrics = UI.hbox(8)
		_metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
			var val: float = float(m_dict.get(k, 50.0))
			var col: Color = UI.GOOD if val >= 75 else (UI.OK if val >= 50 else UI.BAD)
			var m_item := UI.hbox(4)
			m_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			m_item.add_child(UI.label(METRIC_SHORT[k], 10, UI.MUTED))
			m_item.add_child(UI.label(str(int(val)), 10, col))
			var b := UI.bar(val, col, 50)
			b.custom_minimum_size = Vector2(40, 6)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			m_item.add_child(b)
			_metrics.add_child(m_item)
		v_all.add_child(_metrics)

	elif not is_phone:
		# Desktop single row: avatar 88px + client info + mini competency bars
		var h_row := UI.hbox(10)
		h_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_panel.add_child(h_row)

		# Avatar 88px desktop
		var avatar_box := _client_portrait(c, 88)
		h_row.add_child(avatar_box)

		# Info column
		var info_v := UI.vbox(2)
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Line 1: name, age, job, tag, dynamic life twist
		# Flow layout: wrap whole tags if overflowing; individual tags don't wrap to prevent single-char columns
		var top_line := HFlowContainer.new()
		top_line.add_theme_constant_override("h_separation", 6)
		top_line.add_theme_constant_override("v_separation", 4)
		top_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c_name: String = str(c.get("name", "客戶"))
		var c_age: int = int(c.get("age", 30))
		var c_gender: String = str(c.get("gender", ""))
		var c_job: String = str(c.get("job", ""))
		top_line.add_child(UI.label(c_name, 16, UI.GOLD if referral else UI.TEXT))
		top_line.add_child(UI.label("｜ %d 歲・%s・%s" % [c_age, c_gender, c_job], 12, UI.MUTED))

		var tag_str: String = str(c.get("tag", ""))
		if tag_str != "":
			var tag_p := UI.chip(UI.PANEL_2, Color(0, 0, 0, 0), 6, 10, 4)
			tag_p.add_child(UI.label("［%s］" % tag_str, 11, UI.ACCENT_2))
			top_line.add_child(tag_p)

		# Dynamic life variable twist tag (twist title)
		if not twist.is_empty() and twist.get("title") != null:
			var tw_p := UI.chip(Color("#2e2614"), UI.GOLD, 6, 10, 4)
			tw_p.add_child(UI.label("※ " + str(twist.get("title")), 11, UI.GOLD))
			top_line.add_child(tw_p)

		var diff: String = str(c.get("difficulty", "normal"))
		var diff_stars: String = "★☆☆" if diff == "easy" else ("★★☆" if diff == "normal" else "★★★")
		var diff_p := UI.chip(Color("#262214"), Color(0, 0, 0, 0), 6, 10, 4)
		diff_p.add_child(UI.label(diff_stars, 11, UI.GOLD))
		top_line.add_child(diff_p)

		if referral:
			var ref_p := UI.chip(Color("#183d2a"), Color(0, 0, 0, 0), 6, 10, 4)
			ref_p.add_child(UI.label("♥ 轉介紹", 11, UI.GOOD))
			top_line.add_child(ref_p)

		if generated:
			var ai_p := UI.chip(UI.PANEL_2, Color(0, 0, 0, 0), 6, 10, 4)
			ai_p.add_child(UI.label("AI 客戶" if Net.ai_enabled else "規則版客戶", 11, UI.INFO if Net.ai_enabled else UI.MUTED))
			top_line.add_child(ai_p)

		info_v.add_child(top_line)

		# Line 2: core goal one-liner
		var goal_str: String = str(c.get("goal", ""))
		var amount_str: String = str(c.get("amount", ""))
		if goal_str != "":
			var goal_lbl := UI.label("◎ 核心目標：%s（需求預算：%s）" % [goal_str, amount_str], 12, UI.TEXT, true)
			info_v.add_child(goal_lbl)

		if not _actor:
			var obs_lbl := UI.label("★ 觀摩學習中（%s 面談）" % actor_name, 11, UI.GOLD, true)
			info_v.add_child(obs_lbl)

		h_row.add_child(info_v)

		# Five competencies as a row of 5 mini bars
		_metrics = UI.hbox(6)
		_metrics.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
			var val: float = float(m_dict.get(k, 50.0))
			var col: Color = UI.GOOD if val >= 75 else (UI.OK if val >= 50 else UI.BAD)
			var m_item := UI.vbox(1)
			m_item.alignment = BoxContainer.ALIGNMENT_CENTER
			var top_h := UI.hbox(2)
			top_h.add_child(UI.label(METRIC_SHORT[k], 10, UI.MUTED))
			top_h.add_child(UI.label(str(int(val)), 10, col))
			m_item.add_child(top_h)
			var b := UI.bar(val, col, 36)
			b.custom_minimum_size = Vector2(36, 6)
			m_item.add_child(b)
			_metrics.add_child(m_item)
		h_row.add_child(_metrics)

	else:
		# Phone portrait two rows: top row avatar 64px and profile, bottom row mini competency bars
		var v_all := UI.vbox(6)
		card_panel.add_child(v_all)

		var top_row := UI.hbox(8)
		var avatar_box := _client_portrait(c, 64)
		top_row.add_child(avatar_box)

		var info_v := UI.vbox(2)
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_row := HFlowContainer.new()
		name_row.add_theme_constant_override("h_separation", 6)
		name_row.add_theme_constant_override("v_separation", 4)
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c_name: String = str(c.get("name", "客戶"))
		name_row.add_child(UI.label(c_name, 15, UI.GOLD if referral else UI.TEXT))
		var tag_str: String = str(c.get("tag", ""))
		if tag_str != "":
			var tag_p := UI.chip(UI.PANEL_2, Color(0, 0, 0, 0), 6, 10, 4)
			tag_p.add_child(UI.label("［%s］" % tag_str, 10, UI.ACCENT_2))
			name_row.add_child(tag_p)
		info_v.add_child(name_row)
		if not twist.is_empty() and twist.get("title") != null:
			var tw_row := HFlowContainer.new()
			tw_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var tw_p := UI.chip(Color("#2e2614"), UI.GOLD, 6, 10, 4)
			tw_p.add_child(UI.label("※ " + str(twist.get("title")), 11, UI.GOLD))
			tw_row.add_child(tw_p)
			info_v.add_child(tw_row)

		var goal_str: String = str(c.get("goal", ""))
		if goal_str != "":
			info_v.add_child(UI.label("◎ 目標：%s" % goal_str, 11, UI.TEXT, true))

		top_row.add_child(info_v)
		v_all.add_child(top_row)

		# Bottom row 5 mini competency bars
		_metrics = UI.hbox(4)
		_metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
			var val: float = float(m_dict.get(k, 50.0))
			var col: Color = UI.GOOD if val >= 75 else (UI.OK if val >= 50 else UI.BAD)
			var m_item := UI.vbox(1)
			m_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var top_h := UI.hbox(2)
			top_h.add_child(UI.label(METRIC_SHORT[k], 9, UI.MUTED))
			top_h.add_child(UI.label(str(int(val)), 9, col))
			m_item.add_child(top_h)
			var b := UI.bar(val, col, 28)
			b.custom_minimum_size = Vector2(28, 5)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			m_item.add_child(b)
			_metrics.add_child(m_item)
		v_all.add_child(_metrics)

	_header_box.add_child(card_panel)


func _build_steps() -> void:
	UI.clear(_steps)
	var cur_step: String = str(_sess.get("step", ""))
	var is_phone: bool = UI.is_phone()
	var step_keys := ["discover", "plan", "objection", "result"]
	# Steps numbered by left icons (✓/●/number); on phones use short names ("1 線索", "2 方案", "3 異議", "4 結果") to fit 480 canvas
	var step_names := ["線索", "方案", "異議", "結果"] if is_phone else ["訪談線索", "方案配置", "異議處理", "結果預演"]
	var cur_idx: int = step_keys.find(cur_step)
	if cur_idx < 0:
		cur_idx = 0

	for i: int in range(4):
		var is_past: bool = i < cur_idx
		var is_curr: bool = i == cur_idx
		var bg_col: Color = UI.ACCENT.darkened(0.2) if is_curr else (UI.PANEL_2 if is_past else UI.PANEL.darkened(0.2))
		var border_col: Color = UI.GOLD if is_curr else (UI.GOOD.darkened(0.4) if is_past else UI.ACCENT.darkened(0.5))

		var s_box := UI.panel(bg_col, 6 if is_phone else 8, 2 if is_phone else 6)
		s_box.add_theme_stylebox_override("panel", UI.box(bg_col, 6 if is_phone else 8, border_col, 2 if is_phone else 6, false))
		s_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sh := UI.hbox(2 if is_phone else 6)
		sh.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon_txt: String = "✓" if is_past else ("●" if is_curr else "%d" % (i + 1))
		var icon_col: Color = UI.GOOD if is_past else (UI.GOLD if is_curr else UI.MUTED)
		sh.add_child(UI.label(icon_txt, 11 if is_phone else 13, icon_col))

		var name_col: Color = Color.WHITE if is_curr else (UI.TEXT if is_past else UI.MUTED)
		sh.add_child(UI.label(step_names[i], 11 if is_phone else 13, name_col))

		s_box.add_child(sh)
		_steps.add_child(s_box)

		if i < 3:
			var arrow := UI.label("→", 10 if is_phone else 13, UI.GOOD if is_past else UI.MUTED)
			_steps.add_child(arrow)


func _render_coach_hint() -> void:
	var hint_str: String = str(_sess.get("hint", "")) if _sess.get("hint") != null else ""
	var hint_used: bool = bool(_sess.get("hintUsed", false))
	var step_str: String = str(_sess.get("step", ""))

	if hint_str != "" or _streamed_hint_text != "":
		_waiting_hint = false
		var hb := UI.panel(UI.INFO.darkened(0.65), 10, 10)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hv := UI.vbox(4)
		hv.add_child(UI.label("★ AI 教練提示：" if Net.ai_enabled else "★ 教練提示：", 15, UI.INFO))
		var display_text := hint_str if hint_str != "" else _streamed_hint_text
		_hint_label = UI.label(display_text, 14, UI.TEXT, true)
		if hint_str != "":
			if not _hint_streamed:
				UI.typewriter(_hint_label, hint_str, false)
				_hint_streamed = true
			else:
				_hint_label.text = hint_str
		hv.add_child(_hint_label)
		hb.add_child(hv)
		_content.add_child(hb)
	elif _actor and not hint_used and step_str in ["discover", "plan", "objection"]:
		var hint_bar: BoxContainer = UI.vbox(4) if UI.is_phone_portrait() else UI.hbox(8)
		hint_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _waiting_hint:
			_hint_label = UI.label("教練思考中……", 14, UI.GOLD, true)
			hint_bar.add_child(_hint_label)
		else:
			var hint_btn := UI.button("求助教練", func():
				_waiting_hint = true
				_streamed_hint_text = ""
				_hint_streamed = false
				Net.act({"type": "hint"})
				refresh(_sess, "")
			, 14, UI.PANEL_2)
			hint_bar.add_child(hint_btn)
			var hint_note: String = "（每場面談限一次）" if Net.ai_enabled else "（每場面談限一次・規則版教練）"
			var hint_desc := UI.label(hint_note, 12 if UI.is_phone_portrait() else 13, UI.MUTED, true)
			hint_bar.add_child(hint_desc)
		_content.add_child(hint_bar)


func _render_spectator_prediction() -> void:
	if _pred_strip_container == null or not is_instance_valid(_pred_strip_container):
		_build_spectator_prediction_overlay()
	if _pred_strip == null or not is_instance_valid(_pred_strip):
		return

	var preds: Dictionary = _sess.get("predictions", {}) if _sess.get("predictions") is Dictionary else {}
	var mine_pred: Variant = preds.get("mine")
	var has_predicted: bool = mine_pred != null and str(mine_pred) != ""

	var pad_x: int = 8 if UI.is_phone_portrait() else 12
	var pad_b: int = 8 if UI.is_phone_portrait() else 10
	_pred_strip_container.add_theme_constant_override("margin_left", pad_x)
	_pred_strip_container.add_theme_constant_override("margin_right", pad_x)
	_pred_strip_container.add_theme_constant_override("margin_bottom", pad_b)

	UI.clear(_pred_strip)

	if has_predicted:
		# After predicting: collapse to a small pill 「已預測［A］· N 人參與」 (still floating, no buttons)
		var pill_sb := UI.box(UI.PANEL_2, 14, Color(-1, -1, -1, -1), 8, true)
		_pred_strip.add_theme_stylebox_override("panel", pill_sb)
		var pill_h := UI.hbox(6)
		pill_h.mouse_filter = Control.MOUSE_FILTER_PASS
		var count_val: int = int(preds.get("count", 1))
		var pill_lbl := UI.label("已預測［%s］· %d 人參與" % [str(mine_pred), count_val], 12 if UI.is_phone_portrait() else 13, UI.GOLD)
		pill_h.add_child(pill_lbl)
		_pred_strip.add_child(pill_h)
	else:
		# Before predicting: compact one-line strip 「旁觀競猜：猜評級，猜中聲望 +2」 + S A B C buttons
		var strip_sb := UI.box(UI.PANEL_2, 12, Color(-1, -1, -1, -1), 8, true)
		_pred_strip.add_theme_stylebox_override("panel", strip_sb)
		var is_narrow: bool = UI.is_phone_portrait()
		var box_c: BoxContainer = UI.vbox(4) if is_narrow else UI.hbox(8)
		box_c.mouse_filter = Control.MOUSE_FILTER_PASS
		var prompt_lbl := UI.label("旁觀競猜：猜評級，猜中聲望 +2", 12 if is_narrow else 13, UI.GOLD)
		box_c.add_child(prompt_lbl)

		var btn_row := UI.hbox(6)
		btn_row.mouse_filter = Control.MOUSE_FILTER_PASS
		if is_narrow:
			btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		for g: String in ["S", "A", "B", "C"]:
			var grade_val: String = g
			var btn := UI.button(grade_val, func():
				if not Engine.is_editor_hint():
					Net.send({"t": "predict", "grade": grade_val})
			, 13, UI.PANEL)
			btn.custom_minimum_size = Vector2(36, 30)
			btn_row.add_child(btn)
		box_c.add_child(btn_row)
		_pred_strip.add_child(box_c)

	_pred_strip_container.visible = true

	if not _pred_strip_shown:
		_pred_strip_shown = true
		UI.pop_in(_pred_strip, 0.22)


func _section(title: String) -> VBoxContainer:
	var p := UI.panel(UI.PANEL, 12, 10 if UI.is_phone_portrait() else (12 if UI.is_portrait() else 14))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6 if UI.is_phone_portrait() else 8)
	p.add_child(v)
	v.add_child(UI.label(title, 15 if UI.is_phone_portrait() else (16 if UI.is_portrait() else 17), UI.ACCENT_2, true))
	_content.add_child(p)
	return v


# ───────── ① Clues and Interview ─────────

func _build_discover() -> void:
	var clues: Array = _sess.get("clues", [])
	var observed: int = 0
	for cl: Dictionary in clues:
		if cl.get("observed", false): observed += 1

	var c_dict: Dictionary = _sess.get("client", {})
	var scene_path: String = UI.client_scene_path(c_dict)

	if scene_path != "":
		_build_scene_hotspots(scene_path, clues, observed)
	else:
		_build_clues_grid(clues, observed)

	# ───────── Dialogue Thread ─────────
	var dv := _section("◎ 需求訪談對話串")
	var c_short: String = str(c_dict.get("short", c_dict.get("name", "客戶")))
	var twist_dict: Dictionary = _sess.get("twist", {}) if _sess.get("twist") is Dictionary else {}
	var has_twist: bool = not twist_dict.is_empty() and twist_dict.get("hint") != null

	# Client opening message
	var open_row := UI.hbox(8)
	open_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_row.add_child(_client_portrait(c_dict, 36, true))

	var open_v := UI.vbox(2)
	open_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var open_h := UI.hbox(6)
	open_h.add_child(UI.label(c_short, 13, UI.TEXT))
	var emo_tag: String = "情境透露" if has_twist else "開場"
	var emo_p := UI.panel(UI.PANEL_2, 4, 2)
	emo_p.add_child(UI.label("［%s］" % emo_tag, 11, UI.ACCENT_2))
	open_h.add_child(emo_p)
	open_v.add_child(open_h)

	var open_bubble := UI.panel(UI.PANEL_2, 10, 8)
	open_bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var open_txt: String = str(twist_dict.get("hint", "")) if has_twist else str(c_dict.get("quote", "您好，想了解一下您能提供哪些規劃建議……"))
	open_bubble.add_child(UI.label(open_txt, 14, UI.TEXT, true))
	open_v.add_child(open_bubble)
	open_row.add_child(open_v)
	dv.add_child(open_row)

	# Dialogue history
	var asked: Array = _sess.get("asked", [])
	var idx: int = 0
	_last_client_row = null
	for a: Dictionary in asked:
		var q_text: String = str(a.get("question", ""))
		var ans_text: String = str(a.get("answer", ""))
		var a_idx: int = idx

		# 1. Advisor statement (right side, soft dark bubble)
		var cons_row := UI.hbox(8)
		cons_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cons_pad := UI.spacer()
		# Phones: the advisor column takes ~80% of the row so the coach note is not squeezed into a narrow column
		if UI.is_phone():
			cons_pad.size_flags_stretch_ratio = 0.25
		cons_row.add_child(cons_pad)

		var cons_v := UI.vbox(3)
		cons_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var cons_bubble := UI.panel(UI.PANEL_2.lightened(0.06), 10, 8)
		cons_bubble.add_theme_stylebox_override("panel", UI.box(UI.PANEL_2.lightened(0.06), 10, UI.ACCENT.lightened(0.12), 8, false))
		var q_lbl := UI.label(q_text, 14, Color.WHITE, true)
		cons_bubble.add_child(q_lbl)
		cons_v.add_child(cons_bubble)

		# Compliance indicator and short review
		var comp_level: String = str(a.get("compliance", ""))
		if comp_level == "" or comp_level == "null":
			comp_level = Compliance.check(q_text).level

		var comp_issues: Array = a.get("issues", []) as Array if a.get("issues") != null else []
		if comp_issues.is_empty():
			comp_issues = Compliance.check(q_text).issues

		if comp_level == "violation":
			var is_exp: bool = bool(_expanded_compliance_issues.get(a_idx, true))
			if is_exp:
				var viol_card := UI.panel(Color("#260e0e"), 10, 10)
				viol_card.add_theme_stylebox_override("panel", UI.box(Color("#260e0e"), 10, UI.BAD, 8, false))
				var vv := UI.vbox(4)
				var v_head := UI.hbox(6)
				v_head.add_child(UI.label("× 踩到合規紅燈（評級上限 C）", 13, UI.BAD))
				v_head.add_child(UI.spacer())
				var collapse_btn := UI.button("收合 ▲", func():
					_expanded_compliance_issues[a_idx] = false
					refresh(_sess, "")
				, 11, UI.PANEL_2)
				v_head.add_child(collapse_btn)
				vv.add_child(v_head)

				for iss: Dictionary in comp_issues:
					var r_str: String = str(iss.get("rule", ""))
					if r_str != "":
						vv.add_child(UI.label("規範：%s" % r_str, 12, Color("#ffb3b3"), true))
					var q_str: String = str(iss.get("quote", ""))
					if q_str != "":
						vv.add_child(UI.label("原句：「%s」" % q_str, 12, UI.GOLD, true))
					var s_str: String = str(iss.get("suggestion", ""))
					if s_str != "":
						vv.add_child(UI.label("改寫建議：%s" % s_str, 12, UI.ACCENT_2, true))
				viol_card.add_child(vv)
				cons_v.add_child(viol_card)
			else:
				var comp_h := UI.hbox(6)
				comp_h.add_child(UI.spacer())
				var badge_p := UI.chip(Color(UI.BAD.r, UI.BAD.g, UI.BAD.b, 0.18), UI.BAD, 4, 10, 4)
				badge_p.add_child(UI.label("× 違規", 11, UI.BAD))
				comp_h.add_child(badge_p)
				var exp_btn := UI.button("［查看合規分析 ▼］", func():
					_expanded_compliance_issues[a_idx] = true
					refresh(_sess, "")
				, 11, UI.PANEL_2)
				comp_h.add_child(exp_btn)
				cons_v.add_child(comp_h)
		else:
			var comp_h := UI.hbox(6)
			comp_h.add_child(UI.spacer())
			var badge_col: Color = Compliance.level_color(comp_level)
			var badge_p := UI.chip(Color(badge_col.r, badge_col.g, badge_col.b, 0.18), badge_col, 4, 10, 4)
			badge_p.add_child(UI.label(Compliance.level_tag(comp_level), 11, badge_col))
			comp_h.add_child(badge_p)

			if comp_level == "warning" and not comp_issues.is_empty():
				var is_exp: bool = bool(_expanded_compliance_issues.get(a_idx, false))
				var exp_btn := UI.button("［收合 ▲］" if is_exp else "［查看合規分析 ▼］", func():
					_expanded_compliance_issues[a_idx] = not bool(_expanded_compliance_issues.get(a_idx, false))
					refresh(_sess, "")
				, 11, UI.PANEL_2)
				comp_h.add_child(exp_btn)
			cons_v.add_child(comp_h)

			if comp_level == "warning" and bool(_expanded_compliance_issues.get(a_idx, false)) and not comp_issues.is_empty():
				var issues_p := UI.panel(UI.PANEL_2, 8, 8)
				issues_p.add_theme_stylebox_override("panel", UI.box(UI.PANEL_2, 8, badge_col, 6, false))
				var iv_item := UI.vbox(4)
				for iss: Dictionary in comp_issues:
					var q_str: String = str(iss.get("quote", ""))
					if q_str != "":
						iv_item.add_child(UI.label("原句：「%s」" % q_str, 12, UI.GOLD, true))
					var r_str: String = str(iss.get("rule", ""))
					if r_str != "":
						iv_item.add_child(UI.label("規範：%s" % r_str, 12, UI.MUTED, true))
					var s_str: String = str(iss.get("suggestion", ""))
					if s_str != "":
						iv_item.add_child(UI.label("改寫建議：%s" % s_str, 12, UI.ACCENT_2, true))
				issues_p.add_child(iv_item)
				cons_v.add_child(issues_p)

		# Coach tip
		var coach_str: String = str(a.get("coachTip", a.get("note", "")))
		if coach_str != "" and coach_str != "null":
			var c_lbl := UI.label("教練短評：" + coach_str, 12, UI.MUTED, true)
			cons_v.add_child(c_lbl)

		cons_row.add_child(cons_v)
		dv.add_child(cons_row)

		# 2. Client response (left side, light bubble)
		var client_row := UI.hbox(8)
		client_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c_port := _client_portrait(c_dict, 40, true)
		c_port.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		client_row.add_child(c_port)

		var client_v := UI.vbox(2)
		client_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var c_head := UI.hbox(6)
		c_head.add_child(UI.label(c_short, 13, UI.TEXT))
		var emo_str: String = str(a.get("emotion", ""))
		if emo_str != "" and emo_str != "null":
			var ep := UI.chip(UI.PANEL_2, Color(0, 0, 0, 0), 4, 10, 4)
			var emo_names := {"receptive": "願意多聊", "neutral": "平靜", "defensive": "有點防備", "impatient": "不耐煩"}
			var emo_cols := {"receptive": UI.GOOD, "neutral": UI.INFO, "defensive": UI.OK, "impatient": UI.BAD}
			ep.add_child(UI.label("［%s］" % str(emo_names.get(emo_str, emo_str)), 11, emo_cols.get(emo_str, UI.INFO)))
			c_head.add_child(ep)
		client_v.add_child(c_head)

		var client_bubble := UI.panel(UI.PANEL_2, 10, 8)
		client_bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		client_bubble.add_child(UI.label(ans_text, 14, UI.TEXT, true))
		client_v.add_child(client_bubble)

		if a.get("key") != null and str(a.get("key", "")) != "":
			client_v.add_child(UI.label("※ 掌握線索：" + str(a.get("key", "")), 12, UI.GOLD, true))

		client_row.add_child(client_v)
		dv.add_child(client_row)
		_last_client_row = client_row

		idx += 1

	# Local real-time radar statement (sending)
	_pending_row = null
	if _waiting_ai and not _pending_talk.is_empty():
		var pend_row := UI.hbox(8)
		pend_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pend_pad := UI.spacer()
		if UI.is_phone():
			pend_pad.size_flags_stretch_ratio = 0.25
		pend_row.add_child(pend_pad)

		var pend_v := UI.vbox(3)
		pend_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var pend_bubble := UI.panel(UI.ACCENT.darkened(0.2), 10, 8)
		pend_bubble.add_theme_stylebox_override("panel", UI.box(UI.ACCENT.darkened(0.2), 10, UI.ACCENT_2, 8, false))
		pend_bubble.add_child(UI.label(str(_pending_talk.get("text", "")), 14, Color.WHITE, true))
		pend_v.add_child(pend_bubble)

		var pend_h := UI.hbox(6)
		pend_h.add_child(UI.spacer())
		var pend_lvl: String = str(_pending_talk.get("level", "pass"))
		var pend_col: Color = Compliance.level_color(pend_lvl)
		var p_badge := UI.chip(Color(pend_col.r, pend_col.g, pend_col.b, 0.18), pend_col, 4, 10, 4)
		p_badge.add_child(UI.label(Compliance.level_tag(pend_lvl), 11, pend_col))
		pend_h.add_child(p_badge)
		if not _stream_answer_done:
			pend_h.add_child(UI.label("（送出中……）", 11, UI.MUTED))
		pend_v.add_child(pend_h)

		if _stream_answer_done:
			pend_v.add_child(UI.label("教練短評整理中……", 12, UI.MUTED, true))

		pend_row.add_child(pend_v)
		dv.add_child(pend_row)
		_pending_row = pend_row

	# Waiting for AI typing animation
	_think_label = null
	if _waiting_ai or bool(_sess.get("aiBusy", false)) or _streaming():
		var think_row := UI.hbox(8)
		think_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t_port := _client_portrait(c_dict, 40, true)
		t_port.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		think_row.add_child(t_port)

		var think_v := UI.vbox(2)
		think_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		think_v.add_child(UI.label(c_short, 13, UI.TEXT))

		var think_bubble := UI.panel(UI.PANEL_2, 10, 8)
		think_bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Streaming: client answer appears word by word; shows "thinking" before first chunk
		_think_label = UI.label(_stream_text if (_streaming() or _stream_answer_done) else "客戶思考中……", 14, UI.TEXT if (_streaming() or _stream_answer_done) else UI.GOLD, true)
		think_bubble.add_child(_think_label)
		think_v.add_child(think_bubble)

		think_row.add_child(think_v)
		dv.add_child(think_row)

	# Queued advisor statement (waiting for previous exchange to finish)
	_queued_row = null
	if not _queued_talk.is_empty():
		var q_row := UI.hbox(8)
		q_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var q_pad := UI.spacer()
		if UI.is_phone():
			q_pad.size_flags_stretch_ratio = 0.25
		q_row.add_child(q_pad)

		var q_v := UI.vbox(3)
		q_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var q_bubble := UI.panel(UI.PANEL_2.lightened(0.06), 10, 8)
		q_bubble.add_theme_stylebox_override("panel", UI.box(UI.PANEL_2.lightened(0.06), 10, UI.ACCENT.lightened(0.12), 8, false))
		q_bubble.add_child(UI.label(str(_queued_talk.get("text", "")), 14, Color.WHITE, true))
		q_v.add_child(q_bubble)

		var q_h := UI.hbox(6)
		q_h.add_child(UI.spacer())
		var q_lvl: String = str(_queued_talk.get("level", "pass"))
		var q_col: Color = Compliance.level_color(q_lvl)
		var q_badge := UI.chip(Color(q_col.r, q_col.g, q_col.b, 0.18), q_col, 4, 10, 4)
		q_badge.add_child(UI.label(Compliance.level_tag(q_lvl), 11, q_col))
		q_h.add_child(q_badge)
		q_h.add_child(UI.label("（排隊中）", 11, UI.MUTED))
		q_v.add_child(q_h)

		q_row.add_child(q_v)
		dv.add_child(q_row)
		_queued_row = q_row

	# ───────── Bottom Input Area ─────────
	var talk_left: int = int(_sess.get("talkLeft", 3))
	var iv := _section("◎ 顧問發言與提問（剩 %d 輪）" % talk_left)

	var sub_h := UI.hbox(6)
	sub_h.add_child(UI.label("5 個建議問句（點選直接發問）：", 13, UI.MUTED))
	sub_h.add_child(UI.spacer())
	sub_h.add_child(UI.label("AI 對話模式" if Net.ai_enabled else "規則版對話模式", 11, UI.INFO if Net.ai_enabled else UI.MUTED))
	iv.add_child(sub_h)

	var questions_src: Array = Net.static_data.get("questions", []) if Net.static_data.get("questions") != null else []
	if questions_src.is_empty():
		questions_src = STANDARD_QUESTIONS

	var asked_qids: Array = asked.map(func(x: Dictionary): return str(x.get("qid", "")))
	var covered_qids: Array = _sess.get("covered", []) if _sess.get("covered") != null else []
	var pending_qid: String = str(_pending_talk.get("suggested", ""))
	var queued_qid: String = str(_queued_talk.get("suggested", ""))

	var is_waiting: bool = _waiting_ai or bool(_sess.get("aiBusy", false)) or _streaming()
	var can_queue: bool = is_waiting and _stream_answer_done and _queued_talk.is_empty() and talk_left > 1
	var can_act: bool = not is_waiting and talk_left > 0 and _queued_talk.is_empty()
	var can_talk: bool = _actor and (can_act or can_queue)

	for q_item in questions_src:
		var qid: String = str(q_item.get("id", ""))
		var qtext: String = str(q_item.get("text", ""))
		var was_asked: bool = (qid in asked_qids) or (qid in covered_qids) or (qid != "" and (qid == pending_qid or qid == queued_qid))

		var b := UI.option_button(qtext, func():
			_send_talk(qtext, qid)
		)
		b.disabled = not can_talk or was_asked
		if was_asked:
			b.text = UI.glue("✓ " + qtext)
		iv.add_child(b)

	# Free-form input row
	if _actor:
		if talk_left > 0:
			iv.add_child(UI.label("自由提問／溝通：", 13, UI.MUTED))
			var ti := UI.text_input("輸入你想向客戶詢問或溝通的話語……", func(t: String):
				_send_talk(t, "")
			, 150)
			for child in ti.get_children():
				if child is LineEdit:
					child.editable = can_talk
				elif child is Button:
					child.disabled = not can_talk
			iv.add_child(ti)
		else:
			iv.add_child(UI.label("3 輪對話已完成，請點選下方進入方案配置", 13, UI.GOLD, true))
	else:
		iv.add_child(UI.label("（只有面談中的顧問可以發言）", 13, UI.MUTED))

	if _actor and talk_left > 0:
		Tutorial.show_spotlight(self, iv, "talk", "可以點建議提問，也可以自己打字；違規說法會被合規雷達抓到", func(): refresh(_sess, ""))

	# Proceed to plan allocation button
	var busy: bool = bool(_sess.get("aiBusy", false)) or _waiting_ai or _streaming() or not _queued_talk.is_empty()
	var ready_to_plan: bool = (bool(_sess.get("ready", false)) or talk_left <= 0) and not busy
	var go := UI.button("進入方案配置 →", func(): Net.act({"type": "to_plan"}), 18)
	go.disabled = not _actor or not ready_to_plan
	_content.add_child(go)


func _build_clues_grid(clues: Array, observed: int) -> void:
	_clues_observed = observed
	var cv := _section("◎ 觀察線索（%d/3）— 場景中有 3 個需求線索與 1 個干擾物" % observed)
	_clues_control = cv.get_parent() as Control
	var grid := GridContainer.new()
	grid.columns = 1 if UI.is_phone_portrait() else 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var i: int = 0
	for cl: Dictionary in clues:
		var idx: int = i
		if cl.get("observed", false):
			var real: bool = bool(cl.get("real", false))
			var p := UI.panel(UI.GOOD.darkened(0.65) if real else UI.PANEL_2, 10, 10)
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var v := UI.vbox(2)
			v.add_child(UI.label(("✓ " if real else "× ") + str(cl.get("title", "")), 15, UI.GOOD if real else UI.MUTED, true))
			v.add_child(UI.label(str(cl.get("detail", "")), 13, UI.TEXT, true))
			if real:
				v.add_child(UI.label("→ " + str(cl.get("fact", "")), 13, UI.GOLD, true))
			p.add_child(v)
			grid.add_child(p)
		else:
			var b := UI.option_button("？ " + str(cl.get("title", "")), func(): Net.act({"type": "observe", "index": idx}))
			b.set_meta("hotspot_index", idx)
			b.disabled = not _actor or observed >= 3
			grid.add_child(b)
		i += 1
	cv.add_child(grid)


func _build_scene_hotspots(scene_path: String, clues: Array, observed: int) -> void:
	_clues_observed = observed
	var cv := _section("◎ 生活場景探索（%d/3）— 共 3 個需求線索與 1 個干擾物" % observed)
	_clues_control = cv.get_parent() as Control
	var toggle_h := UI.hbox(8)
	toggle_h.add_child(UI.spacer())
	var hint_btn := UI.button("提示", func():
		_flashing_hotspots = true
		_hint_used_this_session = true
		refresh(_sess, "")
		get_tree().create_timer(1.5).timeout.connect(func():
			_flashing_hotspots = false
			if is_inside_tree() and not _sess.is_empty():
				refresh(_sess, "")
		)
	, 11 if UI.is_phone_portrait() else 12, UI.PANEL_2)
	hint_btn.disabled = not _actor or observed >= 3 or _flashing_hotspots
	toggle_h.add_child(hint_btn)
	var toggle_btn := UI.button("收合為縮圖 ▲" if not _scene_collapsed else "展開場景熱點 ▼", func():
		_scene_collapsed = not _scene_collapsed
		refresh(_sess, "")
	, 11 if UI.is_phone_portrait() else 12, UI.PANEL_2)
	toggle_h.add_child(toggle_btn)
	cv.add_child(toggle_h)

	if _scene_collapsed:
		var thumb_card := UI.panel(UI.PANEL_2, 8, 8)
		thumb_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var th := UI.hbox(10)
		var tr := TextureRect.new()
		tr.texture = load(scene_path)
		tr.custom_minimum_size = Vector2(110, 62)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		th.add_child(tr)

		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UI.label("生活場景（縮圖模式・已調查 %d/3 個線索）" % observed, 13, UI.TEXT))
		var obs_titles: Array = []
		for cl: Dictionary in clues:
			if cl.get("observed", false):
				obs_titles.append(str(cl.get("title", "")))
		if not obs_titles.is_empty():
			tv.add_child(UI.label("已發現：" + "、".join(obs_titles), 12, UI.MUTED, true))
		else:
			tv.add_child(UI.label("尚未發現線索，點擊右上按鈕展開搜尋熱點", 12, UI.MUTED, true))
		th.add_child(tv)
		thumb_card.add_child(th)
		cv.add_child(thumb_card)
		return

	# Use AspectRatioContainer locked to 16:9 to guarantee hotspot boxes align 1:1 with illustration objects across resolutions
	# Display at native aspect ratio (neither 16:9 nor 1:1 distorted) so percentage hotspot coords align with objects
	var scene_tex: Texture2D = load(scene_path)
	var img_ratio: float = 16.0 / 9.0
	if scene_tex and scene_tex.get_height() > 0:
		img_ratio = float(scene_tex.get_width()) / float(scene_tex.get_height())
	var aspect_h: float = 240.0 if UI.is_phone_portrait() else (320.0 if UI.is_portrait() else 380.0)
	# Square images appear too small at default height; increase height for easier clicking
	if img_ratio < 1.4:
		aspect_h *= 1.35
	var arc := AspectRatioContainer.new()
	arc.ratio = img_ratio
	arc.stretch_mode = AspectRatioContainer.STRETCH_FIT
	arc.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	arc.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arc.custom_minimum_size = Vector2(0, aspect_h)
	arc.mouse_filter = Control.MOUSE_FILTER_PASS

	var scene_box := Control.new()
	scene_box.clip_contents = true
	# Default STOP consumes wheel events, preventing outer ScrollContainer from scrolling
	scene_box.mouse_filter = Control.MOUSE_FILTER_PASS
	arc.add_child(scene_box)

	var tex := TextureRect.new()
	tex.texture = scene_tex
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_box.add_child(tex)

	var i: int = 0
	for cl: Dictionary in clues:
		var idx: int = i
		var is_obs: bool = bool(cl.get("observed", false))
		var spot: Dictionary = cl.get("spot", {}) if cl.get("spot") is Dictionary else {}
		var sx: float = float(spot.get("x", 10.0 + i * 22.0)) / 100.0
		var sy: float = float(spot.get("y", 20.0 + (i % 2) * 30.0)) / 100.0
		var sw: float = float(spot.get("w", 18.0)) / 100.0
		var sh: float = float(spot.get("h", 20.0)) / 100.0

		var btn := Button.new()
		btn.anchor_left = sx
		btn.anchor_top = sy
		btn.anchor_right = sx + sw
		btn.anchor_bottom = sy + sh
		btn.offset_left = 0
		btn.offset_top = 0
		btn.offset_right = 0
		btn.offset_bottom = 0

		# Do not set flat: flat buttons omit stylebox, making borders disappear completely
		btn.text = ""
		btn.set_meta("hotspot_index", idx)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS

		if is_obs:
			var real: bool = bool(cl.get("real", false))
			var border_col: Color = UI.GOOD if real else UI.BAD
			var fill_col: Color = Color(border_col.r, border_col.g, border_col.b, 0.14)

			var obs_sb := UI.box(fill_col, 6, border_col, 2)
			btn.add_theme_stylebox_override("normal", obs_sb)
			btn.add_theme_stylebox_override("hover", obs_sb)
			btn.add_theme_stylebox_override("pressed", obs_sb)
			btn.add_theme_stylebox_override("disabled", obs_sb)
			btn.add_theme_stylebox_override("focus", obs_sb)
			btn.disabled = true

			# Put tag as small label at top edge so it does not obscure illustration objects
			var tag_p := PanelContainer.new()
			var tag_sb := UI.box(border_col.darkened(0.2), 4, Color(0, 0, 0, 0), 2)
			tag_p.add_theme_stylebox_override("panel", tag_sb)
			tag_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag_p.position = Vector2(2, 2)
			var tag_lbl := UI.label("✓ 線索" if real else "× 干擾", 10, Color.WHITE)
			tag_p.add_child(tag_lbl)
			btn.add_child(tag_p)
		else:
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var unobs_fill: Color = Color(0.95, 0.75, 0.3, 0.15) if _flashing_hotspots else Color(0, 0, 0, 0)
			var unobs_border: Color = UI.GOLD if _flashing_hotspots else Color(0, 0, 0, 0)
			var unobs_normal := UI.box(unobs_fill, 6, unobs_border, 2 if _flashing_hotspots else 0)
			var unobs_hover := UI.box(Color(1, 1, 1, 0.05), 6, Color(1, 1, 1, 0.4), 1)
			var unobs_disabled := UI.box(Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 0)

			btn.add_theme_stylebox_override("normal", unobs_normal)
			btn.add_theme_stylebox_override("hover", unobs_hover)
			btn.add_theme_stylebox_override("pressed", unobs_hover)
			btn.add_theme_stylebox_override("disabled", unobs_disabled)
			btn.add_theme_stylebox_override("focus", unobs_normal)

			btn.disabled = not _actor or observed >= 3
			btn.pressed.connect(func():
				Net.act({"type": "observe", "index": idx})
			)
		scene_box.add_child(btn)
		i += 1

	cv.add_child(arc)
	if _actor and observed < 3:
		Tutorial.show_spotlight(self, arc, "discover", "點擊畫面中可疑的物品，找出客戶沒說出口的需求", func(): refresh(_sess, ""))

	var obs_list := UI.vbox(4)
	var any_obs: bool = false
	for cl: Dictionary in clues:
		if cl.get("observed", false):
			any_obs = true
			var real: bool = bool(cl.get("real", false))
			var p := UI.panel(UI.GOOD.darkened(0.65) if real else UI.PANEL_2, 8, 8)
			var bv := UI.vbox(2)
			bv.add_child(UI.label(("✓ " if real else "× ") + str(cl.get("title", "")), 14, UI.GOOD if real else UI.MUTED, true))
			bv.add_child(UI.label(str(cl.get("detail", "")), 13, UI.TEXT, true))
			if real and cl.get("fact") != null and str(cl.get("fact", "")) != "":
				bv.add_child(UI.label("→ " + str(cl.get("fact", "")), 13, UI.GOLD, true))
			p.add_child(bv)
			obs_list.add_child(p)
	if any_obs:
		cv.add_child(obs_list)
	elif _actor:
		cv.add_child(UI.label("提示：在生活場景中仔細觀察，點擊可疑物品找出需求線索！", 13, UI.MUTED, true))


# ───────── ② Plan Allocation ─────────

func _build_plan() -> void:
	var key: String = str(_sess.get("client", {}).get("id", ""))
	if key != _plan_key:
		_plan_key = key
		_alloc = {"cash": 4, "protect": 3, "growth": 3}
		_cards = []
	_plan_ui = {"rows": {}, "cards": {}}
	var av := _section("")
	_plan_alloc_section = av.get_parent() as Control
	_plan_ui["alloc_title"] = av.get_child(0)
	if _actor:
		Tutorial.show_spotlight(self, av, "plan", "10 枚資源幣代表客戶每月可運用的錢；保障卡選 2–3 張", func(): refresh(_sess, ""))
	var hints := {"cash": "可支撐必要支出、避免低點賣出", "protect": "承接傷病、意外與收入中斷", "growth": "長期目標的資產累積"}
	var is_narrow: bool = UI.is_phone_portrait()
	for r: String in ["cash", "protect", "growth"]:
		var res: String = r
		var minus := UI.button("－", func(): _bump(res, -1), 16, UI.PANEL_2)
		minus.custom_minimum_size = Vector2(44, 44)
		minus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var value := UI.label("", 19 if is_narrow else 20, UI.GOLD)
		value.custom_minimum_size = Vector2(24 if is_narrow else 26, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var plus := UI.button("＋", func(): _bump(res, 1), 16, UI.PANEL_2)
		plus.custom_minimum_size = Vector2(44, 44)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# Tray containing the round chips in resource color
		var tray := PanelContainer.new()
		var tray_sb := StyleBoxFlat.new()
		tray_sb.bg_color = Color("#091714")
		tray_sb.set_corner_radius_all(8)
		tray_sb.border_color = Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.25)
		tray_sb.set_border_width_all(1)
		tray_sb.content_margin_left = 8
		tray_sb.content_margin_right = 8
		tray_sb.content_margin_top = 4
		tray_sb.content_margin_bottom = 4
		tray.add_theme_stylebox_override("panel", tray_sb)
		tray.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var coins := UI.label("", 15 if is_narrow else 16, RES_COLORS[r])
		coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tray.add_child(coins)

		if UI.is_portrait():
			var row_v := UI.vbox(2)
			row_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var h := UI.hbox(8)
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(UI.label(UI.RES_NAMES[r], 15 if is_narrow else 16, UI.TEXT))
			h.add_child(UI.spacer())
			h.add_child(minus)
			h.add_child(value)
			h.add_child(plus)
			tray.custom_minimum_size = Vector2(48 if is_narrow else 80, 0)
			h.add_child(tray)
			row_v.add_child(h)
			var desc := UI.label(hints[r], 11 if is_narrow else 12, UI.MUTED, true)
			row_v.add_child(desc)
			av.add_child(row_v)
		else:
			var h := UI.hbox(8)
			var nm := UI.vbox(0)
			nm.custom_minimum_size = Vector2(220, 0)
			nm.add_child(UI.label(UI.RES_NAMES[r], 16, UI.TEXT, true))
			nm.add_child(UI.label(hints[r], 12, UI.MUTED, true))
			h.add_child(nm)
			h.add_child(minus)
			h.add_child(value)
			h.add_child(plus)
			tray.custom_minimum_size = Vector2(120, 0)
			h.add_child(tray)
			av.add_child(h)

		_plan_ui["rows"][r] = {"minus": minus, "plus": plus, "value": value, "coins": coins, "tray": tray}

	var cv := _section("")
	_plan_cards_section = cv.get_parent() as Control
	_plan_ui["cards_title"] = cv.get_child(0)
	var grid := GridContainer.new()
	# Phone portrait 480 width uses 1 column, tablet portrait 2 columns, landscape 3 columns
	grid.columns = 1 if UI.is_phone_portrait() else (2 if UI.is_portrait() else 3)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for card: Dictionary in Net.static_data.get("cards", []):
		var cid: String = str(card.get("id", ""))
		var cat_col: Color = CARD_CATEGORY_COLORS.get(cid, UI.ACCENT_2)
		var b := UI.option_button("", func(): _toggle(cid))
		b.clip_text = false
		var card_w: float = 130.0 if not UI.is_phone_portrait() else 240.0
		b.custom_minimum_size = Vector2(card_w, 0)
		# Native text stays only for automation; keep it tiny so it does not inflate the card
		b.add_theme_font_size_override("font_size", 1)
		b.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		b.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		b.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
		b.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		b.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
		b.disabled = not _actor
		b.set_meta("card", card)

		# Playing card top category colour band
		var band := Panel.new()
		band.name = "Band"
		var band_sb := StyleBoxFlat.new()
		band_sb.bg_color = cat_col
		band_sb.set_corner_radius_all(3)
		band_sb.anti_aliasing = true
		band.add_theme_stylebox_override("panel", band_sb)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.anchor_left = 0.0
		band.anchor_right = 1.0
		band.anchor_top = 0.0
		band.anchor_bottom = 0.0
		band.offset_left = 12.0
		band.offset_right = -12.0
		band.offset_top = 5.0
		band.offset_bottom = 10.0
		b.add_child(band)

		var mc := MarginContainer.new()
		mc.name = "Margin"
		mc.set_anchors_preset(Control.PRESET_FULL_RECT)
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_theme_constant_override("margin_left", 10)
		mc.add_theme_constant_override("margin_right", 10)
		mc.add_theme_constant_override("margin_top", 12)
		mc.add_theme_constant_override("margin_bottom", 10)
		b.add_child(mc)

		var v := UI.vbox(3)
		v.name = "VBox"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(v)

		var title_lbl := UI.label("", 14, UI.TEXT, true)
		title_lbl.name = "Title"
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(title_lbl)

		var detail_lbl := UI.label("", 12, UI.MUTED, true)
		detail_lbl.name = "Detail"
		detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(detail_lbl)

		grid.add_child(b)
		# Card height follows the wrapped text at the card's real width (re-fit whenever it resizes)
		b.resized.connect(_fit_card.bind(b), CONNECT_DEFERRED)
		_plan_ui["cards"][cid] = b
	cv.add_child(grid)

	if not _actor:
		_content.add_child(UI.label("（等待顧問提交方案……）", 15, UI.MUTED))
	else:
		var submit := UI.button("提交方案 →", func(): Net.act({"type": "plan", "alloc": _alloc, "cards": _cards}), 18)
		_content.add_child(submit)
		_plan_ui["submit"] = submit
	_sync_plan()


func _fit_card(b: Button) -> void:
	if not is_instance_valid(b):
		return
	var title_lbl: Label = b.get_node_or_null("Margin/VBox/Title")
	var detail_lbl: Label = b.get_node_or_null("Margin/VBox/Detail")
	if title_lbl == null or detail_lbl == null:
		return
	# Measure wrapping at the card's current inner width (child labels may not be laid out yet)
	detail_lbl.size.x = maxf(b.size.x - 20.0, 1.0)
	# 12 + 10 margins, 3 vbox gap, 8 slack for the colour band
	var h := 12.0 + title_lbl.get_minimum_size().y + 3.0 + detail_lbl.get_line_count() * detail_lbl.get_line_height() + 10.0 + 8.0
	h = maxf(h, 56.0)
	if absf(b.custom_minimum_size.y - h) > 1.0:
		b.custom_minimum_size.y = h


## Only updates text and button states without rebuilding nodes (prevents missing rapid clicks)
func _sync_plan() -> void:
	var left: int = 10 - int(_alloc["cash"]) - int(_alloc["protect"]) - int(_alloc["growth"])
	(_plan_ui["alloc_title"] as Label).text = "◎ 分配 10 枚資源幣（剩 %d 枚）" % left
	var is_narrow: bool = UI.is_phone_portrait()
	for r: String in _plan_ui["rows"]:
		var row: Dictionary = _plan_ui["rows"][r]
		(row["value"] as Label).text = str(_alloc[r])
		var c_cnt: int = int(_alloc[r])
		if is_narrow:
			(row["coins"] as Label).text = "● %d" % c_cnt
		else:
			var chips_str := "● ".repeat(c_cnt) + "○ ".repeat(max(0, left))
			(row["coins"] as Label).text = chips_str.strip_edges() if chips_str != "" else "―"
		(row["minus"] as Button).disabled = not _actor or int(_alloc[r]) <= 0
		(row["plus"] as Button).disabled = not _actor or left <= 0
	(_plan_ui["cards_title"] as Label).text = "◎ 選擇 2–3 張保障卡（已選 %d）— 避免過度配置" % _cards.size()
	for cid: String in _plan_ui["cards"]:
		var b: Button = _plan_ui["cards"][cid]
		var card: Dictionary = b.get_meta("card")
		var on: bool = cid in _cards
		b.text = "%s%s\n［%s］%s" % ["✓ " if on else "", card.get("title", ""), card.get("tag", ""), card.get("detail", "")]

		var title_lbl: Label = b.get_node_or_null("Margin/VBox/Title")
		var detail_lbl: Label = b.get_node_or_null("Margin/VBox/Detail")
		if title_lbl != null:
			title_lbl.text = ("✓ " if on else "") + str(card.get("title", ""))
			title_lbl.add_theme_color_override("font_color", UI.GOLD if on else UI.TEXT)
		if detail_lbl != null:
			detail_lbl.text = "［%s］%s" % [card.get("tag", ""), card.get("detail", "")]
			detail_lbl.add_theme_color_override("font_color", UI.ACCENT_2.lightened(0.2) if on else UI.MUTED)

		_fit_card.call_deferred(b)

		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 12
		sb.content_margin_bottom = 10
		if on:
			sb.bg_color = UI.PANEL_2.lightened(0.04)
			sb.set_border_width_all(3)
			sb.border_color = UI.ACCENT_2
			sb.shadow_color = Color(UI.ACCENT_2.r, UI.ACCENT_2.g, UI.ACCENT_2.b, 0.45)
			sb.shadow_size = 6
			sb.shadow_offset = Vector2.ZERO
		else:
			sb.bg_color = UI.PANEL_2
			sb.set_border_width_all(1)
			sb.border_color = Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.25)
			sb.shadow_color = Color(0, 0, 0, 0.25)
			sb.shadow_size = 4
			sb.shadow_offset = Vector2(0, 2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
	if _plan_ui.has("submit"):
		(_plan_ui["submit"] as Button).disabled = left != 0 or _cards.size() < 2 or _cards.size() > 3


func _bump(r: String, d: int) -> void:
	_alloc[r] = clampi(int(_alloc[r]) + d, 0, 10)
	_sync_plan()


func _toggle(cid: String) -> void:
	if cid in _cards:
		_cards.erase(cid)
	elif _cards.size() < 3:
		_cards.append(cid)
	else:
		main.toast("最多選 3 張保障卡", UI.OK)
	_sync_plan()


# ───────── ③ Objection Handling ─────────

func _build_objection() -> void:
	var o: Dictionary = _sess.get("objection", {})
	var plan: Dictionary = _sess.get("plan", {})
	if not plan.is_empty():
		var pv := _section("你的方案：預備 %d／保障 %d／成長 %d　保障卡：%s" % [plan.get("alloc", {}).get("cash", 0), plan.get("alloc", {}).get("protect", 0), plan.get("alloc", {}).get("growth", 0), _card_names(plan.get("cards", []))])
		for n in plan.get("notes", []):
			pv.add_child(UI.label("・" + str(n), 14, UI.OK, true))
	var v := _section("◎ 客戶提出異議")
	_objection_section = v.get_parent() as Control
	v.add_child(UI.label(str(o.get("text", "")), 18 if UI.is_portrait() else 20, UI.GOLD, true))
	var raw_options: Array = o.get("options", [])
	var indices: Array = range(raw_options.size())
	var seed_val: int = hash(str(_sess.get("client", {}).get("id", "")) + str(o.get("text", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for idx_i in range(indices.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, idx_i)
		var tmp = indices[idx_i]
		indices[idx_i] = indices[j]
		indices[j] = tmp

	for orig_idx in indices:
		var t = raw_options[orig_idx]
		var b := UI.option_button(str(t), func(): Net.act({"type": "objection", "index": orig_idx}))
		b.disabled = not _actor or _waiting_ai
		v.add_child(b)
	# No remaining-count display: NIM calls are unlimited; main.gd toasts only when the Workers AI quota actually runs out
	var fv := _section("或用你自己的話回應（AI 講師評分；恐嚇與保證重扣合規）" if Net.ai_enabled else "或用你自己的話回應（規則版評分；恐嚇與保證重扣合規）")
	if _actor:
		if _waiting_ai:
			var default_wait := "AI 講師評分中……" if Net.ai_enabled else "講師評分中……"
			var disp := _streamed_obj_text if _streamed_obj_text != "" else default_wait
			_obj_think_label = UI.label(disp, 15, UI.TEXT if _streamed_obj_text != "" else UI.GOLD, true)
			fv.add_child(_obj_think_label)
		else:
			fv.add_child(UI.text_input("輸入你的回應……", func(t: String):
				_waiting_ai = true
				_streamed_obj_text = ""
				_obj_streamed = false
				Net.act({"type": "objection_free", "text": t})
				refresh(_sess, "")
			, 200))
	else:
		fv.add_child(UI.label("（等待顧問回應……）", 14, UI.MUTED))


func _card_names(ids: Array) -> String:
	var names: Array = []
	for card: Dictionary in Net.static_data.get("cards", []):
		if card.get("id") in ids:
			names.append(card.get("title", ""))
	return "、".join(names)


# ───────── ④ Results and Stress Test ─────────

func _build_result() -> void:
	if _actor and not Engine.is_editor_hint():
		Tutorial.record_game()
	var r: Dictionary = _sess.get("result", {})
	var result_key: String = "%s_%s_%s" % [str(_sess.get("client", {}).get("id", "")), str(r.get("score", "")), str(r.get("signed", ""))]
	var is_signed: bool = bool(r.get("signed", false))
	var is_new_result: bool = (result_key != _last_result_sound_key)
	if is_new_result:
		_last_result_sound_key = result_key
		var is_s_grade: bool = str(r.get("grade", "")) == "S"
		if is_signed:
			Sound.play("win", self)
		else:
			Sound.play("fail", self)
		if is_signed:
			UI.spawn_confetti(self)

	var is_phone: bool = UI.is_phone_portrait()

	var letter_data: Dictionary = r.get("letter", {}) if r.get("letter") is Dictionary else {}
	var outcome_str: String = str(letter_data.get("outcome", r.get("outcome", "")))
	if outcome_str == "complaint":
		var comp_banner := UI.panel(Color("#2d1010"), 10, 10)
		comp_banner.add_theme_stylebox_override("panel", UI.box(Color("#2d1010"), 10, UI.BAD, 8, false))
		comp_banner.add_child(UI.label("⚠ 合規紅燈：雖然簽約，但已埋下客訴風險（評級上限 C）", 14 if is_phone else 15, UI.BAD, true))
		_content.add_child(comp_banner)

	var top := UI.hbox(10 if is_phone else 16)
	var grade_color: Color = {"S": UI.GOLD, "A": UI.GOOD, "B": UI.INFO}.get(str(r.get("grade", "C")), UI.BAD)
	var gp := UI.panel(grade_color.darkened(0.35), 36 if is_phone else 60, 8 if is_phone else 14)
	gp.custom_minimum_size = Vector2(70 if is_phone else 110, 70 if is_phone else 110)
	var gl := UI.label(str(r.get("grade", "?")), 38 if is_phone else 60, Color.WHITE)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gp.add_child(gl)
	# Keep the badge a circle: do not let the row stretch it to the text column's height
	gp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(gp)

	var tv := UI.vbox(3 if is_phone else 4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_stamp: Control = UI.stamp("已簽約", UI.GOLD, 14 if is_phone else 16) if is_signed else UI.stamp("再考慮", UI.MUTED, 14 if is_phone else 16)
	var final_score: int = int(r.get("score", 0))
	var score_lbl := UI.label("評分 0 分", 18 if is_phone else 22, UI.TEXT)
	var stamp_row := UI.hbox(8)
	stamp_row.add_child(score_lbl)
	stamp_row.add_child(status_stamp)
	tv.add_child(stamp_row)

	# Number rolling animation (0.45s)
	if is_new_result and not Engine.is_editor_hint():
		var score_tw := create_tween()
		score_tw.tween_method(func(val: int):
			score_lbl.text = "評分 %d 分" % val
		, 0, final_score, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		score_lbl.text = "評分 %d 分" % final_score

	# Stamp scaling from 1.6 with slight rotation (0.28s) + stamp sound on impact
	if is_new_result and not Engine.is_editor_hint():
		status_stamp.pivot_offset = Vector2(40, 14)
		status_stamp.scale = Vector2(1.6, 1.6)
		status_stamp.rotation = -0.12
		status_stamp.modulate.a = 0.0
		var stamp_tw := create_tween()
		stamp_tw.set_parallel(true)
		stamp_tw.tween_property(status_stamp, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		stamp_tw.tween_property(status_stamp, "rotation", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		stamp_tw.tween_property(status_stamp, "modulate:a", 1.0, 0.18)
		stamp_tw.chain().tween_callback(func():
			Sound.play("stamp", self)
			var punch_tw := tv.create_tween()
			punch_tw.tween_property(tv, "position:y", tv.position.y + 3.0, 0.04)
			punch_tw.tween_property(tv, "position:y", tv.position.y, 0.05)
		)

	tv.add_child(UI.label(str(r.get("summary", "")), 14 if is_phone else 15, UI.TEXT, true))
	if is_signed:
		var comm_val: int = int(r.get("commission", 0))
		var comm_lbl: Label = UI.label("業績 +%d" % (0 if (is_new_result and not Engine.is_editor_hint()) else comm_val), 15, UI.GOLD)
		tv.add_child(comm_lbl)
		if is_new_result and not Engine.is_editor_hint() and comm_val > 0:
			var comm_tw := create_tween()
			comm_tw.tween_method(func(val: int):
				if comm_lbl and is_instance_valid(comm_lbl):
					comm_lbl.text = "業績 +%d" % val
			, 0, comm_val, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for cap in r.get("caps", []):
		tv.add_child(UI.label("評級上限：" + str(cap), 13, UI.OK, true))
	top.add_child(tv)
	_content.add_child(top)

	# Display spectator prediction hit list
	var hits: Array = r.get("predictionHits", []) if r.get("predictionHits") is Array else []
	if not hits.is_empty():
		var hit_box := UI.panel(UI.GOOD.darkened(0.65), 10, 8)
		hit_box.add_child(UI.label("★ 評級預測成功（聲望 +2）：%s" % "、".join(hits), 14, UI.GOOD, true))
		_content.add_child(hit_box)

	var rep: Dictionary = _sess.get("objectionReply", {}) if _sess.get("objectionReply") != null else {}
	if not rep.is_empty():
		var v := _section("異議回應回饋")
		v.add_child(UI.label("你說：" + str(rep.get("text", "")), 13, UI.MUTED, true))
		v.add_child(UI.label(str(rep.get("title", "")), 16 if is_phone else 17, UI.tone_color(str(rep.get("quality", "")))))
		var body_str: String = str(rep.get("body", ""))
		var body_lbl := UI.label(body_str, 14, UI.TEXT, true)
		UI.typewriter(body_lbl, body_str, _rep_body_streamed)
		v.add_child(body_lbl)

	# Stress test visualization: clash comparison display
	var stress: Array = _sess.get("stress", []) if _sess.get("stress") != null else []
	if not stress.is_empty():
		var sv := _section("◎ 90 天壓力預演（事件承接測試）")
		var s_idx: int = 0
		for e: Dictionary in stress:
			var res: String = str(e.get("result", ""))
			var tone: String = "good" if res == "held" else ("ok" if res == "partial" else "bad")
			var tag_text: String = "● 穩健承接" if res == "held" else ("▲ 部分承受" if res == "partial" else "× 風險擊穿")

			var card := UI.panel(UI.PANEL_2, 10, 14)
			var cv := UI.vbox(5 if is_phone else 6)
			card.add_child(cv)

			var h := UI.hbox(6 if is_phone else 8)
			var title_lbl := UI.label("［%s］%s" % [e.get("tag", ""), e.get("title", "")], 14, UI.TEXT, true)
			title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(title_lbl)
			h.add_child(UI.label(tag_text, 13 if is_phone else 14, UI.tone_color(tone)))
			cv.add_child(h)

			# Visual clash comparison: need vs defense
			var need_val: float = float(e.get("need", 10.0))
			var def_val: float = float(e.get("defense", 0.0))
			var ratio: float = clampf((def_val / maxf(1.0, need_val)) * 100.0, 0.0, 100.0)

			var meter := UI.hbox(8)
			meter.add_child(UI.label("防禦度", 13, UI.MUTED))
			var pbar: ProgressBar = UI.bar(ratio, UI.tone_color(tone), 140 if UI.is_portrait() else 200)
			pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var def_s: String = ("%d" % int(def_val)) if is_equal_approx(def_val, roundf(def_val)) else ("%.1f" % def_val)
			var need_s: String = ("%d" % int(need_val)) if is_equal_approx(need_val, roundf(need_val)) else ("%.1f" % need_val)
			meter.add_child(UI.label("%s / %s" % [def_s, need_s], 13, UI.MUTED))
			cv.add_child(meter)

			cv.add_child(UI.label(str(e.get("text", "")), 13, UI.MUTED, true))
			sv.add_child(card)

			# 90-day stress events reveal one by one every 0.6s with sound
			if is_new_result and not Engine.is_editor_hint():
				card.modulate.a = 0.0
				var cur_card := card
				var cur_cv := cv
				var cur_res := res
				var delay: float = float(s_idx) * 0.6
				var row_tw := create_tween()
				row_tw.tween_interval(delay)
				row_tw.tween_callback(func():
					if cur_res == "held":
						Sound.play("shield", self)
					elif cur_res == "broken":
						Sound.play("crack", self)
					else:
						Sound.play("shield", self)
				)
				row_tw.tween_callback(func():
					# Slide from 12 px below the container-assigned position, not from y=0 (that ignores the padding)
					var base_y: float = cur_cv.position.y
					cur_cv.position.y = base_y + 12.0
					cur_cv.create_tween().tween_property(cur_cv, "position:y", base_y, 0.35).set_ease(Tween.EASE_OUT)
				)
				row_tw.tween_property(cur_card, "modulate:a", 1.0, 0.35)

			s_idx += 1

	# Dedicated ending and no-plan comparison
	var ep: Dictionary = r.get("epilogue", {}) if r.get("epilogue") is Dictionary else {}
	if not ep.is_empty():
		var ep_v := _section("◎ 人生結局對比")
		var headline: String = str(ep.get("headline", "")).replace("<br>", "\n").replace("<br/>", "\n")
		if headline != "":
			ep_v.add_child(UI.label(headline, 16 if is_phone else 18, UI.GOLD, true))
		var ep_title: String = str(ep.get("title", ""))
		if ep_title != "":
			ep_v.add_child(UI.label("方案效果：%s" % ep_title, 14 if is_phone else 15, UI.ACCENT_2, true))

		var comp_box: BoxContainer = UI.vbox(8) if is_phone else UI.hbox(12)
		comp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Without a plan
		var np_card := UI.panel(UI.BAD.darkened(0.7), 10, 10)
		np_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var np_v := UI.vbox(4)
		np_card.add_child(np_v)
		np_v.add_child(UI.label("× 如果沒有規劃", 15, UI.BAD))
		for item in (ep.get("noPlan", []) as Array):
			np_v.add_child(UI.label("・" + str(item), 13, UI.MUTED, true))
		comp_box.add_child(np_card)

		# Your advisor plan
		var pl_card := UI.panel(UI.GOOD.darkened(0.7), 10, 10)
		pl_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pl_v := UI.vbox(4)
		pl_card.add_child(pl_v)
		pl_v.add_child(UI.label("✓ 你的顧問方案", 15, UI.GOOD))
		for item in (ep.get("list", []) as Array):
			pl_v.add_child(UI.label("・" + str(item), 13, UI.TEXT, true))
		comp_box.add_child(pl_card)

		ep_v.add_child(comp_box)

	# 10-Year Financial Timeline
	var timeline: Dictionary = r.get("timeline", {}) if r.get("timeline") is Dictionary else {}
	if not timeline.is_empty():
		var tv_sec := _section("◎ 十年財務人生（有你的規劃 vs 沒有規劃）")
		var chart := TimelineChart.new()
		chart.set_data(timeline, false)
		tv_sec.add_child(chart)

		var adopted_flag: bool = bool(timeline.get("adopted", true))
		var stats_v := UI.vbox(3)
		if not adopted_flag:
			stats_v.add_child(UI.label("※ 客戶沒有採納你的建議", 13, UI.MUTED, true))
		else:
			var worst_with: int = int(round(float(timeline.get("worstWith", 0)) / 10000.0))
			var worst_no: int = int(round(float(timeline.get("worstNo", 0)) / 10000.0))
			var prem_total: int = int(round(float(timeline.get("premiumTotal", 0)) / 10000.0))
			var stat_str := "最壞的一年：有規劃 %d 萬 ／ 沒有規劃 %d 萬" % [worst_with, worst_no]
			stats_v.add_child(UI.label(stat_str, 14 if is_phone else 15, UI.TEXT, true))
			stats_v.add_child(UI.label("十年保費合計 %d 萬" % prem_total, 13 if is_phone else 14, UI.MUTED, true))
		tv_sec.add_child(stats_v)

	# Letter from ten years later (letter paper style card)
	if not letter_data.is_empty():
		var c_name: String = str(_sess.get("client", {}).get("name", "客戶"))
		var l_card := UI.letter_card(letter_data, c_name)
		_content.add_child(l_card)

	var plan: Dictionary = _sess.get("plan", {}) if _sess.get("plan") != null else {}
	if not plan.is_empty() and not (plan.get("notes", []) as Array).is_empty():
		var nv := _section("方案檢討")
		for n in plan.get("notes", []):
			nv.add_child(UI.label("・" + str(n), 14, UI.OK, true))

	if _actor:
		_content.add_child(UI.button("繼續 →", func(): Net.act({"type": "continue"}), 18))
