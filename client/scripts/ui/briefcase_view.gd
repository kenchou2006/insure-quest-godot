extends Control
## 顧問公事包: one fixed layout filled from data — the customer and clues on the left, the tools in
## the case in the middle, the focused tool's attributes on the right, packed tools and 開始會談 at
## the bottom. Nothing here names a client or a tool: set_customer() / set_tools() refill the same
## nodes, so a different customer never moves the layout. Gold lines and checks come from
## BriefcaseData.matches() (discovered clues only); there is no right / wrong marking.

signal toggle_requested(tool_id: String)
signal start_requested

const BriefcaseData := preload("res://scripts/briefcase_data.gd")
const LineIcon := preload("res://scripts/ui/line_icon.gd")
const FONT := preload("res://assets/fonts/regular.tres")
const BOLD := preload("res://assets/fonts/bold.tres")

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_LEATHER := Color("#0A3631")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_CREAM := Color("#EFE6D2")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
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
var k := 1.0
var _settle := 0

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
var _avatar_box: Control
var _avatar_id := ""
var _c_name: Label
var _c_sub: Label
var _c_tags: Label
var _ov_values: Array = []
var _clue_count: Label
var _clue_box: VBoxContainer
var _clue_rows: Array = []
var _risk_row: ClueRow
# Briefcase
var _case_title: Label
var _slots: Array = []
# Attributes
var _a_status: Label
var _a_status_box: PanelContainer
var _a_plate: IconPlate
var _a_name: Label
var _a_cat: Label
var _a_effect: Label
var _a_chips: HFlowContainer
var _a_usage: Label
var _a_matches: VBoxContainer
var _a_button: Button
var _a_note: Label
# Bottom bar
var _bar: Panel
var _bar_title: Label
var _bar_count: Label
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
	v.add_theme_constant_override("separation", 4)
	clue_panel.add_child(v)
	_clue_box = v
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	_avatar_box = Control.new()
	_avatar_box.custom_minimum_size = Vector2(50, 50)
	_avatar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_avatar_box)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 1)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nv)
	_c_name = _label("", 19, C_TEXT, BOLD)
	nv.add_child(_c_name)
	_c_sub = _label("", 13, C_MUTED)
	_c_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_c_sub.clip_text = true
	nv.add_child(_c_sub)
	_c_tags = _label("", 12, C_GOLD)
	nv.add_child(_c_tags)
	v.add_child(_divider())
	for key: String in ["家庭", "需求", "限制", "預算"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var kl := _label(key, 12, C_GOLD)
		kl.custom_minimum_size = Vector2(32, 0)
		kl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(kl)
		var vl := _label("", 13, C_TEXT)
		vl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		vl.max_lines_visible = 2
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(vl)
		_ov_values.append(vl)
		v.add_child(row)
	v.add_child(_divider())
	var ch := HBoxContainer.new()
	var cl := _label("關鍵線索", 14, C_GOLD, BOLD)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(cl)
	_clue_count = _label("", 12, C_MUTED)
	ch.add_child(_clue_count)
	v.add_child(ch)
	for i in range(CLUE_ROWS):
		var r := ClueRow.new(self)
		_clue_rows.append(r)
		v.add_child(r)
	_risk_row = ClueRow.new(self)
	v.add_child(_risk_row)


func _build_case() -> void:
	briefcase_area = CaseBody.new()
	_body.add_child(briefcase_area)
	_case_title = _label("", 14, C_GOLD, BOLD)
	briefcase_area.add_child(_case_title)
	for i in range(SLOTS):
		var s := ToolSlot.new(self)
		s.pressed.connect(_on_slot_pressed.bind(s))
		briefcase_area.add_child(s)
		_slots.append(s)


func _build_attributes() -> void:
	attr_panel = PanelContainer.new()
	attr_panel.add_theme_stylebox_override("panel", _panel_style(Color(C_CARD, 0.95), 16))
	_body.add_child(attr_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	attr_panel.add_child(v)
	var top := HBoxContainer.new()
	var tl := _label("工具屬性", 13, C_GOLD, BOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	_a_status_box = PanelContainer.new()
	_a_status = _label("", 12, C_TEXT)
	_a_status_box.add_child(_a_status)
	top.add_child(_a_status_box)
	v.add_child(top)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_a_plate = IconPlate.new()
	_a_plate.custom_minimum_size = Vector2(52, 52)
	head.add_child(_a_plate)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 1)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_a_name = _label("", 20, C_TEXT, BOLD)
	nv.add_child(_a_name)
	_a_cat = _label("", 13, C_MUTED)
	nv.add_child(_a_cat)
	head.add_child(nv)
	v.add_child(head)
	v.add_child(_divider())
	v.add_child(_label("會談效果", 12, C_GOLD))
	_a_effect = _label("", 14, C_TEXT)
	_a_effect.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(_a_effect)
	_a_chips = HFlowContainer.new()
	_a_chips.add_theme_constant_override("h_separation", 6)
	_a_chips.add_theme_constant_override("v_separation", 6)
	v.add_child(_a_chips)
	var uh := HBoxContainer.new()
	uh.add_theme_constant_override("separation", 8)
	uh.add_child(_label("使用時機", 12, C_GOLD))
	_a_usage = _label("", 13, C_TEXT)
	_a_usage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uh.add_child(_a_usage)
	v.add_child(uh)
	v.add_child(_label("對應已取得的線索", 12, C_GOLD))
	_a_matches = VBoxContainer.new()
	_a_matches.add_theme_constant_override("separation", 3)
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
	_a_button.focus_mode = Control.FOCUS_NONE
	_a_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_a_button.add_theme_font_override("font", BOLD)
	_fonts.append([_a_button, 16])
	_a_button.pressed.connect(func():
		if focused != "" and not sending:
			toggle_requested.emit(focused)
	)
	v.add_child(_a_button)


func _build_bar() -> void:
	_bar = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_BG, 0.94)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_GOLD, 0.32)
	sb.anti_aliasing = true
	_bar.add_theme_stylebox_override("panel", sb)
	add_child(_bar)
	_bar_title = _label("本次攜帶", 15, C_TEXT)
	_bar.add_child(_bar_title)
	_bar_count = _label("", 22, C_GOLD, BOLD)
	_bar.add_child(_bar_count)
	status_label = _label("", 14, C_MUTED)
	_bar.add_child(status_label)
	start_button = StartButton.new()
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


