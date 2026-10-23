extends PanelContainer
## 本局對練配置 under the 單人實戰 card: the player (fixed, cannot be removed) and three sparring
## advisors — 沈知妍 同理洞察型, 顧承宇 數據配置型, 程雅寧 合規策略型 — of which 1–3 play.
## Selected: check + full brightness; not selected: 55% brightness and 「＋ 加入第 N 位」. Adding or
## removing plays a short card animation. 確認配置 saves the line-up (PlayerProfile) and starts;
## 恢復初次建議 goes back to 沈知妍 + 顧承宇. Unconfirmed changes are kept while the player steps away.

signal confirmed

const MIN_ADVISORS := 1
const MAX_ADVISORS := 3
## Shortest the person cards get on a low screen
const MIN_CARD_H := 112.0

var selected: Array = []
var confirm_button: Button
var reset_button: Button
var _count: Label
var _hint: Label
var _cards: Dictionary = {}
var _player_card: Control
var _portrait := false
var _small := false


func _init(portrait_mode := false, small := false) -> void:
	name = "SparringSetup"
	_portrait = portrait_mode
	_small = small
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0D4038", 0.92)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.content_margin_left = 14 if small else 22
	sb.content_margin_right = 14 if small else 22
	sb.content_margin_top = 10 if small else 14
	sb.content_margin_bottom = 10 if small else 14
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	selected = (PlayerProfile.sparring_draft if not PlayerProfile.sparring_draft.is_empty() else PlayerProfile.selected_simulated_advisors).duplicate()
	var v := QuestUI.vbox(8 if _small else 12)
	add_child(v)
	var head := QuestUI.hbox(14)
	var bar := ColorRect.new()
	bar.color = QuestUI.GREEN
	bar.custom_minimum_size = Vector2(3, 24)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(bar)
	head.add_child(QuestUI.title("本局對練配置", 24 if not _small else 18))
	_count = QuestUI.label("", 17 if not _small else 14, QuestUI.TEXT)
	_count.name = "AdvisorCount"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	v.add_child(head)
	v.add_child(QuestUI.divider(0.12))
	var row: Container
	if _portrait:
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 10)
		g.add_theme_constant_override("v_separation", 10)
		row = g
	else:
		row = QuestUI.hbox(12 if _small else 18)
	v.add_child(row)
	_player_card = _make_player_card()
	row.add_child(_player_card)
	for s in PlayerProfile.SIM_ADVISORS:
		var c := AdvisorCard.new(s, _small or _portrait)
		c.pressed.connect(func(): _toggle(str(s.id)))
		row.add_child(c)
		_cards[str(s.id)] = c
	var foot: BoxContainer = QuestUI.vbox(8) if _portrait else QuestUI.hbox(14)
	v.add_child(foot)
	var info := QuestUI.hbox(8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(QuestUI.icon("info", 20.0, QuestUI.MUTED))
	_hint = QuestUI.label("單人實戰共 2～4 位顧問；你的會談計時只在你的回合進行。", 14 if not _small else 12, QuestUI.MUTED, true)
	_hint.name = "SparringHint"
	info.add_child(_hint)
	foot.add_child(info)
	confirm_button = QuestUI.button("確認配置，開始單人實戰", _on_confirm, "primary", "next")
	confirm_button.name = "ConfirmSparring"
	confirm_button.custom_minimum_size.x = 0 if _portrait else (300 if not _small else 230)
	foot.add_child(confirm_button)
	reset_button = QuestUI.button("恢復初次建議", _reset, "secondary", "refresh")
	reset_button.name = "ResetSparring"
	foot.add_child(reset_button)
	_sync(false)


## The panel's height with the shortest cards (the page makes room for at least this)
func min_height() -> float:
	return get_combined_minimum_size().y - (_player_card.custom_minimum_size.y - MIN_CARD_H)


## Shorter cards when the page has less room under the mode cards (never below MIN_CARD_H)
func fit_height(avail: float) -> void:
	var base := 138.0 if (_small or _portrait) else 168.0
	var rest := get_combined_minimum_size().y - _player_card.custom_minimum_size.y
	_set_card_h(clampf(avail - rest, MIN_CARD_H, base))


func _set_card_h(h: float) -> void:
	if is_equal_approx(_player_card.custom_minimum_size.y, h):
		return
	_player_card.custom_minimum_size.y = h
	for id in _cards:
		(_cards[id] as Control).custom_minimum_size.y = h


func _make_player_card() -> Control:
	var p := PanelContainer.new()
	p.name = "PlayerCard"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#062F2A", 0.7)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(QuestUI.GOLD, 0.85)
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, 138 if _small or _portrait else 168)
	p.tooltip_text = "玩家固定參加，不能移除"
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(holder)
	var pic := TextureRect.new()
	pic.texture = PlayerProfile.portrait()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.material = UI.get_rounded_material(0.06)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	var shade := Shade.new()
	holder.add_child(shade)
	var you := QuestUI.chip("你", QuestUI.GOLD, 0.9, 14)
	(you.get_child(0) as Label).add_theme_color_override("font_color", QuestUI.INK)
	holder.add_child(you)
	var nm := QuestUI.title(PlayerProfile.player_name if PlayerProfile.player_name != "" else "顧問", 20 if not _small else 16)
	nm.name = "PlayerName"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(nm)
	var lv := QuestUI.label(PlayerProfile.level_text(), 14 if not _small else 12, QuestUI.TEXT)
	lv.name = "PlayerLevel"
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(lv)
	holder.resized.connect(func():
		var s := holder.size
		pic.position = Vector2(2, 2)
		pic.size = s - Vector2(4, 4)
		shade.position = Vector2(2, s.y * 0.45)
		shade.size = Vector2(s.x - 4, s.y * 0.55 - 2)
		you.reset_size()
		you.position = Vector2(10, 10)
		lv.size = Vector2(s.x, lv.get_combined_minimum_size().y)
		lv.position = Vector2(0, s.y - lv.size.y - 8)
		nm.size = Vector2(s.x, nm.get_combined_minimum_size().y)
		nm.position = Vector2(0, lv.position.y - nm.size.y)
	)
	return p


