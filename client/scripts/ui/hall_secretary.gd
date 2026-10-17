@tool
extends Control
## Training hall guide in the bottom-right corner. Shows only the secretary chosen on the previous
## screen (selected_secretary "female" → Aly, "male" → Kevin) using the cover's own transparent
## portraits, cropped waist-up; voice comes from SecretaryVoice, so Aly is always a female voice and
## Kevin a male one. "none" (自行挑戰): no portrait, no automatic speech, only a small 「開啟引導」 pill.
## Closing shrinks the dialog into a round portrait (or the pill) that reopens it.

signal portrait_pressed

const LineIcon := preload("res://scripts/ui/line_icon.gd")
const HallButton := preload("res://scripts/ui/hall_button.gd")
## When true the round portrait asks the training secretary (強制聚焦導覽) instead of this dialog
var use_tutorial := false
const SecretaryVoice := preload("res://scripts/secretary_voice.gd")
const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
## Waist-up crops of the cover portraits (same framing for both)
const FEMALE_CROP := Rect2(88, 0, 760, 1000)
const MALE_CROP := Rect2(128, 0, 760, 1000)
const FEMALE_FACE := Rect2(340, 90, 340, 340)
const MALE_FACE := Rect2(320, 60, 340, 340)
const LINES := [
	"這裡是新人顧問培訓大廳，你可以選擇單人實戰或多人演練。",
	"第一次培訓建議從單人實戰開始，我會在關鍵時刻提醒你。",
]
const GOLD := Color("#C6A15B")
const CREAM := Color("#F3F0E7")
const MUTED := Color("#AABCB5")

## "female", "male" or "none"
var selected_secretary := "none"
## "aly", "kevin" or "none"
var secretary_id := "none"
var is_open := false

var _index := 0
var _box: Panel
var _portrait: TextureRect
var _heading: Label
var _progress: Label
var _text: Label
var _speaker: Button
var _replay: Button
var _next: Button
var _close: Button
var _avatar: Button
var _pill: Button
var _breath: Tween
var _k := 1.0
var _phone := false
var _view := Vector2(1280, 720)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## sel: "female" / "male" / "none". Auto-opens with speech only for a chosen secretary.
func setup(sel: String, auto_open: bool) -> void:
	selected_secretary = sel if sel in ["female", "male"] else "none"
	secretary_id = {"female": "aly", "male": "kevin"}.get(selected_secretary, "none")
	var has := selected_secretary != "none"
	_portrait.visible = false
	if has:
		_portrait.texture = _crop(FEMALE if selected_secretary == "female" else MALE, FEMALE_CROP if selected_secretary == "female" else MALE_CROP)
		(_avatar.get_node("Face") as TextureRect).texture = _crop(FEMALE if selected_secretary == "female" else MALE, FEMALE_FACE if selected_secretary == "female" else MALE_FACE)
	_speaker.visible = has
	if has and auto_open:
		open_dialog(true)
	else:
		_show_collapsed(false)


func open_dialog(speak := true) -> void:
	is_open = true
	_index = 0
	_avatar.visible = false
	_pill.visible = false
	_box.visible = true
	_portrait.visible = selected_secretary != "none"
	_update_line(speak and selected_secretary != "none")
	_layout()
	if UI.is_animation_disabled():
		_box.modulate.a = 1.0
		_portrait.modulate.a = 1.0
		return
	# Enter: slide in from the bottom-right while fading in
	var off := Vector2(36, 28) * _k
	var box_to := _box.position
	var por_to := _portrait.position
	_box.position += off
	_portrait.position += off
	_box.modulate.a = 0.0
	_portrait.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_box, "position", box_to, 0.4)
	tw.tween_property(_box, "modulate:a", 1.0, 0.4)
	tw.tween_property(_portrait, "position", por_to, 0.4)
	tw.tween_property(_portrait, "modulate:a", 1.0, 0.4)
	_start_breathing()


func close_dialog() -> void:
	if not is_open:
		return
	is_open = false
	if not Engine.is_editor_hint():
		SecretaryVoice.stop()
	if UI.is_animation_disabled():
		_box.visible = false
		_portrait.visible = false
		_show_collapsed(false)
		return
	# Shrink toward the corner where the round portrait / pill appears
	_box.pivot_offset = _box.size
	_portrait.pivot_offset = Vector2(_portrait.size.x, _portrait.size.y)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_box, "scale", Vector2.ONE * 0.2, 0.24)
	tw.tween_property(_box, "modulate:a", 0.0, 0.24)
	tw.tween_property(_portrait, "scale", Vector2.ONE * 0.2, 0.24)
	tw.tween_property(_portrait, "modulate:a", 0.0, 0.24)
	tw.chain().tween_callback(func():
		_box.visible = false
		_portrait.visible = false
		_box.scale = Vector2.ONE
		_portrait.scale = Vector2.ONE
		_show_collapsed(true)
	)


