@tool
extends Control
## Main game screen: left board (interviews/events shown in overlay panels), right player status, client book, activity log, and emoji reactions.
## Supports phone portrait 3-tab switching, dynamic dice roll cutscenes, clear personal/spectator turn transitions, and status ribbons.

const Board := preload("res://scripts/ui/board.gd")
const SessionPanel := preload("res://scripts/ui/session_panel.gd")
const EventPanel := preload("res://scripts/ui/event_panel.gd")

var main: Node
var _board: Control
var _center: VBoxContainer
var _turn_label: Label
var _roll_btn: Button
var _session: Control
var _event: Control
var _players_box: VBoxContainer
var _book_box: VBoxContainer
var _log_box: VBoxContainer
var _top_label: Label
var _prev_stage := ""
var _dice_anim := 0.0
var _seen_announcement_id := ""
var _announcement_modal: Control = null

# Turn and cutscene state tracking
var _prev_last_roll: int = 0
var _prev_turn_player_id: String = ""
var _prev_round_num: int = -1
var _dice_cutscene_layer: Control = null
var _cutscene_center_box: Control = null
var _dice_roll_info_lbl: Label = null
var _my_turn_banner: PanelContainer = null
var _spectator_ribbon: PanelContainer = null
var _spectator_ribbon_lbl: Label = null
var _turn_toast_layer: Control = null
var _screen_glow: Panel = null
var _btn_pulse := 0.0
var _actor_avatar_panel: PanelContainer = null
var _actor_avatar_label: Label = null

# Deferred overlay display (waiting for dice and pawn animations to complete)
var _is_overlay_deferred: bool = false
var _deferred_overlay_timer: float = 0.0

# Current match quest cards
var _quests_card: PanelContainer = null
var _quests_content: VBoxContainer = null
var _quests_toggle_btn: Button = null
var _quests_title_lbl: Label = null
var _quests_collapsed: bool = true

# Responsive layout and tab control
var _current_tab: int = 0  # Portrait tabs: 0 game (board, directly shows interview/event panel if active), 1 status activity
var _was_overlay: bool = false
var _root: BoxContainer
var _left_stack: Control
var _side_panel: Control
var _tab_bar: HBoxContainer
var _tab_buttons: Array[Button] = []
var _dice_ctl: DiceControl


