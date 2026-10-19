extends CanvasLayer
## 培訓秘書聚焦導覽 (map page and every mission page). A CanvasLayer above the whole game UI, so
## while it is up nothing underneath gets hover, clicks or cursor changes, whatever the node order:
##   SecretaryGuide (this, layer 40)
##   ├─ DimOverlay (ColorRect, #021C19 at 55%; blocks every click, also over a highlight)
##   ├─ DimCutout (draws the dim with bright holes over the elements being explained)
##   ├─ SecretaryPortrait (TextureRect, chosen secretary, bottom-right)
##   ├─ DialoguePanel (PanelContainer: SecretaryName, PageIndicator, DialogueText, VoiceIndicator,
##   │                 ContinueButton)
##   ├─ SkipGuideButton (top-right)
##   └─ VoiceToggleButton
## One instance for the whole game; every button signal is connected once, here. Every way out
## (finished, 開始操作, 跳過本次引導, voice failure, errors, screen or page change) goes through
## end_secretary_focus(reason), which hides everything and sets the dim back to MOUSE_FILTER_IGNORE.

signal finished(page_id: String, reason: String)
signal voice_toggled(on: bool)

const UiLock := preload("res://scripts/ui_lock.gd")
const FONT := preload("res://assets/fonts/regular.tres")
const BOLD := preload("res://assets/fonts/bold.tres")
const GUIDE_LAYER := 40
const DIM_COLOR := Color("#021C19", 0.55)
const C_PANEL := Color("#0B3A33", 0.97)
const C_GOLD := Color("#C6A15B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GREEN := Color("#0E7A55")
## Typewriter speed (seconds per character)
const CHAR_SECONDS := 0.03

var guide_active := false
var input_locked := false
var secretary_is_speaking := false
var current_dialogue_index := 0
var secretary_gender := "female"
var voice_enabled := true
var page_id := ""
var dialogues: Array = []
## Speaks one line; returns false when it stays silent (no voice, voice off, failure). Set by the owner.
var speak_line: Callable
## Stops the current line's voice. Set by the owner.
var stop_voice: Callable
## Where the portrait grows from (the small 培訓秘書 entry), in viewport coordinates
var origin_rect := Rect2()
## Voice fallback: a line whose end is never reported is treated as finished after this many
## seconds per character (+1.5 s); tests shorten it
var voice_fallback_per_char := 0.32
## Elements kept bright while the secretary explains them (viewport rects)
var highlight_rects: Array = []
## Buttons the portrait and dialogue must not cover (擲骰, 提交, 返回, 下一步, 結算)
var avoid_rects: Array = []

var dim: ColorRect
var cutout: Control
var portrait: TextureRect
var panel: PanelContainer
var name_label: Label
var page_label: Label
var text: RichTextLabel
var voice_indicator: Label
var continue_button: Button
var skip_button: Button
var voice_button: Button

var _typing := false
var _voice_done := true
var _gen := 0
## 頁面導覽：持續取得要照亮／要避開的位置（按鈕在導覽開啟後移動時，照亮框跟著走）
var _highlight_provider: Callable
var _avoid_provider: Callable
var _track := 0.0
var _type_tween: Tween
var _anim: Tween
var _k := 1.0
var _panel_y := 0.0


func _ready() -> void:
	layer = GUIDE_LAYER
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)