## Rect occupied on screen (for keeping other UI clear of it)
func occupied_rect() -> Rect2:
	if is_open:
		var r := _box.get_rect()
		if _portrait.visible:
			r = r.merge(_portrait.get_rect())
		return r
	return (_avatar if _avatar.visible else _pill).get_rect()


func layout(view: Vector2, k: float, phone: bool) -> void:
	_view = view
	_k = k
	_phone = phone
	_layout()


# --- Build -------------------------------------------------------------------------------------

func _build() -> void:
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.visible = false

	_box = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0D4038", 0.96)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.anti_aliasing = true
	_box.add_theme_stylebox_override("panel", sb)
	_box.visible = false
	add_child(_box)
	add_child(_portrait)

	_heading = _label("", 15, GOLD)
	_box.add_child(_heading)
	_progress = _label("", 13, MUTED)
	_box.add_child(_progress)
	_text = _label("", 16, CREAM)
	_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_box.add_child(_text)

	_speaker = _icon_button("speaker", "重新播放語音")
	_speaker.pressed.connect(_speak)
	_box.add_child(_speaker)
	_replay = _icon_button("replay", "重播")
	_replay.pressed.connect(_speak)
	_box.add_child(_replay)
	_next = HallButton.new("下一句", true, 14)
	(_next as Object).activated.connect(_advance)
	_box.add_child(_next)
	_close = HallButton.new("關閉引導", false, 14, false)
	(_close as Object).activated.connect(close_dialog)
	_box.add_child(_close)

	# Collapsed: round portrait for Aly / Kevin
	_avatar = Button.new()
	_avatar.focus_mode = Control.FOCUS_NONE
	_avatar.tooltip_text = "開啟培訓秘書"
	_avatar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color("#0D4038")
	ring.set_corner_radius_all(64)
	ring.set_border_width_all(2)
	ring.border_color = GOLD
	ring.anti_aliasing = true
	for st: String in ["normal", "hover", "pressed", "focus"]:
		_avatar.add_theme_stylebox_override(st, ring)
	var face := TextureRect.new()
	face.name = "Face"
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.material = UI.get_circle_material()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.add_child(face)
	_avatar.pressed.connect(func():
		if use_tutorial:
			portrait_pressed.emit()
		else:
			open_dialog(true)
	)
	_avatar.visible = false
	add_child(_avatar)

	# Collapsed: small pill for 自行挑戰
	_pill = HallButton.new("開啟引導", false, 14, false)
	(_pill as Object).activated.connect(func(): open_dialog(false))
	_pill.visible = false
	add_child(_pill)


