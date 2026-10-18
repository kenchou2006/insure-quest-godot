extends Control
## 顧問公事包: one fixed layout filled from data — clue cards on the left, the tools in an open
## leather case in the middle, the focused tool on the right, packed tools and 開始會談 at the
## bottom. Nothing here names a client or a tool: set_customer() / set_tools() refill the same
## nodes, so a different customer never moves the layout. Pictures come from the data files
## (tool image, clue image or tag picture) and fall back to line icons. Gold lines and checks come
## from BriefcaseData.matches() (discovered clues only); there is no right / wrong marking.

signal toggle_requested(tool_id: String)
signal start_requested

const BriefcaseData := preload("res://scripts/briefcase_data.gd")
const LineIcon := preload("res://scripts/ui/line_icon.gd")
const FONT := preload("res://assets/fonts/regular.tres")
const BOLD := preload("res://assets/fonts/bold.tres")

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_VELVET := Color("#0B3A32")
const C_LEATHER := Color("#0C2622")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_CREAM := Color("#EFE6D2")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
const C_PLATE := Color("#D8B66E")
const C_PLATE_TEXT := Color("#2B2010")
const C_LINE := Color(1, 1, 1, 0.12)
const CLUE_ROWS := 3
const SLOTS := 6

## current_customer from BriefcaseData.customer()
var customer: Dictionary = {}
## Tools with status from BriefcaseData.tools()
var tools: Array = []
var capacity := 3
var selected: Array = []
var focused := ""
var sending := false
## Right-hand space kept clear in the bottom bar (the secretary's corner portrait)
var reserve_right := 0.0
## Wide screens: the page title sits above the step bar (drawn by the screen), not in here
var title_outside := false
var k := 1.0
var _settle := 0
## Sizes the layout gave the panels (a panel can come out larger while its text still measures)
var _planned := {}
var _relayout_queued := false

## Areas the tutorial keeps bright, and the controls case_setup drives
var clue_panel: PanelContainer
var briefcase_area: Control
var attr_panel: PanelContainer
var start_button: Button
var status_label: Label

var _fonts: Array = []
var _scroll: ScrollContainer
var _body: Control
var _title: Label
var _sub: Label
var _lines: LinesOverlay
# Customer panel
var _clue_box: VBoxContainer
var _avatar_box: Control
var _avatar_id := ""
var _c_name: Label
var _c_sub: Label
var _info_btn: Button
var _name_lines: Array = []
var _clue_rows: Array = []
var _risk_row: ClueCard
# Case
var _slots: Array = []
# Attributes
var _attr_box: VBoxContainer
var _a_name: Label
var _a_status: Label
var _a_status_box: PanelContainer
var _a_rule: ColorRect
var _a_frame: Panel
var _a_art: IconPlate
var _a_circles: HBoxContainer
var _a_effect: Label
var _a_matches: Label
var _a_button: Button
var _a_note: Label
# Bottom bar
var _bar: Panel
var _bar_title: Label
var _bar_count: Label
var _bar_total: Label
var _bar_sep: ColorRect
var _pack: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_title = _label("", 22, C_TEXT, BOLD)
	_body.add_child(_title)
	_sub = _label("先看左側已取得的線索，再挑出這次會談要帶的工具；工具會改變會談中能問的問題、看到的提示與最後的報告。", 13, C_MUTED)
	_body.add_child(_sub)
	_build_customer()
	_build_case()
	_build_attributes()
	_lines = LinesOverlay.new()
	_lines.view = self
	_body.add_child(_lines)
	_build_bar()
	resized.connect(_layout)
	_refresh()


# --- Data in -----------------------------------------------------------------------------------

func set_customer(c: Dictionary) -> void:
	customer = c
	_refresh()


func set_tools(t: Array, cap: int) -> void:
	tools = t
	if cap != capacity or _pack.size() != cap:
		capacity = cap
		_rebuild_pack()
	if focused == "" or _tool(focused).is_empty():
		focused = ""
		for x: Dictionary in tools:
			if str(x.get("status", "")) != "locked":
				focused = str(x.get("id", ""))
				break
	_refresh()


func set_selected(ids: Array) -> void:
	selected = ids.duplicate()
	for t: Dictionary in tools:
		var st := str(t.get("status", ""))
		if st in ["available", "selected"]:
			t.status = "selected" if selected.has(str(t.get("id", ""))) else "available"
	_refresh()


func set_k(v: float) -> void:
	k = v
	_layout()


func set_sending(on: bool) -> void:
	sending = on
	_refresh()


## Focus a tool: lift it in the case, show its attributes, draw its clue lines
func focus_tool(id: String) -> void:
	if _tool(id).is_empty():
		return
	focused = id
	_refresh()


func _tool(id: String) -> Dictionary:
	for t: Dictionary in tools:
		if str(t.get("id", "")) == id:
			return t
	return {}


## Clue ids the focused tool connects to (discovered clues and the compliance row only)
func focused_matches() -> Array:
	var t := _tool(focused)
	return [] if t.is_empty() or customer.is_empty() else BriefcaseData.matches(t, customer)


# --- Build -------------------------------------------------------------------------------------

func _build_customer() -> void:
	clue_panel = PanelContainer.new()
	clue_panel.add_theme_stylebox_override("panel", _panel_style(Color(C_CARD, 0.95), 12))
	_body.add_child(clue_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	clue_panel.add_child(v)
	_clue_box = v
	var head := HBoxContainer.new()
	var hl := _label("客戶線索", 20, C_TEXT, BOLD)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	_info_btn = Button.new()
	_info_btn.name = "CustomerInfoButton"
	_info_btn.text = "客戶資料"
	_info_btn.focus_mode = Control.FOCUS_NONE
	_info_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_info_btn.tooltip_text = "家庭、需求、財務限制、預算與合規提醒"
	_fonts.append([_info_btn, 12])
	_info_btn.pressed.connect(_open_info)
	for st: String in ["normal", "hover", "pressed", "focus"]:
		var ib := StyleBoxFlat.new()
		ib.bg_color = Color(C_GOLD, 0.18 if st in ["hover", "pressed"] else 0.06)
		ib.set_border_width_all(1)
		ib.border_color = Color(C_GOLD, 0.9 if st == "hover" else 0.6)
		ib.set_corner_radius_all(8)
		ib.content_margin_left = 10
		ib.content_margin_right = 10
		ib.content_margin_top = 3
		ib.content_margin_bottom = 3
		ib.anti_aliasing = true
		_info_btn.add_theme_stylebox_override(st, ib)
	_info_btn.add_theme_color_override("font_color", C_GOLD)
	_info_btn.add_theme_color_override("font_hover_color", Color("#F1D58C"))
	_info_btn.add_theme_color_override("font_pressed_color", Color("#F1D58C"))
	_info_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_info_btn)
	v.add_child(head)
	v.add_child(_rule(C_GOLD, 0.35))
	# —— portrait + name ——
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	nr.alignment = BoxContainer.ALIGNMENT_CENTER
	for side in range(2):
		var line := ColorRect.new()
		line.color = Color(C_GOLD, 0.6)
		line.custom_minimum_size = Vector2(0, 1)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_lines.append(line)
		if side == 0:
			nr.add_child(line)
			_avatar_box = Control.new()
			_avatar_box.custom_minimum_size = Vector2(34, 34)
			_avatar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nr.add_child(_avatar_box)
			_c_name = _label("", 20, C_TEXT, BOLD)
			nr.add_child(_c_name)
		else:
			nr.add_child(line)
	v.add_child(nr)
	_c_sub = _label("", 12, C_MUTED)
	_c_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_c_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_c_sub.clip_text = true
	v.add_child(_c_sub)
	for i in range(CLUE_ROWS):
		var r := ClueCard.new(self)
		_clue_rows.append(r)
		v.add_child(r)
	_risk_row = ClueCard.new(self, true)
	v.add_child(_risk_row)