func _refresh_customer() -> void:
	var c := customer
	var id := str(c.get("customer_portrait", ""))
	if id != _avatar_id or _avatar_box.get_child_count() == 0:
		_avatar_id = id
		for n in _avatar_box.get_children():
			n.queue_free()
		if id != "" or str(c.get("customer_name", "")) != "":
			var av := Portraits.create_avatar(id, str(c.get("customer_name", "")), 50)
			av.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_avatar_box.add_child(av)
			_fit_avatar()
	_c_name.text = str(c.get("customer_name", ""))
	var age := int(c.get("customer_age", 0))
	_c_sub.text = ("%d 歲・" % age if age > 0 else "") + str(c.get("customer_job", ""))
	var tags: Array = []
	for f: String in ["customer_age_group", "difficulty_level"]:
		var t := str(c.get(f, ""))
		if t != "":
			tags.append(t if f != "difficulty_level" else "難度 " + t)
	_c_tags.text = "｜".join(tags)
	var vals := [str(c.get("family_structure", "")), _joined(c.get("primary_needs", [])), _joined(c.get("financial_constraints", [])), str(c.get("budget_range", ""))]
	for i in range(_ov_values.size()):
		var l: Label = _ov_values[i]
		l.text = vals[i] if str(vals[i]).strip_edges() != "" else "會談中確認"
		l.tooltip_text = l.text
		l.get_parent().visible = not c.is_empty()
	var shown: Array = BriefcaseData.top_clues(c, CLUE_ROWS)
	var found := 0
	for x: Dictionary in shown:
		if bool(x.get("unlocked", false)):
			found += 1
	_clue_count.text = "已取得 %d 項" % found if not shown.is_empty() else ""
	var matched := focused_matches()
	for i in range(_clue_rows.size()):
		var r: ClueRow = _clue_rows[i]
		r.visible = i < shown.size()
		if i < shown.size():
			var cl: Dictionary = shown[i]
			r.clue_id = str(cl.get("id", ""))
			if bool(cl.get("unlocked", false)):
				r.set_content(str(cl.get("icon", "search")), str(cl.get("title", "")), str(cl.get("detail", "")), false)
			else:
				# Never the answer: a locked row says only that something is still to be found
				r.set_content("lock", "未取得線索", "會談中觀察後才會出現", true)
			r.set_matched(matched.has(r.clue_id) and bool(cl.get("unlocked", false)))
	var risk := str(c.get("compliance_risk", ""))
	_risk_row.visible = risk != ""
	_risk_row.clue_id = "compliance"
	_risk_row.set_content("stamp", "合規提醒", risk, false)
	_risk_row.set_matched(matched.has("compliance"))