func _build() -> void:
	dim = ColorRect.new()
	dim.name = "DimOverlay"
	dim.color = DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	add_child(dim)
	cutout = Control.new()
	cutout.name = "DimCutout"
	cutout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutout.visible = false
	cutout.draw.connect(_draw_cutout)
	add_child(cutout)

	portrait = TextureRect.new()
	portrait.name = "SecretaryPortrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.visible = false
	add_child(portrait)

	panel = PanelContainer.new()
	panel.name = "DialoguePanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_GOLD, 0.85)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 12
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(_on_panel_input)
	panel.visible = false
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	name_label = _label(14, C_GOLD, BOLD)
	name_label.name = "SecretaryName"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	page_label = _label(13, C_MUTED, FONT)
	page_label.name = "PageIndicator"
	head.add_child(page_label)
	text = RichTextLabel.new()
	text.name = "DialogueText"
	text.bbcode_enabled = false
	text.fit_content = false
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_color_override("default_color", C_TEXT)
	text.add_theme_font_override("normal_font", FONT)
	v.add_child(text)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	voice_indicator = _label(12, C_MUTED, FONT)
	voice_indicator.name = "VoiceIndicator"
	voice_indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_indicator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(voice_indicator)
	continue_button = _button("下一句", true)
	continue_button.name = "ContinueButton"
	continue_button.pressed.connect(advance_dialogue)
	continue_button.visible = false
	foot.add_child(continue_button)

	skip_button = _button("跳過本次引導", false)
	skip_button.name = "SkipGuideButton"
	skip_button.pressed.connect(skip_guide)
	skip_button.visible = false
	add_child(skip_button)
	voice_button = _button("語音：開", false)
	voice_button.name = "VoiceToggleButton"
	voice_button.pressed.connect(toggle_voice)
	voice_button.visible = false
	add_child(voice_button)