func _build_case() -> void:
	briefcase_area = CaseBody.new()
	_body.add_child(briefcase_area)
	for i in range(SLOTS):
		var s := ToolSlot.new(self)
		s.pressed.connect(_on_slot_pressed.bind(s))
		briefcase_area.add_child(s)
		_slots.append(s)


func _build_attributes() -> void:
	attr_panel = PanelContainer.new()
	var ps := _panel_style(Color(C_CARD, 0.95), 16)
	ps.border_color = Color(C_GOLD, 0.45)
	attr_panel.add_theme_stylebox_override("panel", ps)
	_body.add_child(attr_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	attr_panel.add_child(v)
	_attr_box = v
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_a_name = _label("", 26, C_TEXT, BOLD)
	_a_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_a_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_a_name.clip_text = true
	top.add_child(_a_name)
	_a_status_box = PanelContainer.new()
	_a_status_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_a_status = _label("", 12, C_TEXT)
	_a_status_box.add_child(_a_status)
	top.add_child(_a_status_box)
	v.add_child(top)
	_a_rule = _rule(C_GOLD, 0.5)
	v.add_child(_a_rule)
	_a_frame = Panel.new()
	_a_frame.clip_contents = true
	_a_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color("#082A25")
	fs.set_corner_radius_all(10)
	fs.set_border_width_all(1)
	fs.border_color = Color(C_GOLD, 0.6)
	fs.anti_aliasing = true
	_a_frame.add_theme_stylebox_override("panel", fs)
	v.add_child(_a_frame)
	_a_art = IconPlate.new()
	_a_art.cover = true
	_a_frame.add_child(_a_art)
	_a_frame.resized.connect(func():
		_a_art.position = Vector2(2, 2)
		_a_art.size = _a_frame.size - Vector2(4, 4)
	)
	_a_circles = HBoxContainer.new()
	_a_circles.add_theme_constant_override("separation", 4)
	v.add_child(_a_circles)
	_a_effect = _label("", 13, Color(C_CREAM, 0.9))
	_a_effect.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(_a_effect)
	_a_matches = _label("", 12, C_GOLD)
	_a_matches.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(_a_matches)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fill)
	_a_note = _label("", 12, C_MUTED)
	_a_note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_a_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_a_note)
	_a_button = Button.new()
	_a_button.name = "UseToolButton"
	_a_button.focus_mode = Control.FOCUS_NONE
	_a_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_a_button.add_theme_font_override("font", BOLD)
	_fonts.append([_a_button, 20])
	_a_button.pressed.connect(func():
		if focused != "" and not sending:
			toggle_requested.emit(focused)
	)
	v.add_child(_a_button)


func _build_bar() -> void:
	_bar = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_BG, 0.95)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_GOLD, 0.45)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 10
	sb.anti_aliasing = true
	_bar.add_theme_stylebox_override("panel", sb)
	add_child(_bar)
	_bar_title = _label("本次攜帶", 20, C_TEXT, BOLD)
	_bar.add_child(_bar_title)
	_bar_count = _label("", 28, C_GOLD, BOLD)
	_bar.add_child(_bar_count)
	_bar_total = _label("", 20, C_TEXT, BOLD)
	_bar.add_child(_bar_total)
	_bar_sep = ColorRect.new()
	_bar_sep.color = Color(C_GOLD, 0.5)
	_bar_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_bar_sep)
	status_label = _label("", 14, C_MUTED)
	_bar.add_child(status_label)
	start_button = StartButton.new()
	start_button.name = "StartMeetingButton"
	start_button.pressed.connect(func():
		if not start_button.disabled:
			start_requested.emit()
	)
	_bar.add_child(start_button)
	_rebuild_pack()


func _rebuild_pack() -> void:
	for p: Node in _pack:
		p.queue_free()
	_pack.clear()
	if _bar == null:
		return
	for i in range(capacity):
		var p := PackSlot.new(self, i + 1)
		p.pressed.connect(func():
			if p.tool_id != "" and not sending:
				toggle_requested.emit(p.tool_id)
		)
		_bar.add_child(p)
		_pack.append(p)


func _on_slot_pressed(s: ToolSlot) -> void:
	var id := str(s.tool.get("id", ""))
	if id == "":
		return
	# First tap inspects; tapping the inspected tool again packs or unpacks it
	if id == focused and str(s.tool.get("status", "")) in ["available", "selected"] and not sending:
		toggle_requested.emit(id)
		return
	Sound.play("click", self)
	focus_tool(id)


