@tool
extends Control
## Main game screen: left board (interviews/events shown in overlay panels), right player status, client book, activity log, and emoji reactions.
## Supports phone portrait 3-tab switching, dynamic dice roll cutscenes, clear personal/spectator turn transitions, and status ribbons.

## Taipei 101 Advisor HQ, 3D isometric board (board_hq.gd is the earlier painted-map version;
## the 3D city board in board.gd stays available to the preview studio)
const Board := preload("res://scripts/ui/board_aerial.gd")
const RouteProgress := preload("res://scripts/quest/widgets/route_progress.gd")

# HQ interface palette
const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
const C_RED := Color("#D9685F")
const STEP_TASKS := {
	"discover": ["了解客戶需求", "提問並觀察線索，找出客戶真正在意的事。"],
	"plan": ["設計保障方案", "依照需求分配預備金、保障與成長，並選擇保障卡。"],
	"objection": ["回應客戶疑慮", "選擇或寫下合規、誠實的回覆。"],
	"result": ["查看面談結果", "確認成交結果與教練回饋後繼續。"],
}
## What each station trains: shown in the task card with its goals
const STATION_INFO := {
	"start": ["季度結算：檢視客戶簿，滿意的客戶續約，不滿意的客戶解約。", ["客戶滿意度維持 60 以上即可續約", "避免滿意度低於 30 而解約", "累積業績與聲望"]],
	"client": ["客戶會談：從生活與目標找出客戶真正的需求。", ["觀察場景線索並提問", "依需求配置預備金、保障與成長", "合規回應客戶疑慮"]],
	"training": ["合規訓練：用測驗或情境抉擇練習合規判斷。", ["正確回答合規測驗", "在業績與合規之間做出正確選擇", "避免保證收益與誇大說法"]],
	"market": ["市場快訊：市場變動會檢驗所有客戶的資產配置。", ["檢查配置能否承受波動", "預備金守住短期需求", "理解事件背後的投資觀念"]],
	"life": ["人生事件：客戶的人生出現變化，檢驗保障是否到位。", ["確認保障能承接事件", "協助客戶理賠與調整", "維持客戶滿意度"]],
	"audit": ["合規稽核：稽核人員抽查你的客戶紀錄。", ["配置與需求相符", "紀錄完整、沒有不當說法", "通過稽核累積聲望"]],
	"seminar": ["顧問研討會：資深顧問針對你的表現給建議。", ["回顧最近的決策", "吸收 AI 教練建議", "持續學習，聲望 +2"]],
	"referral": ["客戶轉介紹：被好好服務的客戶會介紹新朋友。", ["客戶滿意度維持 70 以上", "拓展人脈", "轉介紹客戶信任 +10"]],
}


class LineIcon extends Control:
	## Small 2px line icon for panel headers, stat tiles and the record timeline
	var kind := ""
	var color := Color("#F3F0E7")

	func _init(icon_kind: String, sz := 22.0, col := Color("#F3F0E7")) -> void:
		kind = icon_kind
		color = col
		custom_minimum_size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var w := 2.0
		match kind:
			"pin":
				draw_arc(c + Vector2(0, -r * 0.25), r * 0.55, PI * 0.85, PI * 2.15, 16, color, w, true)
				draw_line(c + Vector2(-r * 0.5, -r * 0.05), c + Vector2(0, r), color, w, true)
				draw_line(c + Vector2(r * 0.5, -r * 0.05), c + Vector2(0, r), color, w, true)
				draw_circle(c + Vector2(0, -r * 0.25), r * 0.15, color)
			"people":
				draw_arc(c + Vector2(-r * 0.35, -r * 0.35), r * 0.3, 0, TAU, 12, color, w, true)
				draw_arc(c + Vector2(r * 0.4, -r * 0.35), r * 0.3, 0, TAU, 12, color, w, true)
				draw_arc(c + Vector2(-r * 0.35, r * 0.85), r * 0.6, PI * 1.1, PI * 1.9, 10, color, w, true)
				draw_arc(c + Vector2(r * 0.4, r * 0.85), r * 0.6, PI * 1.1, PI * 1.9, 10, color, w, true)
			"handshake":
				draw_polyline(PackedVector2Array([c + Vector2(-r, -r * 0.1), c + Vector2(-r * 0.3, -r * 0.5), c + Vector2(r * 0.2, -r * 0.1), c + Vector2(-r * 0.1, r * 0.3), c + Vector2(r * 0.4, r * 0.5), c + Vector2(r, 0)]), color, w, true)
			"bars":
				for k in range(3):
					draw_line(c + Vector2(-r * 0.6 + k * r * 0.6, r * 0.8), c + Vector2(-r * 0.6 + k * r * 0.6, r * 0.8 - r * (0.6 + k * 0.5)), color, w + 1, true)
			"coins":
				for k in range(3):
					draw_arc(c + Vector2(0, r * 0.5 - k * r * 0.45), r * 0.7, PI, TAU, 12, color, w, true)
					draw_arc(c + Vector2(0, r * 0.5 - k * r * 0.45), r * 0.7, 0, PI, 12, Color(color, 0.4), w, true)
			"doc":
				draw_rect(Rect2(c - Vector2(r * 0.7, r), Vector2(r * 1.4, r * 2)), color, false, w)
				for k in range(3):
					draw_line(c + Vector2(-r * 0.4, -r * 0.45 + k * r * 0.45), c + Vector2(r * 0.4, -r * 0.45 + k * r * 0.45), color, w, true)
			"done":
				draw_circle(c, r * 0.45, color)
			"now":
				draw_arc(c, r * 0.6, 0, TAU, 20, color, w, true)
				draw_circle(c, r * 0.32, color)
			"goal":
				draw_arc(c, r * 0.55, 0, TAU, 16, color, w, true)
			"goal_done":
				draw_arc(c, r * 0.55, 0, TAU, 16, color, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.3, 0), c + Vector2(-r * 0.05, r * 0.25), c + Vector2(r * 0.32, -r * 0.25)]), color, w, true)


const TILE_HINTS := {
	"start": "結算本季業績與聲望",
	"client": "可能遇見一位新客戶",
	"referral": "老客戶可能介紹一位新客戶",
	"life": "客戶的人生可能出現變化",
	"market": "市場變動會考驗客戶的規劃",
	"training": "完成一題合規測驗",
	"audit": "檢視過往成交是否合規",
	"seminar": "與同儕交流，累積專業",
}
const SessionPanel := preload("res://scripts/ui/session_panel.gd")
const EventPanel := preload("res://scripts/ui/event_panel.gd")
const CaseSetup := preload("res://scripts/ui/case_setup.gd")
const UiLock := preload("res://scripts/ui_lock.gd")
## The ten mission pages (own turn); spectators and ?classic=1 keep the panels above
const QuestLayer := preload("res://scripts/quest/quest_layer.gd")
const GameHeader := preload("res://scripts/quest/widgets/game_header.gd")
const LeaveDialog := preload("res://scripts/quest/widgets/leave_dialog.gd")
const BackButton := preload("res://scripts/ui/back_button.gd")
## Pawn walk per station and the camera's arrival focus (seconds)
const STEP_SECONDS := 0.22
const FOCUS_SECONDS := 0.6

var main: Node
var _board: Control
var _center: VBoxContainer
var _save_label: Label
var _save_retry: Button
var _action_row: HBoxContainer
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
var _local_roll_in_flight: bool = false
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
var _client_strip: PanelContainer = null
var _client_avatars_box: HBoxContainer = null

# Deferred overlay display (waiting for dice and pawn animations to complete)
var _is_overlay_deferred: bool = false
var _deferred_overlay_timer: float = 0.0

# Current match quest cards
var _quests_card: PanelContainer = null
var _quests_content: VBoxContainer = null
var _quests_title_lbl: Label = null

# Responsive layout and tab control
var _current_tab: int = 0  # Portrait tabs: 0 game (board, directly shows interview/event panel if active), 1 status activity
var _was_overlay: bool = false
var _root: BoxContainer
var _left_stack: Control
var _side_panel: Control
var _tab_bar: HBoxContainer
var _tab_buttons: Array[Button] = []
var _dice_ctl: DiceControl

# Map HUD card (where am I / what next / key numbers / main button)
var _hud_card: PanelContainer
var _hud_status: Label
var _hud_title: Label
var _hud_hint: Label
var _hud_rounds: Label
var _hud_rep: Label

# Right panel: three primary layers
var _task_title: Label
var _task_body: Label
var _task_quest: Label
var _task_case: Label
var _task_where: Label
var _task_img: TextureRect
var _goals_box: VBoxContainer
var _stats_box: GridContainer
var _goals_progress: Label
var _client_panel: Control
var _timeline_box: VBoxContainer
## 目前任務裡的主線路線進度，與最近決策（最新 3 筆）
var _route: Control
var _recent_box: VBoxContainer
## Stations this advisor has landed on, newest last (for the record timeline)
var _history: Array = []
var _case_setup: Control
var _client_box: VBoxContainer
var _record_box: VBoxContainer
var _hud_action: HBoxContainer
var _quest: Control
var _map_header: Control
var _focus_fired := false
## 返回培訓方式 on the client brief (case setup step 1), placed inside the case setup
var _brief_back: Button