class DiceControl extends Control:
	var value: int = 0
	var rolling: bool = false
	var dot_color: Color = Color("#f2c14e")

	func _init() -> void:
		var sz: float = 72.0 if UI.is_phone_portrait() else (48.0 if UI.is_phone_landscape() else 84.0)
		custom_minimum_size = Vector2(sz, sz)
		pivot_offset = Vector2(sz * 0.5, sz * 0.5)

	func set_dice_size(sz: float) -> void:
		if absf(custom_minimum_size.x - sz) > 0.5:
			custom_minimum_size = Vector2(sz, sz)
			size = Vector2(sz, sz)
			pivot_offset = Vector2(sz * 0.5, sz * 0.5)
			queue_redraw()

	func set_value(v: int) -> void:
		value = v
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-3 if UI.is_phone() else -4)
		var bg_col := Color("#173748") if not rolling else Color("#225068")
		var border_col := Color("#f2c14e") if not rolling else Color("#2fd197")
		draw_style_box(UI.box(bg_col, int(size.x * 0.16), border_col, 0), r)

		if value <= 0 or value > 6:
			var font := get_theme_default_font()
			var q_fs: int = UI.fs(int(size.y * 0.42))
			draw_string(font, Vector2(0, size.y * 0.5 + q_fs * 0.36), "？", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), q_fs, border_col)
			return

		var cx: float = size.x * 0.5
		var cy: float = size.y * 0.5
		var off: float = size.x * 0.23
		var rad: float = size.x * 0.08
		var col: Color = dot_color

		var dots: Array[Vector2] = []
		match value:
			1:
				dots = [Vector2(cx, cy)]
			2:
				dots = [Vector2(cx - off, cy - off), Vector2(cx + off, cy + off)]
			3:
				dots = [Vector2(cx - off, cy - off), Vector2(cx, cy), Vector2(cx + off, cy + off)]
			4:
				dots = [Vector2(cx - off, cy - off), Vector2(cx + off, cy - off), Vector2(cx - off, cy + off), Vector2(cx + off, cy + off)]
			5:
				dots = [Vector2(cx - off, cy - off), Vector2(cx + off, cy - off), Vector2(cx, cy), Vector2(cx - off, cy + off), Vector2(cx + off, cy + off)]
			6:
				dots = [Vector2(cx - off, cy - off), Vector2(cx + off, cy - off), Vector2(cx - off, cy), Vector2(cx + off, cy), Vector2(cx - off, cy + off), Vector2(cx + off, cy + off)]

		for p in dots:
			draw_circle(p, rad, col)


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
	_tab_buttons.clear()
	var portrait: bool = UI.is_portrait()

	_root = UI.vbox(0) if portrait else UI.hbox(0)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Content container
	var content_box: Control
	if portrait:
		content_box = Control.new()
		content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_root.add_child(content_box)
	else:
		content_box = _root

	# Board and popup panel container
	var left := MarginContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pad: int = (2 if UI.is_phone_portrait() else 8) if portrait else (6 if UI.is_phone_landscape() else 14)
	for s in ["left", "top", "bottom", "right"]:
		left.add_theme_constant_override("margin_" + s, pad)
	if portrait:
		left.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_box.add_child(left)

	_left_stack = Control.new()
	_left_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_left_stack)

	_board = Board.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_left_stack.add_child(_board)

	# Screen border subtle glow hint (glows when it's your turn)
	_screen_glow = Panel.new()
	_screen_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_glow.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), 12, UI.GOLD, 0, false))
	_screen_glow.visible = false
	_left_stack.add_child(_screen_glow)

	_center = UI.vbox(2 if UI.is_phone_landscape() else UI.scale_val(4, 8))
	_center.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_left_stack.add_child(_center)

	# Prominent full-width banner when it's your turn
	_my_turn_banner = UI.panel(Color("#133647"), 12, 6)
	_my_turn_banner.add_theme_stylebox_override("panel", UI.box(Color("#133647"), 12, UI.GOLD, 8, false))
	_my_turn_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var banner_l := UI.label("★ 輪到你了！請擲骰前進 ★", 14 if UI.is_phone_landscape() else (16 if UI.is_phone_portrait() else 18), UI.GOLD)
	banner_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_my_turn_banner.add_child(banner_l)
	_my_turn_banner.visible = false
	_center.add_child(_my_turn_banner)

	# Spectator ribbon during other players' turns
	_spectator_ribbon = UI.panel(Color("#0d2432"), 10, 6)
	_spectator_ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spectator_ribbon_lbl = UI.label("觀看中：其他顧問的回合", 12 if UI.is_phone_landscape() else (13 if UI.is_phone_portrait() else 14), UI.MUTED)
	_spectator_ribbon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_ribbon.add_child(_spectator_ribbon_lbl)
	_spectator_ribbon.visible = false
	_center.add_child(_spectator_ribbon)

	_top_label = UI.label("", 12 if UI.is_phone_landscape() else (13 if UI.is_phone_portrait() else (15 if portrait else 16)), UI.MUTED, true)
	_top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_child(_top_label)

	var actor_row := UI.hbox(6 if UI.is_phone_landscape() else 8)
	actor_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var av_sz: float = 20.0 if UI.is_phone_landscape() else 24.0
	_actor_avatar_panel = UI.panel(UI.PLAYER_COLORS[0], 12, 0)
	_actor_avatar_panel.custom_minimum_size = Vector2(av_sz, av_sz)
	_actor_avatar_label = UI.label("顧", 11 if UI.is_phone_landscape() else 13, Color.WHITE)
	_actor_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_actor_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_actor_avatar_panel.add_child(_actor_avatar_label)
	actor_row.add_child(_actor_avatar_panel)

	_turn_label = UI.label("", 16 if UI.is_phone_landscape() else (19 if UI.is_phone_portrait() else (19 if portrait else 22)), UI.TEXT, true)
	actor_row.add_child(_turn_label)
	_center.add_child(actor_row)

	_dice_ctl = DiceControl.new()
	_dice_ctl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_center.add_child(_dice_ctl)

	_dice_roll_info_lbl = UI.label("", 11 if UI.is_phone_landscape() else (12 if UI.is_phone_portrait() else 14), UI.GOLD, true)
	_dice_roll_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_child(_dice_roll_info_lbl)

	_roll_btn = UI.button("▶ 擲骰子", func():
		Sound.play("dice", self)
		Net.act({"type": "roll"})
	, 16 if UI.is_phone_landscape() else (22 if UI.is_phone_portrait() else (22 if portrait else 24)), UI.ACCENT)
	_roll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_roll_btn.custom_minimum_size = Vector2(160 if UI.is_phone_landscape() else (180 if UI.is_phone_portrait() else (180 if portrait else 220)), 38 if UI.is_phone_landscape() else (54 if UI.is_phone_portrait() else (50 if portrait else 56)))
	_center.add_child(_roll_btn)

	if not UI.is_phone():
		var leg_text: String = "◎客戶 ✚事件 ↗市場 ✓合規 ⚠稽核 ♥介紹 ◇研討 ★結算"
		var legend := UI.label(leg_text, 12 if portrait else 13, UI.MUTED, true)
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_center.add_child(legend)

	_session = SessionPanel.new()
	_session.main = main
	_session.visible = false
	_session.z_index = 20
	if not UI.is_phone():
		_session.anchor_left = 0.35
		_session.anchor_right = 1.0
		_session.anchor_top = 0.0
		_session.anchor_bottom = 1.0
		_session.offset_left = 0
		_session.offset_right = 0
		_session.offset_top = 0
		_session.offset_bottom = 0
	else:
		_session.set_anchors_preset(Control.PRESET_FULL_RECT)
		_session.offset_left = 0
		_session.offset_right = 0
		_session.offset_top = 0
		_session.offset_bottom = 0
	_left_stack.add_child(_session)

	_event = EventPanel.new()
	_event.set_anchors_preset(Control.PRESET_FULL_RECT)
	if UI.is_phone_portrait():
		_event.offset_left = 4; _event.offset_right = -4; _event.offset_top = 8; _event.offset_bottom = -8
	elif UI.is_phone_landscape():
		_event.offset_left = 0; _event.offset_right = 0; _event.offset_top = 0; _event.offset_bottom = 0
	elif portrait:
		_event.offset_left = 8; _event.offset_right = -8; _event.offset_top = 12; _event.offset_bottom = -12
	else:
		_event.offset_left = 80; _event.offset_right = -80; _event.offset_top = 40; _event.offset_bottom = -40
	_event.z_index = 20
	_event.visible = false
	_left_stack.add_child(_event)

	# Right side / page 2: info column
	_side_panel = UI.panel(UI.PANEL, 0, 12 if UI.is_phone() else 14)
	if not portrait:
		var side_w: float = 260.0 if UI.is_phone_landscape() else 340.0
		_side_panel.custom_minimum_size = Vector2(side_w, 0)
	else:
		_side_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_box.add_child(_side_panel)

	var sv := UI.vbox(8 if UI.is_phone() else 10)
	if portrait:
		sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_panel.add_child(UI.scroll(sv))

	var top := UI.hbox(8)
	if Net.is_multiplayer():
		top.add_child(UI.label("房間 " + Net.room_code, 14 if UI.is_phone() else 15, UI.GOLD))
	else:
		top.add_child(UI.label("單人練習", 14 if UI.is_phone() else 15, UI.ACCENT_2))
	top.add_child(UI.spacer())
	var sound_btn: Button = UI.button("音效：關" if Sound.is_muted() else "音效：開", Callable(), 13, UI.PANEL_2)
	sound_btn.pressed.connect(func():
		var m: bool = Sound.toggle_mute()
		sound_btn.text = "音效：關" if m else "音效：開"
	)
	top.add_child(sound_btn)
	top.add_child(UI.button("離開", func(): main.leave_to_menu(), 13, UI.PANEL_2))
	sv.add_child(top)

	# Collapsible match quest card (collapsed by default into one line "★ 任務 2/3 ▼", click to expand)
	_quests_card = UI.panel(Color("#102b3a"), 8, 8)
	_quests_card.add_theme_stylebox_override("panel", UI.box(Color("#102b3a"), 8, UI.GOLD.darkened(0.3), 8, false))
	var q_box := UI.vbox(4)
	var q_head := UI.hbox(6)
	_quests_title_lbl = UI.label("★ 任務 0/0 ▼", 14 if UI.is_phone() else 15, UI.GOLD)
	q_head.add_child(_quests_title_lbl)
	q_head.add_child(UI.spacer())
	_quests_toggle_btn = UI.button("展開" if _quests_collapsed else "收合", Callable(), 11, UI.PANEL_2)
	var toggle_fn := func():
		_quests_collapsed = not _quests_collapsed
		_quests_toggle_btn.text = "展開" if _quests_collapsed else "收合"
		_quests_content.visible = not _quests_collapsed
		_update_quests_title()
	_quests_toggle_btn.pressed.connect(toggle_fn)
	q_head.add_child(_quests_toggle_btn)
	q_box.add_child(q_head)

	_quests_content = UI.vbox(4)
	_quests_content.visible = not _quests_collapsed
	q_box.add_child(_quests_content)
	_quests_card.add_child(q_box)
	_quests_card.visible = false
	sv.add_child(_quests_card)

	_players_box = UI.vbox(5 if UI.is_phone() else 6)
	sv.add_child(_players_box)

	sv.add_child(UI.label("我的客戶簿", 15 if UI.is_phone() else 16, UI.ACCENT_2))
	_book_box = UI.vbox(4)
	sv.add_child(_book_box)

	sv.add_child(UI.label("動態", 15 if UI.is_phone() else 16, UI.ACCENT_2))
	_log_box = UI.vbox(3)
	var ls := UI.scroll(_log_box)
	if portrait:
		ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ls.custom_minimum_size.y = 120.0
	else:
		ls.custom_minimum_size.y = 120.0 if UI.is_phone() else 160.0
	sv.add_child(ls)

	var react := UI.hbox(4 if UI.is_phone() else 6)
	for e: String in ["讚！", "學到了", "好問題", "？", "♥"]:
		var emo: String = e
		react.add_child(UI.button(emo, func(): Net.send({"t": "react", "emoji": emo}), 13 if UI.is_phone() else 15, UI.PANEL_2))
	sv.add_child(react)

	# Portrait bottom navigation tab bar
	if portrait:
		var tab_h: int = 46 if UI.is_phone_portrait() else 52
		_tab_bar = UI.hbox(4 if UI.is_phone_portrait() else 6)
		_tab_bar.custom_minimum_size = Vector2(0, tab_h)
		_root.add_child(_tab_bar)

		var tab_names := ["◎ 遊戲", "● 狀態動態"]
		for idx: int in range(tab_names.size()):
			var tab_i: int = idx
			var btn := UI.button(tab_names[idx], func(): _switch_tab(tab_i), 14 if UI.is_phone_portrait() else 16, UI.PANEL_2)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_tab_buttons.append(btn)
			_tab_bar.add_child(btn)