## 客戶資料: every customer field from the data file, on demand (the panel keeps to the clues)
func _open_info() -> void:
	var dim := ColorRect.new()
	dim.name = "CustomerInfo"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var p := PanelContainer.new()
	var ps := _panel_style(C_CARD, 18)
	ps.border_color = Color(C_GOLD, 0.6)
	p.add_theme_stylebox_override("panel", ps)
	p.custom_minimum_size = Vector2(minf(460.0 * k, size.x - 24.0), 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var head := HBoxContainer.new()
	var t := _label("客戶資料｜%s" % str(customer.get("customer_name", "")), 18, C_GOLD, BOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "關閉"
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(dim.queue_free)
	head.add_child(x)
	v.add_child(head)
	var rows := [
		["年齡層", str(customer.get("customer_age_group", ""))],
		["家庭", str(customer.get("family_structure", ""))],
		["需求", _joined(customer.get("primary_needs", []))],
		["財務限制", _joined(customer.get("financial_constraints", []))],
		["預算", str(customer.get("budget_range", ""))],
		["合規提醒", str(customer.get("compliance_risk", ""))],
	]
	for r: Array in rows:
		if str(r[1]).strip_edges() == "":
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var kl := _label(str(r[0]), 13, C_GOLD)
		kl.custom_minimum_size = Vector2(64, 0) * k
		kl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(kl)
		var vl := _label(str(r[1]), 14, C_TEXT, null, true)
		h.add_child(vl)
		v.add_child(h)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and not p.get_global_rect().has_point(e.global_position):
			dim.queue_free()
	)


# --- Refresh (same nodes, new data) -------------------------------------------------------------

func _refresh() -> void:
	if _title == null:
		return
	_title.text = "依照客戶線索，選擇 %d 項會談工具" % capacity
	_refresh_customer()
	_refresh_case()
	_refresh_attributes()
	_refresh_bar()
	_lines.queue_redraw()
	_queue_relayout()


## New text can grow a panel for a frame; put the panels back to their planned sizes
func _queue_relayout() -> void:
	if _relayout_queued or not is_inside_tree():
		return
	_relayout_queued = true
	await get_tree().process_frame
	_relayout_queued = false
	if is_instance_valid(self):
		_layout()


func _refresh_customer() -> void:
	var c := customer
	var id := str(c.get("customer_portrait", ""))
	if id != _avatar_id or _avatar_box.get_child_count() == 0:
		_avatar_id = id
		for n in _avatar_box.get_children():
			n.queue_free()
		if id != "" or str(c.get("customer_name", "")) != "":
			var av := Portraits.create_avatar(id, str(c.get("customer_name", "")), 34)
			av.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_avatar_box.add_child(av)
			_fit_avatar()
	_c_name.text = str(c.get("customer_name", ""))
	var parts: Array = []
	var age := int(c.get("customer_age", 0))
	var job := str(c.get("customer_job", ""))
	if age > 0 or job != "":
		parts.append(("%d 歲・" % age if age > 0 else "") + job)
	for f: String in ["customer_age_group", "difficulty_level"]:
		var t := str(c.get(f, ""))
		if t != "":
			parts.append(t if f != "difficulty_level" else "難度 " + t)
	_c_sub.text = "｜".join(parts)
	_c_sub.tooltip_text = _c_sub.text
	_info_btn.visible = not c.is_empty()
	var shown: Array = BriefcaseData.top_clues(c, CLUE_ROWS)
	var matched := focused_matches()
	for i in range(_clue_rows.size()):
		var r: ClueCard = _clue_rows[i]
		r.visible = i < shown.size()
		if i < shown.size():
			var cl: Dictionary = shown[i]
			r.clue_id = str(cl.get("id", ""))
			if bool(cl.get("unlocked", false)):
				r.set_content(str(cl.get("icon", "search")), str(cl.get("title", "")), str(cl.get("detail", "")), false, str(cl.get("image", "")))
			else:
				# Never the answer: a locked card says only that something is still to be found
				r.set_content("lock", "未取得線索", "會談中觀察後才會出現", true, "")
			r.set_matched(matched.has(r.clue_id) and bool(cl.get("unlocked", false)))
	var risk := str(c.get("compliance_risk", ""))
	_risk_row.visible = risk != ""
	_risk_row.clue_id = "compliance"
	_risk_row.set_content("stamp", "合規提醒", risk, false, "")
	_risk_row.set_matched(matched.has("compliance"))


func _refresh_case() -> void:
	for i in range(_slots.size()):
		var s: ToolSlot = _slots[i]
		s.visible = i < tools.size()
		if i < tools.size():
			s.set_tool(tools[i])
			s.set_focused(str((tools[i] as Dictionary).get("id", "")) == focused)


func _refresh_attributes() -> void:
	var t := _tool(focused)
	attr_panel.modulate.a = 1.0 if not t.is_empty() else 0.5
	var st := str(t.get("status", "available"))
	_a_status.text = BriefcaseData.status_label(st) if not t.is_empty() else ""
	var col: Color = {"selected": C_GREEN, "locked": C_MUTED, "used": C_MUTED}.get(st, C_GOLD)
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(col, 0.16)
	chip.set_border_width_all(1)
	chip.border_color = Color(col, 0.7)
	chip.set_corner_radius_all(10)
	chip.content_margin_left = 8 * k
	chip.content_margin_right = 8 * k
	chip.content_margin_top = 1 * k
	chip.content_margin_bottom = 2 * k
	_a_status_box.add_theme_stylebox_override("panel", chip)
	_a_status_box.visible = not t.is_empty()
	_a_status.add_theme_color_override("font_color", col.lightened(0.2))
	_a_art.set_tool(t)
	_a_name.text = str(t.get("name", "")) if not t.is_empty() else "選一項工具查看"
	_a_name.tooltip_text = str(t.get("category", ""))
	_a_effect.text = str(t.get("effect", ""))
	# Effect circles: the tool's chips, then when it can be used (three at most)
	for n in _a_circles.get_children():
		n.queue_free()
	var items: Array = []
	for c: Dictionary in t.get("chips", []):
		items.append([str(c.get("icon", "check")), str(c.get("label", ""))])
	if str(t.get("usage_limit", "")) != "":
		items.append(["doc", str(t.get("usage_limit", ""))])
	for it: Array in items.slice(0, 3):
		_a_circles.add_child(_circle(str(it[0]), str(it[1])))
	var titles := {"compliance": "合規提醒"}
	for cl: Dictionary in customer.get("clues", []):
		titles[str(cl.get("id", ""))] = str(cl.get("title", ""))
	var m := focused_matches()
	if t.is_empty():
		_a_matches.text = ""
	elif m.is_empty():
		_a_matches.text = "對應線索：目前已取得的線索中，沒有直接對應的項目"
		_a_matches.add_theme_color_override("font_color", C_MUTED)
	else:
		_a_matches.text = "對應線索：" + "、".join(m.map(func(id): return str(titles.get(id, id))))
		_a_matches.add_theme_color_override("font_color", C_GOLD)
	# Action
	var packed := selected.has(focused)
	var full := selected.size() >= capacity
	var label := "選用此工具"
	var enabled := true
	_a_note.text = ""
	match st:
		"locked":
			label = "未解鎖"
			enabled = false
			_a_note.text = str(t.get("unlock_text", ""))
		"used":
			label = "已使用"
			enabled = false
		_:
			if packed:
				label = "移出公事包"
			elif full:
				label = "公事包已滿"
				enabled = false
				_a_note.text = "先移除一項已攜帶的工具"
	if t.is_empty() or sending:
		enabled = false
	_a_note.visible = _a_note.text != ""
	_a_button.text = label
	_a_button.disabled = not enabled
	_style_action(_a_button, packed)


func _refresh_bar() -> void:
	_bar_count.text = "%d" % selected.size()
	_bar_total.text = "/ %d" % capacity
	for i in range(_pack.size()):
		var p: PackSlot = _pack[i]
		p.set_tool(_tool(str(selected[i])) if i < selected.size() else {})
	var left := capacity - selected.size()
	if sending:
		status_label.text = "準備中……"
	elif left > 0:
		status_label.text = "再選 %d 項即可開始會談" % left
	else:
		status_label.text = "已備妥，可以開始會談"
	status_label.add_theme_color_override("font_color", C_GOLD if left == 0 and not sending else C_CREAM)
	start_button.disabled = left != 0 or sending or customer.is_empty()
	(start_button as StartButton).refresh_state()


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _bar == null or size.x < 10:
		return
	_fonts = _fonts.filter(func(f: Array) -> bool: return is_instance_valid(f[0]))
	for f: Array in _fonts:
		if is_instance_valid(f[0]):
			(f[0] as Control).add_theme_font_size_override("font_size", _fs(int(f[1])))
	_avatar_box.custom_minimum_size = Vector2(34, 34) * k
	_clue_box.add_theme_constant_override("separation", roundi(6 * k))
	_attr_box.add_theme_constant_override("separation", roundi(6 * k))
	_fit_avatar()
	for r: ClueCard in _clue_rows + [_risk_row]:
		r.set_k(k)
	if UI.is_portrait():
		_layout_portrait()
	else:
		_layout_wide()
	_refresh_attributes()
	_lines.queue_redraw()
	_settle_later()


## Wrapped labels measure their height from their width a frame late: lay out again until the
## panels hold their planned size (a few frames at most)
func _settle_later() -> void:
	var off := false
	for p: Control in [clue_panel, attr_panel]:
		var want: Vector2 = _planned.get(p, p.size)
		if UI.is_portrait():
			off = off or absf(p.size.y - p.get_combined_minimum_size().y) > 1.0
		else:
			off = off or (p.size - want).length() > 1.0
	if not off or _settle >= 4 or not is_inside_tree():
		_settle = 0
		return
	_settle += 1
	await get_tree().process_frame
	if is_instance_valid(self):
		_layout()


func _text_h(l: Label, width: float) -> float:
	var f: Font = l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	return f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, width, fs).y