func _toggle(id: String) -> void:
	if selected.has(id):
		if selected.size() <= MIN_ADVISORS:
			_warn("至少保留 1 位模擬顧問（單人實戰需 2～4 位顧問）")
			QuestUI.shake(_cards[id])
			return
		selected.erase(id)
	else:
		if selected.size() >= MAX_ADVISORS:
			_warn("模擬顧問最多 3 位")
			return
		# Keep the advisors in their listed order (the order bots join the room)
		var ordered: Array = []
		for s in PlayerProfile.SIM_ADVISORS:
			if selected.has(str(s.id)) or str(s.id) == id:
				ordered.append(str(s.id))
		selected = ordered
	AudioManager.play("card_flip")
	PlayerProfile.sparring_draft = selected.duplicate()
	_sync(true, id)


func _reset() -> void:
	selected = PlayerProfile.DEFAULT_SPARRING.duplicate()
	PlayerProfile.sparring_draft = selected.duplicate()
	_sync(true)


func _warn(text: String) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", QuestUI.GOLD)
	AudioManager.play("trust_down")
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_callback(func():
		_hint.text = "單人實戰共 2～4 位顧問；你的會談計時只在你的回合進行。"
		_hint.add_theme_color_override("font_color", QuestUI.MUTED)
	)


func _sync(animate: bool, changed_id := "") -> void:
	_count.text = "玩家 1 位 ＋ 模擬顧問 %d／%d" % [selected.size(), MAX_ADVISORS]
	var next_ordinal: String = ["一", "二", "三"][mini(selected.size(), 2)]
	for id in _cards:
		var c: AdvisorCard = _cards[id]
		c.set_selected(selected.has(id), "＋ 加入第%s位" % next_ordinal, animate and id == changed_id)
	confirm_button.call("set_reason", "" if selected.size() >= MIN_ADVISORS else "請至少選擇 1 位模擬顧問")


func _on_confirm() -> void:
	PlayerProfile.set_sparring(selected)
	AudioManager.play("confirm_soft")
	confirmed.emit()


## Gradient behind the name so it reads over any portrait
class Shade extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := 16
		for i in range(n):
			var a := float(i) / n
			draw_rect(Rect2(0, size.y * a, size.x, size.y / n + 1), Color("#062F2A", 0.85 * a))