func _sync_center_bounds() -> void:
	if _board == null or _center == null:
		return
	var r: Rect2 = _board.get_inner_rect()
	var is_phone_land := UI.is_phone_landscape()
	var is_phone_port := UI.is_phone_portrait()
	var pad := 3.0 if is_phone_land else (4.0 if is_phone_port else 6.0)
	var avail_w := maxf(80.0, r.size.x - pad * 2.0)
	var avail_h := maxf(80.0, r.size.y - pad * 2.0)

	if is_phone_land:
		_center.add_theme_constant_override("separation", 2)
		var dice_sz := clampf(avail_h * 0.22, 42.0, 52.0)
		if _dice_ctl != null:
			_dice_ctl.set_dice_size(dice_sz)
		if _roll_btn != null:
			var btn_w := clampf(avail_w * 0.70, 140.0, 175.0)
			var btn_h := clampf(avail_h * 0.15, 34.0, 40.0)
			_roll_btn.custom_minimum_size = Vector2(btn_w, btn_h)
	elif is_phone_port:
		_center.add_theme_constant_override("separation", 4)
		var dice_sz := clampf(avail_h * 0.20, 52.0, 72.0)
		if _dice_ctl != null:
			_dice_ctl.set_dice_size(dice_sz)
		if _roll_btn != null:
			var btn_w := clampf(avail_w * 0.65, 150.0, 180.0)
			var btn_h := clampf(avail_h * 0.14, 40.0, 48.0)
			_roll_btn.custom_minimum_size = Vector2(btn_w, btn_h)
	else:
		_center.add_theme_constant_override("separation", 8)
		if _dice_ctl != null:
			_dice_ctl.set_dice_size(84.0)
		if _roll_btn != null:
			_roll_btn.custom_minimum_size = Vector2(220, 56)

	_center.position = r.position + Vector2(pad, pad)
	_center.size = Vector2(avail_w, avail_h)
	if _cutscene_center_box != null and is_instance_valid(_cutscene_center_box):
		var inner_c: Vector2 = r.get_center()
		_cutscene_center_box.position = inner_c - (_cutscene_center_box.size * 0.5)