func _layout_wide() -> void:
	var w := size.x
	var gap := 16.0 * k
	var bar_h := 84.0 * k
	_bar.position = Vector2(0, size.y - bar_h)
	_bar.size = Vector2(w - reserve_right, bar_h)
	_layout_bar_wide()
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(w, size.y - bar_h - 12.0 * k)
	_body.custom_minimum_size = Vector2(0, _scroll.size.y)
	_body.size = _scroll.size
	var top := 0.0
	_title.visible = not title_outside
	_sub.visible = not title_outside
	if not title_outside:
		_title.autowrap_mode = TextServer.AUTOWRAP_OFF
		_title.custom_minimum_size = Vector2.ZERO
		_title.reset_size()
		_title.position = Vector2.ZERO
		_sub.autowrap_mode = TextServer.AUTOWRAP_OFF
		_sub.custom_minimum_size = Vector2.ZERO
		_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_sub.clip_text = true
		_sub.reset_size()
		var sx := _title.size.x + 16.0 * k
		_sub.size.x = maxf(w - sx, 0)
		_sub.position = Vector2(sx, _title.size.y - _sub.size.y - 3.0 * k)
		top = _title.size.y + 10.0 * k
	var col_h := _scroll.size.y - top
	var left_w := clampf(w * 0.24, 250.0 * k, 320.0 * k)
	var right_w := clampf(w * 0.25, 260.0 * k, 320.0 * k)
	var center_w := w - left_w - right_w - gap * 2
	_a_frame.custom_minimum_size = Vector2(0, clampf(col_h * 0.27, 96.0 * k, 170.0 * k))
	_place(clue_panel, Vector2(0, top), Vector2(left_w, col_h))
	_place(briefcase_area, Vector2(left_w + gap, top), Vector2(center_w, col_h))
	_place(attr_panel, Vector2(w - right_w, top), Vector2(right_w, col_h))
	_layout_slots(3)
	_lines.position = Vector2.ZERO
	_lines.size = _body.size
	_lines.visible = true


func _layout_portrait() -> void:
	var w := size.x
	var gap := 12.0 * k
	var bar_h := 132.0 * k
	_bar.position = Vector2(0, size.y - bar_h)
	_bar.size = Vector2(w, bar_h)
	_layout_bar_portrait()
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(w, size.y - bar_h - gap)
	_title.visible = true
	_sub.visible = true
	for l: Label in [_title, _sub]:
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.clip_text = false
		l.custom_minimum_size = Vector2(w, 0)
	_title.position = Vector2.ZERO
	_title.size = Vector2(w, _text_h(_title, w))
	_sub.position = Vector2(0, _title.size.y + 2.0 * k)
	_sub.size = Vector2(w, _text_h(_sub, w))
	var y := _sub.position.y + _sub.size.y + 10.0 * k
	clue_panel.custom_minimum_size = Vector2(w, 0)
	_place(clue_panel, Vector2(0, y), Vector2(w, clue_panel.get_combined_minimum_size().y))
	y += clue_panel.size.y + gap
	var slot_h := 132.0 * k
	var case_h := CaseBody.LID * k + CaseBody.FOOT * k + 24.0 * k + slot_h * 3 + 10.0 * k * 2
	_place(briefcase_area, Vector2(0, y), Vector2(w, case_h))
	_layout_slots(2)
	y += case_h + gap
	attr_panel.custom_minimum_size = Vector2(w, 0)
	_a_frame.custom_minimum_size = Vector2(0, 170.0 * k)
	_place(attr_panel, Vector2(0, y), Vector2(w, attr_panel.get_combined_minimum_size().y))
	y += attr_panel.size.y + gap
	_body.custom_minimum_size = Vector2(0, y)
	_body.size = Vector2(w, y)
	# Lines need the columns side by side; the checks on the clue cards still show the fit
	_lines.visible = false


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz
	_planned[c] = sz


func _layout_slots(cols: int) -> void:
	var cb := briefcase_area as CaseBody
	cb.k = k
	briefcase_area.queue_redraw()
	var tray := cb.tray_rect()
	var pad := 10.0 * k
	var gap := 10.0 * k
	var rows := ceili(float(SLOTS) / cols)
	var sw := (tray.size.x - pad * 2 - gap * (cols - 1)) / cols
	var sh := (tray.size.y - pad * 2 - gap * (rows - 1)) / rows
	for i in range(_slots.size()):
		var s: ToolSlot = _slots[i]
		s.k = k
		s.size = Vector2(sw, sh)
		s.base_pos = tray.position + Vector2(pad + (i % cols) * (sw + gap), pad + floori(float(i) / cols) * (sh + gap))
		s.apply_lift()
		s.layout_inner()


func _layout_bar_wide() -> void:
	var h := _bar.size.y
	var pad := 22.0 * k
	for l: Label in [_bar_title, _bar_count, _bar_total]:
		l.reset_size()
	var x := pad
	var base := h * 0.5
	_bar_title.position = Vector2(x, base - _bar_title.size.y * 0.5)
	x += _bar_title.size.x + 10.0 * k
	_bar_count.position = Vector2(x, base - _bar_count.size.y * 0.5 - 1.0 * k)
	x += _bar_count.size.x + 4.0 * k
	_bar_total.position = Vector2(x, base - _bar_total.size.y * 0.5)
	x += _bar_total.size.x + 20.0 * k
	var ps := 60.0 * k
	for i in range(_pack.size()):
		var p: PackSlot = _pack[i]
		p.k = k
		p.size = Vector2(ps, ps)
		p.position = Vector2(x + i * (ps + 16.0 * k), (h - ps) * 0.5)
		p.layout_inner()
	x += _pack.size() * (ps + 16.0 * k) + 4.0 * k
	_bar_sep.position = Vector2(x, h * 0.22)
	_bar_sep.size = Vector2(1, h * 0.56)
	x += 18.0 * k
	var bw := clampf(_bar.size.x * 0.17, 160.0 * k, 210.0 * k)
	var bh := 54.0 * k
	start_button.size = Vector2(bw, bh)
	start_button.position = Vector2(_bar.size.x - pad - bw, (h - bh) * 0.5)
	(start_button as StartButton).set_k(k)
	status_label.custom_minimum_size = Vector2.ZERO
	status_label.reset_size()
	status_label.position = Vector2(x, (h - status_label.size.y) * 0.5)
	status_label.size.x = maxf(start_button.position.x - 12.0 * k - x, 0)
	status_label.clip_text = true
	_bar_sep.visible = true


