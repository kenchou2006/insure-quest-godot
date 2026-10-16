extends Control
## Pre-game case setup: choose the primary client for this game and pack the advisor briefcase.
## Sends {"type": "setup"}; game.gd removes this overlay once the server state shows the case.

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")

var _client_id := ""
var _tools: Array[String] = []
var _size := 3
var _client_cards := {}
var _tool_cards := {}
var _confirm: Button
var _status: Label
var _sent := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(C_BG, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 16 if UI.is_phone() else 32
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	add_child(margin)
	var outer := UI.vbox(16)
	margin.add_child(outer)

	var body := UI.vbox(24)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := UI.scroll(body)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var s: Dictionary = Net.state
	_size = int(s.get("briefcaseSize", 3))

	var head := UI.vbox(4)
	head.add_child(UI.label("今日案件", 13, C_MUTED))
	head.add_child(UI.label("選擇這一局的主要客戶", 26 if UI.is_phone() else 30, C_TEXT, true))
	head.add_child(UI.label("整局都會陪同一位客戶：每次抵達客戶節點，就推進一次會談（需求訪談 → 方案設計 → 異議處理與結果）。其他客戶會透過轉介紹與人脈陸續出現。", 15, C_MUTED, true))
	body.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 1 if UI.is_phone_portrait() else (2 if UI.is_portrait() or UI.is_phone() else 5)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for c: Dictionary in s.get("caseOptions", []):
		var card := _client_card(c)
		grid.add_child(card)

	var tools_head := UI.vbox(4)
	tools_head.add_child(UI.label("顧問公事包｜選 %d 樣工具" % _size, 20, C_TEXT, true))
	tools_head.add_child(UI.label("工具有限，選對工具能提前掌握資料；少了合規檢核表，對話中的說法風險會更高。", 14, C_MUTED, true))
	body.add_child(tools_head)
	var tgrid := GridContainer.new()
	tgrid.columns = 1 if UI.is_phone_portrait() else (2 if UI.is_portrait() or UI.is_phone() else 3)
	tgrid.add_theme_constant_override("h_separation", 12)
	tgrid.add_theme_constant_override("v_separation", 12)
	body.add_child(tgrid)
	for t: Dictionary in s.get("tools", []):
		tgrid.add_child(_tool_card(t))

	var foot := UI.hbox(16)
	_status = UI.label("", 14, C_MUTED, true)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_status)
	_confirm = UI.button("帶著公事包出發", _on_confirm, 18, C_GREEN)
	_confirm.custom_minimum_size = Vector2(220, 52)
	foot.add_child(_confirm)
	outer.add_child(foot)
	_sync()


func _card_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD if not selected else C_CARD.lightened(0.06)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2 if selected else 1)
	sb.border_color = C_GREEN if selected else Color(1, 1, 1, 0.12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _selectable(content: Control, on_press: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	var box := MarginContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		box.add_theme_constant_override("margin_" + side, 14)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ignore_mouse(content)
	box.add_child(content)
	b.add_child(box)
	# Button height follows its content
	box.resized.connect(func(): b.custom_minimum_size.y = box.get_combined_minimum_size().y)
	box.minimum_size_changed.connect(func(): b.custom_minimum_size.y = box.get_combined_minimum_size().y)
	return b


func _ignore_mouse(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(ch)


func _client_card(c: Dictionary) -> Button:
	var id := str(c.get("id", ""))
	var v := UI.vbox(6)
	var top := UI.hbox(10)
	top.add_child(Portraits.create_avatar(id, str(c.get("name", "")), 48))
	var nv := UI.vbox(0)
	nv.add_child(UI.label(str(c.get("name", "")), 18, C_TEXT))
	nv.add_child(UI.label("%d 歲・%s" % [int(c.get("age", 0)), str(c.get("job", ""))], 13, C_MUTED, true))
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nv)
	v.add_child(top)
	v.add_child(UI.label("%s｜難度 %s" % [str(c.get("tag", "")), str(c.get("difficulty", ""))], 13, C_GOLD, true))
	v.add_child(UI.label("目標：" + str(c.get("goal", "")), 14, C_TEXT, true))
	v.add_child(UI.label(str(c.get("family", "")), 13, C_MUTED, true))
	var b := _selectable(v, func():
		_client_id = id
		_sync()
	)
	_client_cards[id] = b
	return b


func _tool_card(t: Dictionary) -> Button:
	var id := str(t.get("id", ""))
	var v := UI.vbox(4)
	v.add_child(UI.label(str(t.get("name", "")), 16, C_TEXT, true))
	v.add_child(UI.label(str(t.get("effect", "")), 13, C_MUTED, true))
	var b := _selectable(v, func():
		if _tools.has(id):
			_tools.erase(id)
		elif _tools.size() < _size:
			_tools.append(id)
		_sync()
	)
	_tool_cards[id] = b
	return b


func _sync() -> void:
	for id: String in _client_cards:
		var b: Button = _client_cards[id]
		for st: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, _card_style(id == _client_id))
	for id: String in _tool_cards:
		var b: Button = _tool_cards[id]
		for st: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, _card_style(_tools.has(id)))
	var ready_to_go := _client_id != "" and _tools.size() == _size and not _sent
	_confirm.disabled = not ready_to_go
	if _sent:
		_status.text = "準備中……"
	elif _client_id == "":
		_status.text = "請先選擇一位主要客戶"
	else:
		_status.text = "公事包 %d / %d" % [_tools.size(), _size]


func _on_confirm() -> void:
	if _client_id == "" or _tools.size() != _size:
		return
	_sent = true
	_sync()
	Net.act({"type": "setup", "clientId": _client_id, "tools": _tools})
	# Re-enable if the server rejects it (game.gd removes this overlay on success)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self):
			_sent = false
			_sync()
	)