func _label(fs: int, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(t: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", BOLD if primary else FONT)
	for st: String in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(10)
		s.set_border_width_all(1)
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		s.anti_aliasing = true
		if primary:
			s.bg_color = C_GREEN.lightened(0.08) if st == "hover" else C_GREEN
			s.border_color = Color(C_GOLD, 1.0 if st == "hover" else 0.7)
		else:
			s.bg_color = Color("#062F2A", 0.92) if st != "hover" else Color("#0B3A33", 0.95)
			s.border_color = C_GOLD if st == "hover" else Color(C_TEXT, 0.55)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", C_TEXT)
	b.add_theme_color_override("font_pressed_color", C_TEXT)
	return b


# --- Flow --------------------------------------------------------------------------------------

## Opens the focus guide for a page. A second call while it is open does nothing (one dim only).
## opts: highlights (Array of Rect2 kept bright), avoid (Array of Rect2 the guide must not cover)
func begin_secretary_focus(pid: String, lines: Array, gender: String, portrait_tex: Texture2D, secretary_name: String, voice_on: bool, opts := {}) -> bool:
	if guide_active or lines.is_empty():
		return false
	highlight_rects = opts.get("highlights", [])
	avoid_rects = opts.get("avoid", [])
	_highlight_provider = opts.get("highlight_provider", Callable())
	_avoid_provider = opts.get("avoid_provider", Callable())
	_track = 0.0
	page_id = pid
	dialogues = lines.duplicate()
	secretary_gender = gender
	voice_enabled = voice_on
	portrait.texture = portrait_tex
	name_label.text = secretary_name
	guide_active = true
	input_locked = true
	secretary_is_speaking = true
	visible = true
	dim.visible = true
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# With highlights the cut-out draws the dim (holes stay bright); the ColorRect still takes every click
	dim.color = Color(DIM_COLOR, 0.0) if not highlight_rects.is_empty() else DIM_COLOR
	cutout.visible = not highlight_rects.is_empty()
	portrait.visible = portrait_tex != null
	panel.visible = true
	skip_button.visible = true
	voice_button.visible = true
	_sync_voice_button()
	# Nothing behind may keep keyboard focus while the guide is up
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()
	_layout()
	_enter_animation()
	UiLock.log_event("map_guide_begin:" + pid)
	show_dialogue(0)
	return true


func show_dialogue(index: int) -> void:
	if not guide_active:
		return
	if index < 0 or index >= dialogues.size():
		end_secretary_focus("dialogue_error")
		return
	_gen += 1
	var gen := _gen
	_stop_voice()
	current_dialogue_index = index
	var line := str(dialogues[index])
	text.text = line
	text.visible_ratio = 0.0
	page_label.text = "%d／%d" % [index + 1, dialogues.size()]
	continue_button.text = "開始操作" if index == dialogues.size() - 1 else "下一句"
	continue_button.visible = false
	_typing = true
	if _type_tween:
		_type_tween.kill()
	_type_tween = create_tween()
	# 文字顯示速度 from the settings (立即 shows the whole line)
	var per_char: float = GameState.char_seconds(CHAR_SECONDS) if not Engine.is_editor_hint() else CHAR_SECONDS
	_type_tween.tween_property(text, "visible_ratio", 1.0, maxf(line.length() * per_char, 0.05))
	_type_tween.tween_callback(func():
		if gen == _gen:
			complete_typewriter()
	)
	# Voice: never required — silent or failed lines just show the text
	_voice_done = true
	if voice_enabled and speak_line.is_valid():
		var ok: bool = speak_line.call(line)
		if ok:
			_voice_done = false
			voice_indicator.text = "● 語音播放中"
			# 字幕關閉: the spoken line is not repeated on screen (shown again when the voice ends or fails)
			if not GameState.subtitles:
				if _type_tween:
					_type_tween.kill()
				text.text = "（字幕已關閉，語音播放中）"
				text.visible_ratio = 1.0
				_typing = false
			get_tree().create_timer(line.length() * voice_fallback_per_char + 1.5).timeout.connect(func():
				if gen == _gen and guide_active and not _voice_done:
					on_voice_ended()
			)
		else:
			voice_indicator.text = "靜音（只顯示文字）"
	else:
		voice_indicator.text = "語音已關閉" if not voice_enabled else "靜音（只顯示文字）"


## First tap on the dialogue: the whole sentence at once (never skips the line)
func complete_typewriter() -> void:
	if _type_tween:
		_type_tween.kill()
		_type_tween = null
	text.visible_ratio = 1.0
	_typing = false
	_check_ready()


## The owner reports the end of the spoken line (or the fallback timer does)
func on_voice_ended() -> void:
	if not guide_active:
		return
	_voice_done = true
	if text.text.begins_with("（字幕已關閉"):
		text.text = str(dialogues[current_dialogue_index])
		text.visible_ratio = 1.0
	if voice_indicator.text == "● 語音播放中":
		voice_indicator.text = "語音完成"
	_check_ready()


func _check_ready() -> void:
	if guide_active and not _typing and _voice_done:
		continue_button.visible = true


## 下一句 / 開始操作 (and a tap on the dialogue once the line is complete)
func advance_dialogue() -> void:
	if not guide_active:
		return
	if _typing:
		complete_typewriter()
		return
	if not _voice_done:
		# The player chose to move on: the voice stops, the button appears
		_stop_voice()
		on_voice_ended()
		return
	if current_dialogue_index >= dialogues.size() - 1:
		end_secretary_focus("complete")
	else:
		show_dialogue(current_dialogue_index + 1)


func skip_guide() -> void:
	end_secretary_focus("skip")


func toggle_voice() -> void:
	voice_enabled = not voice_enabled
	_sync_voice_button()
	if not voice_enabled:
		_stop_voice()
		voice_indicator.text = "語音已關閉"
		_voice_done = true
		_check_ready()
	voice_toggled.emit(voice_enabled)


func _sync_voice_button() -> void:
	voice_button.text = "語音：開" if voice_enabled else "語音：關"


## The one cleanup for every way out. Safe to call any number of times.
func end_secretary_focus(reason: String) -> void:
	var was_active := guide_active
	_gen += 1
	_highlight_provider = Callable()
	_avoid_provider = Callable()
	_stop_voice()
	if _type_tween:
		_type_tween.kill()
		_type_tween = null
	if _anim:
		_anim.kill()
		_anim = null
	_typing = false
	_voice_done = true
	portrait.visible = false
	panel.visible = false
	continue_button.visible = false
	skip_button.visible = false
	voice_button.visible = false
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.modulate.a = 1.0
	dim.color = DIM_COLOR
	cutout.visible = false
	highlight_rects = []
	avoid_rects = []
	visible = false
	guide_active = false
	input_locked = false
	secretary_is_speaking = false
	if was_active:
		UiLock.log_event("map_guide_end:%s:%s" % [page_id, reason])
		finished.emit(page_id, reason)


func _stop_voice() -> void:
	if stop_voice.is_valid():
		stop_voice.call()


## Keys while the guide is up: Esc skips, Enter / Space advances; nothing reaches the game
func _input(event: InputEvent) -> void:
	if not guide_active or not (event is InputEventKey):
		return
	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("ui_cancel"):
			skip_guide()
		elif event.is_action_pressed("ui_accept"):
			advance_dialogue()
	get_viewport().set_input_as_handled()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance_dialogue()
		panel.accept_event()


## A guide that is not active never keeps its dim: released on the next frame whatever happened
func _process(delta: float) -> void:
	if not guide_active and (dim.visible or dim.mouse_filter != Control.MOUSE_FILTER_IGNORE or visible):
		end_secretary_focus("watchdog")
	if guide_active and _highlight_provider.is_valid():
		_track += delta
		if _track >= 0.1:
			_track = 0.0
			_follow_targets()


## 被解說的元件移動了（卡片進場、文字換行）：照亮框與對話框位置跟著更新
func _follow_targets() -> void:
	var hl: Variant = _highlight_provider.call()
	var av: Variant = _avoid_provider.call() if _avoid_provider.is_valid() else avoid_rects
	if not (hl is Array) or not (av is Array):
		return
	if hl == highlight_rects and av == avoid_rects:
		return
	highlight_rects = hl
	avoid_rects = av
	_layout()


# --- Layout & animation ------------------------------------------------------------------------

func _layout() -> void:
	if dim == null or not is_inside_tree():
		return
	_layout_for(get_viewport().get_visible_rect().size)


## Places everything for a screen of size vs (content units)
func _layout_for(vs: Vector2) -> void:
	# A resize during the entrance: finish it at once, then place everything again
	if _anim and _anim.is_running():
		_anim.kill()
		_anim = null
		dim.modulate.a = 1.0
		portrait.scale = Vector2.ONE
		portrait.modulate.a = 1.0
		panel.modulate.a = 1.0
	_k = clampf(minf(vs.x / 1280.0, vs.y / 720.0), 0.62, 1.6)
	var k := _k
	var margin := 16.0 * k
	dim.position = Vector2.ZERO
	dim.size = vs
	cutout.position = Vector2.ZERO
	cutout.size = vs
	cutout.queue_redraw()
	# Portrait: about 35% of the screen height, bottom-right, never cropped by the edges
	var ph := clampf(vs.y * 0.35, 130.0, 420.0)
	var pw := ph * 0.76
	portrait.size = Vector2(pw, ph)
	portrait.position = Vector2(vs.x - margin - pw, vs.y - ph)
	# Dialogue: left of the portrait (above it on narrow screens), 460–620 px, two lines of text
	var fs := roundi(19 * k)
	name_label.add_theme_font_size_override("font_size", roundi(14 * k))
	page_label.add_theme_font_size_override("font_size", roundi(13 * k))
	voice_indicator.add_theme_font_size_override("font_size", roundi(12 * k))
	text.add_theme_font_size_override("normal_font_size", fs)
	for b: Button in [continue_button, skip_button, voice_button]:
		b.add_theme_font_size_override("font_size", roundi(15 * k))
	text.custom_minimum_size = Vector2(0, ceilf(FONT.get_height(fs) * 2.0 + 4.0))
	var room := portrait.position.x - margin * 2
	var stacked := room < 300.0
	var dw := clampf(room, 0.0, 620.0) if not stacked else vs.x - margin * 2
	if not stacked:
		dw = clampf(minf(dw, maxf(vs.x * 0.42, 460.0)), minf(460.0, room), 620.0)
	# Two lines at most: the text gets smaller before any line would wrap a third time
	var inner := dw - 40.0
	var longest := 0
	for d in dialogues:
		longest = maxi(longest, str(d).length())
	while fs > 12 and longest > 0 and ceili(float(longest) / floorf(inner / (fs * 1.02))) > 2:
		fs -= 1
	text.add_theme_font_size_override("normal_font_size", fs)
	panel.custom_minimum_size = Vector2(dw, 0)
	panel.size = Vector2(dw, 0)
	panel.reset_size()
	panel.size.x = dw
	var dh := panel.size.y
	if stacked:
		panel.position = Vector2(margin, portrait.position.y - dh - margin * 0.5)
	else:
		panel.position = Vector2(portrait.position.x - margin - dw, vs.y - margin * 1.5 - dh)
	# Never over the page's key buttons: mirror to the left, then lift the dialogue to the top
	if _covers_avoid():
		portrait.position.x = margin
		if not stacked:
			panel.position.x = portrait.position.x + pw + margin
		if _covers_avoid():
			panel.position.y = margin * 4.0
			if _covers_avoid():
				portrait.visible = false
	_panel_y = panel.position.y
	# 跳過本次引導 fixed top-right; the voice toggle beside it
	skip_button.reset_size()
	voice_button.reset_size()
	skip_button.position = Vector2(vs.x - margin - skip_button.size.x, margin)
	voice_button.position = Vector2(skip_button.position.x - 8.0 * k - voice_button.size.x, margin)


func _covers_avoid() -> bool:
	for r in avoid_rects:
		var rr := r as Rect2
		if rr.size.x <= 0:
			continue
		if (portrait.visible and Rect2(portrait.position, portrait.size).intersects(rr)) or Rect2(panel.position, panel.size).intersects(rr):
			return true
	return false


## Dim with bright holes (soft gold outline) over the highlighted elements
func _draw_cutout() -> void:
	var vs := cutout.size
	var holes: Array = []
	for r in highlight_rects:
		var rr := (r as Rect2).grow(6.0)
		holes.append(rr.intersection(Rect2(Vector2.ZERO, vs)))
	var col := Color(DIM_COLOR, DIM_COLOR.a * dim.modulate.a)
	if holes.is_empty():
		cutout.draw_rect(Rect2(Vector2.ZERO, vs), col)
		return
	# Horizontal bands between hole edges keep the dim exact without a shader
	var ys: Array = [0.0, vs.y]
	for h in holes:
		ys.append((h as Rect2).position.y)
		ys.append((h as Rect2).end.y)
	ys.sort()
	for i in range(ys.size() - 1):
		var y0: float = ys[i]
		var y1: float = ys[i + 1]
		if y1 - y0 <= 0.5:
			continue
		var xs: Array = []
		for h in holes:
			var hr := h as Rect2
			if hr.position.y <= y0 + 0.1 and hr.end.y >= y1 - 0.1:
				xs.append([hr.position.x, hr.end.x])
		xs.sort_custom(func(a, b): return a[0] < b[0])
		var x := 0.0
		for seg in xs:
			if seg[0] > x:
				cutout.draw_rect(Rect2(x, y0, seg[0] - x, y1 - y0), col)
			x = maxf(x, seg[1])
		if x < vs.x:
			cutout.draw_rect(Rect2(x, y0, vs.x - x, y1 - y0), col)
	for h in holes:
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(2)
		sb.border_color = Color(C_GOLD, 0.85 * dim.modulate.a)
		sb.set_corner_radius_all(12)
		cutout.draw_style_box(sb, h)


func _enter_animation() -> void:
	if _anim:
		_anim.kill()
	if UI.is_animation_disabled():
		dim.modulate.a = 1.0
		portrait.modulate.a = 1.0
		portrait.scale = Vector2.ONE
		panel.modulate.a = 1.0
		panel.position.y = _panel_y
		return
	dim.modulate.a = 0.0
	# Portrait grows out of the small entry in the corner
	var final_pos := portrait.position
	var from := origin_rect if origin_rect.size.x > 0 else Rect2(final_pos + portrait.size * 0.8, portrait.size * 0.2)
	portrait.pivot_offset = Vector2.ZERO
	portrait.scale = Vector2.ONE * clampf(from.size.y / maxf(portrait.size.y, 1.0), 0.1, 1.0)
	portrait.position = from.position
	portrait.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.position.y = _panel_y + 8.0
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim.tween_property(dim, "modulate:a", 1.0, 0.2)
	_anim.tween_method(func(_v: float): cutout.queue_redraw(), 0.0, 1.0, 0.22)
	_anim.tween_property(portrait, "scale", Vector2.ONE, 0.25)
	_anim.tween_property(portrait, "position", final_pos, 0.25)
	_anim.tween_property(portrait, "modulate:a", 1.0, 0.18)
	_anim.tween_property(panel, "modulate:a", 1.0, 0.22).set_delay(0.08)
	_anim.tween_property(panel, "position:y", _panel_y, 0.22).set_delay(0.08)