func _switch_tab(tab_idx: int) -> void:
	_current_tab = tab_idx
	_sync_tabs()


func _sync_tabs() -> void:
	var sess = Net.state.get("session")
	var ev = Net.state.get("event")
	var is_sess: bool = sess is Dictionary and not _is_overlay_deferred
	var is_ev: bool = ev is Dictionary and not is_sess and not _is_overlay_deferred
	var overlay: bool = is_sess or is_ev

	if not UI.is_portrait():
		_left_stack.get_parent().visible = true
		if UI.is_phone_landscape():
			_side_panel.visible = not overlay
			if overlay:
				_board.visible = false
			else:
				_board.visible = true
				_board.modulate = Color.WHITE
		else:
			_side_panel.visible = true
			_board.visible = true
			_board.modulate = Color(1, 1, 1, 0.75) if is_sess else Color.WHITE
		_session.visible = is_sess
		_event.visible = is_ev
		_center.visible = not overlay
		return

	for i: int in range(_tab_buttons.size()):
		var b: Button = _tab_buttons[i]
		if i == _current_tab:
			b.add_theme_stylebox_override("normal", UI.box(UI.ACCENT, 8, Color(0, 0, 0, 0), 10))
		else:
			b.add_theme_stylebox_override("normal", UI.box(UI.PANEL_2, 8, Color(0, 0, 0, 0), 10))

	if _current_tab == 0:
		# Game tab: displays panel directly if interview or event active (own or spectating), otherwise shows board
		_left_stack.get_parent().visible = true
		if overlay and UI.is_phone():
			# Phone: fullscreen panel
			_board.visible = false
			_board.modulate = Color.WHITE
		else:
			# Tablet portrait: interview panel ~65% width, left board semi-transparently visible
			_board.visible = true
			_board.modulate = Color(1, 1, 1, 0.75) if is_sess else Color.WHITE
		_center.visible = not overlay
		_session.visible = is_sess
		_event.visible = is_ev
		_side_panel.visible = false
	else:
		_left_stack.get_parent().visible = false
		_side_panel.visible = true