class DiceControl extends Control:
	var value: int = 0
	var rolling: bool = false
	var dot_color: Color = Color("#F3F0E7")

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
		var bg_col := Color("#0D4038") if not rolling else Color("#134A41")
		var border_col := Color(1, 1, 1, 0.35) if not rolling else Color("#00A86B")
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
	if not Engine.is_editor_hint():
		# Office / city room tone under the game screen (Ambience bus)
		AudioManager.set_ambience(true)
		# 流程狀態機：新的一局從地圖待機開始；下一站解鎖由這裡播放動畫
		QuestFlow.reset()
		if not QuestFlow.state_changed.is_connected(_on_flow_state):
			QuestFlow.state_changed.connect(_on_flow_state)
		if not Net.server_error.is_connected(_on_roll_error):
			Net.server_error.connect(_on_roll_error)
		if not GameState.decision_added.is_connected(_refresh_recent):
			GameState.decision_added.connect(_refresh_recent)
	if not Net.state.is_empty():
		refresh(Net.state)


func on_layout_changed(_is_portrait: bool) -> void:
	# The case setup keeps its step, client and packed tools through the rebuild
	var keep: Control = _case_setup if _case_setup != null and is_instance_valid(_case_setup) else null
	if keep:
		keep.set("_moving", true)
		remove_child(keep)
	_build_ui()
	if keep:
		_case_setup = keep
		add_child(keep)
		keep.set("_moving", false)
		keep.call("refresh_layout")
	if not Net.state.is_empty():
		refresh(Net.state)


func _build_ui() -> void:
	UI.clear(self)
	_case_setup = null
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
	_center.alignment = BoxContainer.ALIGNMENT_END
	_left_stack.add_child(_center)
	_build_hud()

	# Prominent full-width banner when it's your turn
	_my_turn_banner = UI.panel(Color("#1a4239"), 12, 6)
	_my_turn_banner.add_theme_stylebox_override("panel", UI.box(Color("#1a4239"), 12, UI.GOLD, 8, false))
	_my_turn_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var banner_l := UI.label("★ 輪到你了！請擲骰前進 ★", 12 if UI.is_phone_landscape() else (13 if UI.is_phone_portrait() else 18), UI.GOLD, true)
	banner_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_my_turn_banner.add_child(banner_l)
	_my_turn_banner.visible = false
	_center.add_child(_my_turn_banner)

	# Spectator ribbon during other players' turns
	_spectator_ribbon = UI.panel(Color("#0f2922"), 10, 6)
	_spectator_ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spectator_ribbon_lbl = UI.label("觀看中：其他顧問的回合", 11 if UI.is_phone_landscape() else (12 if UI.is_phone_portrait() else 14), UI.MUTED, true)
	_spectator_ribbon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_ribbon.add_child(_spectator_ribbon_lbl)
	_spectator_ribbon.visible = false
	_center.add_child(_spectator_ribbon)

	_top_label = UI.label("", 11 if UI.is_phone_landscape() else (12 if UI.is_phone_portrait() else (15 if portrait else 16)), UI.MUTED, true)
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
	actor_row.hide()

	# Compact client book strip in board center (up to 6 signed clients)
	_client_strip = UI.panel(Color("#102821", 0.85), 8, 4)
	_client_strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var strip_inner := UI.vbox(2)
	strip_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	var strip_head := UI.hbox(4)
	strip_head.alignment = BoxContainer.ALIGNMENT_CENTER
	strip_head.add_child(UI.label("客戶簿", 11 if UI.is_phone() else 12, UI.GOLD))
	strip_inner.add_child(strip_head)
	_client_avatars_box = UI.hbox(4 if UI.is_phone() else 6)
	_client_avatars_box.alignment = BoxContainer.ALIGNMENT_CENTER
	strip_inner.add_child(_client_avatars_box)
	_client_strip.add_child(strip_inner)

	_dice_ctl = DiceControl.new()
	_dice_ctl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dice_ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action_row = UI.hbox(10)
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_action.add_child(_action_row)
	_action_row.add_child(_dice_ctl)

	_dice_roll_info_lbl = UI.label("", 11 if UI.is_phone_landscape() else (12 if UI.is_phone_portrait() else 14), UI.GOLD, true)
	_dice_roll_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_child(_dice_roll_info_lbl)

	# 擲骰前進: disabled the moment it is pressed (no double rolls), real hover / pressed / focus /
	# disabled / loading states
	_roll_btn = QuestUI.button("擲骰前進", _on_roll, "primary", "dice")
	_roll_btn.name = "RollButton"
	_roll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if UI.is_phone() else Control.SIZE_SHRINK_CENTER
	_roll_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_roll_btn.custom_minimum_size = Vector2(196, 52)
	_action_row.add_child(_roll_btn)
	_center.add_child(_client_strip)

	if not UI.is_phone():
		var leg_text: String = "◎客戶 ✚事件 ↗市場 ✓合規 ⚠稽核 ♥介紹 ◇研討 ★結算"
		var legend := UI.label(leg_text, 12 if portrait else 13, UI.MUTED, true)
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_center.add_child(legend)
		legend.hide()

	_session = SessionPanel.new()
	_session.main = main
	_session.visible = false
	_session.z_index = 20
	_session.violation_occurred.connect(_trigger_screen_shake)
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

	# Right side / page 2: task panel (30%) — three primary layers, everything else in collapsible drawers
	_side_panel = PanelContainer.new()
	var side_sb := StyleBoxFlat.new()
	side_sb.bg_color = C_BG
	side_sb.border_color = Color(1, 1, 1, 0.08)
	side_sb.border_width_left = 1
	side_sb.set_content_margin_all(16 if not UI.is_phone() else 12)
	# The secretary's 培訓秘書 entry sits in a strip of its own under the task panel, covering nothing
	if not portrait and _secretary_on():
		side_sb.content_margin_bottom = 74
	_side_panel.add_theme_stylebox_override("panel", side_sb)
	if not portrait:
		var side_w: float = 260.0 if UI.is_phone_landscape() else clampf(size.x * 0.30, 320.0, 440.0)
		_side_panel.custom_minimum_size = Vector2(side_w, 0)
	else:
		_side_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_box.add_child(_side_panel)

	var sv := UI.vbox(16)
	if portrait:
		sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_panel.add_child(UI.scroll(sv))

	var top := UI.hbox(8)
	if Net.is_multiplayer():
		top.add_child(UI.label("房間 " + Net.room_code, 13, C_MUTED))
	else:
		top.add_child(UI.label("單人練習", 13, C_MUTED))
	top.add_child(UI.spacer())
	top.add_child(_quiet_button("聲音", func(): _open_audio_settings()))
	top.add_child(_quiet_button("離開培訓", func(): _confirm_leave()))
	sv.add_child(top)

	# 1. Current task: where I am, what this station trains, goals
	var task_v := UI.vbox(10)
	var th := _panel_header("pin", "目前任務")
	_task_where = UI.label("", 14, C_GOLD)
	th.add_child(_task_where)
	task_v.add_child(th)
	var main_row := UI.hbox(8)
	var main_chip := QuestUI.chip("主線任務", QuestUI.GOLD)
	main_chip.name = "MainLineChip"
	main_row.add_child(main_chip)
	task_v.add_child(main_row)
	_route = RouteProgress.new()
	task_v.add_child(_route)
	_task_img = TextureRect.new()
	_task_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_task_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_task_img.custom_minimum_size = Vector2(0, 112 if not UI.is_phone() else 96)
	_task_img.material = UI.get_rounded_material(0.06)
	task_v.add_child(_task_img)
	_task_title = UI.label("", 18, C_TEXT, true)
	task_v.add_child(_task_title)
	_task_body = UI.label("", 14, C_MUTED, true)
	task_v.add_child(_task_body)
	var goals := PanelContainer.new()
	var gsb := _card_style(0.5)
	gsb.shadow_size = 0
	gsb.bg_color = Color(C_BG, 0.6)
	gsb.content_margin_top = 10
	gsb.content_margin_bottom = 10
	goals.add_theme_stylebox_override("panel", gsb)
	var gv := UI.vbox(6)
	gv.add_child(UI.label("任務目標", 14, C_GOLD))
	_goals_box = UI.vbox(6)
	gv.add_child(_goals_box)
	_goals_progress = UI.label("", 13, C_GOLD)
	_goals_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gv.add_child(_goals_progress)
	goals.add_child(gv)
	task_v.add_child(goals)
	_task_case = UI.label("", 13, C_GREEN, true)
	task_v.add_child(_task_case)
	_task_quest = UI.label("", 13, C_GOLD, true)
	task_v.add_child(_task_quest)
	sv.add_child(_card(task_v))

	# 2. Client status: the client being served (portrait, 信任 / 需求 / 預算適配 / 合規)
	var client_v := UI.vbox(10)
	client_v.add_child(_panel_header("people", "客戶狀態"))
	_client_panel = load("res://scripts/quest/widgets/client_status_panel.gd").new(true, false)
	_client_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	client_v.add_child(_client_panel)
	_client_box = UI.vbox(8)
	client_v.add_child(_client_box)
	sv.add_child(_card(client_v))
	# 最近決策：本局最新 3 筆選擇（完整紀錄在結算的「查看決策回顧」）
	var recent_v := UI.vbox(8)
	recent_v.add_child(_panel_header("doc", "最近決策"))
	_recent_box = UI.vbox(6)
	_recent_box.name = "RecentDecisions"
	recent_v.add_child(_recent_box)
	sv.add_child(_card(recent_v))
	# Advisor numbers (prospects, clients, reputation, sales) in a drawer of their own
	_stats_box = GridContainer.new()
	_stats_box.columns = 2
	_stats_box.add_theme_constant_override("h_separation", 8)
	_stats_box.add_theme_constant_override("v_separation", 8)

	# 3. Advisor record: timeline of stations visited
	var record_v := UI.vbox(10)
	record_v.add_child(_panel_header("doc", "顧問紀錄"))
	_timeline_box = UI.vbox(4)
	record_v.add_child(_timeline_box)
	sv.add_child(_card(record_v))

	# Secondary information: collapsed drawers
	var drawers := UI.vbox(8)
	sv.add_child(drawers)

	_record_box = UI.vbox(8)
	drawers.add_child(_drawer("決策與 AI 提示", _record_box)[0])
	drawers.add_child(_drawer("顧問數據", _stats_box)[0])

	_quests_content = UI.vbox(6)
	var qd: Array = _drawer("本季任務", _quests_content)
	_quests_card = qd[0]
	_quests_title_lbl = qd[1]
	_quests_card.visible = false
	drawers.add_child(_quests_card)

	_players_box = UI.vbox(6)
	drawers.add_child(_drawer("顧問名單", _players_box)[0])

	_book_box = UI.vbox(4)
	drawers.add_child(_drawer("我的客戶簿", _book_box)[0])

	_log_box = UI.vbox(4)
	drawers.add_child(_drawer("完整動態", _log_box)[0])

	var react := UI.hbox(6)
	for e: String in ["讚！", "學到了", "好問題", "？", "♥"]:
		var emo: String = e
		react.add_child(_quiet_button(emo, func(): Net.send({"t": "react", "emoji": emo})))
	drawers.add_child(_drawer("互動回應", react)[0])

	var save_v := UI.vbox(6)
	_save_label = UI.label("", 12, C_MUTED, true)
	save_v.add_child(_save_label)
	_save_retry = _quiet_button("重試儲存訓練紀錄", func(): Net.retry_training_save())
	save_v.add_child(_save_retry)
	sv.add_child(save_v)
	if not Net.training_save_changed.is_connected(_show_save_status):
		Net.training_save_changed.connect(_show_save_status)
	_show_save_status(Net.training_save_status)

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

	# Map header: the cover logo, 第 N / M 站 and the client clock over the map (the board's own
	# painted title is turned off), settings and sound on the right
	if "show_title" in _board:
		_board.show_title = false
	_map_header = GameHeader.new(UI.is_phone())
	_map_header.name = "MapHeader"
	_map_header.position = Vector2(8, 8) if UI.is_phone() else Vector2(14, 12)
	_map_header.connect("settings_requested", _open_quest_settings)
	_left_stack.add_child(_map_header)
	# Mission pages sit above everything in this screen
	_quest = QuestLayer.new()
	_quest.game = self
	add_child(_quest)

	if not Engine.is_editor_hint():
		Portraits.add_player_avatar_callback(_on_player_avatar_loaded)
		if Net != null and not Net.avatar_loaded.is_connected(_on_player_avatar_loaded):
			Net.avatar_loaded.connect(_on_player_avatar_loaded)


