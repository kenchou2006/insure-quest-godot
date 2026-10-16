class_name AudioSettings
extends VBoxContainer
## Volume panel used by the menu settings and the in-game 「聲音」 popup:
## master / music / secretary voice / SFX sliders plus mute. Changes apply at once and are saved.

const ROWS := [["Master", "總音量"], ["BGM", "背景音樂"], ["Voice", "秘書語音"], ["SFX", "操作音效"]]

var _sliders := {}
var _mute: CheckBox


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	for row: Array in ROWS:
		add_child(_slider_row(str(row[0]), str(row[1])))
	_mute = CheckBox.new()
	_mute.text = "靜音"
	_mute.button_pressed = MusicManager.muted
	_mute.toggled.connect(func(on: bool):
		MusicManager.set_muted(on)
		_refresh()
	)
	add_child(_mute)
	_refresh()


func _slider_row(bus: String, title: String) -> Control:
	var h := UI.hbox(12)
	var name_lbl := UI.label(title, 14, UI.TEXT)
	name_lbl.custom_minimum_size = Vector2(64, 0)
	h.add_child(name_lbl)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 28)
	_style(s)
	s.set_value_no_signal(MusicManager.get_slider(bus))
	h.add_child(s)
	var val := UI.label("", 13, UI.MUTED)
	val.custom_minimum_size = Vector2(44, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	_sliders[bus] = [s, val]
	s.value_changed.connect(func(v: float):
		MusicManager.set_slider(bus, v)
		_refresh()
	)
	# Short click so the player hears the new effect level
	if bus in ["Master", "SFX"]:
		s.drag_ended.connect(func(_changed: bool): Sound.play("click", self))
	return h


func _refresh() -> void:
	for bus: String in _sliders:
		var s: HSlider = _sliders[bus][0]
		var val: Label = _sliders[bus][1]
		val.text = "關" if s.value <= 0 else "%d%%" % roundi(s.value)
		s.modulate.a = 0.45 if MusicManager.muted else 1.0


func _style(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#062F2A")
	track.border_color = Color("#C6A15B", 0.35)
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#00A86B")
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	var fill_hl := fill.duplicate() as StyleBoxFlat
	fill_hl.bg_color = Color("#2ED59E")
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hl)
	var knob := _knob(Color("#C6A15B"))
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", _knob(Color("#E2C489")))
	s.add_theme_icon_override("grabber_disabled", knob)


## Champagne-gold round grabber
static func _knob(col: Color) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.78, 0.9])
	g.colors = PackedColorArray([col, col, Color(col, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 18
	t.height = 18
	return t