func _layout_bar_portrait() -> void:
	var h := _bar.size.y
	var pad := 12.0 * k
	for l: Label in [_bar_title, _bar_count, _bar_total]:
		l.reset_size()
	var row1 := 64.0 * k
	var x := pad
	_bar_title.position = Vector2(x, pad + (row1 - _bar_title.size.y) * 0.5)
	x += _bar_title.size.x + 6.0 * k
	_bar_count.position = Vector2(x, pad + (row1 - _bar_count.size.y) * 0.5)
	x += _bar_count.size.x + 2.0 * k
	_bar_total.position = Vector2(x, pad + (row1 - _bar_total.size.y) * 0.5)
	x += _bar_total.size.x + 12.0 * k
	var ps := minf(56.0 * k, (_bar.size.x - x - pad - 12.0 * k * (capacity - 1)) / maxi(capacity, 1))
	for i in range(_pack.size()):
		var p: PackSlot = _pack[i]
		p.k = k
		p.size = Vector2(ps, ps)
		p.position = Vector2(x + i * (ps + 12.0 * k), pad + (row1 - ps) * 0.5)
		p.layout_inner()
	_bar_sep.visible = false
	var bh := 46.0 * k
	var bw := minf(190.0 * k, _bar.size.x * 0.45)
	var by := h - pad - bh
	# Keep the secretary's corner portrait clear
	start_button.size = Vector2(bw, bh)
	start_button.position = Vector2(_bar.size.x - pad - bw - reserve_right, by)
	(start_button as StartButton).set_k(k)
	status_label.reset_size()
	status_label.position = Vector2(pad, by + (bh - status_label.size.y) * 0.5)
	status_label.size.x = maxf(start_button.position.x - pad * 2, 0)
	status_label.clip_text = true


func _fit_avatar() -> void:
	for n in _avatar_box.get_children():
		if n is Control:
			(n as Control).custom_minimum_size = _avatar_box.custom_minimum_size
			(n as Control).size = _avatar_box.custom_minimum_size
			(n as Control).position = Vector2.ZERO


# --- Helpers -----------------------------------------------------------------------------------

func _label(t: String, fs: int, col: Color, font: Font = null, wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", _fs(fs))
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fonts.append([l, fs])
	return l


## Phones read the full-width panels at arm's length: larger type, never below 14 px
func _fs(base: int) -> int:
	if UI.is_phone_portrait():
		return maxi(roundi(base * k * 1.15), 14)
	return roundi(base * k)


static func _joined(v: Variant) -> String:
	if v is Array:
		return "、".join((v as Array).map(func(x): return str(x)))
	return str(v)


func _rule(col: Color, a: float) -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(col, a)
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## Round effect badge with its label underneath (right panel)
func _circle(icon: String, text: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(4 * k))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := Disc.new()
	disc.custom_minimum_size = Vector2(40, 40) * k
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(disc)
	var ic: Control = LineIcon.new(icon, C_GOLD, 2.0)
	ic.size = Vector2(20, 20) * k
	ic.position = Vector2(10, 10) * k
	disc.add_child(ic)
	var l := _label(text, 12, C_CREAM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.tooltip_text = text
	col.add_child(l)
	return col


func _panel_style(bg: Color, pad := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_GOLD, 0.3)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.85
	sb.content_margin_bottom = pad * 0.85
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 10
	sb.anti_aliasing = true
	return sb


func _style_action(b: Button, packed: bool) -> void:
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.content_margin_top = 10 * k
		sb.content_margin_bottom = 10 * k
		sb.anti_aliasing = true
		sb.set_border_width_all(2 if st != "disabled" else 1)
		if st == "disabled":
			sb.bg_color = Color(C_MUTED, 0.12)
			sb.border_color = Color(C_MUTED, 0.25)
		elif packed:
			sb.bg_color = Color(C_CREAM, 0.06 if st != "hover" else 0.12)
			sb.border_color = Color(C_CREAM, 0.5)
		else:
			sb.bg_color = Color("#0E7A55") if st != "hover" else Color("#11905F")
			sb.border_color = Color(C_GOLD, 0.75 if st != "hover" else 1.0)
			sb.shadow_color = Color(C_GOLD, 0.18 if st != "hover" else 0.3)
			sb.shadow_size = roundi(8 * k)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", C_TEXT)
	b.add_theme_color_override("font_pressed_color", C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(C_MUTED, 0.8))


# --- Pieces ------------------------------------------------------------------------------------

## Dark disc with a gold ring (effect badges)
class Disc extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color("#082A25"))
		draw_arc(c, r - 1.0, 0, TAU, 48, Color(C_GOLD, 0.85), 1.6, true)


## One clue card: the clue's picture on the right fading into the card, icon and title on the
## left; locked cards stay dark. Compact cards (the compliance reminder) are a single line.
## A gold frame and check badge when the focused tool connects to it.
class ClueCard extends Control:
	var clue_id := ""
	var matched := false
	var compact := false
	var locked := false
	var has_image := false
	var view
	var _clip: Control
	var _img: TextureRect
	var _fade: CardFade
	var _icon: Control
	var _title: Label
	var _detail: Label
	var _frame: CardFrame

	func _init(v, is_compact := false) -> void:
		view = v
		compact = is_compact
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clip = Control.new()
		_clip.clip_contents = true
		_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_clip)
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clip.add_child(_img)
		_fade = CardFade.new(self)
		add_child(_fade)
		_icon = LineIcon.new("search", C_GOLD, 2.0)
		add_child(_icon)
		_title = v._label("", 13 if compact else 17, C_TEXT, BOLD)
		_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_title.clip_text = true
		add_child(_title)
		_detail = v._label("", 11, C_MUTED)
		_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_detail.clip_text = true
		add_child(_detail)
		_frame = CardFrame.new(self)
		add_child(_frame)
		resized.connect(_fit)
		set_k(1.0)

	func set_k(kk: float) -> void:
		custom_minimum_size.y = (34.0 if compact else 84.0) * kk
		_fit()

	func set_content(icon: String, title: String, detail: String, is_locked: bool, image: String) -> void:
		locked = is_locked
		_icon.set("kind", icon)
		_icon.set("color", Color(C_MUTED, 0.7) if locked else C_GOLD)
		_icon.queue_redraw()
		_title.text = title
		_title.add_theme_color_override("font_color", Color(C_MUTED, 0.85) if locked else C_TEXT)
		_detail.text = detail
		_detail.tooltip_text = detail
		var tex: Texture2D = load(image) as Texture2D if not compact and image != "" and ResourceLoader.exists(image) else null
		_img.texture = tex
		has_image = tex != null and not locked
		_clip.visible = has_image
		_fade.visible = has_image
		_fit()
		queue_redraw()

	func set_matched(on: bool) -> void:
		matched = on
		_frame.queue_redraw()
		queue_redraw()

	func _fit() -> void:
		if view == null:
			return
		var kk: float = view.k
		var w := size.x
		var h := size.y
		_frame.size = size
		if compact:
			var ic := 18.0 * kk
			_icon.size = Vector2(ic, ic)
			_icon.position = Vector2(10.0 * kk, (h - ic) * 0.5)
			# Clipped labels report no width: measure the title itself
			var f: Font = _title.get_theme_font("font")
			var tfs := _title.get_theme_font_size("font_size")
			_title.reset_size()
			_title.size.x = f.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 2.0
			_title.position = Vector2(_icon.position.x + ic + 8.0 * kk, (h - _title.size.y) * 0.5)
			var dx := _title.position.x + _title.size.x + 8.0 * kk
			_detail.reset_size()
			_detail.position = Vector2(dx, (h - _detail.size.y) * 0.5)
			_detail.size.x = maxf(w - dx - (34.0 if matched else 10.0) * kk, 0)
			return
		# Wide cards (phones) keep the text clear of the picture
		var share := 0.42 if w > 360.0 * kk else 0.6
		var iw := w * share if has_image else 0.0
		_clip.position = Vector2(w - iw, 1)
		_clip.size = Vector2(maxf(iw - 1, 0), maxf(h - 2, 0))
		_img.position = Vector2.ZERO
		_img.size = _clip.size
		_fade.position = Vector2(w - iw - 1, 0)
		_fade.size = Vector2(iw * 0.6, h)
		var ic := 26.0 * kk
		_icon.size = Vector2(ic, ic)
		_icon.position = Vector2(12.0 * kk, 10.0 * kk)
		_title.reset_size()
		_title.position = Vector2(12.0 * kk, _icon.position.y + ic + 4.0 * kk)
		_title.size.x = maxf((w * 0.62 if has_image else w - 44.0 * kk) - 12.0 * kk, 0)
		_detail.reset_size()
		_detail.position = Vector2(12.0 * kk, _title.position.y + _title.size.y)
		_detail.size.x = maxf((w * 0.66 if has_image else w - 44.0 * kk) - 12.0 * kk, 0)

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#0A2C27") if locked else Color("#0F3F37")
		sb.set_corner_radius_all(roundi(10 * float(view.k)) if view else 10)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))