## 擲骰前進：只在地圖待機時接受（動畫或頁面切換中連點不會送出第二次）；點數由後端決定
func _on_roll() -> void:
	if _local_roll_in_flight or _roll_btn.disabled:
		return
	if not Engine.is_editor_hint() and not QuestFlow.can_roll():
		push_warning("擲骰前進：目前狀態為「%s」，這次點擊不送出" % QuestFlow.label())
		return
	QuestFlow.claim(0.6)
	_local_roll_in_flight = true
	_roll_btn.call("set_loading", true, "擲骰中")
	QuestFlow.go(QuestFlow.DICE_ROLLING, "擲骰前進")
	Net.act({"type": "roll"})
	# 後端 6 秒內沒有回應：按鈕與狀態復原，不讓畫面停在擲骰中
	get_tree().create_timer(6.0).timeout.connect(func():
		if _local_roll_in_flight and QuestFlow.state == QuestFlow.DICE_ROLLING:
			_abort_roll("擲骰沒有收到後端回應，請再按一次「擲骰前進」")
	)


func _on_roll_error(msg: String) -> void:
	if _local_roll_in_flight and QuestFlow.state == QuestFlow.DICE_ROLLING:
		_abort_roll("擲骰失敗：" + msg)


func _abort_roll(reason: String) -> void:
	push_error("擲骰前進：" + reason)
	_local_roll_in_flight = false
	if is_instance_valid(_roll_btn):
		_roll_btn.call("set_loading", false)
		_roll_btn.disabled = false
	QuestFlow.go(QuestFlow.MAP_IDLE, "擲骰中止")
	if _quest != null:
		_quest.show_toast(reason, "error")


## 跳過動畫：骰子落定、棋子直接到站，鏡頭聚焦後馬上進任務簡報（點數與站點仍是後端的結果）
func skip_move_animation() -> void:
	if not _is_overlay_deferred:
		return
	if _board.has_method("freeze_movement"):
		_board.freeze_movement(0.0)
	if _board.has_method("snap_pawns"):
		_board.snap_pawns()
	_deferred_overlay_timer = minf(_deferred_overlay_timer, FOCUS_SECONDS + 0.05)
	_focus_fired = false
	if QuestFlow.state == QuestFlow.DICE_ROLLING:
		QuestFlow.go(QuestFlow.PLAYER_MOVING, "跳過動畫")


## 流程狀態改變：下一站解鎖時沿路線播放金線，播完回到地圖待機
func _on_flow_state(_from: String, to: String) -> void:
	if to != QuestFlow.NEXT_STAGE_UNLOCKED:
		return
	var dur := 1.2
	if _board != null and _board.has_method("play_unlock"):
		dur = float(_board.call("play_unlock", int(Net.me().get("pos", 0)), GameState.next_node(), dur))
	AudioManager.play("node_unlock")
	get_tree().create_timer(dur).timeout.connect(func():
		if QuestFlow.state == QuestFlow.NEXT_STAGE_UNLOCKED:
			QuestFlow.go(QuestFlow.MAP_IDLE, "解鎖動畫結束")
	)


func _open_quest_settings() -> void:
	if _quest != null:
		_quest.open_settings()


## Client brief (case setup step 1): 返回培訓方式 leaves this room and goes back to the
## training-mode page with the line-up kept. Added inside the case setup so it takes the click.
func _sync_brief_back() -> void:
	var cs := _case_setup
	var on := cs != null and is_instance_valid(cs) and int(cs.get("_step")) == 1 and not bool(cs.get("_accepting"))
	if not on:
		if _brief_back != null and is_instance_valid(_brief_back):
			_brief_back.visible = false
		return
	if _brief_back == null or not is_instance_valid(_brief_back) or _brief_back.get_parent() != cs:
		_brief_back = BackButton.new("返回培訓方式")
		_brief_back.name = "BriefBackButton"
		_brief_back.z_index = 5
		_brief_back.pressed.connect(func():
			if main and main.has_method("back_to_training_mode"):
				main.back_to_training_mode()
		)
		cs.add_child(_brief_back)
	_brief_back.visible = true
	var k := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.7, 1.4)
	_brief_back.reset_size()
	_brief_back.position = Vector2(16.0 * k, (66.0 if not UI.is_portrait() else 60.0) * k)
	if _brief_back.get_index() != cs.get_child_count() - 1:
		cs.move_child(_brief_back, cs.get_child_count() - 1)


## True when the mission layer shows this state itself (own session or event)
func _quest_owns(s: Dictionary = Net.state) -> bool:
	return _quest != null and is_instance_valid(_quest) and _quest.owns(s)


## Back on the map after a page: the camera eases out again
func on_map_shown() -> void:
	if _board != null and _board.has_method("reset_view"):
		_board.reset_view()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		AudioManager.set_ambience(false)
		AudioManager.stop_tension_layers()
		if QuestFlow.state_changed.is_connected(_on_flow_state):
			QuestFlow.state_changed.disconnect(_on_flow_state)
		if Net.server_error.is_connected(_on_roll_error):
			Net.server_error.disconnect(_on_roll_error)
		if GameState.decision_added.is_connected(_refresh_recent):
			GameState.decision_added.disconnect(_refresh_recent)
		QuestFlow.reset()
	if Net.training_save_changed.is_connected(_show_save_status):
		Net.training_save_changed.disconnect(_show_save_status)
	if not Engine.is_editor_hint():
		Portraits.remove_player_avatar_callback(_on_player_avatar_loaded)
		if Net != null and Net.avatar_loaded.is_connected(_on_player_avatar_loaded):
			Net.avatar_loaded.disconnect(_on_player_avatar_loaded)

func _show_save_status(status: Dictionary) -> void:
	if not is_instance_valid(_save_label):
		return
	var failed := str(status.get("local", "")) == "failed" or str(status.get("cloud", "")) == "failed"
	_save_retry.visible = failed
	if failed:
		_save_label.text = "訓練紀錄尚未完整儲存，請重試"
		_save_label.modulate = UI.GOLD
	else:
		_save_label.modulate = Color.WHITE
		match str(status.get("cloud", "")):
			"saved": _save_label.text = "✓ 本次訓練已同步至帳號"
			"pending": _save_label.text = "訓練紀錄同步中…"
			_: _save_label.text = "✓ 本次訓練保存在這個裝置" if str(status.get("local", "")) == "saved" else "每次訓練會自動留下紀錄"