func _refresh_case() -> void:
	_case_title.text = "顧問公事包｜可攜帶 %d 項" % capacity
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
	_a_plate.set_tool(t)
	_a_name.text = str(t.get("name", "")) if not t.is_empty() else "選一項工具查看"
	_a_cat.text = str(t.get("category", ""))
	_a_effect.text = str(t.get("effect", ""))
	for n in _a_chips.get_children():
		n.queue_free()
	for c: Dictionary in t.get("chips", []):
		_a_chips.add_child(_chip(str(c.get("icon", "check")), str(c.get("label", ""))))
	_a_usage.text = str(t.get("usage_limit", "")) if str(t.get("usage_limit", "")) != "" else "—"
	for n in _a_matches.get_children():
		n.queue_free()
	var titles := {"compliance": "合規提醒"}
	for cl: Dictionary in customer.get("clues", []):
		titles[str(cl.get("id", ""))] = str(cl.get("title", ""))
	var m := focused_matches()
	for id in m:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var ic: Control = LineIcon.new("check", C_GOLD, 2.0)
		ic.custom_minimum_size = Vector2(14, 14) * k
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		row.add_child(_label(str(titles.get(id, id)), 13, C_CREAM, null, true))
		_a_matches.add_child(row)
	if m.is_empty() and not t.is_empty():
		var none := _label("目前已取得的線索中，沒有直接對應的項目", 12, C_MUTED, null, true)
		none.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_a_matches.add_child(none)
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
	_bar_count.text = "%d／%d" % [selected.size(), capacity]
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
	status_label.add_theme_color_override("font_color", C_GOLD if left == 0 and not sending else C_MUTED)
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
	_avatar_box.custom_minimum_size = Vector2(50, 50) * k
	_clue_box.add_theme_constant_override("separation", roundi(4 * k))
	_fit_avatar()
	_a_plate.custom_minimum_size = Vector2(52, 52) * k
	for r: ClueRow in _clue_rows + [_risk_row]:
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
		if absf(p.size.y - p.get_combined_minimum_size().y) > 1.0 and (UI.is_portrait() or p.get_combined_minimum_size().y > p.size.y):
			off = true
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
	var gap := 14.0 * k
	var bar_h := 78.0 * k
	_bar.position = Vector2(0, size.y - bar_h)
	_bar.size = Vector2(w - reserve_right, bar_h)
	_layout_bar_wide()
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(w, size.y - bar_h - gap)
	_body.custom_minimum_size = Vector2(0, _scroll.size.y)
	_body.size = _scroll.size
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.custom_minimum_size = Vector2.ZERO
	_title.reset_size()
	_title.position = Vector2.ZERO
	_sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sub.custom_minimum_size = Vector2.ZERO
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub.clip_text = true
	_sub.reset_size()
	# One header line: the hint follows the title
	var sx := _title.size.x + 16.0 * k
	_sub.size.x = maxf(w - sx, 0)
	_sub.position = Vector2(sx, _title.size.y - _sub.size.y - 3.0 * k)
	var top := _title.size.y + 10.0 * k
	var col_h := _scroll.size.y - top
	var left_w := clampf(w * 0.28, 280.0 * k, 350.0 * k)
	var right_w := clampf(w * 0.24, 250.0 * k, 300.0 * k)
	var center_w := w - left_w - right_w - gap * 2
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
	var bar_h := 128.0 * k
	_bar.position = Vector2(0, size.y - bar_h)
	_bar.size = Vector2(w, bar_h)
	_layout_bar_portrait()
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(w, size.y - bar_h - gap)
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
	var slot_h := 124.0 * k
	var case_h := 48.0 * k + slot_h * 3 + 12.0 * k * 2 + 18.0 * k
	_place(briefcase_area, Vector2(0, y), Vector2(w, case_h))
	_layout_slots(2)
	y += case_h + gap
	attr_panel.custom_minimum_size = Vector2(w, 0)
	_place(attr_panel, Vector2(0, y), Vector2(w, attr_panel.get_combined_minimum_size().y))
	y += attr_panel.size.y + gap
	_body.custom_minimum_size = Vector2(0, y)
	_body.size = Vector2(w, y)
	# Lines need the columns side by side; the checks on the clues still show the fit
	_lines.visible = false


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz


