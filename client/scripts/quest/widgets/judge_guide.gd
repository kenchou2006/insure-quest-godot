@tool
extends PanelContainer
## JudgeGuide（評審導覽進度條）：右上角小型半透明面板。
## 評審體驗模式 (?judge=1) 的核心亮點引導：
##   ① 場景找線索 ② 需求提問 ③ 合規紅燈與法條 ④ 保障配置 ⑤ 十年時間軸 ⑥ 十年後的信
## 支援目前步驟高亮、已完成打勾、可收合；字級與配色沿用 UI 常數。
## 依 QuestFlow 狀態與頁面切換自動推進。

const STEPS: Array[String] = [
	"場景找線索",
	"需求提問",
	"合規紅燈與法條",
	"保障配置",
	"十年時間軸",
	"十年後的信",
]

const STEP_ICONS: Array[String] = [
	"①",
	"②",
	"③",
	"④",
	"⑤",
	"⑥",
]

const STEP_CLUES := 0
const STEP_DIALOGUE := 1
const STEP_COMPLIANCE := 2
const STEP_PROPOSAL := 3
const STEP_TIMELINE := 4
const STEP_LETTER := 5

var quest_layer: Control = null
var current_step: int = 0
var completed_steps: Array[bool] = [false, false, false, false, false, false]
var collapsed: bool = false

var _root_vbox: VBoxContainer
var _header_box: HBoxContainer
var _title_label: Label
var _count_label: Label
var _collapse_btn: Button
var _items_box: VBoxContainer
var _hint_label: Label
var _hint_text: String = ""
var _step_rows: Array[Control] = []
var _step_labels: Array[Label] = []
var _step_marks: Array[Label] = []
var _last_page_id: String = ""


func _init() -> void:
	name = "JudgeGuide"
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	custom_minimum_size = Vector2(190, 0)
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -210.0
	offset_top = 12.0
	offset_right = -14.0
	offset_bottom = 0.0

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.PANEL.r, UI.PANEL.g, UI.PANEL.b, 0.88)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.45)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", sb)

	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", 6)
	add_child(_root_vbox)

	_header_box = HBoxContainer.new()
	_header_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_header_box.add_theme_constant_override("separation", 6)
	_header_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_vbox.add_child(_header_box)

	_title_label = Label.new()
	_title_label.name = "JudgeGuideTitle"
	_title_label.text = "評審導覽"
	_title_label.add_theme_font_size_override("font_size", UI.fs(13))
	_title_label.add_theme_color_override("font_color", UI.GOLD)
	_header_box.add_child(_title_label)

	_count_label = Label.new()
	_count_label.name = "JudgeGuideCount"
	_count_label.text = "(0/6)"
	_count_label.add_theme_font_size_override("font_size", UI.fs(11))
	_count_label.add_theme_color_override("font_color", UI.MUTED)
	_header_box.add_child(_count_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_box.add_child(spacer)

	_collapse_btn = Button.new()
	_collapse_btn.name = "JudgeGuideCollapseButton"
	_collapse_btn.text = "▲"
	_collapse_btn.flat = true
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.add_theme_font_size_override("font_size", UI.fs(11))
	_collapse_btn.add_theme_color_override("font_color", UI.MUTED)
	_collapse_btn.add_theme_color_override("font_hover_color", UI.TEXT)
	_collapse_btn.pressed.connect(toggle_collapse)
	_header_box.add_child(_collapse_btn)

	_header_box.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			toggle_collapse()
	)

	_items_box = VBoxContainer.new()
	_items_box.name = "JudgeGuideItems"
	_items_box.add_theme_constant_override("separation", 4)
	_root_vbox.add_child(_items_box)

	for i in range(STEPS.size()):
		var row := PanelContainer.new()
		row.name = "StepRow_%d" % i
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 6)
		row.add_child(rh)

		var mark := Label.new()
		mark.name = "StepMark_%d" % i
		mark.text = STEP_ICONS[i]
		mark.custom_minimum_size = Vector2(16, 0)
		mark.add_theme_font_size_override("font_size", UI.fs(12))
		rh.add_child(mark)

		var lbl := Label.new()
		lbl.name = "StepLabel_%d" % i
		lbl.text = STEPS[i]
		lbl.add_theme_font_size_override("font_size", UI.fs(12))
		rh.add_child(lbl)

		_step_rows.append(row)
		_step_marks.append(mark)
		_step_labels.append(lbl)
		_items_box.add_child(row)

	_hint_label = Label.new()
	_hint_label.name = "JudgeGuideHint"
	_hint_label.text = ""
	_hint_label.visible = false
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(170, 0)
	_hint_label.add_theme_font_size_override("font_size", UI.fs(11))
	_hint_label.add_theme_color_override("font_color", UI.GOLD)
	_root_vbox.add_child(_hint_label)

	refresh_ui()


func _ready() -> void:
	refresh_ui()


func is_collapsed() -> bool:
	return collapsed


func set_collapsed(c: bool) -> void:
	if collapsed == c:
		return
	collapsed = c
	refresh_ui()


