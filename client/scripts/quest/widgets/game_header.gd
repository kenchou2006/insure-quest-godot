extends PanelContainer
## GameHeader: the cover's own transparent logo (never re-typed or stretched), 第 N / M 站, the
## client clock, and on the right the always-there controls: 音效開關 and 設定 (pause, return to
## the main screen). Pages may add their own items to `extra`.

const MissionProgress := preload("res://scripts/quest/widgets/mission_progress.gd")
const TimerBadge := preload("res://scripts/quest/widgets/timer_badge.gd")

signal settings_requested

var progress: Control
var timer: Control
var extra: HBoxContainer
var sound_btn: Button
var settings_btn: Button
var player_chip: Control
var _level_label: Label
var _xp_bar: ProgressBar
var _left_controls: Array = []
var compact := false


func _init(is_compact := false) -> void:
	compact = is_compact
	name = "GameHeader"
	# The bar itself lets the map through; only its buttons take clicks
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(QuestUI.BG, 0.88)
	s.set_corner_radius_all(14)
	s.set_border_width_all(1)
	s.border_color = Color(QuestUI.GOLD, 0.35)
	s.content_margin_left = 14 if not compact else 8
	s.content_margin_right = 10 if not compact else 6
	s.content_margin_top = 6 if not compact else 3
	s.content_margin_bottom = 6 if not compact else 3
	add_theme_stylebox_override("panel", s)
	var h := QuestUI.hbox(14 if not compact else 8)
	add_child(h)
	var logo := QuestUI.logo(52.0 if not compact else 32.0)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(logo)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.16)
	sep.custom_minimum_size = Vector2(1, 30 if not compact else 20)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sep)
	progress = MissionProgress.new(compact)
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(progress)
	timer = TimerBadge.new(compact)
	timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(timer)
	_left_controls = [logo, sep, progress, timer]
	h.add_child(QuestUI.spacer())
	extra = QuestUI.hbox(8)
	h.add_child(extra)
	# The player's advisor (新人顧問報到): portrait, name and real level
	player_chip = _player_chip()
	h.add_child(player_chip)
	sound_btn = _icon_button("speaker", "音效開關")
	sound_btn.pressed.connect(_toggle_sound)
	h.add_child(sound_btn)
	settings_btn = _icon_button("gear", "設定・暫停・返回主畫面")
	settings_btn.name = "SettingsButton"
	settings_btn.pressed.connect(func(): settings_requested.emit())
	h.add_child(settings_btn)


## Free middle gap between the left group (logo, progress, timer) and right group (extra, player, sound, settings)
func middle_gap() -> Rect2:
	if not is_inside_tree() or not is_visible_in_tree():
		return Rect2()
	var left_end := get_global_rect().position.x
	for c in _left_controls:
		if c is Control and (c as Control).is_inside_tree() and (c as Control).is_visible_in_tree() and (c as Control).size.x > 0.0:
			left_end = maxf(left_end, (c as Control).get_global_rect().end.x)
	var right_start := get_global_rect().end.x
	for c in [extra, player_chip, sound_btn, settings_btn]:
		if c is Control and (c as Control).is_inside_tree() and (c as Control).is_visible_in_tree():
			if c == extra and (extra.get_child_count() == 0 or extra.size.x <= 0.0):
				continue
			if (c as Control).size.x > 0.0:
				right_start = minf(right_start, (c as Control).get_global_rect().position.x)
	var gap_w := maxf(0.0, right_start - left_end)
	var hr := get_global_rect()
	return Rect2(left_end, hr.position.y, gap_w, hr.size.y)


func _ready() -> void:
	MusicManager.volumes_changed.connect(_sync_sound)
	_sync_sound()
	refresh()


func _player_chip() -> Control:
	var c := QuestUI.hbox(8)
	c.name = "PlayerChip"
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not PlayerProfile.player_profile_created:
		c.visible = false
		return c
	var sz := 34.0 if not compact else 28.0
	var av := UI.RoundTex.new(PlayerProfile.portrait(), Vector2(sz, sz), -1.0, PlayerProfile.token_color(), 2.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(av)
	if not compact:
		var v := QuestUI.vbox(2)
		v.add_child(QuestUI.label(PlayerProfile.player_name, 14, QuestUI.TEXT, false, true))
		_level_label = QuestUI.label(PlayerProfile.level_text(), 11, QuestUI.GOLD)
		_level_label.name = "LevelText"
		v.add_child(_level_label)
		# 經驗值：距離下一級的進度
		_xp_bar = ProgressBar.new()
		_xp_bar.name = "XpBar"
		_xp_bar.min_value = 0
		_xp_bar.max_value = PlayerProfile.XP_PER_LEVEL
		_xp_bar.show_percentage = false
		_xp_bar.custom_minimum_size = Vector2(90, 4)
		_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var back := StyleBoxFlat.new()
		back.bg_color = Color(1, 1, 1, 0.12)
		back.set_corner_radius_all(2)
		var fill := StyleBoxFlat.new()
		fill.bg_color = QuestUI.GOLD
		fill.set_corner_radius_all(2)
		_xp_bar.add_theme_stylebox_override("background", back)
		_xp_bar.add_theme_stylebox_override("fill", fill)
		v.add_child(_xp_bar)
		c.add_child(v)
	_sync_level()
	if not PlayerProfile.changed.is_connected(_sync_level):
		PlayerProfile.changed.connect(_sync_level)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


## 等級與經驗值（經驗值變動時即時更新）
func _sync_level() -> void:
	if not is_instance_valid(player_chip):
		return
	var xp := PlayerProfile.advisor_xp
	player_chip.tooltip_text = "顧問：%s｜%s｜經驗 %d（距離下一級 %d）" % [PlayerProfile.player_name, PlayerProfile.level_text(), xp, PlayerProfile.XP_PER_LEVEL - xp % PlayerProfile.XP_PER_LEVEL]
	if _level_label != null and is_instance_valid(_level_label):
		_level_label.text = PlayerProfile.level_text()
	if _xp_bar != null and is_instance_valid(_xp_bar):
		_xp_bar.value = xp % PlayerProfile.XP_PER_LEVEL


func _exit_tree() -> void:
	if PlayerProfile.changed.is_connected(_sync_level):
		PlayerProfile.changed.disconnect(_sync_level)


func _icon_button(kind: String, tip: String) -> Button:
	var b: Button = QuestUI.button("", Callable(), "quiet", kind)
	b.tooltip_text = tip
	var sz := 40.0 if not compact else 32.0
	b.custom_minimum_size = Vector2(sz, sz)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		if sb:
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			b.add_theme_stylebox_override(st, sb)
	b.resized.connect(func():
		for c in b.get_children():
			if c is Control:
				(c as Control).position = (b.size - (c as Control).custom_minimum_size) * 0.5
	)
	return b


func _toggle_sound() -> void:
	MusicManager.set_muted(not MusicManager.muted)


func _sync_sound() -> void:
	if sound_btn == null:
		return
	for c in sound_btn.get_children():
		if c.has_method("set_color"):
			c.set("kind", "speaker_off" if MusicManager.muted else "speaker")
			c.queue_redraw()
	sound_btn.tooltip_text = "音效：已靜音（按下開啟）" if MusicManager.muted else "音效：開啟（按下靜音）"


func refresh() -> void:
	if progress:
		progress.call("refresh")