func _layout_slots(cols: int) -> void:
	var a := briefcase_area.size
	var pad := 18.0 * k
	var head := 48.0 * k
	_case_title.reset_size()
	_case_title.position = Vector2(pad + 4.0 * k, 22.0 * k + (head - 22.0 * k - _case_title.size.y) * 0.5)
	(briefcase_area as CaseBody).k = k
	briefcase_area.queue_redraw()
	var rows := ceili(float(SLOTS) / cols)
	var gap := 12.0 * k
	var sw := (a.x - pad * 2 - gap * (cols - 1)) / cols
	var sh := (a.y - head - pad - gap * (rows - 1)) / rows
	for i in range(_slots.size()):
		var s: ToolSlot = _slots[i]
		s.k = k
		s.size = Vector2(sw, sh)
		s.base_pos = Vector2(pad + (i % cols) * (sw + gap), head + floori(float(i) / cols) * (sh + gap))
		s.apply_lift()
		s.layout_inner()


func _layout_bar_wide() -> void:
	var h := _bar.size.y
	var pad := 18.0 * k
	_bar_title.reset_size()
	_bar_count.reset_size()
	var x := pad
	_bar_title.position = Vector2(x, h * 0.5 - _bar_title.size.y - 1.0 * k)
	_bar_count.position = Vector2(x, h * 0.5 - 2.0 * k)
	x += maxf(_bar_title.size.x, _bar_count.size.x) + 16.0 * k
	var bw := clampf(_bar.size.x * 0.17, 150.0 * k, 210.0 * k)
	var bh := 52.0 * k
	start_button.size = Vector2(bw, bh)
	start_button.position = Vector2(_bar.size.x - pad - bw, (h - bh) * 0.5)
	(start_button as StartButton).set_k(k)
	var hint_w := 190.0 * k
	var room := start_button.position.x - 14.0 * k - hint_w - x
	var pw := clampf((room - 10.0 * k * (capacity - 1)) / maxi(capacity, 1), 110.0 * k, 190.0 * k)
	for i in range(_pack.size()):
		var p: PackSlot = _pack[i]
		p.k = k
		p.size = Vector2(pw, 56.0 * k)
		p.position = Vector2(x + i * (pw + 10.0 * k), (h - p.size.y) * 0.5)
		p.layout_inner()
	var after := x + _pack.size() * (pw + 10.0 * k) + 6.0 * k
	status_label.custom_minimum_size = Vector2.ZERO
	status_label.reset_size()
	status_label.position = Vector2(after, (h - status_label.size.y) * 0.5)
	status_label.size.x = maxf(start_button.position.x - 10.0 * k - after, 0)
	status_label.clip_text = true


func _layout_bar_portrait() -> void:
	var h := _bar.size.y
	var pad := 12.0 * k
	_bar_title.reset_size()
	_bar_count.reset_size()
	_bar_title.position = Vector2(pad, pad)
	_bar_count.position = Vector2(pad, pad + _bar_title.size.y)
	var x := pad + maxf(_bar_title.size.x, _bar_count.size.x) + 10.0 * k
	var row_h := 50.0 * k
	var pw := (_bar.size.x - x - pad - 8.0 * k * (capacity - 1)) / maxi(capacity, 1)
	for i in range(_pack.size()):
		var p: PackSlot = _pack[i]
		p.k = k
		p.size = Vector2(pw, row_h)
		p.position = Vector2(x + i * (pw + 8.0 * k), pad)
		p.layout_inner()
	var bh := 48.0 * k
	var bw := minf(200.0 * k, _bar.size.x * 0.45)
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