func _process(delta: float) -> void:
	_sync_center_bounds()

	# Deferred panel countdown timer (waiting for dice roll and pawn movement to finish)
	if _is_overlay_deferred:
		_deferred_overlay_timer -= delta
		if _deferred_overlay_timer <= 0.0:
			_is_overlay_deferred = false
			_apply_deferred_overlay()

	# Dice roll button subtle breathing glow (when it's your turn)
	if _roll_btn != null and _roll_btn.visible:
		_btn_pulse += delta * 4.0
		var sc: float = 1.0 + sin(_btn_pulse) * 0.035
		_roll_btn.scale = Vector2(sc, sc)
		_roll_btn.pivot_offset = _roll_btn.size * 0.5
	else:
		_btn_pulse = 0.0

	# Border subtle breathing glow (warm gold pulse on own turn, calm cool color on others)
	if _screen_glow != null and _screen_glow.visible:
		if Net.is_my_turn():
			var alpha: float = 0.5 + sin(_btn_pulse) * 0.35
			_screen_glow.modulate.a = alpha
		else:
			_screen_glow.modulate.a = 0.45

	if _dice_anim > 0:
		_dice_anim -= delta
		if _dice_anim > 0:
			_dice_ctl.rolling = true
			_dice_ctl.set_value(randi() % 6 + 1)
			_dice_ctl.rotation = randf_range(-0.25, 0.25)
		else:
			_dice_ctl.rolling = false
			_dice_ctl.rotation = 0.0
			_show_die()
			var tw := create_tween()
			_dice_ctl.scale = Vector2(1.2, 1.2)
			tw.tween_property(_dice_ctl, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_die() -> void:
	var r = Net.state.get("lastRoll")
	var roll_val: int = int(r) if r != null else 0
	_dice_ctl.set_value(roll_val)
	if _dice_roll_info_lbl != null:
		if roll_val > 0:
			_dice_roll_info_lbl.text = "上一步擲出 %d 點" % roll_val
			_dice_roll_info_lbl.visible = true
		else:
			_dice_roll_info_lbl.text = ""
			_dice_roll_info_lbl.visible = false


func refresh(s: Dictionary) -> void:
	if _board == null:
		return
	_sync_center_bounds()
	var cur: Dictionary = Net.current_player()
	var cur_id: String = str(cur.get("id", ""))
	var cur_name: String = str(cur.get("name", ""))
	var round_num: int = int(s.get("round", 1))
	var mine: bool = Net.is_my_turn()
	var stage: String = str(s.get("turnStage", ""))
	var last_roll_val: int = int(s.get("lastRoll", 0)) if s.get("lastRoll") != null else 0

	# Turn change detection: play transition card
	if cur_id != "" and (cur_id != _prev_turn_player_id or round_num != _prev_round_num):
		_prev_turn_player_id = cur_id
		_prev_round_num = round_num
		var cur_player_idx: int = int(s.get("turn", 0)) % 4
		var player_col: Color = UI.PLAYER_COLORS[cur_player_idx]
		_show_turn_transition(round_num, cur_name, player_col, mine)
		if mine:
			Sound.play("step", self)

	# Dice roll cutscene trigger: when stage changes from roll or lastRoll changes
	if last_roll_val > 0 and last_roll_val != _prev_last_roll:
		_prev_last_roll = last_roll_val
		_play_dice_cutscene(cur_name, last_roll_val, mine)
		# Defer interview/event panel display: dice roll animation (1.0s) + pawn 1/6s per tile + buffer (0.35s)
		var total_anim_time: float = 1.0 + (float(last_roll_val) * (1.0 / 6.0)) + 0.35
		_is_overlay_deferred = true
		_deferred_overlay_timer = total_anim_time

	_board.set_data(Net.static_data.get("board", []), s.get("players", []), cur_id)
	_top_label.text = "第 %d / %d 回合 ｜ 名單剩 %d 位" % [round_num, int(s.get("settings", {}).get("rounds", 6)), int(s.get("deckLeft", 0))]

	# Own turn vs spectating other player turn indicator
	var cur_player_idx: int = int(s.get("turn", 0)) % 4
	var player_col: Color = UI.PLAYER_COLORS[cur_player_idx]
	if _actor_avatar_panel != null:
		_actor_avatar_panel.add_theme_stylebox_override("panel", UI.box(player_col, 12, Color.WHITE if mine else Color(0, 0, 0, 0), 0))
		_actor_avatar_label.text = cur_name.substr(0, 1) if cur_name != "" else "顧"
	if mine:
		_turn_label.text = "★ 輪到你了！請擲骰"
		_turn_label.add_theme_color_override("font_color", UI.GOLD)
		_my_turn_banner.visible = true
		_spectator_ribbon.visible = false
		_screen_glow.visible = true
		_screen_glow.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), 12, UI.GOLD, 3, false))
		_center.modulate = Color(1.0, 0.98, 0.92)
		_roll_btn.visible = stage == "roll"
		_roll_btn.disabled = false
	else:
		_turn_label.text = "【%s】行動中……" % cur_name
		_turn_label.add_theme_color_override("font_color", player_col.lightened(0.2))
		_my_turn_banner.visible = false
		_spectator_ribbon.visible = true
		_spectator_ribbon_lbl.text = "觀看中：【%s】的回合（觀察其決策與作答）" % cur_name
		_screen_glow.visible = true
		_screen_glow.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), 12, Color("#1e4256"), 2, false))
		_screen_glow.modulate.a = 0.45
		_roll_btn.visible = false
		_roll_btn.disabled = true
		_center.modulate = Color(0.85, 0.92, 0.98)

	if stage == "roll":
		_is_overlay_deferred = false
		_deferred_overlay_timer = 0.0
		_dice_ctl.set_value(0)
		if _dice_roll_info_lbl != null:
			_dice_roll_info_lbl.text = "請點選下方擲骰" if mine else "等待【%s】擲骰……" % cur_name
			_dice_roll_info_lbl.visible = true
	elif _prev_stage == "roll":
		_dice_anim = 0.5
	elif _dice_anim <= 0:
		_show_die()
	_prev_stage = stage

	# End-game major event / global announcement
	var ann = s.get("announcement")
	if ann is Dictionary and ann.has("id"):
		var ann_id: String = str(ann.get("id", ""))
		if ann_id != "" and ann_id != _seen_announcement_id:
			_seen_announcement_id = ann_id
			_show_announcement(ann)

	var sess = s.get("session")
	var is_sess: bool = sess is Dictionary
	var ev = s.get("event")
	var is_ev: bool = ev is Dictionary and not is_sess
	var has_overlay: bool = is_sess or is_ev

	if _is_overlay_deferred:
		# Deferred display: temporarily hide panel during dice roll and pawn movement to ensure animation and board visibility
		_session.visible = false
		_event.visible = false
		_center.visible = true
		_board.visible = true
		if UI.is_portrait():
			_current_tab = 0
	else:
		# Auto-switch phone tab
		# When own interview/event appears, switch back from status tab to game tab
		if UI.is_portrait() and has_overlay and not _was_overlay and mine:
			_current_tab = 0
		_was_overlay = has_overlay

		if not UI.is_portrait():
			if UI.is_phone_landscape():
				_side_panel.visible = not has_overlay
				_board.visible = not has_overlay
				_board.modulate = Color.WHITE
			else:
				_side_panel.visible = true
				_board.visible = true
				_board.modulate = Color(1, 1, 1, 0.75) if is_sess else Color.WHITE
			_session.visible = is_sess
			_event.visible = is_ev
			_center.visible = not has_overlay

		if is_sess:
			_session.refresh(sess, cur_name)
		if is_ev:
			_event.refresh(ev, cur_name)

	_sync_tabs()

	# Automatically collapse quest card when interview or event opens
	if has_overlay:
		_quests_collapsed = true

	# Match quest card update
	var quests: Array = s.get("quests", []) if s.get("quests") != null else []
	if quests.is_empty():
		_quests_card.visible = false
	else:
		_quests_card.visible = true
		UI.clear(_quests_content)
		var done_count: int = 0
		for q: Dictionary in quests:
			var q_row := UI.panel(Color("#0c202c"), 6, 6)
			var qv := UI.vbox(2)
			var qh := UI.hbox(4)
			var q_title: String = str(q.get("title", "任務"))
			var q_prog: Dictionary = q.get("progress", {}).get(Net.player_id, {})
			var cur_p: int = int(q_prog.get("cur", 0))
			var target_p: int = int(q_prog.get("target", 1))
			var is_done: bool = bool(q_prog.get("done", false)) or (target_p > 0 and cur_p >= target_p)
			if is_done:
				done_count += 1

			qh.add_child(UI.label(q_title, 13 if UI.is_phone() else 14, UI.GOLD if is_done else UI.TEXT, true))
			qh.add_child(UI.spacer())
			if is_done:
				qh.add_child(UI.label("✓ 達成", 12 if UI.is_phone() else 13, UI.GOLD))
			else:
				qh.add_child(UI.label("%d/%d" % [cur_p, target_p], 12 if UI.is_phone() else 13, UI.ACCENT_2))
			qv.add_child(qh)

			var q_desc: String = str(q.get("desc", ""))
			if q_desc != "":
				qv.add_child(UI.label(q_desc, 11 if UI.is_phone() else 12, UI.MUTED, true))

			var q_rew_val = q.get("reward", null)
			if q_rew_val != null and str(q_rew_val) != "":
				var rew_str: String = str(q_rew_val)
				if typeof(q_rew_val) in [TYPE_FLOAT, TYPE_INT] or rew_str.is_valid_float():
					rew_str = "聲望 +%d" % int(float(rew_str))
				qv.add_child(UI.label("獎勵：%s" % rew_str, 11 if UI.is_phone() else 12, UI.GOLD.darkened(0.2), true))

			q_row.add_child(qv)
			_quests_content.add_child(q_row)

		if _quests_title_lbl != null:
			if _quests_collapsed:
				_quests_title_lbl.text = "★ 任務 %d/%d ▼" % [done_count, quests.size()]
				_quests_toggle_btn.text = "展開"
				_quests_content.visible = false
			else:
				_quests_title_lbl.text = "★ 任務 %d/%d ▲" % [done_count, quests.size()]
				_quests_toggle_btn.text = "收合"
				_quests_content.visible = true

	# Player list
	UI.clear(_players_box)
	var i: int = 0
	for p: Dictionary in s.get("players", []):
		var is_cur: bool = str(p.get("id", "")) == cur_id
		var card := UI.panel(UI.PANEL_2 if is_cur else Color("#0f2733"), 10, 8)
		var v := UI.vbox(2)
		var h := UI.hbox(6)
		h.add_child(UI.label("●", 16, UI.PLAYER_COLORS[i % 4]))
		var nm: String = str(p.get("name", "")) + ("（你）" if str(p.get("id", "")) == Net.player_id else "")
		if bool(p.get("loggedIn", false)):
			nm += " [會員]"
		h.add_child(UI.label(nm, 15, UI.TEXT))
		var streak: int = int(p.get("complianceStreak", 0))
		if streak >= 2:
			h.add_child(UI.label("★ 合規連擊 ×%d" % streak, 12, UI.GOLD))
		if not p.get("connected", true) and not p.get("isBot", false):
			h.add_child(UI.label("斷線", 12, UI.BAD))
		if is_cur:
			h.add_child(UI.label("◀", 14, UI.GOLD))
		v.add_child(h)
		v.add_child(UI.label("聲望 %d　業績 %d　客戶 %d　測驗 %d/%d" % [int(p.get("reputation", 0)), int(p.get("commission", 0)), (p.get("book", []) as Array).size(), int(p.get("quizCorrect", 0)), int(p.get("quizTotal", 0))], 13, UI.MUTED))
		card.add_child(v)
		_players_box.add_child(card)
		i += 1