## Left edge of a clue picture fading into the card colour
class CardFade extends Control:
	var card

	func _init(c) -> void:
		card = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var bg := Color("#0F3F37")
		var r := Rect2(Vector2.ZERO, size)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([bg, Color(bg, 0.0), Color(bg, 0.0), bg]))


## Card border on top of the picture: gold frame and check badge when matched
class CardFrame extends Control:
	var card

	func _init(c) -> void:
		card = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var kk: float = card.view.k if card.view else 1.0
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_corner_radius_all(roundi(10 * kk))
		sb.anti_aliasing = true
		if card.matched:
			sb.set_border_width_all(2)
			sb.border_color = C_GOLD
			sb.shadow_color = Color(C_GOLD, 0.35)
			sb.shadow_size = roundi(8 * kk)
		else:
			sb.set_border_width_all(1)
			sb.border_color = Color(C_MUTED, 0.22) if card.locked else Color(1, 1, 1, 0.1)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if card.matched:
			var r := (11.0 if card.compact else 14.0) * kk
			var c := Vector2(size.x - r - 8.0 * kk, (size.y * 0.5) if card.compact else (r + 8.0 * kk))
			draw_circle(c, r, Color("#E9CF8C"))
			draw_arc(c, r, 0, TAU, 32, Color("#8A6A2E"), 1.2, true)
			var s := r * 0.55
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, 0), c + Vector2(-s * 0.15, s * 0.55), c + Vector2(s * 0.8, -s * 0.55)]), C_PLATE_TEXT, 2.0 * kk, true)


## Tool picture (cover-cropped in its frame) or, without one, a cream disc with the line icon
class IconPlate extends Control:
	var image: Texture2D
	var dim := false
	var cover := false
	var _icon: Control
	var _img: TextureRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_img)
		_icon = LineIcon.new("briefcase", C_BG, 2.2)
		add_child(_icon)
		resized.connect(_fit)

	func set_tool(t: Dictionary) -> void:
		var path := str(t.get("image", ""))
		image = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
		var st := str(t.get("status", ""))
		dim = st in ["locked", "used"]
		clip_contents = cover
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_img.texture = image
		_img.visible = image != null
		_img.modulate = Color(0.42, 0.42, 0.42) if dim else Color.WHITE
		_icon.visible = image == null and not t.is_empty()
		_icon.set("kind", "lock" if st == "locked" else str(t.get("icon", "briefcase")))
		_icon.set("color", Color(C_BG, 0.55) if dim else C_BG)
		_icon.queue_redraw()
		_fit()
		queue_redraw()

	func _disc_r() -> float:
		return minf(size.x, size.y) * (0.36 if cover else 0.5)

	func _fit() -> void:
		var r := _disc_r()
		_icon.size = Vector2(r, r) * 1.04
		_icon.position = (size - _icon.size) * 0.5
		_img.size = size
		_img.position = Vector2.ZERO

	func _draw() -> void:
		if image != null or not _icon.visible:
			return
		var c := size * 0.5
		var r := _disc_r()
		draw_circle(c + Vector2(0, r * 0.06), r, Color(0, 0, 0, 0.25))
		draw_circle(c, r, Color(C_CREAM, 0.55) if dim else C_CREAM)
		draw_arc(c, r - 2.0, 0, TAU, 48, Color(C_GOLD, 0.8), 1.5, true)


## The open case: leather shell with gold trim, clasps on the lid edge, locks on the front, and a
## velvet tray the tool compartments sit in
class CaseBody extends Control:
	const LID := 30.0
	const FOOT := 34.0
	var k := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func tray_rect() -> Rect2:
		var side := 14.0 * k
		return Rect2(side, LID * k + 4.0 * k, size.x - side * 2, size.y - (LID + FOOT) * k - 8.0 * k)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var shell := StyleBoxFlat.new()
		shell.bg_color = C_LEATHER
		shell.set_corner_radius_all(roundi(18 * k))
		shell.set_border_width_all(2)
		shell.border_color = Color(C_GOLD, 0.85)
		shell.shadow_color = Color(0, 0, 0, 0.5)
		shell.shadow_size = roundi(20 * k)
		shell.shadow_offset = Vector2(0, 6) * k
		shell.anti_aliasing = true
		draw_style_box(shell, Rect2(0, 0, w, h))
		# Lid edge: a lighter band with a gold seam
		var lid := StyleBoxFlat.new()
		lid.bg_color = Color("#123430")
		lid.corner_radius_top_left = roundi(16 * k)
		lid.corner_radius_top_right = roundi(16 * k)
		lid.anti_aliasing = true
		draw_style_box(lid, Rect2(2, 2, w - 4, LID * k - 2))
		draw_line(Vector2(10 * k, LID * k), Vector2(w - 10 * k, LID * k), Color(C_GOLD, 0.7), 1.5, true)
		# Velvet tray
		var tray := tray_rect()
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color("#082E28")
		tb.set_corner_radius_all(roundi(12 * k))
		tb.set_border_width_all(2)
		tb.border_color = Color("#041A17")
		tb.anti_aliasing = true
		draw_style_box(tb, tray)
		# Stitching just inside the shell
		var st := Rect2(7 * k, 7 * k, w - 14 * k, h - 14 * k)
		var sc := Color(C_GOLD, 0.28)
		var d := 6.0 * k
		draw_dashed_line(Vector2(st.position.x, st.end.y), st.end, sc, 1.0, d)
		draw_dashed_line(st.position, Vector2(st.position.x, st.end.y), sc, 1.0, d)
		draw_dashed_line(Vector2(st.end.x, st.position.y), st.end, sc, 1.0, d)
		# Clasps on the lid edge, locks and handle base on the front
		for fx in [0.22, 0.78]:
			_gold_box(Rect2(w * fx - 9 * k, LID * k - 12 * k, 18 * k, 20 * k), 3)
		var fy := h - FOOT * k * 0.5
		for fx in [0.14, 0.86]:
			_gold_box(Rect2(w * fx - 13 * k, fy - 11 * k, 26 * k, 22 * k), 4)
			draw_circle(Vector2(w * fx, fy), 3.0 * k, Color("#4A3818"))
		_gold_box(Rect2(w * 0.5 - 50 * k, fy - 5 * k, 100 * k, 10 * k), 5)
		draw_line(Vector2(10 * k, h - FOOT * k), Vector2(w - 10 * k, h - FOOT * k), Color(C_GOLD, 0.45), 1.0, true)

	func _gold_box(r: Rect2, radius: int) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#C9A55A")
		sb.set_corner_radius_all(roundi(radius * k))
		sb.set_border_width_all(1)
		sb.border_color = Color("#7A5C24")
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = roundi(3 * k)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		draw_line(r.position + Vector2(3 * k, 2 * k), Vector2(r.end.x - 3 * k, r.position.y + 2 * k), Color(1, 0.95, 0.75, 0.6), 1.0, true)