func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = C_LINE
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _chip(icon: String, text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_GOLD, 0.12)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_GOLD, 0.55)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 8 * k
	sb.content_margin_right = 10 * k
	sb.content_margin_top = 3 * k
	sb.content_margin_bottom = 3 * k
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	var ic: Control = LineIcon.new(icon, C_GOLD, 1.6)
	ic.custom_minimum_size = Vector2(14, 14) * k
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(_label(text, 12, C_CREAM))
	p.add_child(h)
	return p


func _panel_style(bg: Color, pad := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = C_LINE
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.85
	sb.content_margin_bottom = pad * 0.85
	sb.anti_aliasing = true
	return sb


func _style_action(b: Button, packed: bool) -> void:
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.content_margin_top = 10 * k
		sb.content_margin_bottom = 10 * k
		sb.anti_aliasing = true
		sb.set_border_width_all(1)
		if st == "disabled":
			sb.bg_color = Color(C_MUTED, 0.12)
			sb.border_color = Color(C_MUTED, 0.25)
		elif packed:
			sb.bg_color = Color(C_CREAM, 0.06 if st != "hover" else 0.12)
			sb.border_color = Color(C_CREAM, 0.45)
		else:
			sb.bg_color = C_GREEN if st != "hover" else C_GREEN.lightened(0.08)
			sb.border_color = Color(C_GOLD, 0.5 if st != "hover" else 0.9)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", C_TEXT)
	b.add_theme_color_override("font_pressed_color", C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(C_MUTED, 0.8))


# --- Pieces ------------------------------------------------------------------------------------

## One clue (or the compliance reminder) on the customer panel; gold frame and check when the
## focused tool connects to it
class ClueRow extends PanelContainer:
	var clue_id := ""
	var matched := false
	var view
	var _icon: Control
	var _title: Label
	var _detail: Label
	var _check: Control
	var _locked := false

	func _init(v) -> void:
		view = v
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		add_child(h)
		_icon = LineIcon.new("search", C_GOLD, 1.8)
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_icon)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tv)
		_title = v._label("", 14, C_TEXT, BOLD)
		tv.add_child(_title)
		_detail = v._label("", 12, C_MUTED)
		_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_detail.clip_text = true
		tv.add_child(_detail)
		_check = LineIcon.new("check", C_GOLD, 2.2)
		_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_check)
		set_k(1.0)
		set_matched(false)

	func set_k(k: float) -> void:
		_icon.custom_minimum_size = Vector2(20, 20) * k
		_check.custom_minimum_size = Vector2(16, 16) * k
		custom_minimum_size.y = 40.0 * k
		_restyle(k)

	func set_content(icon: String, title: String, detail: String, locked: bool) -> void:
		_locked = locked
		_icon.set("kind", icon)
		_icon.set("color", Color(C_MUTED, 0.7) if locked else C_GOLD)
		_icon.queue_redraw()
		_title.text = title
		_title.add_theme_color_override("font_color", Color(C_MUTED, 0.85) if locked else C_TEXT)
		_detail.text = detail
		_detail.tooltip_text = detail
		_restyle(view.k)

	func set_matched(on: bool) -> void:
		matched = on
		_check.modulate.a = 1.0 if on else 0.0
		_restyle(view.k if view else 1.0)

	func _restyle(k: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(C_GOLD, 0.1) if matched else (Color(0, 0, 0, 0.16) if _locked else Color(1, 1, 1, 0.035))
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2 if matched else 1)
		sb.border_color = C_GOLD if matched else (Color(C_MUTED, 0.22) if _locked else C_LINE)
		if _locked:
			sb.border_blend = false
		sb.content_margin_left = 10 * k
		sb.content_margin_right = 10 * k
		sb.content_margin_top = 3 * k
		sb.content_margin_bottom = 3 * k
		sb.anti_aliasing = true
		add_theme_stylebox_override("panel", sb)


