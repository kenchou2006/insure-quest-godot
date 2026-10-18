extends Control
## Base for the mission pages. Full pages own the whole game screen (background, GameHeader,
## columns); modal pages (modal = true) sit over the map with a dim and a centred card.
## The QuestLayer opens / closes pages under a transition and forwards every server state.
## Pages send server actions through `act` (the layer shows loading and errors) and switch
## client-side pages through `go`.

signal act(action: Dictionary)
signal go(page: String, data: Dictionary)

const GameHeader := preload("res://scripts/quest/widgets/game_header.gd")
const ClientStatusPanel := preload("res://scripts/quest/widgets/client_status_panel.gd")
const SecretaryButton := preload("res://scripts/quest/widgets/secretary_button.gd")
const BACKGROUND := preload("res://assets/unified/background.webp")

var page_id := ""
var layer: Control
var modal := false
## Runs the meeting clock while on screen
var timed := true
var header: Control
var content: Control
var built := false
var ctx: Dictionary = {}
var _bg: TextureRect


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Called once, under the transition veil, with the latest state
func build() -> void:
	pass


## Every server state while the page is up
func refresh(_s: Dictionary) -> void:
	pass


## The page became visible (after build); start entrance motion here
func on_open() -> void:
	pass


func on_close() -> void:
	pass


## First-visit secretary explanation (empty = none)
func guide_lines() -> Array:
	return []


## Secretary button explanation
func help_lines() -> Array:
	return guide_lines()


## Gentle nudge after a long idle stretch
func idle_lines() -> Array:
	return []


## Key buttons (viewport rects) the secretary must never cover
func key_rects() -> Array:
	return []


## Elements kept bright while the secretary explains this page
func highlight_rects() -> Array:
	return []


## A server error answered this page's last action: undo loading states
func server_error(_msg: String) -> void:
	pass


func phone() -> bool:
	return UI.is_phone()


## Stacked layout only on portrait screens or very narrow windows; landscape phones keep columns
func narrow() -> bool:
	return UI.is_portrait() or (size.x > 0.0 and size.x < 700.0)


func compact() -> bool:
	return UI.is_phone_landscape() or (size.y > 0 and size.y < 560.0)


## Background art (office at night) under a brand-green veil, for full pages
func add_background() -> void:
	_bg = TextureRect.new()
	_bg.name = "PageBackground"
	_bg.texture = BACKGROUND
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	var veil := ColorRect.new()
	veil.color = Color(QuestUI.BG, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)


## Header + body in a margin; returns the body container
func add_frame() -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 8 if phone() else 16
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var v := QuestUI.vbox(8 if phone() else 14)
	m.add_child(v)
	header = GameHeader.new(compact() or UI.is_phone_portrait())
	header.connect("settings_requested", _open_settings)
	v.add_child(header)
	return v


func _open_settings() -> void:
	if layer:
		layer.call("open_settings")


func secretary_button() -> Button:
	var b: Button = SecretaryButton.new(page_id)
	b.lines_provider = help_lines
	b.highlight_provider = highlight_rects
	return b


## 目前任務 line: one clear sentence of what to do now
func task_line(text: String) -> HBoxContainer:
	var h := QuestUI.hbox(8)
	h.add_child(QuestUI.icon("target", 18.0, QuestUI.GOLD))
	var l := QuestUI.label("目前任務：" + text, 15, QuestUI.GOLD, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


## 回顧上一步: the server has moved on (a stage cannot be undone), so the previous step opens as a
## read-only record of what was decided there
func review_button(label_text: String, stages: Array) -> Button:
	var b: Button = QuestUI.button(label_text, func(): _open_review(label_text, stages), "quiet", "back")
	b.name = "BackButton"
	return b


func _open_review(title_text: String, stages: Array) -> void:
	var old := find_child("ReviewModal", false, false)
	if old:
		old.queue_free()
	var m := Control.new()
	m.name = "ReviewModal"
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(m)
	var dim := ColorRect.new()
	dim.color = Color(QuestUI.INK, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	m.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(center)
	var card := QuestUI.card(null, 1.0, Color(QuestUI.GOLD, 0.5))
	card.custom_minimum_size = Vector2(minf(560.0, size.x - 32.0), 0)
	center.add_child(card)
	var v := QuestUI.vbox(10)
	card.add_child(v)
	v.add_child(QuestUI.header("doc", title_text))
	var any := false
	for d in GameState.decision_history():
		var dd := d as Dictionary
		if stages.has(str(dd.get("stage", ""))):
			any = true
			var h := QuestUI.hbox(8)
			var q := str(dd.get("quality", ""))
			h.add_child(QuestUI.icon("circle_check" if q == "good" else ("alert" if q == "bad" else "circle"), 16.0, QuestUI.GREEN if q == "good" else (QuestUI.GOLD if q == "bad" else QuestUI.MUTED)))
			var dv := QuestUI.vbox(2)
			dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dv.add_child(QuestUI.label(str(dd.get("title", "")), 14, QuestUI.TEXT, true, true))
			dv.add_child(QuestUI.label(str(dd.get("detail", "")), 12, QuestUI.MUTED, true))
			h.add_child(dv)
			v.add_child(h)
	if not any:
		v.add_child(QuestUI.label("上一步沒有留下紀錄。", 14, QuestUI.MUTED))
	v.add_child(QuestUI.label("這一步已經送出，無法再修改；可以參考上面的紀錄繼續。", 12, QuestUI.MUTED, true))
	var close: Button = QuestUI.button("返回目前步驟", func(): m.queue_free(), "primary", "back")
	close.name = "ReviewClose"
	v.add_child(close)


func send(action: Dictionary) -> void:
	act.emit(action)


func rect_of(c: Control) -> Rect2:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()


## A side column: its content scrolls, its key buttons stay pinned at the bottom (never below the
## fold). On narrow screens the pinned buttons go to the page footer instead.
var _footer_items: Array = []


func side(parts: Array, pinned: Array) -> Control:
	var inner := QuestUI.vbox(12)
	for p in parts:
		inner.add_child(p)
	if narrow():
		_footer_items.append_array(pinned)
		return inner
	var v := QuestUI.vbox(10)
	var sc := QuestUI.scroll(inner)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	for p in pinned:
		v.add_child(p)
	return v


## Two-or-three column row on wide screens, a vertical stack (in a scroll) on narrow ones; on
## narrow screens the pinned buttons of the side columns sit in a footer under the scroll
func columns(parts: Array, ratios: Array) -> Control:
	if narrow():
		var outer := QuestUI.vbox(8)
		outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var v := QuestUI.vbox(10)
		for p in parts:
			(p as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(p)
		var sc := QuestUI.scroll(v)
		outer.add_child(sc)
		if not _footer_items.is_empty():
			# Footer: buttons side by side (main action widest), reasons and notes under them
			var foot := QuestUI.card(null, 0.97)
			var fv := QuestUI.vbox(6)
			foot.add_child(fv)
			var row := QuestUI.hbox(8)
			fv.add_child(row)
			for f in _footer_items:
				var c := f as Control
				if c is Button or c is BoxContainer:
					c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					c.size_flags_stretch_ratio = 2.0 if (c is Button and str((c as Button).get("kind")) == "primary") else 1.0
					row.add_child(c)
				else:
					fv.add_child(c)
			outer.add_child(foot)
			_footer_items = []
		return outer
	var h := QuestUI.hbox(12 if compact() else 16)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in range(parts.size()):
		var p: Control = parts[i]
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_stretch_ratio = float(ratios[i]) if i < ratios.size() else 1.0
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		h.add_child(p)
	return h