## One sparring advisor: portrait, type icon, name and type. The whole card toggles the choice.
class AdvisorCard extends Button:
	var info: Dictionary
	var visual: Control
	var _frame: Panel
	var _check: Control
	var _add: PanelContainer
	var _add_label: Label
	var _sel := false
	var _tw: Tween

	func _init(s: Dictionary, small: bool) -> void:
		info = s
		name = "Advisor_" + str(s.id)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 138 if small else 168)
		tooltip_text = "%s｜%s\n%s" % [s.name, s.type, s.note]
		for st in ["normal", "hover", "pressed", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var fb := StyleBoxFlat.new()
		fb.draw_center = false
		fb.set_border_width_all(2)
		fb.border_color = Color("#C6A15B", 0.8)
		fb.set_corner_radius_all(14)
		add_theme_stylebox_override("focus", fb)
		visual = Control.new()
		visual.name = "Visual"
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(visual)
		var pic := TextureRect.new()
		pic.name = "Portrait"
		pic.texture = PlayerProfile.texture_for(str(s.path))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.material = UI.get_rounded_material(0.06)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.add_child(pic)
		var shade := Shade.new()
		shade.name = "Shade"
		visual.add_child(shade)
		var row := QuestUI.hbox(8)
		row.name = "Caption"
		row.add_child(QuestUI.icon(str(s.icon), 26.0 if not small else 20.0, Color("#C6A15B")))
		var tv := QuestUI.vbox(0)
		tv.add_child(QuestUI.title(str(s.name), 19 if not small else 15))
		tv.add_child(QuestUI.label(str(s.type), 14 if not small else 12, Color("#F3F0E7")))
		row.add_child(tv)
		visual.add_child(row)
		_frame = Panel.new()
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_frame)
		_check = CheckDot.new()
		add_child(_check)
		_add = PanelContainer.new()
		_add.name = "AddPill"
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color("#062F2A", 0.85)
		ps.set_corner_radius_all(999)
		ps.set_border_width_all(1)
		ps.border_color = Color("#F3F0E7", 0.75)
		ps.content_margin_left = 12
		ps.content_margin_right = 12
		ps.content_margin_top = 4
		ps.content_margin_bottom = 4
		_add.add_theme_stylebox_override("panel", ps)
		_add.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_add_label = QuestUI.label("＋ 加入", 14 if not small else 12, Color("#F3F0E7"))
		_add.add_child(_add_label)
		add_child(_add)
		resized.connect(_place)
		mouse_entered.connect(_hover.bind(true))
		mouse_exited.connect(_hover.bind(false))
		button_down.connect(_press.bind(true))
		button_up.connect(_press.bind(false))

	func _place() -> void:
		visual.size = size
		visual.pivot_offset = size * 0.5
		var pic: Control = visual.get_node("Portrait")
		pic.position = Vector2(2, 2)
		pic.size = size - Vector2(4, 4)
		var shade: Control = visual.get_node("Shade")
		shade.position = Vector2(2, size.y * 0.4)
		shade.size = Vector2(size.x - 4, size.y * 0.6 - 2)
		var cap: Control = visual.get_node("Caption")
		cap.reset_size()
		cap.position = Vector2(12, size.y - cap.size.y - 10)
		_frame.position = Vector2.ZERO
		_frame.size = size
		var cs := clampf(size.x * 0.13, 22.0, 34.0)
		_check.size = Vector2(cs, cs)
		_check.position = Vector2(size.x - cs - 10, 10)
		_add.reset_size()
		_add.position = Vector2(size.x - _add.size.x - 10, size.y * 0.42 - _add.size.y * 0.5)

	func set_selected(on: bool, add_text: String, animate: bool) -> void:
		_sel = on
		_check.visible = on
		_add.visible = not on
		_add_label.text = add_text
		_restyle(false)
		var dim := Color(1, 1, 1) if on else Color(0.55, 0.55, 0.55)
		if animate and not UI.is_animation_disabled():
			if _tw and _tw.is_valid():
				_tw.kill()
			_tw = create_tween().set_parallel(true)
			visual.scale = Vector2.ONE * 0.94
			_tw.tween_property(visual, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tw.tween_property(visual, "modulate", dim, 0.2)
		else:
			visual.modulate = dim
		_place.call_deferred()

	func is_selected() -> bool:
		return _sel

	func _restyle(hover: bool) -> void:
		var s := StyleBoxFlat.new()
		s.draw_center = false
		s.set_corner_radius_all(12)
		s.set_border_width_all(2 if _sel else 1)
		s.border_color = Color("#00A86B", 0.9) if _sel else (Color("#C6A15B", 0.8) if hover else Color(1, 1, 1, 0.2))
		_frame.add_theme_stylebox_override("panel", s)

	func _hover(on: bool) -> void:
		_restyle(on)
		if on:
			AudioManager.play("ui_hover")
		if UI.is_animation_disabled():
			return
		var tw := create_tween()
		tw.tween_property(visual, "position:y", -4.0 if on else 0.0, 0.16)

	func _press(down: bool) -> void:
		if UI.is_animation_disabled():
			return
		var tw := create_tween()
		tw.tween_property(visual, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.07 if down else 0.12)


class CheckDot extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color("#062F2A", 0.9))
		draw_arc(c, r - 1, 0, TAU, 28, Color("#00A86B"), 2.0, true)
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.42, 0), c + Vector2(-r * 0.1, r * 0.32), c + Vector2(r * 0.45, -r * 0.32)]), Color("#00A86B"), 2.5, true)
