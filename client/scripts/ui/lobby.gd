@tool
extends Control
## Multiplayer lobby: room code, player list, add bot advisors, rounds, AI client toggle, start. Supports portrait/landscape layout switching.

var main: Node
var _code_label: Label
var _players: VBoxContainer
var _host_buttons: Array[Button] = []
var _rounds_label: Label
var _ai_check: CheckButton
var _start_btn: Button
var _hint: Label
var _visitor_hint: Label


func _ready() -> void:
	_build_ui()
	if not Net.state.is_empty():
		refresh(Net.state)


func on_layout_changed(_is_portrait: bool) -> void:
	_build_ui()
	if not Net.state.is_empty():
		refresh(Net.state)


func _build_ui() -> void:
	UI.clear(self)
	_host_buttons.clear()
	var portrait: bool = UI.is_portrait()

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad: int = 12 if UI.is_phone_portrait() else (16 if portrait else 36)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, pad)
	add_child(outer)

	var v := UI.vbox(12 if UI.is_phone_portrait() else (14 if portrait else 16))
	outer.add_child(v)

	var top := UI.hbox(12)
	top.add_child(UI.label("多人大廳", 24 if UI.is_phone_portrait() else (28 if portrait else 32), UI.ACCENT_2))
	top.add_child(UI.spacer())
	top.add_child(UI.button("離開", func(): main.leave_to_menu(), 15, UI.PANEL_2))
	v.add_child(top)

	var code_panel := UI.panel(UI.PANEL_2, 14, 14 if portrait else 18)
	var ch: BoxContainer = UI.vbox(8) if portrait else UI.hbox(18)
	var code_row := UI.hbox(12)
	code_row.add_child(UI.label("房間代碼", 18, UI.MUTED))
	_code_label = UI.label(Net.room_code, 36 if portrait else 44, UI.GOLD)
	code_row.add_child(_code_label)
	code_row.add_child(UI.button("複製", func():
		DisplayServer.clipboard_set(Net.room_code)
		main.toast("已複製房間代碼", UI.GOOD)
	, 15, UI.PANEL))
	ch.add_child(code_row)
	ch.add_child(UI.label("把代碼給同伴，在主選單輸入即可加入（最多 4 人）", 14 if portrait else 16, UI.MUTED, true))
	code_panel.add_child(ch)
	v.add_child(code_panel)

	# Content area (vertical stack in portrait, two-column split in landscape)
	var body_container: Control
	var body: BoxContainer
	if portrait:
		body = UI.vbox(12)
		body_container = UI.scroll(body)
		body_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(body_container)
	else:
		body = UI.hbox(20)
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(body)

	var left := UI.panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lv := UI.vbox(10)
	left.add_child(lv)
	lv.add_child(UI.label("玩家", 20))
	_players = UI.vbox(8)
	lv.add_child(_players)
	body.add_child(left)

	var right := UI.panel()
	if not portrait:
		right.custom_minimum_size = Vector2(420, 0)
	else:
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := UI.vbox(12)
	right.add_child(rv)
	rv.add_child(UI.label("房主設定", 20))
	var bots := UI.hbox(8)
	_host_buttons.append(UI.button("＋ 資深電腦", func(): Net.send({"t": "add_bot", "level": "pro"}), 15))
	_host_buttons.append(UI.button("＋ 新人電腦", func(): Net.send({"t": "add_bot", "level": "novice"}), 15, UI.PANEL_2))
	for b in _host_buttons:
		bots.add_child(b)
	rv.add_child(bots)

	var rr := UI.hbox(8)
	rr.add_child(UI.label("回合數", 16, UI.MUTED))
	var minus := UI.button("－", func(): _set_rounds(-1), 15, UI.PANEL_2)
	var plus := UI.button("＋", func(): _set_rounds(1), 15, UI.PANEL_2)
	_host_buttons.append_array([minus, plus])
	rr.add_child(minus)
	_rounds_label = UI.label("6", 18)
	rr.add_child(_rounds_label)
	rr.add_child(plus)
	rv.add_child(rr)

	_ai_check = CheckButton.new()
	_ai_check.text = "AI 即時生成新客戶"
	_ai_check.toggled.connect(func(on: bool): Net.send({"t": "settings", "aiClients": on}))
	rv.add_child(_ai_check)

	_hint = UI.label("", 14, UI.MUTED, true)
	rv.add_child(_hint)

	_visitor_hint = UI.label("", 13, UI.GOLD, true)
	rv.add_child(_visitor_hint)

	_start_btn = UI.button("▶ 開始遊戲", func(): Net.send({"t": "start"}), 22)
	rv.add_child(_start_btn)
	body.add_child(right)


func _set_rounds(d: int) -> void:
	var r: int = int(Net.state.get("settings", {}).get("rounds", 6)) + d
	Net.send({"t": "settings", "rounds": clampi(r, 2, 12)})


func refresh(s: Dictionary) -> void:
	if _code_label == null:
		return
	_code_label.text = str(s.get("code", Net.room_code))
	UI.clear(_players)
	var host: bool = Net.is_host()
	var i: int = 0
	for p: Dictionary in s.get("players", []):
		var row := UI.panel(UI.PANEL_2, 10, 10)
		var h := UI.hbox(10)
		var dot := UI.label("●", 20, UI.PLAYER_COLORS[i % 4])
		h.add_child(dot)
		var tag := ""
		if p.get("isBot", false):
			tag = "　電腦"
		elif str(p.get("id", "")) == str(s.get("hostId", "")):
			tag = "　房主"
		if str(p.get("id", "")) == Net.player_id:
			tag += "（你）"
		var p_name_lbl := UI.label(str(p.get("name", "")) + tag, 16 if UI.is_phone_portrait() else 18, UI.TEXT, true)
		p_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(p_name_lbl)
		h.add_child(UI.spacer())
		if host and str(p.get("id", "")) != Net.player_id:
			var pid: String = str(p.get("id", ""))
			h.add_child(UI.button("移除", func(): Net.send({"t": "remove_player", "id": pid}), 14, UI.BAD.darkened(0.3)))
		row.add_child(h)
		_players.add_child(row)
		i += 1
	var st: Dictionary = s.get("settings", {})
	_rounds_label.text = "%d" % int(st.get("rounds", 6))
	_ai_check.set_pressed_no_signal(bool(st.get("aiClients", false)))
	_ai_check.disabled = not Net.ai_enabled or not host
	for b in _host_buttons:
		b.disabled = not host
	_start_btn.disabled = not host
	var n: int = s.get("players", []).size()
	if not host:
		_hint.text = "等待房主開始遊戲……"
	elif n < 2:
		_hint.text = "目前只有你一人：可以等同伴加入，或加入電腦顧問。也可以直接開始自主練習。"
	else:
		var ai_note := ""
		if not Net.ai_enabled:
			ai_note = "（訪客房主：AI 功能改用規則版）" if not Net.is_logged_in() else "（伺服器未啟用 AI：AI 功能改用規則版）"
		_hint.text = "%d 位玩家就緒。%s" % [n, ai_note]

	if not Net.is_logged_in():
		_visitor_hint.text = "※ 訪客模式：AI 功能改用規則版、紀錄不保存，登入後可使用"
		_visitor_hint.visible = true
	else:
		_visitor_hint.text = ""
		_visitor_hint.visible = false