func _on_player_avatar_loaded(_arg1: Variant = null, _arg2: Variant = null) -> void:
	if Net.state != null and not Net.state.is_empty():
		refresh(Net.state)


func _fit_wrapped_label(lbl: Label, max_w: float) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font: Font = lbl.get_theme_font("font")
	var fsz: int = lbl.get_theme_font_size("font_size")
	var text_w: float = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x if font != null else max_w
	lbl.custom_minimum_size.x = clampf(text_w + 2.0, 0.0, maxf(max_w, 40.0))


func _sync_center_bounds() -> void:
	if _board == null or _center == null:
		return
	# The HUD card sits in the board's reserved strip at the bottom of the map
	var r: Rect2 = _board.get_inner_rect()
	# Never under the map header (logo / 第 N 站 / clock): the main button stays in the open
	if _map_header != null and is_instance_valid(_map_header):
		var hr := Rect2(_map_header.position, _map_header.size).grow(6)
		if hr.intersects(r):
			r.position.y = hr.end.y + 6
	_center.add_theme_constant_override("separation", 0)
	# The map design docks only the main button; the dice animation still plays as a cutscene
	_dice_ctl.visible = false
	for legacy: Control in [_my_turn_banner, _spectator_ribbon, _dice_roll_info_lbl, _client_strip, _top_label]:
		if legacy != null:
			legacy.hide()
	_center.size = r.size
	_center.position = r.position
	if _cutscene_center_box != null and is_instance_valid(_cutscene_center_box):
		_cutscene_center_box.position = (_board.size - _cutscene_center_box.size) * 0.5


# ───────── HQ interface building blocks ─────────

func _card_style(alpha := 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_CARD, alpha)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.shadow_color = Color(0, 0, 0, 0.12)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _card(content: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _card_style())
	p.add_child(content)
	return p


func _section_label(text: String) -> Label:
	return UI.label(text, 12, C_MUTED)


## Low-emphasis text button for secondary actions (sound, leave, reactions)
func _quiet_button(text: String, cb: Callable) -> Button:
	var b := UI.button(text, cb, 13, C_CARD)
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := _card_style(0.6 if st == "normal" else 0.95)
		sb.set_corner_radius_all(10)
		sb.shadow_size = 0
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", C_TEXT)
	return b


## Collapsible drawer, closed by default. Returns [container, title label].
func _drawer(title: String, content: Control) -> Array:
	var box := PanelContainer.new()
	var sb := _card_style(0.55)
	sb.shadow_size = 0
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(8)
	box.add_child(v)
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.custom_minimum_size.y = 32
	var hh := UI.hbox(8)
	hh.set_anchors_preset(Control.PRESET_FULL_RECT)
	hh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_lbl := UI.label(title, 14, C_TEXT)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_child(title_lbl)
	var sp := UI.spacer()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_child(sp)
	var arrow := UI.label("展開", 12, C_MUTED)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hh.add_child(arrow)
	head.add_child(hh)
	v.add_child(head)
	content.visible = false
	v.add_child(content)
	head.pressed.connect(func():
		content.visible = not content.visible
		arrow.text = "收合" if content.visible else "展開"
	)
	return [box, title_lbl]


## Action dock: just the main button, placed by the board under the current station
func _build_hud() -> void:
	_hud_card = PanelContainer.new()
	_hud_card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hud_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_center.add_child(_hud_card)
	_hud_action = UI.hbox(10)
	_hud_action.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_card.add_child(_hud_action)


func _hud_stat(caption: String) -> Array:
	var v := UI.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UI.label(caption, 12, C_MUTED))
	var val := UI.label("—", 22, C_TEXT)
	v.add_child(val)
	return [v, val]


func _refresh_hud(s: Dictionary, mine: bool, cur_name: String, stage: String, round_num: int) -> void:
	var total_rounds: int = int(s.get("settings", {}).get("rounds", 5))
	var turn_text := "輪到你了" if mine else "%s 行動中" % cur_name
	if "title_sub" in _board:
		_board.title_sub = "第 %d / %d 回合｜%s" % [round_num, total_rounds, turn_text]
	if _hud_title == null:
		return
	_hud_status.text = "第 %d / %d 回合｜%s" % [round_num, total_rounds, turn_text]
	var tiles: Array = Net.static_data.get("board", [])
	if not tiles.is_empty():
		var pos := int(Net.current_player().get("pos", 0)) % tiles.size()
		var tile: Dictionary = tiles[pos]
		_hud_title.text = "目前位置｜%s" % str(tile.get("name", ""))
		var owner: Variant = s.get("territory", {}).get(str(pos), null)
		if mine and stage == "roll":
			_hud_hint.text = "按「擲骰前進」前往下一站"
		elif owner is Dictionary:
			_hud_hint.text = "%s 的生活圈" % str(owner.get("clientName", "客戶"))
		elif str(tile.get("type", "")) == "client" and Net.current_player().get("mainCase") is Dictionary and not bool(Net.current_player().get("mainCase").get("done", false)):
			_hud_hint.text = "與主要客戶 %s 會談" % str(Net.current_player().get("mainCase").get("clientName", ""))
		else:
			_hud_hint.text = str(TILE_HINTS.get(str(tile.get("type", "")), ""))
	if _hud_rounds != null:
		_hud_rounds.text = str(maxi(0, total_rounds - round_num + 1))
		_hud_rep.text = str(int(Net.me().get("reputation", 0)))


func _refresh_task(s: Dictionary, mine: bool, cur_name: String, stage: String, done: int, total: int) -> void:
	if _task_title == null:
		return
	var sess = s.get("session")
	var ev = s.get("event")
	if sess is Dictionary:
		var client_name := str((sess.get("client", {}) as Dictionary).get("name", "客戶"))
		var step: Array = STEP_TASKS.get(str(sess.get("step", "")), ["客戶面談", ""])
		if str(sess.get("playerId", "")) == Net.player_id:
			_task_title.text = "%s｜%s" % [step[0], client_name]
			_task_body.text = step[1]
		else:
			_task_title.text = "觀看面談｜%s" % client_name
			_task_body.text = "%s 正在與客戶面談，可以先想想你會怎麼問。" % cur_name
	elif ev is Dictionary:
		_task_title.text = str(ev.get("title", "處理事件"))
		_task_body.text = "完成事件卡後繼續。" if str(ev.get("playerId", "")) == Net.player_id else "%s 正在處理事件。" % cur_name
	elif mine and stage == "roll":
		_task_title.text = "擲骰前進"
		_task_body.text = "擲骰沿著顧問行程前進，抵達的節點會觸發面談或事件。"
	elif mine:
		_task_title.text = "處理目前站點"
		_task_body.text = "依照畫面提示完成這一站。"
	else:
		_task_title.text = "等待 %s 行動" % cur_name
		_task_body.text = "其他顧問的回合。展開下方抽屜可以查看完整動態。"
	# Station header, image and what this station trains
	var board: Array = Net.static_data.get("board", [])
	var kind := ""
	if not board.is_empty():
		var idx := int(Net.current_player().get("pos", 0)) % board.size()
		var tile: Dictionary = board[idx]
		kind = str(tile.get("type", ""))
		_task_where.text = "%02d %s" % [idx, str(tile.get("name", ""))]
		_task_img.texture = _station_image(idx, kind)
		if mine and stage == "roll" and not (sess is Dictionary) and not (ev is Dictionary):
			_task_body.text = str(STATION_INFO.get(kind, ["", []])[0]) + "\n按地圖上的「擲骰前進」前往下一站。"
	_refresh_goals(kind)
	var lines: Array = []
	var mc = Net.me().get("mainCase")
	if mc is Dictionary:
		if bool(mc.get("done", false)):
			lines.append("主要客戶・%s｜案件完成，新的客戶案件已解鎖" % str(mc.get("clientName", "")))
		elif int(mc.get("visits", 0)) == 0:
			lines.append("主要客戶・%s｜尚未會談，抵達客戶節點開始需求訪談" % str(mc.get("clientName", "")))
		else:
			var stage_name: String = {"plan": "方案設計", "objection": "異議處理與結果", "result": "面談結果"}.get(str(mc.get("step", "")), "需求訪談")
			lines.append("主要客戶・%s｜第 %d / %d 次會談%s：%s" % [str(mc.get("clientName", "")), int(mc.get("visits", 0)), int(mc.get("meetings", 3)), "進行中" if bool(mc.get("inMeeting", false)) else "已完成，下一次", stage_name])
	_task_case.text = "\n".join(lines)
	_task_case.visible = not lines.is_empty()
	_task_quest.text = "本季任務已完成 %d / %d" % [done, total] if total > 0 else ""
	_task_quest.visible = total > 0
	if _route != null and is_instance_valid(_route):
		_route.queue_redraw()
	_refresh_recent()