func _update_quests_title() -> void:
	if _quests_title_lbl == null:
		return
	var quests: Array = Net.state.get("quests", []) if Net.state.get("quests") != null else []
	var done_count: int = 0
	for q: Dictionary in quests:
		var q_prog: Dictionary = q.get("progress", {}).get(Net.player_id, {})
		var cur_p: int = int(q_prog.get("cur", 0))
		var target_p: int = int(q_prog.get("target", 1))
		if bool(q_prog.get("done", false)) or (target_p > 0 and cur_p >= target_p):
			done_count += 1
	if _quests_collapsed:
		_quests_title_lbl.text = "★ 任務 %d/%d ▼" % [done_count, quests.size()]
	else:
		_quests_title_lbl.text = "★ 任務 %d/%d ▲" % [done_count, quests.size()]


func _apply_deferred_overlay() -> void:
	if Net.state.is_empty():
		return
	var s: Dictionary = Net.state
	var sess = s.get("session")
	var is_sess: bool = sess is Dictionary
	var ev = s.get("event")
	var is_ev: bool = ev is Dictionary and not is_sess
	var has_overlay: bool = is_sess or is_ev
	var cur: Dictionary = Net.current_player()
	var cur_name: String = str(cur.get("name", ""))
	var mine: bool = Net.is_my_turn()

	if UI.is_portrait() and has_overlay and not _was_overlay and mine:
		_current_tab = 0
	_was_overlay = has_overlay

	if not UI.is_portrait():
		if UI.is_phone_landscape():
			_side_panel.visible = not has_overlay
			_board.visible = not has_overlay
			_board.modulate = Color.WHITE
		else:
			_side_panel.visible = true
			_board.visible = true
			_board.modulate = Color(1, 1, 1, 0.75) if is_sess else Color.WHITE
		_session.visible = is_sess
		_event.visible = is_ev
		_center.visible = not has_overlay

	if is_sess:
		_session.refresh(sess, cur_name)
	if is_ev:
		_event.refresh(ev, cur_name)

	_sync_tabs()

	# My client book
	UI.clear(_book_box)
	var me: Dictionary = Net.me()
	var book: Array = me.get("book", [])
	if book.is_empty():
		_book_box.add_child(UI.label("尚無客戶。走到 ◎ 客戶格開始面談！", 13, UI.MUTED, true))
	for b: Dictionary in book:
		var h := UI.hbox(6)
		h.add_child(UI.label(str(b.get("name", "")) + (" ⚠" if b.get("mis", false) else ""), 14, UI.OK if b.get("mis", false) else UI.TEXT))
		h.add_child(UI.spacer())
		h.add_child(UI.label("滿意 %d" % int(b.get("satisfaction", 0)), 12, UI.MUTED))
		_book_box.add_child(h)

	# Activity log
	UI.clear(_log_box)
	var logs: Array = s.get("log", [])
	for idx: int in range(logs.size() - 1, -1, -1):
		var l: Dictionary = logs[idx]
		_log_box.add_child(UI.label(str(l.get("text", "")), 13, UI.tone_color(str(l.get("tone", "info"))), true))