## Gold name plate under a tool (the name comes from data, never from the picture)
class NamePlate extends Control:
	var text := ""
	var dim := false
	var fs := 13
	var k := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var tw := BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var w := minf(tw.x + 30.0 * k, size.x)
		var r := Rect2((size.x - w) * 0.5, 0, w, size.y)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(C_PLATE, 0.55) if dim else C_PLATE
		sb.set_corner_radius_all(roundi(6 * k))
		sb.set_border_width_all(1)
		sb.border_color = Color("#7A5C24")
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = roundi(4 * k)
		sb.shadow_offset = Vector2(0, 2) * k
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		draw_rect(Rect2(r.position + Vector2(3, 2), Vector2(r.size.x - 6, r.size.y * 0.4)), Color(1, 0.96, 0.8, 0.22))
		for x in [r.position.x + 6.0 * k, r.end.x - 6.0 * k]:
			draw_circle(Vector2(x, r.get_center().y), 1.6 * k, Color("#7A5C24"))
		var tx := r.position.x + (r.size.x - tw.x) * 0.5
		draw_string(BOLD, Vector2(tx, r.get_center().y + tw.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, w - 16.0 * k, fs, Color(C_PLATE_TEXT, 0.7) if dim else C_PLATE_TEXT)


## One velvet compartment: the tool's picture, its gold name plate, and on top the focus glow and
## 已選擇 / 未解鎖 / 已使用 badges. Lifts a little when focused.
class ToolSlot extends Button:
	var tool: Dictionary = {}
	var focused := false
	var base_pos := Vector2.ZERO
	var lift := 0.0
	var k := 1.0
	var view
	var hovered := false
	var _art: IconPlate
	var _plate: NamePlate
	var _over: SlotOverlay
	var _tw: Tween

	func _init(v) -> void:
		view = v
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_art = IconPlate.new()
		_art.cover = true
		add_child(_art)
		_plate = NamePlate.new()
		add_child(_plate)
		_over = SlotOverlay.new(self)
		add_child(_over)
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))

	func _on_hover(on: bool) -> void:
		hovered = on
		_relift()
		queue_redraw()
		_over.queue_redraw()

	func set_tool(t: Dictionary) -> void:
		tool = t
		_art.set_tool(t)
		var st := str(t.get("status", ""))
		_plate.text = str(t.get("name", ""))
		_plate.dim = st in ["locked", "used"]
		_plate.queue_redraw()
		tooltip_text = str(t.get("effect", "")) if st != "locked" else str(t.get("unlock_text", ""))
		queue_redraw()
		_over.queue_redraw()

	func set_focused(on: bool) -> void:
		if on == focused:
			return
		focused = on
		_relift()
		queue_redraw()
		_over.queue_redraw()

	func _relift() -> void:
		var target := (6.0 if focused else (2.0 if hovered else 0.0)) * k
		if _tw:
			_tw.kill()
		if UI.is_animation_disabled() or not is_inside_tree():
			lift = target
			apply_lift()
			return
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(_set_lift, lift, target, 0.16)

	func _set_lift(v: float) -> void:
		lift = v
		apply_lift()

	func apply_lift() -> void:
		position = base_pos - Vector2(0, lift)

	func layout_inner() -> void:
		var ph := 24.0 * k
		var inset := 5.0 * k
		_art.position = Vector2(inset, inset)
		_art.size = Vector2(size.x - inset * 2, size.y - inset - ph * 0.5 - 6.0 * k)
		_plate.k = k
		_plate.fs = view._fs(13) if view else roundi(13 * k)
		_plate.size = Vector2(size.x - 12.0 * k, ph)
		_plate.position = Vector2(6.0 * k, size.y - ph - 5.0 * k)
		_plate.queue_redraw()
		_over.position = Vector2.ZERO
		_over.size = size
		_over.queue_redraw()
		queue_redraw()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_VELVET.lightened(0.05) if hovered and str(tool.get("status", "")) != "locked" else C_VELVET
		sb.set_corner_radius_all(roundi(10 * k))
		sb.set_border_width_all(2)
		sb.border_color = Color("#05201C")
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))