## 最近決策：最新 3 筆（不含經驗值），做得好綠勾、需要加強金色警示，附上幾分鐘前
func _refresh_recent(_entry: Dictionary = {}) -> void:
	if _recent_box == null or not is_instance_valid(_recent_box):
		return
	UI.clear(_recent_box)
	var picked: Array = []
	var ds: Array = [] if Engine.is_editor_hint() else GameState.decision_history()
	for k in range(ds.size() - 1, -1, -1):
		var d := ds[k] as Dictionary
		if str(d.get("stage", "")) == "經驗值":
			continue
		picked.append(d)
		if picked.size() == 3:
			break
	if picked.is_empty():
		_recent_box.add_child(UI.label("還沒有決策紀錄。抵達客戶站點後的每個選擇都會記在這裡。", 13, C_MUTED, true))
		return
	var now := Time.get_unix_time_from_system()
	for d: Dictionary in picked:
		var q := str(d.get("quality", ""))
		var row := UI.hbox(8)
		var ic := QuestUI.icon("circle_check" if q == "good" else ("alert" if q == "bad" else "circle"), 18.0, C_GREEN if q == "good" else (C_GOLD if q == "bad" else C_MUTED))
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var v := UI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := UI.label(str(d.get("title", "")), 14, C_TEXT, true)
		t.max_lines_visible = 2
		v.add_child(t)
		v.add_child(UI.label(str(d.get("stage", "")), 12, C_MUTED))
		row.add_child(v)
		var ts := float(d.get("ts", 0.0))
		if ts > 0.0:
			var mins := int((now - ts) / 60.0)
			row.add_child(UI.label("剛剛" if mins < 1 else "%d 分鐘前" % mins, 12, C_MUTED))
		_recent_box.add_child(row)


## Shows the primary-client + briefcase picker until the server records this player's case
func _sync_case_setup(s: Dictionary) -> void:
	var me_p: Dictionary = Net.me()
	var need := str(s.get("phase", "")) == "playing" and not Net.spectator and not me_p.is_empty() and me_p.get("mainCase") == null
	if need and (_case_setup == null or not is_instance_valid(_case_setup)):
		_case_setup = CaseSetup.new()
		_case_setup.z_index = 110
		add_child(_case_setup)
	elif not need and _case_setup != null and is_instance_valid(_case_setup):
		_case_setup.queue_free()
		_case_setup = null
	if _case_setup != null and is_instance_valid(_case_setup):
		_keep_case_setup_first()


## The map page (board + task panel, nothing on top) is what the player sees: the secretary shows
## its 培訓秘書 entry there and plays the map focus guide on the first visit
func _sync_map_guide(s: Dictionary) -> void:
	if main == null or not main.has_method("secretary_guide"):
		return
	var g: Node = main.secretary_guide()
	if g == null or not g.has_method("map_page"):
		return
	var on_map := str(s.get("phase", "")) == "playing" and not Net.spectator \
		and (_case_setup == null or not is_instance_valid(_case_setup)) \
		and not (s.get("session") is Dictionary) and not (s.get("event") is Dictionary) \
		and (_announcement_modal == null or not is_instance_valid(_announcement_modal))
	var mc: Variant = Net.me().get("mainCase")
	var client_name := str((mc as Dictionary).get("clientName", "")) if mc is Dictionary else ""
	# Portrait: the entry stays above the bottom tab bar
	var bottom := _tab_bar.size.y if UI.is_portrait() and _tab_bar != null and is_instance_valid(_tab_bar) else 0.0
	g.map_page(on_map, {"client_name": client_name, "focus": _roll_btn, "entry_bottom": bottom})


func _secretary_on() -> bool:
	var g: Node = main.secretary_guide() if main != null and main.has_method("secretary_guide") else null
	return g != null and bool(g.get("enabled"))


## Clicks go to the last child, not to the highest z_index: a layer added after the case setup but
## drawn under it would take every click while staying out of sight. Keep the case setup after it.
func _keep_case_setup_first() -> void:
	for i in range(_case_setup.get_index() + 1, get_child_count()):
		var c := get_child(i)
		if c is CanvasItem and (c as CanvasItem).visible and (c as CanvasItem).z_index < _case_setup.z_index:
			move_child(_case_setup, get_child_count() - 1)
			UiLock.log_event("case_setup_to_front (over %s)" % c.name)
			return


func _panel_header(icon_kind: String, title: String) -> HBoxContainer:
	var h := UI.hbox(8)
	var ic := LineIcon.new(icon_kind, 22, C_GOLD)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(UI.label(title, 18, C_TEXT))
	h.add_child(UI.spacer())
	return h


## Station picture: the primary client's scene at client stations, otherwise a view of that spot on the map
func _station_image(idx: int, kind: String) -> Texture2D:
	var mc = Net.me().get("mainCase")
	if kind == "client" and mc is Dictionary and not bool(mc.get("done", false)):
		var path := UI.client_scene_path(str(mc.get("clientId", "")))
		if path != "" and ResourceLoader.exists(path):
			return load(path)
	if _board != null and _board.has_method("station_crop"):
		return _board.station_crop(idx)
	return null