# ───────── Dynamic cutscene: dice tumbling and bounce freeze ─────────

func _play_dice_cutscene(roller_name: String, roll_val: int, is_self: bool) -> void:
	if _board != null and _board.has_method("freeze_movement"):
		_board.freeze_movement(1.0)

	if _dice_cutscene_layer != null and is_instance_valid(_dice_cutscene_layer):
		_dice_cutscene_layer.queue_free()

	var cutscene := Control.new()
	cutscene.set_anchors_preset(Control.PRESET_FULL_RECT)
	cutscene.z_index = 80
	cutscene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_stack.add_child(cutscene)
	_dice_cutscene_layer = cutscene

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutscene.add_child(dim)

	var center_box := UI.vbox(10)
	var box_w: float = 240.0
	var box_h: float = 160.0
	center_box.custom_minimum_size = Vector2(box_w, box_h)
	center_box.size = Vector2(box_w, box_h)
	var inner_r: Rect2 = _board.get_inner_rect()
	center_box.position = inner_r.get_center() - Vector2(box_w * 0.5, box_h * 0.5)
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	cutscene.add_child(center_box)
	_cutscene_center_box = center_box

	var big_dice := DiceControl.new()
	big_dice.custom_minimum_size = Vector2(96, 96)
	big_dice.pivot_offset = Vector2(48, 48)
	big_dice.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.add_child(big_dice)

	var text_lbl := UI.label("【%s】擲骰中……" % roller_name, 20, UI.TEXT)
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(text_lbl)

	var tw: Tween = cutscene.create_tween()
	for step: int in range(6):
		tw.tween_callback(func():
			big_dice.rolling = true
			big_dice.set_value(randi() % 6 + 1)
			big_dice.rotation = randf_range(-0.35, 0.35)
		)
		tw.tween_interval(0.08)

	tw.tween_callback(func():
		big_dice.rolling = false
		big_dice.rotation = 0.0
		big_dice.set_value(roll_val)
		text_lbl.text = "【%s】擲出 %d 點！" % [roller_name, roll_val]
		text_lbl.add_theme_color_override("font_color", UI.GOLD)
		Sound.play("dice", self)

		var bounce_tw: Tween = big_dice.create_tween()
		big_dice.scale = Vector2(1.4, 1.4)
		bounce_tw.tween_property(big_dice, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		if is_self:
			_trigger_screen_shake()
			dim.color = Color(1, 0.9, 0.6, 0.35)
	)
	tw.tween_interval(0.4)
	tw.tween_property(cutscene, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		_cutscene_center_box = null
		cutscene.queue_free()
	)


func _trigger_screen_shake() -> void:
	if _root == null:
		return
	var tw: Tween = create_tween()
	var orig_pos: Vector2 = _root.position
	for i: int in range(4):
		var offset: Vector2 = Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		tw.tween_property(_root, "position", orig_pos + offset, 0.035)
	tw.tween_property(_root, "position", orig_pos, 0.035)


# ───────── Dynamic cutscene: turn transition card ─────────

func _show_turn_transition(round_num: int, player_name: String, player_col: Color, is_self: bool) -> void:
	if _turn_toast_layer != null and is_instance_valid(_turn_toast_layer):
		_turn_toast_layer.queue_free()

	var card_layer := Control.new()
	card_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_layer.z_index = 85
	card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_stack.add_child(card_layer)
	_turn_toast_layer = card_layer

	var p := UI.panel(UI.PANEL_2, 14, 10)
	p.add_theme_stylebox_override("panel", UI.box(Color("#102e3f"), 14, UI.GOLD if is_self else player_col, 10))
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.position = Vector2((_left_stack.size.x - 340) * 0.5, 14)
	p.custom_minimum_size = Vector2(340, 0)
	card_layer.add_child(p)

	var h := UI.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UI.label("●", 18, player_col))
	var title_str: String = "第 %d 回合 ｜ %s 的回合" % [round_num, player_name]
	if is_self:
		title_str += "（輪到你了！）"
	var l := UI.label(title_str, 15, UI.GOLD if is_self else Color.WHITE)
	h.add_child(l)
	p.add_child(h)

	card_layer.modulate.a = 0.0
	card_layer.position.y = -18
	var tw: Tween = card_layer.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card_layer, "modulate:a", 1.0, 0.22)
	tw.tween_property(card_layer, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_property(card_layer, "modulate:a", 0.0, 0.22)
	tw.tween_callback(card_layer.queue_free)


func _show_announcement(ann: Dictionary) -> void:
	if _announcement_modal != null:
		_announcement_modal.queue_free()
		_announcement_modal = null

	var portrait: bool = UI.is_portrait()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 100
	add_child(dim)
	_announcement_modal = dim

	var p := UI.panel(UI.PANEL, 16, 16 if UI.is_phone_portrait() else 24)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 12 if UI.is_phone_portrait() else (24 if portrait else 140)
	p.offset_right = -12 if UI.is_phone_portrait() else (-24 if portrait else -140)
	p.offset_top = 20 if UI.is_phone_portrait() else (36 if portrait else 60)
	p.offset_bottom = -20 if UI.is_phone_portrait() else (-36 if portrait else -60)
	dim.add_child(p)

	var v := UI.vbox(12)
	p.add_child(v)

	v.add_child(UI.label("★ 全域市場重大事件 ★", 18 if UI.is_phone_portrait() else 22, UI.GOLD))
	v.add_child(UI.label(str(ann.get("title", "市場公告")), 22 if UI.is_phone_portrait() else 28, UI.ACCENT_2, true))

	var body_v := UI.vbox(8)
	body_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll_body := UI.scroll(body_v)
	v.add_child(scroll_body)

	body_v.add_child(UI.label(str(ann.get("body", "")), 15 if UI.is_phone_portrait() else 17, UI.TEXT, true))

	var lines: Array = ann.get("lines", []) if ann.get("lines") is Array else []
	if not lines.is_empty():
		body_v.add_child(HSeparator.new())
		for line: Dictionary in lines:
			var txt: String = str(line.get("text", ""))
			var tone: String = str(line.get("tone", "info"))
			body_v.add_child(UI.label(txt, 14 if UI.is_phone_portrait() else 15, UI.tone_color(tone), true))

	var close_btn := UI.button("知道了", func():
		if _announcement_modal != null:
			_announcement_modal.queue_free()
			_announcement_modal = null
	, 18)
	v.add_child(close_btn)
	Sound.play("alarm", self)