class SlotOverlay extends Control:
	var slot

	func _init(s) -> void:
		slot = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k: float = slot.k
		var st := str(slot.tool.get("status", ""))
		var r := Rect2(Vector2.ZERO, size)
		if st == "locked":
			var lc := size * 0.5 - Vector2(0, 10.0 * k)
			draw_circle(lc, 20.0 * k, Color(0, 0, 0, 0.45))
			draw_arc(lc, 20.0 * k, 0, TAU, 40, Color(C_MUTED, 0.6), 1.2, true)
			var bw := 14.0 * k
			draw_rect(Rect2(lc + Vector2(-bw * 0.5, -2.0 * k), Vector2(bw, bw * 0.75)), Color(C_MUTED, 0.85), false, 1.6)
			draw_arc(lc + Vector2(0, -2.0 * k), bw * 0.3, PI, TAU, 16, Color(C_MUTED, 0.85), 1.6, true)
		if slot.focused:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_corner_radius_all(roundi(11 * k))
			sb.set_border_width_all(2)
			sb.border_color = Color("#F1D58C")
			sb.shadow_color = Color(C_GOLD, 0.5)
			sb.shadow_size = roundi(14 * k)
			sb.anti_aliasing = true
			draw_style_box(sb, r.grow(1))
		elif slot.hovered and st != "locked":
			var hb := StyleBoxFlat.new()
			hb.draw_center = false
			hb.set_corner_radius_all(roundi(10 * k))
			hb.set_border_width_all(1)
			hb.border_color = Color(C_GOLD, 0.6)
			hb.anti_aliasing = true
			draw_style_box(hb, r)
		var badge: Array = {"selected": ["已選擇", C_GREEN], "locked": ["未解鎖", C_MUTED], "used": ["已使用", C_MUTED]}.get(st, [])
		if badge.is_empty():
			return
		var fs := roundi(11 * k)
		var tw := BOLD.get_string_size(str(badge[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var bw := tw.x + 14.0 * k + (12.0 * k if st == "selected" else 0.0)
		var bh := 20.0 * k
		var br := Rect2(size.x - bw - 8.0 * k, 8.0 * k, bw, bh)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(badge[1], 0.95) if st == "selected" else Color(0.1, 0.12, 0.12, 0.85)
		bs.set_corner_radius_all(roundi(10 * k))
		bs.anti_aliasing = true
		draw_style_box(bs, br)
		var tx := br.position.x + 7.0 * k
		if st == "selected":
			var c := Vector2(tx + 4.0 * k, br.get_center().y)
			draw_polyline(PackedVector2Array([c + Vector2(-3.5, 0) * k, c + Vector2(-1, 2.6) * k, c + Vector2(4, -2.8) * k]), C_TEXT, 1.6 * k, true)
			tx += 12.0 * k
		draw_string(BOLD, Vector2(tx, br.get_center().y + tw.y * 0.32), str(badge[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)


## A packed tool in the bottom bar (its picture, tap to take it out), or an empty dashed slot
## with a plus; a numbered badge on the corner either way
class PackSlot extends Button:
	var tool_id := ""
	var tool_name := ""
	var index := 1
	var k := 1.0
	var view
	var hovered := false
	var _art: IconPlate
	var _over: PackOverlay

	func _init(v, i: int) -> void:
		view = v
		index = i
		focus_mode = Control.FOCUS_NONE
		for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_art = IconPlate.new()
		_art.cover = true
		add_child(_art)
		_over = PackOverlay.new(self)
		add_child(_over)
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))

	func _on_hover(on: bool) -> void:
		hovered = on
		_over.queue_redraw()

	func set_tool(t: Dictionary) -> void:
		tool_id = str(t.get("id", ""))
		tool_name = str(t.get("name", ""))
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if tool_id != "" else Control.CURSOR_ARROW
		_art.visible = tool_id != ""
		_art.set_tool(t)
		tooltip_text = "%s（點擊移出公事包）" % tool_name if tool_id != "" else "空位 %d" % index
		layout_inner()

	func layout_inner() -> void:
		var inset := 3.0 * k
		_art.position = Vector2(inset, inset)
		_art.size = size - Vector2(inset, inset) * 2
		_over.position = Vector2.ZERO
		_over.size = size
		_over.queue_redraw()


class PackOverlay extends Control:
	var slot

	func _init(s) -> void:
		slot = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k: float = slot.k
		var r := Rect2(Vector2.ZERO, size)
		var filled: bool = slot.tool_id != ""
		if filled:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_corner_radius_all(roundi(8 * k))
			sb.set_border_width_all(2)
			sb.border_color = Color("#F1D58C") if slot.hovered else C_GOLD
			sb.anti_aliasing = true
			draw_style_box(sb, r)
			if slot.hovered:
				draw_rect(r.grow(-2), Color(0, 0, 0, 0.55))
				var fs := roundi(12 * k)
				var tw := BOLD.get_string_size("移除", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(BOLD, Vector2((size.x - tw.x) * 0.5, size.y * 0.5 + tw.y * 0.32), "移除", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)
		else:
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(1, 1, 1, 0.03)
			bg.set_corner_radius_all(roundi(8 * k))
			draw_style_box(bg, r)
			var col := Color(C_CREAM, 0.35)
			var d := 5.0 * k
			draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), col, 1.0, d)
			draw_dashed_line(Vector2(r.position.x, r.end.y), r.end, col, 1.0, d)
			draw_dashed_line(r.position, Vector2(r.position.x, r.end.y), col, 1.0, d)
			draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, col, 1.0, d)
			var c := size * 0.5
			var p := minf(size.x, size.y) * 0.16
			draw_line(c - Vector2(p, 0), c + Vector2(p, 0), Color(C_CREAM, 0.6), 2.0, true)
			draw_line(c - Vector2(0, p), c + Vector2(0, p), Color(C_CREAM, 0.6), 2.0, true)
		# Number badge on the top-left corner
		var br := 10.0 * k
		var bc := Vector2(2.0 * k, 2.0 * k)
		draw_circle(bc, br, Color("#E3C57E") if filled else Color("#3C4A46"))
		draw_arc(bc, br, 0, TAU, 28, Color("#7A5C24") if filled else Color(C_CREAM, 0.35), 1.2, true)
		var nfs := roundi(12 * k)
		var n := str(slot.index)
		var nw := BOLD.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
		draw_string(BOLD, bc + Vector2(-nw.x * 0.5, nw.y * 0.32), n, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, C_PLATE_TEXT if filled else C_CREAM)


## Gold lines from the focused tool to the clue cards it connects to
class LinesOverlay extends Control:
	var view

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var v = view
		if v == null:
			return
		var slot: Control = null
		for s in v._slots:
			if (s as Control).visible and s.focused:
				slot = s
		if slot == null:
			return
		var inv := get_global_transform().affine_inverse()
		var sr: Rect2 = slot.get_global_rect()
		var from: Vector2 = inv * Vector2(sr.position.x + 2.0, sr.position.y + sr.size.y * 0.4)
		var k: float = v.k
		var ids: Array = v.focused_matches()
		for r: Control in v._clue_rows + [v._risk_row]:
			if not r.visible or not ids.has(r.clue_id) or not r.matched:
				continue
			var rr: Rect2 = r.get_global_rect()
			var to: Vector2 = inv * Vector2(rr.end.x, rr.get_center().y)
			var dx := maxf((from.x - to.x) * 0.5, 30.0 * k)
			var pts := PackedVector2Array()
			for i in range(25):
				var t := i / 24.0
				var a := from.lerp(from + Vector2(-dx, 0), t)
				var b := (from + Vector2(-dx, 0)).lerp(to + Vector2(dx, 0), t)
				var c := (to + Vector2(dx, 0)).lerp(to, t)
				pts.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
			draw_polyline(pts, Color(C_GOLD, 0.22), 7.0 * k, true)
			draw_polyline(pts, Color("#F1D58C"), 2.0 * k, true)
			draw_circle(to, 4.0 * k, Color("#F1D58C"))
			draw_circle(from, 5.0 * k, Color("#F1D58C"))
			draw_circle(from, 2.5 * k, C_LEATHER)


## 開始會談: green with a gold edge when the case is packed, grey before
class StartButton extends Button:
	var k := 1.0
	var _label: Label
	var _icon: Control
	var _arrow: Control
	var _hover := false

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_icon = LineIcon.new("chat_user", C_TEXT, 2.0)
		add_child(_icon)
		_label = Label.new()
		_label.text = "開始會談"
		_label.add_theme_font_override("font", BOLD)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		_arrow = LineIcon.new("chevron_r", C_TEXT, 2.0)
		add_child(_arrow)
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))
		resized.connect(_fit)

	func _on_hover(on: bool) -> void:
		_hover = on
		queue_redraw()

	func refresh_state() -> void:
		var col := C_TEXT if not disabled else Color("#C9CFCC")
		_label.add_theme_color_override("font_color", col)
		for ic: Control in [_icon, _arrow]:
			ic.set("color", col)
			ic.queue_redraw()
		queue_redraw()

	func set_k(v: float) -> void:
		k = v
		_fit()

	func _fit() -> void:
		_label.add_theme_font_size_override("font_size", roundi(22 * k))
		_label.reset_size()
		var ic := 24.0 * k
		var aw := 14.0 * k
		var gap := 10.0 * k
		var group := ic + gap + _label.size.x + gap + aw
		var x := (size.x - group) * 0.5
		_icon.size = Vector2(ic, ic)
		_icon.position = Vector2(x, (size.y - ic) * 0.5)
		_label.position = Vector2(x + ic + gap, (size.y - _label.size.y) * 0.5)
		_arrow.size = Vector2(aw, aw)
		_arrow.position = Vector2(_label.position.x + _label.size.x + gap, (size.y - aw) * 0.5)
		queue_redraw()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(roundi(12 * k))
		sb.set_border_width_all(2)
		sb.anti_aliasing = true
		if disabled:
			sb.bg_color = Color("#59615F", 0.9)
			sb.border_color = Color(1, 1, 1, 0.16)
		else:
			sb.bg_color = Color("#11905F") if _hover else Color("#0E7A55")
			sb.border_color = Color(C_GOLD, 1.0 if _hover else 0.8)
			sb.shadow_color = Color(C_GOLD, 0.25)
			sb.shadow_size = roundi(10 * k)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