## Cream disc with the tool's line drawing (or its image when the data names one)
class IconPlate extends Control:
	var kind := "briefcase"
	var image: Texture2D
	var dim := false
	var _icon: Control
	var _img: TextureRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon = LineIcon.new("briefcase", C_BG, 2.2)
		add_child(_icon)
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_img)
		resized.connect(_fit)

	func set_tool(t: Dictionary) -> void:
		var path := str(t.get("image", ""))
		image = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
		dim = str(t.get("status", "")) in ["locked", "used"]
		_img.texture = image
		_img.visible = image != null
		_icon.visible = image == null
		_icon.set("kind", "lock" if str(t.get("status", "")) == "locked" else str(t.get("icon", "briefcase")))
		_icon.set("color", Color(C_BG, 0.55) if dim else C_BG)
		_icon.queue_redraw()
		queue_redraw()

	func _fit() -> void:
		var s := minf(size.x, size.y)
		_icon.size = Vector2(s, s) * 0.52
		_icon.position = (size - _icon.size) * 0.5
		_img.size = size
		_img.position = Vector2.ZERO

	func _draw() -> void:
		if image != null:
			return
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c + Vector2(0, r * 0.06), r, Color(0, 0, 0, 0.25))
		draw_circle(c, r, Color(C_CREAM, 0.55) if dim else C_CREAM)
		draw_arc(c, r - 2.0, 0, TAU, 48, Color(C_GOLD, 0.8), 1.5, true)


## The case: leather body with a handle and gold stitching; the tool slots sit inside
class CaseBody extends Control:
	var k := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var hw := minf(size.x * 0.26, 170.0 * k)
		var hh := 22.0 * k
		var hx := (size.x - hw) * 0.5
		var handle := StyleBoxFlat.new()
		handle.draw_center = false
		handle.set_border_width_all(roundi(5 * k))
		handle.border_color = Color("#6E5530")
		handle.corner_radius_top_left = roundi(12 * k)
		handle.corner_radius_top_right = roundi(12 * k)
		handle.anti_aliasing = true
		draw_style_box(handle, Rect2(hx, 0, hw, hh + 8.0 * k))
		var body := StyleBoxFlat.new()
		body.bg_color = C_LEATHER
		body.set_corner_radius_all(roundi(18 * k))
		body.set_border_width_all(2)
		body.border_color = Color(C_GOLD, 0.75)
		body.shadow_color = Color(0, 0, 0, 0.35)
		body.shadow_size = roundi(14 * k)
		body.shadow_offset = Vector2(0, 4) * k
		body.anti_aliasing = true
		draw_style_box(body, Rect2(0, hh, size.x, size.y - hh))
		# Clasps either side of the handle
		for x in [hx - 18.0 * k, hx + hw + 4.0 * k]:
			var clasp := StyleBoxFlat.new()
			clasp.bg_color = Color(C_GOLD, 0.85)
			clasp.set_corner_radius_all(roundi(3 * k))
			draw_style_box(clasp, Rect2(x, hh - 3.0 * k, 14.0 * k, 9.0 * k))
		# Stitching
		var r := Rect2(8.0 * k, hh + 8.0 * k, size.x - 16.0 * k, size.y - hh - 16.0 * k)
		var col := Color(C_GOLD, 0.35)
		var dash := 6.0 * k
		draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), col, 1.0, dash)
		draw_dashed_line(Vector2(r.position.x, r.end.y), r.end, col, 1.0, dash)
		draw_dashed_line(r.position, Vector2(r.position.x, r.end.y), col, 1.0, dash)
		draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, col, 1.0, dash)