func _label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _icon_button(kind: String, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.0)
	n.set_corner_radius_all(40)
	n.set_border_width_all(1)
	n.border_color = Color(CREAM, 0.35)
	n.anti_aliasing = true
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.08)
	h.border_color = Color(CREAM, 0.6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ic: Control = LineIcon.new(kind, CREAM, 1.8)
	ic.name = "Icon"
	b.add_child(ic)
	b.resized.connect(func():
		var s := b.size.y * 0.56
		ic.size = Vector2(s, s)
		ic.position = (b.size - ic.size) * 0.5
	)
	return b


static func _crop(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = region
	return a


# --- Lines & voice -----------------------------------------------------------------------------

func _update_line(speak: bool) -> void:
	var name_text := "培訓引導"
	if selected_secretary == "female":
		name_text = "女性培訓秘書 · " + str(SecretaryVoice.profile("aly").name)
	elif selected_secretary == "male":
		name_text = "男性培訓秘書 · " + str(SecretaryVoice.profile("kevin").name)
	if selected_secretary != "none" and SecretaryVoice.pick(secretary_id) == "":
		name_text += " · 字幕"
	_heading.text = name_text
	_progress.text = "%d / %d" % [_index + 1, LINES.size()]
	_text.text = str(LINES[_index])
	(_next as Object).set_label("開始選擇" if _index == LINES.size() - 1 else "下一句")
	_replay.visible = selected_secretary != "none"
	_layout()
	if not UI.is_animation_disabled() and _text.modulate.a >= 0.99 and is_open:
		_text.modulate.a = 0.0
		create_tween().tween_property(_text, "modulate:a", 1.0, 0.12)
	if speak:
		_speak()


func _speak() -> void:
	if selected_secretary == "none" or not is_open or Engine.is_editor_hint():
		return
	# Subtitles and speech are the same sentence
	SecretaryVoice.speak(secretary_id, str(LINES[_index]))


func _advance() -> void:
	if _index >= LINES.size() - 1:
		close_dialog()
		return
	_index += 1
	_update_line(selected_secretary != "none")


func _start_breathing() -> void:
	if _breath:
		_breath.kill()
	if not _portrait.visible or UI.is_animation_disabled():
		return
	# Very slight breathing: scale from the waist, no floating
	_portrait.pivot_offset = Vector2(_portrait.size.x * 0.5, _portrait.size.y)
	_breath = create_tween().set_loops()
	_breath.tween_property(_portrait, "scale", Vector2(1.0, 1.008), 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath.tween_property(_portrait, "scale", Vector2.ONE, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _show_collapsed(animate: bool) -> void:
	is_open = false
	if _breath:
		_breath.kill()
	var has := selected_secretary != "none"
	_avatar.visible = has
	_pill.visible = not has
	_layout()
	if animate and not UI.is_animation_disabled():
		UI.pop_in(_avatar if has else _pill, 0.2)


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _box == null:
		return
	var k := _k
	var margin_r := (12.0 if _phone else 24.0) * k
	var margin_b := (12.0 if _phone else 18.0) * k
	var w := minf(414.0 * k, _view.x - margin_r * 2)
	var h := 150.0 * k
	var has := selected_secretary != "none"
	var pw := w * 0.35 if has else 0.0
	_box.size = Vector2(w, h)
	_box.position = Vector2(_view.x - margin_r - w, _view.y - margin_b - h)
	if has:
		var ph := pw / (FEMALE_CROP.size.x / FEMALE_CROP.size.y)
		_portrait.size = Vector2(pw, ph)
		_portrait.position = Vector2(_box.position.x + 6 * k, _box.position.y + h - ph - 1)
		_portrait.pivot_offset = Vector2(pw * 0.5, ph)
	var pad := 14.0 * k
	var tx := pw + pad
	var tw := w - tx - pad
	_heading.add_theme_font_size_override("font_size", roundi(15 * k))
	_progress.add_theme_font_size_override("font_size", roundi(13 * k))
	_text.add_theme_font_size_override("font_size", roundi(16 * k))
	_heading.reset_size()
	_heading.position = Vector2(tx, pad - 2 * k)
	_progress.reset_size()
	var sp := 30.0 * k
	_speaker.size = Vector2(sp, sp)
	_speaker.position = Vector2(w - pad - sp, pad - 6 * k)
	_progress.position = Vector2((_speaker.position.x - 10 * k if has else w - pad) - _progress.size.x, pad)
	_text.size = Vector2(tw, 0)
	_text.custom_minimum_size = Vector2(tw, 0)
	_text.position = Vector2(tx, _heading.position.y + _heading.size.y + 6 * k)
	var bh := 32.0 * k
	var by := h - pad - bh
	var x := tx
	if _replay.visible:
		_replay.size = Vector2(bh, bh)
		_replay.position = Vector2(x, by)
		x += bh + 8 * k
	(_next as Object).set_font_size(roundi(14 * k))
	(_close as Object).set_font_size(roundi(14 * k))
	var nw := 104.0 * k
	_next.size = Vector2(nw, bh)
	_next.position = Vector2(x, by)
	x += nw + 8 * k
	_close.size = Vector2(maxf(84.0 * k, w - pad - x), bh)
	_close.position = Vector2(x, by)
	if _close.position.x + _close.size.x > w - pad:
		_close.size.x = w - pad - _close.position.x
	var a := 64.0 * k
	_avatar.size = Vector2(a, a)
	_avatar.position = Vector2(_view.x - margin_r - a, _view.y - margin_b - a)
	var face: TextureRect = _avatar.get_node("Face")
	face.position = Vector2(3, 3)
	face.size = Vector2(a - 6, a - 6)
	(_pill as Object).set_font_size(roundi(14 * k))
	_pill.size = Vector2(108 * k, 38 * k)
	_pill.position = Vector2(_view.x - margin_r - _pill.size.x, _view.y - margin_b - _pill.size.y)


func _exit_tree() -> void:
	# Leaving the hall stops this line so it never overlaps the next screen
	if not Engine.is_editor_hint():
		SecretaryVoice.stop()
