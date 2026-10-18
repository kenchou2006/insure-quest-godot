extends Control
## FocusOverlay — Critical Decision. Darkens everything around the control being decided, keeps it
## bright, and asks once more (確認送出 / 再想想). The focused area still takes clicks (_has_point
## leaves a hole); everything else is blocked. On 確認 the music dips, a short beat plays, and the
## decision is revealed only after a 0.55 s pause. Choices are never hinted by colour or motion here.

signal confirmed
signal cancelled

const HOLD_BEFORE_REVEAL := 0.55

var target: Control
var _hole := Rect2()
var _card: PanelContainer
var _title: Label
var _body: Label
var _ok: Button
var _cancel: Button
var _alpha := 0.0
var _busy := false


func _init() -> void:
	name = "FocusOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", QuestUI.card_box(0.98, Color(QuestUI.GOLD, 0.7)))
	add_child(_card)
	var v := QuestUI.vbox(10)
	_card.add_child(v)
	var h := QuestUI.hbox(8)
	h.add_child(QuestUI.icon("target", 20.0, QuestUI.GOLD))
	_title = QuestUI.title("關鍵決策", 18, QuestUI.GOLD)
	h.add_child(_title)
	v.add_child(h)
	_body = QuestUI.label("", 15, QuestUI.TEXT, true)
	_body.custom_minimum_size.x = 300
	v.add_child(_body)
	var row := QuestUI.hbox(10)
	v.add_child(row)
	_cancel = QuestUI.button("再想想", func(): close(true), "secondary")
	_cancel.name = "CriticalCancel"
	row.add_child(_cancel)
	_ok = QuestUI.button("確認送出", _confirm, "primary")
	_ok.name = "CriticalConfirm"
	_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ok)


func _ready() -> void:
	resized.connect(_place)


## Opens around `focus` with a one-line consequence; returns at once (listen to confirmed / cancelled)
func open(focus: Control, heading: String, body: String, ok_text := "確認送出") -> void:
	target = focus
	_title.text = heading
	_body.text = body
	_ok.call("set_label", ok_text)
	_ok.call("set_reason", "")
	_busy = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_place()
	TensionManager.enter_critical()
	GameState.hold("critical", true)
	if QuestUI.motion_off():
		_alpha = 1.0
	else:
		_alpha = 0.0
		var tw := create_tween()
		tw.tween_method(func(a: float): _alpha = a; queue_redraw(), 0.0, 1.0, 0.3)
	_card.modulate.a = 1.0
	QuestUI.fade_in(_card, 0.1, 0.25, 0.0)
	_ok.grab_focus()
	queue_redraw()


func is_open() -> bool:
	return visible


func _confirm() -> void:
	if _busy:
		return
	_busy = true
	_ok.call("set_loading", true, "確認中")
	_cancel.disabled = true
	# The pause before the reveal (0.4–0.7 s)
	await get_tree().create_timer(HOLD_BEFORE_REVEAL).timeout
	close(false)
	confirmed.emit()


func close(was_cancel: bool) -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ok.call("set_loading", false)
	_cancel.disabled = false
	TensionManager.exit_critical()
	GameState.hold("critical", false)
	if was_cancel:
		cancelled.emit()


func _place() -> void:
	if not visible:
		return
	_hole = Rect2()
	if target and is_instance_valid(target) and target.is_visible_in_tree():
		_hole = Rect2(target.global_position - global_position, target.size * target.get_global_transform().get_scale()).grow(10)
	_card.reset_size()
	var cs := _card.get_combined_minimum_size()
	_card.size = cs
	var at := Vector2((size.x - cs.x) * 0.5, (size.y - cs.y) * 0.5)
	if _hole.size.x > 0:
		# Beside the focused control: above it when there is room, else below
		at = Vector2(clampf(_hole.get_center().x - cs.x * 0.5, 12, size.x - cs.x - 12), _hole.position.y - cs.y - 14)
		if at.y < 12:
			at.y = minf(_hole.end.y + 14, size.y - cs.y - 12)
			if _hole.intersects(Rect2(at, cs)):
				at.x = clampf(_hole.position.x - cs.x - 14, 12, size.x - cs.x - 12)
	_card.position = at
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	# The focused control keeps its clicks; the rest of the page is blocked
	if _hole.size.x > 0 and _hole.has_point(point) and not Rect2(_card.position, _card.size).has_point(point):
		return false
	return true


func _draw() -> void:
	var col := Color(QuestUI.INK, 0.62 * _alpha)
	if _hole.size.x <= 0:
		draw_rect(Rect2(Vector2.ZERO, size), col)
		return
	var h := _hole.intersection(Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(0, 0, size.x, h.position.y), col)
	draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), col)
	draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), col)
	draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), col)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(2)
	sb.border_color = Color(QuestUI.GOLD, 0.8 * _alpha)
	sb.set_corner_radius_all(14)
	draw_style_box(sb, h)