## Goals checklist: meeting stages at a client station during the primary case, otherwise the station's goals
func _refresh_goals(kind: String) -> void:
	if _goals_box == null:
		return
	UI.clear(_goals_box)
	var goals: Array = STATION_INFO.get(kind, ["", []])[1]
	var done_flags: Array = [false, false, false]
	var mc = Net.me().get("mainCase")
	if kind == "client" and mc is Dictionary and not bool(mc.get("done", false)):
		goals = ["需求訪談：找出 %s 真正在意的事" % str(mc.get("clientName", "")), "方案設計：配置資源與保障卡", "異議處理：合規回應並等待決定"]
		var step := str(mc.get("step", ""))
		var reached: int = {"plan": 1, "objection": 2, "result": 3}.get(step, 0)
		for k in range(3):
			done_flags[k] = k < reached
	var done_n := 0
	for f in done_flags:
		if f:
			done_n += 1
	if _goals_progress != null:
		_goals_progress.text = "任務進度 %d / %d" % [done_n, goals.size()] if goals.size() > 0 else ""
	for k in range(goals.size()):
		var row := UI.hbox(8)
		var ic := LineIcon.new("goal_done" if done_flags[k] else "goal", 18, C_GREEN if done_flags[k] else C_MUTED)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var l := UI.label(str(goals[k]), 14, C_TEXT if not done_flags[k] else C_MUTED, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_goals_box.add_child(row)


func _stat_tile(icon_kind: String, caption: String, value: String, progress := -1.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _card_style(0.5)
	sb.shadow_size = 0
	sb.bg_color = Color(C_BG, 0.55)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UI.hbox(10)
	var ic := LineIcon.new(icon_kind, 28, C_TEXT)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(caption, 12, C_MUTED))
	v.add_child(UI.label(value, 20, C_TEXT))
	if progress >= 0.0:
		var bar := UI.bar(progress * 100.0, C_GREEN, 80)
		bar.custom_minimum_size.y = 4
		v.add_child(bar)
	h.add_child(v)
	p.add_child(h)
	return p


func _refresh_stats(s: Dictionary) -> void:
	if _stats_box == null:
		return
	UI.clear(_stats_box)
	var me_p: Dictionary = Net.me()
	var book: Array = me_p.get("book", [])
	var commission := int(me_p.get("commission", 0))
	_stats_box.add_child(_stat_tile("handshake", "潛在客戶", "%d 位" % int(s.get("deckLeft", 0))))
	_stats_box.add_child(_stat_tile("people", "現有客戶", "%d 位" % book.size()))
	_stats_box.add_child(_stat_tile("bars", "聲望", str(int(me_p.get("reputation", 0)))))
	_stats_box.add_child(_stat_tile("coins", "業績目標", "%d / 100" % commission, clampf(commission / 100.0, 0.0, 1.0)))


## Timeline of stations this advisor landed on: current first, then completed ones
func _refresh_timeline() -> void:
	if _timeline_box == null:
		return
	UI.clear(_timeline_box)
	var board: Array = Net.static_data.get("board", [])
	if board.is_empty() or _history.is_empty():
		_timeline_box.add_child(UI.label("還沒有行程紀錄。", 14, C_MUTED, true))
		return
	var shown := 0
	for k in range(_history.size() - 1, -1, -1):
		if shown >= 4:
			break
		var idx: int = _history[k]
		var is_now := k == _history.size() - 1
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(C_BG, 0.6) if is_now else Color(0, 0, 0, 0)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(1 if is_now else 0)
		sb.border_color = Color(C_GREEN, 0.7)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", sb)
		var h := UI.hbox(10)
		var ic := LineIcon.new("now" if is_now else "done", 18, C_GREEN if is_now else C_MUTED)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var l := UI.label("%02d  %s" % [idx, str((board[idx % board.size()] as Dictionary).get("name", ""))], 14, C_TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UI.label("進行中" if is_now else "已完成", 13, C_GREEN if is_now else C_MUTED))
		row.add_child(h)
		_timeline_box.add_child(row)
		shown += 1


func _status_row(caption: String, value: float) -> HBoxContainer:
	var h := UI.hbox(10)
	var l := UI.label(caption, 14, C_MUTED)
	l.custom_minimum_size.x = 64
	h.add_child(l)
	var bar := UI.bar(value, C_GREEN, 120)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(UI.label(str(int(value)), 14, C_TEXT))
	return h


## level 0 low / 1 medium / 2 high; red is reserved for high risk only
func _risk_row(level: int) -> HBoxContainer:
	var h := UI.hbox(10)
	var l := UI.label("合規風險", 14, C_MUTED)
	l.custom_minimum_size.x = 64
	h.add_child(l)
	h.add_child(UI.spacer())
	h.add_child(UI.label(["低", "中", "高"][level], 15, [C_GREEN, C_TEXT, C_RED][level]))
	return h


func _refresh_client(s: Dictionary) -> void:
	if _client_box == null:
		return
	UI.clear(_client_box)
	# A client in progress (own meeting or the primary case): portrait and the four bars
	var has_client := (s.get("session") is Dictionary and str((s.get("session") as Dictionary).get("playerId", "")) == Net.player_id) \
		or (Net.me().get("mainCase") is Dictionary and not bool((Net.me().get("mainCase") as Dictionary).get("done", false)))
	if _client_panel != null and is_instance_valid(_client_panel):
		_client_panel.visible = has_client
		if has_client:
			_client_panel.call("refresh")
			return
	var sess = s.get("session")
	if sess is Dictionary:
		var c: Dictionary = sess.get("client", {})
		var m: Dictionary = sess.get("metrics", {})
		_client_box.add_child(UI.label("%s・%s" % [str(c.get("name", "客戶")), str(c.get("job", ""))], 16, C_TEXT, true))
		_client_box.add_child(_status_row("信任", float(m.get("trust", 0))))
		_client_box.add_child(_status_row("需求掌握", float(m.get("insight", 0))))
		var budget := str(c.get("amount", "")).strip_edges()
		if budget != "":
			var bh := UI.hbox(10)
			var bl := UI.label("預算", 14, C_MUTED)
			bl.custom_minimum_size.x = 64
			bh.add_child(bl)
			var bv := UI.label(budget, 14, C_TEXT, true)
			bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bh.add_child(bv)
			_client_box.add_child(bh)
		var comp := float(m.get("compliance", 100))
		_client_box.add_child(_risk_row(0 if comp >= 70 else (1 if comp >= 45 else 2)))
		return
	# Primary case between meetings: keep showing the client being served
	var mc = Net.me().get("mainCase")
	if mc is Dictionary and not bool(mc.get("done", false)):
		_client_box.add_child(UI.label("主要客戶｜%s・%s" % [str(mc.get("clientName", "")), str(mc.get("job", ""))], 16, C_TEXT, true))
		var cm = mc.get("metrics")
		if cm is Dictionary:
			_client_box.add_child(_status_row("信任", float(cm.get("trust", 0))))
			_client_box.add_child(_status_row("需求掌握", float(cm.get("insight", 0))))
		if str(mc.get("amount", "")) != "":
			_client_box.add_child(UI.label("預算　" + str(mc.get("amount", "")), 14, C_TEXT, true))
		if cm is Dictionary:
			var cc := float(cm.get("compliance", 100))
			_client_box.add_child(_risk_row(0 if cc >= 70 else (1 if cc >= 45 else 2)))
		else:
			_client_box.add_child(UI.label("還沒見過面。抵達客戶節點即可開始需求訪談。", 14, C_MUTED, true))
		return
	var book: Array = Net.me().get("book", [])
	if book.is_empty():
		_client_box.add_child(UI.label("尚未遇到客戶。抵達客戶節點即可開始面談。", 14, C_MUTED, true))
		return
	var last: Dictionary = book[book.size() - 1]
	_client_box.add_child(UI.label("最近簽約｜%s" % str(last.get("name", "客戶")), 16, C_TEXT, true))
	_client_box.add_child(_status_row("滿意度", float(last.get("satisfaction", 0))))
	_client_box.add_child(_risk_row(2 if bool(last.get("mis", false)) else 0))
	if book.size() > 1:
		_client_box.add_child(UI.label("客戶簿共 %d 位，可在下方抽屜查看。" % book.size(), 12, C_MUTED, true))


func _refresh_record(s: Dictionary) -> void:
	if _record_box == null:
		return
	UI.clear(_record_box)
	var decisions: Array = Net.me().get("decisions", [])
	if decisions.is_empty():
		_record_box.add_child(UI.label("還沒有決策紀錄。", 14, C_MUTED, true))
	else:
		var d: Dictionary = decisions[decisions.size() - 1]
		var q := str(d.get("quality", "ok"))
		var h := UI.hbox(8)
		h.add_child(UI.label({"good": "佳", "ok": "普通", "bad": "待改進"}.get(q, "普通"), 12, {"good": C_GREEN, "bad": C_RED}.get(q, C_MUTED)))
		var t := UI.label(str(d.get("title", "")), 15, C_TEXT, true)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		_record_box.add_child(h)
		var body := str(d.get("body", ""))
		if body != "":
			_record_box.add_child(UI.label(body, 13, C_MUTED, true))
	# Latest AI coach hint: the explicit hint, else the newest coach tip of the interview
	var hint := ""
	var sess = s.get("session")
	if sess is Dictionary:
		if sess.get("hint") != null:
			hint = str(sess.get("hint"))
		var asked: Array = sess.get("asked", []) if sess.get("asked") is Array else []
		for k in range(asked.size() - 1, -1, -1):
			if hint == "" and str((asked[k] as Dictionary).get("coachTip", "")) != "":
				hint = str(asked[k].get("coachTip"))
	if hint != "":
		var hv := UI.vbox(2)
		hv.add_child(UI.label("AI 教練提示", 12, C_GREEN))
		hv.add_child(UI.label(hint, 13, C_TEXT, true))
		_record_box.add_child(hv)


func _switch_tab(tab_idx: int) -> void:
	_current_tab = tab_idx
	_sync_tabs()


func _sync_tabs() -> void:
	var sess = Net.state.get("session")
	var ev = Net.state.get("event")
	var is_sess: bool = sess is Dictionary and not _is_overlay_deferred
	var is_ev: bool = ev is Dictionary and not is_sess and not _is_overlay_deferred
	# Pages shown by the mission layer keep the map (and side panel) underneath, panels hidden
	var hud_hidden: bool = is_sess or is_ev
	if _quest_owns():
		is_sess = false
		is_ev = false
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
		_center.visible = not overlay and not hud_hidden
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
	_sync_brief_back()

	# Deferred panel countdown timer (waiting for dice roll and pawn movement to finish)
	if _is_overlay_deferred:
		_deferred_overlay_timer -= delta
		# The pawn has arrived: ease the camera onto the station before the page opens
		if not _focus_fired and _deferred_overlay_timer <= FOCUS_SECONDS and _quest != null and _quest.active():
			_focus_fired = true
			if _board.has_method("focus_station"):
				_board.focus_station(int(Net.current_player().get("pos", 0)), FOCUS_SECONDS)
		if _deferred_overlay_timer <= 0.0:
			_is_overlay_deferred = false
			_apply_deferred_overlay()

	# Dice roll button subtle breathing glow (when it's your turn)
	if _roll_btn != null and _roll_btn.visible:
		_btn_pulse += delta * 4.0
		var sc: float = 1.0 if UI.reduce_motion else 1.0 + sin(_btn_pulse) * 0.02
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
			_dice_ctl.scale = Vector2(1.4, 1.4)
			tw.tween_property(_dice_ctl, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Sound.play("dice_settle", self)


func _show_die() -> void:
	var r = Net.state.get("lastRoll")
	var roll_val: int = int(r) if r != null else 0
	_dice_ctl.set_value(roll_val)
	if _dice_roll_info_lbl != null:
		if roll_val > 0:
			_dice_roll_info_lbl.text = "上一步擲出 %d 點" % roll_val
			_dice_roll_info_lbl.visible = false
		else:
			_dice_roll_info_lbl.text = ""
			_dice_roll_info_lbl.visible = false


func refresh(s: Dictionary) -> void:
	if _board == null:
		return
	_sync_center_bounds()
	var cur: Dictionary = Net.current_player()
	var cur_id: String = str(cur.get("id", ""))
	var cur_name: String = PlayerProfile.display_name(cur)
	var round_num: int = int(s.get("round", 1))
	var mine: bool = Net.is_my_turn()
	var stage: String = str(s.get("turnStage", ""))
	var last_roll_val: int = int(s.get("lastRoll", 0)) if s.get("lastRoll") != null else 0

	# Turn change detection: play transition card
	if cur_id != "" and (cur_id != _prev_turn_player_id or round_num != _prev_round_num):
		_prev_turn_player_id = cur_id
		_prev_round_num = round_num
		_prev_last_roll = 0
		var cur_player_idx: int = int(s.get("turn", 0)) % 4
		var player_col: Color = PlayerProfile.player_color(cur, cur_player_idx)
		_show_turn_transition(round_num, cur_name, player_col, mine)
		if mine:
			Sound.play("step", self)

	# Dice roll cutscene trigger: when stage changes from roll, lastRoll changes, or local roll was in flight
	# lastRoll is never cleared on the server, so only fire once the turn has left the roll stage
	var trigger_cutscene: bool = stage != "roll" and last_roll_val > 0 and (last_roll_val != _prev_last_roll or _prev_stage == "roll" or _local_roll_in_flight)
	if trigger_cutscene:
		_prev_last_roll = last_roll_val
		_local_roll_in_flight = false
		_roll_btn.call("set_loading", false)
		var total_anim_time: float
		if _quest != null and _quest.active():
			# Page 1: die tumbles and lands, the pawn walks station by station, the camera settles on
			# the arrival, then the arrival brief (never earlier — the event is not hinted)
			var land: float = _quest.play_dice(cur_name, last_roll_val, mine)
			if _board.has_method("freeze_movement"):
				_board.freeze_movement(land)
			total_anim_time = land + float(last_roll_val) * STEP_SECONDS + FOCUS_SECONDS + 0.15
			_focus_fired = false
			# 骰子滾動 → 落定後棋子沿路線逐站移動；到站後由任務層決定下一個狀態
			if QuestFlow.state != QuestFlow.DICE_ROLLING:
				QuestFlow.go(QuestFlow.DICE_ROLLING, "%s 擲出 %d" % [cur_name, last_roll_val])
			get_tree().create_timer(land).timeout.connect(func():
				if QuestFlow.state == QuestFlow.DICE_ROLLING:
					QuestFlow.go(QuestFlow.PLAYER_MOVING, "前進 %d 站" % last_roll_val)
			)
		else:
			_play_dice_cutscene(cur_name, last_roll_val, mine)
			# Defer interview/event panel display: dice roll animation (1.0s) + pawn 1/6s per tile + buffer (0.45s)
			total_anim_time = 1.0 + (float(last_roll_val) * (1.0 / 6.0)) + 0.45
		_is_overlay_deferred = true
		_deferred_overlay_timer = total_anim_time

	_board.set_data(Net.static_data.get("board", []), s.get("players", []), cur_id, s.get("territory", {}))
	_update_center_client_strip()
	if UI.is_phone():
		_top_label.text = "第 %d/%d 回合 ｜ 名單剩 %d 位" % [round_num, int(s.get("settings", {}).get("rounds", 6)), int(s.get("deckLeft", 0))]
	else:
		_top_label.text = "第 %d / %d 回合 ｜ 名單剩 %d 位" % [round_num, int(s.get("settings", {}).get("rounds", 6)), int(s.get("deckLeft", 0))]

	# Own turn vs spectating other player turn indicator
	var cur_player_idx: int = int(s.get("turn", 0)) % 4
	var player_col: Color = UI.PLAYER_COLORS[cur_player_idx]
	if _actor_avatar_panel != null:
		_actor_avatar_panel.add_theme_stylebox_override("panel", UI.box(player_col, 12, Color.WHITE if mine else Color(0, 0, 0, 0), 0))
		_actor_avatar_label.text = cur_name.substr(0, 1) if cur_name != "" else "顧"
	if _actor_avatar_panel != null:
		_actor_avatar_panel.visible = false
	if mine:
		_turn_label.text = ""
		_my_turn_banner.visible = false
		_spectator_ribbon.visible = false
		_screen_glow.visible = true
		_screen_glow.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), 12, UI.GOLD, 3, false))
		_center.modulate = Color(1.0, 0.98, 0.92)
		_roll_btn.visible = stage == "roll"
		if not _local_roll_in_flight:
			_roll_btn.call("set_loading", false)
			_roll_btn.disabled = false
	else:
		_my_turn_banner.visible = false
		_spectator_ribbon.visible = false
		if UI.is_phone():
			var clean_name: String = cur_name
			var p_idx: int = clean_name.find("（")
			if p_idx > 0:
				clean_name = clean_name.substr(0, p_idx)
			clean_name = clean_name.replace("【", "").replace("】", "").strip_edges()
			_spectator_ribbon_lbl.text = "觀看中：%s" % clean_name
		else:
			_spectator_ribbon_lbl.text = "觀看中：【%s】的回合（行動中）" % cur_name
		_turn_label.text = ""
		_screen_glow.visible = true
		_screen_glow.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), 12, Color("#1a4239"), 2, false))
		_screen_glow.modulate.a = 0.45
		_roll_btn.visible = false
		_roll_btn.disabled = true
		_center.modulate = Color(0.85, 0.92, 0.98)

	if stage == "roll":
		_prev_last_roll = 0
		if not _local_roll_in_flight:
			_is_overlay_deferred = false
			_deferred_overlay_timer = 0.0
		_dice_ctl.set_value(0)
		if _dice_roll_info_lbl != null:
			_dice_roll_info_lbl.text = "請點選下方擲骰" if mine else "等待【%s】擲骰……" % cur_name
			_dice_roll_info_lbl.visible = false
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
	var owned: bool = _quest_owns(s)

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
				_side_panel.visible = not has_overlay or owned
				_board.visible = not has_overlay or owned
				_board.modulate = Color.WHITE
			else:
				_side_panel.visible = true
				_board.visible = true
				_board.modulate = Color(1, 1, 1, 0.75) if is_sess and not owned else Color.WHITE
			_session.visible = is_sess and not owned
			_event.visible = is_ev and not owned
			_center.visible = not has_overlay

		if is_sess and not owned:
			_session.refresh(sess, cur_name)
		if is_ev and not owned:
			_event.refresh(ev, cur_name)
		if _quest != null:
			_quest.route(s)

	_sync_tabs()

	# Quarter quests (drawer); the done count also feeds the "current task" card
	var quests: Array = s.get("quests", []) if s.get("quests") != null else []
	var done_count: int = 0
	_quests_card.visible = not quests.is_empty()
	UI.clear(_quests_content)
	for q: Dictionary in quests:
		var qv := UI.vbox(2)
		var qh := UI.hbox(4)
		var q_prog: Dictionary = q.get("progress", {}).get(Net.player_id, {})
		var cur_p: int = int(q_prog.get("cur", 0))
		var target_p: int = int(q_prog.get("target", 1))
		var is_done: bool = bool(q_prog.get("done", false)) or (target_p > 0 and cur_p >= target_p)
		if is_done:
			done_count += 1
		qh.add_child(UI.label(str(q.get("title", "任務")), 14, C_GOLD if is_done else C_TEXT, true))
		qh.add_child(UI.spacer())
		qh.add_child(UI.label("達成" if is_done else "%d/%d" % [cur_p, target_p], 13, C_GOLD if is_done else C_MUTED))
		qv.add_child(qh)
		var q_desc: String = str(q.get("desc", ""))
		if q_desc != "":
			qv.add_child(UI.label(q_desc, 12, C_MUTED, true))
		var q_rew_val = q.get("reward", null)
		if q_rew_val != null and str(q_rew_val) != "":
			var rew_str: String = str(q_rew_val)
			if typeof(q_rew_val) in [TYPE_FLOAT, TYPE_INT] or rew_str.is_valid_float():
				rew_str = "聲望 +%d" % int(float(rew_str))
			qv.add_child(UI.label("獎勵：%s" % rew_str, 12, C_MUTED, true))
		_quests_content.add_child(qv)
	_quests_title_lbl.text = "本季任務 %d/%d" % [done_count, quests.size()]

	var my_pos := int(Net.me().get("pos", -1))
	if my_pos >= 0 and (_history.is_empty() or _history[_history.size() - 1] != my_pos):
		_history.append(my_pos)
	_refresh_stats(s)
	_refresh_timeline()
	_refresh_hud(s, mine, cur_name, stage, round_num)
	_sync_case_setup(s)
	_sync_map_guide(s)
	_refresh_task(s, mine, cur_name, stage, done_count, quests.size())
	_refresh_client(s)
	_refresh_record(s)

	# Player list
	UI.clear(_players_box)
	var i: int = 0
	for p: Dictionary in s.get("players", []):
		var is_cur: bool = str(p.get("id", "")) == cur_id
		var card := UI.panel(Color(C_CARD, 1.0 if is_cur else 0.55), 10, 8, Color(0, 0, 0, 0))
		var v := UI.vbox(2)
		var h := UI.hbox(6)
		var p_col: Color = PlayerProfile.player_color(p, i)
		var av_tex: Texture2D = null
		if not Engine.is_editor_hint():
			# The player's own advisor portrait, the sparring advisors' portraits, else a Google photo
			av_tex = PlayerProfile.portrait_of(p)
			if av_tex == null and str(p.get("id", "")) == Net.player_id and Net.avatar_tex != null:
				av_tex = Net.avatar_tex
			elif av_tex == null:
				var av_url: String = str(p.get("avatar", ""))
				if av_url != "" and av_url != "null" and av_url.begins_with("https://"):
					av_tex = Portraits.get_player_avatar(av_url)
		if av_tex != null:
			var dot_size: float = 20.0
			var av_round := UI.RoundTex.new(av_tex, Vector2(dot_size, dot_size), -1.0, p_col, 2.0)
			av_round.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(av_round)
		else:
			h.add_child(UI.label("●", 16, p_col))
		var adv := PlayerProfile.bot_advisor(p)
		var nm: String = PlayerProfile.display_name(p) + (" (你)" if str(p.get("id", "")) == Net.player_id else ("｜" + str(adv.type) if not adv.is_empty() else ""))
		h.add_child(UI.label(nm, 15, C_TEXT))
		var streak: int = int(p.get("complianceStreak", 0))
		if streak >= 2:
			var strk_chip := UI.chip(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.18), UI.GOLD, 4, 8, 3)
			strk_chip.add_child(UI.label("★ 合規連擊 ×%d" % streak, 11, UI.GOLD))
			h.add_child(strk_chip)
		if not p.get("connected", true) and not p.get("isBot", false):
			var dis_chip := UI.chip(Color(UI.BAD.r, UI.BAD.g, UI.BAD.b, 0.18), UI.BAD, 4, 8, 3)
			dis_chip.add_child(UI.label("斷線", 11, UI.BAD))
			h.add_child(dis_chip)
		if is_cur:
			h.add_child(UI.label("行動中", 12, C_GREEN))
		v.add_child(h)
		v.add_child(UI.label("聲望 %d　業績 %d　客戶 %d　測驗 %d/%d" % [int(p.get("reputation", 0)), int(p.get("commission", 0)), (p.get("book", []) as Array).size(), int(p.get("quizCorrect", 0)), int(p.get("quizTotal", 0))], 13, C_MUTED, true))
		card.add_child(v)
		_players_box.add_child(card)
		i += 1