func toggle_collapse() -> void:
	set_collapsed(not collapsed)


func get_current_step() -> int:
	return current_step


func is_step_completed(idx: int) -> bool:
	if idx >= 0 and idx < completed_steps.size():
		return completed_steps[idx]
	return false


func set_step_completed(idx: int, done: bool = true) -> void:
	if idx >= 0 and idx < completed_steps.size():
		completed_steps[idx] = done
		refresh_ui()


func set_current_step(idx: int) -> void:
	if idx < 0:
		idx = 0
	elif idx > STEPS.size():
		idx = STEPS.size()
	current_step = idx
	for k in range(mini(idx, STEPS.size())):
		completed_steps[k] = true
	if idx >= STEPS.size():
		set_hint("")
	refresh_ui()


func set_hint(text: String) -> void:
	_hint_text = text
	if _hint_label:
		_hint_label.text = text
	refresh_ui()


func get_hint() -> String:
	return _hint_text


func advance_step() -> void:
	if current_step < STEPS.size():
		completed_steps[current_step] = true
		if current_step + 1 < STEPS.size():
			current_step += 1
		else:
			current_step = STEPS.size()
			set_hint("")
	refresh_ui()


func advance_to(target: Variant) -> void:
	var idx := -1
	if typeof(target) == TYPE_INT:
		idx = int(target)
	elif typeof(target) == TYPE_STRING:
		var s := str(target).strip_edges().to_lower()
		for i in range(STEPS.size()):
			if STEPS[i].to_lower() == s or s.contains(STEPS[i].to_lower()) or STEPS[i].to_lower().contains(s):
				idx = i
				break
		if idx == -1:
			match s:
				"clues", "clue": idx = STEP_CLUES
				"dialogue", "talk": idx = STEP_DIALOGUE
				"compliance", "scan": idx = STEP_COMPLIANCE
				"proposal", "plan": idx = STEP_PROPOSAL
				"result": idx = STEP_TIMELINE
	if idx >= 0 and idx <= STEPS.size():
		if idx > current_step:
			set_current_step(idx)
		elif idx == current_step:
			refresh_ui()
		else:
			completed_steps[idx] = true
			refresh_ui()


func on_flow_state(_from: String, to: String) -> void:
	match to:
		"MISSION_RESULT":
			set_current_step(STEP_TIMELINE)
			set_hint("按『生成培訓報告』看十年時間軸與十年後的信")


func on_page_changed(page_id: String) -> void:
	if page_id == "" or page_id == _last_page_id:
		return
	_last_page_id = page_id
	match page_id:
		"clues":
			set_hint("")
			advance_to(STEP_CLUES)
		"dialogue":
			set_hint("")
			advance_to(STEP_DIALOGUE)
		"compliance":
			set_hint("")
			advance_to(STEP_COMPLIANCE)
		"proposal":
			set_hint("")
			advance_to(STEP_PROPOSAL)
		"result":
			set_current_step(STEP_TIMELINE)
			set_hint("按『生成培訓報告』看十年時間軸與十年後的信")


func refresh_ui() -> void:
	var completed_count := 0
	for c in completed_steps:
		if c:
			completed_count += 1
	if _count_label:
		_count_label.text = "(%d/%d)" % [completed_count, STEPS.size()]
		if completed_count == STEPS.size():
			_count_label.add_theme_color_override("font_color", UI.GOOD)
		else:
			_count_label.add_theme_color_override("font_color", UI.MUTED)

	if _collapse_btn:
		_collapse_btn.text = "▼" if collapsed else "▲"
	if _items_box:
		_items_box.visible = not collapsed
	if _hint_label:
		_hint_label.visible = not collapsed and (_hint_text != "")

	for i in range(STEPS.size()):
		if i >= _step_rows.size():
			continue
		var row := _step_rows[i]
		var mark := _step_marks[i]
		var lbl := _step_labels[i]

		var is_done: bool = completed_steps[i]
		var is_cur: bool = (i == current_step) and not is_done

		if is_done:
			mark.text = "✓"
			mark.add_theme_color_override("font_color", UI.GOOD)
			lbl.add_theme_color_override("font_color", Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.7))
			var row_sb := StyleBoxEmpty.new()
			row.add_theme_stylebox_override("panel", row_sb)
		elif is_cur:
			mark.text = "▶"
			mark.add_theme_color_override("font_color", UI.GOLD)
			lbl.add_theme_color_override("font_color", UI.GOLD)
			var cur_sb := StyleBoxFlat.new()
			cur_sb.bg_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.15)
			cur_sb.set_corner_radius_all(4)
			cur_sb.content_margin_left = 4
			cur_sb.content_margin_right = 4
			cur_sb.content_margin_top = 2
			cur_sb.content_margin_bottom = 2
			row.add_theme_stylebox_override("panel", cur_sb)
		else:
			mark.text = STEP_ICONS[i]
			mark.add_theme_color_override("font_color", UI.MUTED)
			lbl.add_theme_color_override("font_color", UI.MUTED)
			var row_sb := StyleBoxEmpty.new()
			row.add_theme_stylebox_override("panel", row_sb)