## One tool in the case: lifts with a gold frame when focused; badges for 已選擇 / 未解鎖 / 已使用
class ToolSlot extends Button:
	var tool: Dictionary = {}
	var focused := false
	var base_pos := Vector2.ZERO
	var lift := 0.0
	var k := 1.0
	var view
	var _plate: IconPlate
	var _name: Label
	var _cat: Label
	var _hover := false
	var _tw: Tween

	func _init(v) -> void:
		view = v
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_plate = IconPlate.new()
		add_child(_plate)
		_name = v._label("", 15, C_TEXT, BOLD)
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.clip_text = true
		add_child(_name)
		_cat = v._label("", 12, C_MUTED)
		_cat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_cat)
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))

	func _on_hover(on: bool) -> void:
		_hover = on
		_relift()
		queue_redraw()

	func set_tool(t: Dictionary) -> void:
		tool = t
		_plate.set_tool(t)
		_name.text = str(t.get("name", ""))
		_cat.text = str(t.get("category", ""))
		var st := str(t.get("status", ""))
		_name.add_theme_color_override("font_color", Color(C_MUTED, 0.8) if st in ["locked", "used"] else C_TEXT)
		tooltip_text = str(t.get("effect", "")) if st != "locked" else str(t.get("unlock_text", ""))
		queue_redraw()

	func set_focused(on: bool) -> void:
		if on == focused:
			return
		focused = on
		_relift()
		queue_redraw()

	func _relift() -> void:
		var target := (8.0 if focused else (3.0 if _hover else 0.0)) * k
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
		var nh := _name.get_combined_minimum_size().y
		var ch := _cat.get_combined_minimum_size().y
		var gap := 6.0 * k
		var ps := clampf(size.y - nh - ch - gap - 26.0 * k, 24.0 * k, 64.0 * k)
		var y := (size.y - (ps + gap + nh + ch)) * 0.5 + 2.0 * k
		_plate.size = Vector2(ps, ps)
		_plate.position = Vector2((size.x - ps) * 0.5, y)
		_name.position = Vector2(6.0 * k, y + ps + gap)
		_name.size = Vector2(size.x - 12.0 * k, nh)
		_cat.position = Vector2(6.0 * k, _name.position.y + nh)
		_cat.size = Vector2(size.x - 12.0 * k, ch)
		queue_redraw()

	func _draw() -> void:
		var st := str(tool.get("status", ""))
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#123F37") if st != "locked" else Color("#0A2C27")
		if _hover and st != "locked":
			sb.bg_color = sb.bg_color.lightened(0.05)
		sb.set_corner_radius_all(roundi(14 * k))
		sb.set_border_width_all(2 if focused else 1)
		sb.border_color = C_GOLD if focused else (Color(C_GREEN, 0.8) if st == "selected" else Color(1, 1, 1, 0.1))
		if focused:
			sb.shadow_color = Color(C_GOLD, 0.28)
			sb.shadow_size = roundi(12 * k)
		elif lift > 0.5:
			sb.shadow_color = Color(0, 0, 0, 0.3)
			sb.shadow_size = roundi(8 * k)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var badge: Array = {"selected": ["已選擇", C_GREEN], "locked": ["未解鎖", C_MUTED], "used": ["已使用", C_MUTED]}.get(st, [])
		if not badge.is_empty():
			var fs := roundi(11 * k)
			var tw := BOLD.get_string_size(str(badge[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var bw := tw.x + 14.0 * k + (12.0 * k if st == "selected" else 0.0)
			var bh := 20.0 * k
			var br := Rect2(size.x - bw - 8.0 * k, 8.0 * k, bw, bh)
			var bs := StyleBoxFlat.new()
			bs.bg_color = Color(badge[1], 0.9 if st == "selected" else 0.25)
			bs.set_corner_radius_all(roundi(10 * k))
			bs.anti_aliasing = true
			draw_style_box(bs, br)
			var tx := br.position.x + 7.0 * k
			if st == "selected":
				var c := Vector2(tx + 4.0 * k, br.get_center().y)
				draw_polyline(PackedVector2Array([c + Vector2(-3.5, 0) * k, c + Vector2(-1, 2.6) * k, c + Vector2(4, -2.8) * k]), C_TEXT, 1.6 * k, true)
				tx += 12.0 * k
			draw_string(BOLD, Vector2(tx, br.get_center().y + tw.y * 0.32), str(badge[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)


## A packed tool in the bottom bar (tap to take it out), or an empty dashed slot
class PackSlot extends Button:
	var tool_id := ""
	var index := 1
	var k := 1.0
	var view
	var _plate: IconPlate
	var _name: Label
	var _hint: Label
	var _hover := false

	func _init(v, i: int) -> void:
		view = v
		index = i
		focus_mode = Control.FOCUS_NONE
		for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_plate = IconPlate.new()
		add_child(_plate)
		_name = v._label("", 13, C_TEXT, BOLD)
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.clip_text = true
		add_child(_name)
		_hint = v._label("", 11, C_MUTED)
		add_child(_hint)
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))

	func _on_hover(on: bool) -> void:
		_hover = on
		_sync_hint()
		queue_redraw()

	func set_tool(t: Dictionary) -> void:
		tool_id = str(t.get("id", ""))
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if tool_id != "" else Control.CURSOR_ARROW
		_plate.set_tool(t)
		_name.text = str(t.get("name", "")) if tool_id != "" else "空位 %d" % index
		_name.add_theme_color_override("font_color", C_TEXT if tool_id != "" else Color(C_MUTED, 0.7))
		tooltip_text = "點擊移出公事包" if tool_id != "" else ""
		_sync_hint()
		layout_inner()
		queue_redraw()

	func _sync_hint() -> void:
		_hint.text = ("點擊移除" if _hover else "已攜帶") if tool_id != "" else "尚未放入"

	func layout_inner() -> void:
		var ps := size.y * 0.7
		_plate.size = Vector2(ps, ps)
		_plate.position = Vector2(8.0 * k, (size.y - ps) * 0.5)
		# Narrow slots (phones) give the room to the tool name
		var plate := tool_id != "" and size.x >= 150.0 * k
		_plate.visible = plate
		var x := (_plate.position.x + ps + 8.0 * k) if plate else 12.0 * k
		_name.reset_size()
		_hint.reset_size()
		var th := _name.size.y + _hint.size.y
		_name.position = Vector2(x, (size.y - th) * 0.5)
		_name.size.x = maxf(size.x - x - 8.0 * k, 0)
		_hint.position = Vector2(x, _name.position.y + _name.size.y)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if tool_id == "":
			var col := Color(C_CREAM, 0.3)
			var d := 5.0 * k
			draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), col, 1.0, d)
			draw_dashed_line(Vector2(r.position.x, r.end.y), r.end, col, 1.0, d)
			draw_dashed_line(r.position, Vector2(r.position.x, r.end.y), col, 1.0, d)
			draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, col, 1.0, d)
			return
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#123F37").lightened(0.05 if _hover else 0.0)
		sb.set_corner_radius_all(roundi(12 * k))
		sb.set_border_width_all(1)
		sb.border_color = Color(C_GOLD, 0.9 if _hover else 0.55)
		sb.anti_aliasing = true
		draw_style_box(sb, r)