func _update_center_client_strip() -> void:
	if _client_avatars_box == null or not is_instance_valid(_client_avatars_box):
		return
	UI.clear(_client_avatars_box)
	var me: Dictionary = Net.me()
	var book: Array = me.get("book", [])
	var av_sz: int = 18 if UI.is_phone_landscape() else (22 if UI.is_phone_portrait() else 32)
	var count: int = mini(book.size(), 6)
	# Hide the strip until the first signing so it never crowds the dice area
	if _client_strip != null:
		_client_strip.visible = false
	if count == 0:
		return

	for idx_c in range(count):
		var b: Dictionary = book[idx_c]
		var c_id: String = str(b.get("clientId", b.get("id", "")))
		var c_name: String = str(b.get("name", "客戶"))
		var sat: int = int(b.get("satisfaction", 50))

		var item := Control.new()
		item.custom_minimum_size = Vector2(av_sz, av_sz)

		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		var av := Portraits.create_avatar(c_id, c_name, av_sz)
		av.position = Vector2.ZERO
		av.size = Vector2(av_sz, av_sz)
		item.add_child(av)

		# Round satisfaction dot with a dark rim at the bottom-right
		var dot_sz: float = maxf(8.0, av_sz * 0.3)
		var dot := Panel.new()
		var dot_sb := StyleBoxFlat.new()
		dot_sb.bg_color = UI.GOOD if sat >= 75 else (UI.OK if sat >= 50 else UI.BAD)
		dot_sb.set_corner_radius_all(int(dot_sz))
		dot_sb.set_border_width_all(2)
		dot_sb.border_color = Color("#102821")
		dot.add_theme_stylebox_override("panel", dot_sb)
		dot.size = Vector2(dot_sz, dot_sz)
		dot.position = Vector2(av_sz - dot_sz * 0.85, av_sz - dot_sz * 0.85)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(dot)

		item.tooltip_text = "%s（滿意度 %d）" % [c_name, sat]
		_client_avatars_box.add_child(item)


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
	var cur_name: String = PlayerProfile.display_name(cur)
	var mine: bool = Net.is_my_turn()
	var owned: bool = _quest_owns(s)

	if UI.is_portrait() and has_overlay and not _was_overlay and mine:
		_current_tab = 0
	_was_overlay = has_overlay

	if not UI.is_portrait():
		if UI.is_phone_landscape():
			_side_panel.visible = not has_overlay or owned
			_board.visible = not has_overlay or owned
			_board.modulate = Color.WHITE
		else:
			_side_panel.visible = true
			_board.visible = true
			_board.modulate = Color(1, 1, 1, 0.75) if is_sess and not owned else Color.WHITE
		_session.visible = is_sess and not owned
		_event.visible = is_ev and not owned
		_center.visible = not has_overlay

	if is_sess and not owned:
		_session.refresh(sess, cur_name)
	if is_ev and not owned:
		_event.refresh(ev, cur_name)
	if _quest != null:
		_quest.route(s)

	_sync_tabs()
	_update_center_client_strip()

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
		_log_box.add_child(UI.label(PlayerProfile.localize(str(l.get("text", ""))), 13, UI.tone_color(str(l.get("tone", "info"))), true))


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

	if _center != null:
		_center.visible = false

	# The 3D board has a narrow control dock; the cutscene uses the whole board.
	var inner_r := Rect2(Vector2.ZERO, _board.size)
	var box_w: float = clampf(inner_r.size.x * 0.85, 280.0, 360.0)
	var box_h: float = 170.0

	var card := UI.panel(Color("#102821", 0.96), 14, 12)
	card.add_theme_stylebox_override("panel", UI.box(Color("#102821", 0.96), 14, UI.GOLD, 2, false))
	card.custom_minimum_size = Vector2(box_w, box_h)
	card.size = Vector2(box_w, box_h)
	card.pivot_offset = Vector2(box_w * 0.5, box_h * 0.5)
	card.position = inner_r.get_center() - Vector2(box_w * 0.5, box_h * 0.5)
	cutscene.add_child(card)
	_cutscene_center_box = card

	var center_box := UI.vbox(10)
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(center_box)

	var big_dice := DiceControl.new()
	big_dice.custom_minimum_size = Vector2(96, 96)
	big_dice.pivot_offset = Vector2(48, 48)
	big_dice.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.add_child(big_dice)

	var text_lbl := UI.label("【%s】擲骰中……" % roller_name, 20, UI.TEXT)
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(text_lbl)

	UI.pop_in(card, 0.2)

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
		Sound.play("dice_settle", self)

		var bounce_tw: Tween = big_dice.create_tween()
		big_dice.scale = Vector2(1.4, 1.4)
		bounce_tw.tween_property(big_dice, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		if is_self:
			_trigger_screen_shake()
			dim.color = Color(1, 0.9, 0.6, 0.35)
	)
	tw.tween_interval(0.4)
	tw.tween_property(cutscene, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		_cutscene_center_box = null
		cutscene.queue_free()
		if _center != null:
			var s_curr: Dictionary = Net.state
			var has_overlay_curr: bool = (s_curr.get("session") is Dictionary) or (s_curr.get("event") is Dictionary)
			_center.visible = not has_overlay_curr and not _is_overlay_deferred
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
	p.add_theme_stylebox_override("panel", UI.box(Color("#14352d"), 14, UI.GOLD if is_self else player_col, 10))
	# Centre horizontally at the top: anchor both sides to 0.5 and grow both ways (no manual x offset)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.0
	p.anchor_bottom = 0.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_left = 0.0
	p.offset_right = 0.0
	p.offset_top = 14.0
	p.custom_minimum_size = Vector2(340, 0)
	card_layer.add_child(p)

	var h := UI.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UI.label("●", 18, player_col))
	var title_str: String = "第 %d 回合 ｜ %s 的回合" % [round_num, player_name]
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
	dim.color = Color(QuestUI.INK, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 100
	add_child(dim)
	_announcement_modal = dim
	AudioManager.play("event_major")

	# Same frame as the mission pages: deep-green card, gold edge, real buttons
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", QuestUI.card_box(0.98, Color(QuestUI.GOLD, 0.6), 16, 16 if UI.is_phone_portrait() else 24))
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 12 if UI.is_phone_portrait() else (24 if portrait else 140)
	p.offset_right = -12 if UI.is_phone_portrait() else (-24 if portrait else -140)
	p.offset_top = 20 if UI.is_phone_portrait() else (36 if portrait else 60)
	p.offset_bottom = -20 if UI.is_phone_portrait() else (-36 if portrait else -60)
	dim.add_child(p)
	UI.pop_in(p, 0.22)

	var v := UI.vbox(12)
	p.add_child(v)

	var head := QuestUI.hbox(10)
	head.add_child(QuestUI.icon("alert", 28.0, QuestUI.GOLD))
	head.add_child(QuestUI.title("全域市場重大事件", 18 if UI.is_phone_portrait() else 22, QuestUI.GOLD))
	v.add_child(head)
	var at := QuestUI.title(str(ann.get("title", "市場公告")), 22 if UI.is_phone_portrait() else 28, QuestUI.TEXT)
	at.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(at)

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

	var close_btn: Button = QuestUI.button("知道了", func():
		if _announcement_modal != null:
			UI.pop_out(p, func():
				if _announcement_modal != null:
					_announcement_modal.queue_free()
					_announcement_modal = null
			, 0.18)
	, "primary", "check")
	close_btn.name = "AnnouncementOk"
	v.add_child(close_btn)

## Volume sliders over the game (same panel as the menu settings); play continues underneath
func _open_audio_settings() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 120
	add_child(dim)
	var p := UI.panel(UI.PANEL, 16, 20)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(320 if UI.is_phone() else 400, 0)
	dim.add_child(p)
	UI.pop_in(p, 0.2)
	var v := UI.vbox(14)
	p.add_child(v)
	var head := UI.hbox(8)
	head.add_child(UI.label("聲音", 18 if UI.is_phone() else 20, UI.GOLD))
	head.add_child(UI.spacer())
	var close_btn := UI.button("×", func(): UI.pop_out(p, dim.queue_free, 0.16), 16, UI.PANEL_2)
	close_btn.custom_minimum_size = Vector2(36, 36)
	head.add_child(close_btn)
	v.add_child(head)
	v.add_child(AudioSettings.new())
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and not p.get_global_rect().has_point(e.global_position):
			UI.pop_out(p, dim.queue_free, 0.16)
	)


## 離開培訓: 繼續培訓 / 儲存並返回主畫面 / 放棄本次培訓
func _confirm_leave() -> void:
	if find_child("LeaveDialog", false, false):
		return
	add_child(LeaveDialog.new(main))
