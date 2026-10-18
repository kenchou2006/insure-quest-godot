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
	h.add_child(QuestUI.spacer())
	extra = QuestUI.hbox(8)
	h.add_child(extra)
	sound_btn = _icon_button("speaker", "音效開關")
	sound_btn.pressed.connect(_toggle_sound)
	h.add_child(sound_btn)
	settings_btn = _icon_button("gear", "設定・暫停・返回主畫面")
	settings_btn.name = "SettingsButton"
	settings_btn.pressed.connect(func(): settings_requested.emit())
	h.add_child(settings_btn)


func _ready() -> void:
	MusicManager.volumes_changed.connect(_sync_sound)
	_sync_sound()
	refresh()


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