## Gold lines from the focused tool to the clues it connects to
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
		var from: Vector2 = inv * Vector2(sr.position.x, sr.get_center().y)
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
			draw_polyline(pts, Color(C_GOLD, 0.18), 6.0 * k, true)
			draw_polyline(pts, Color(C_GOLD, 0.9), 2.0 * k, true)
			draw_circle(to, 4.0 * k, C_GOLD)
			draw_circle(from, 4.0 * k, C_GOLD)


## 開始會談: green when the case is packed, dim before
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
		var col := C_TEXT if not disabled else Color(C_MUTED, 0.8)
		_label.add_theme_color_override("font_color", col)
		for ic: Control in [_icon, _arrow]:
			ic.set("color", col)
			ic.queue_redraw()
		queue_redraw()

	func set_k(v: float) -> void:
		k = v
		_fit()

	func _fit() -> void:
		_label.add_theme_font_size_override("font_size", roundi(20 * k))
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
		sb.set_corner_radius_all(roundi(14 * k))
		sb.set_border_width_all(1)
		sb.anti_aliasing = true
		if disabled:
			sb.bg_color = Color(C_MUTED, 0.14)
			sb.border_color = Color(C_MUTED, 0.3)
		else:
			sb.bg_color = C_GREEN.lightened(0.06 if _hover else 0.0)
			sb.border_color = Color(C_GOLD, 0.9 if _hover else 0.55)
			sb.shadow_color = Color(0, 0, 0, 0.25)
			sb.shadow_size = roundi(8 * k)
			sb.shadow_offset = Vector2(0, 2) * k
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
