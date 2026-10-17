extends Control
## Training secretary: keeps the player's choice (Aly / Kevin / none, saved) and shows lines for the
## current game state in a compact corner dialog — portrait of the chosen secretary, subtitles typed
## in step with the voice, 「略過」 and 「關閉語音」 — that shrinks to a round portrait in the bottom-right
## 1 s after the line ends. Tapping the portrait shows the current hint again.
## State lines (secretary_lines.gd) play automatically only the first time each state is reached,
## remembered across sessions. 自行挑戰: no portrait, dialog or voice at all.

signal dock_changed(height: float)

const PREFS := "user://training_secretary.cfg"
const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
const SecretaryVoice := preload("res://scripts/secretary_voice.gd")
const SecretaryLines := preload("res://scripts/secretary_lines.gd")
const TutorialOverlay := preload("res://scripts/ui/tutorial_overlay.gd")
## Waist-up and face crops of the cover portraits
const CROP_F := Rect2(88, 0, 760, 1000)
const CROP_M := Rect2(128, 0, 760, 1000)
const FACE_F := Rect2(340, 90, 340, 340)
const FACE_M := Rect2(320, 60, 340, 340)
## Bump when the tutorials change, so players who saw the old version get the new one once
const TUTORIAL_VERSION := 2
## Subtitle speed: in step with Mandarin TTS, faster when reading without voice
const CPS_VOICE := 4.8
const CPS_READ := 14.0

var configured := false
var enabled := false
var role := "female"
## "aly", "kevin" or "none"; decides the portrait, name and speech voice
var secretary_id := "none"
## 「關閉語音」 keeps subtitles only (saved)
var voice_on := true

## Voice found for the current secretary ("" = subtitles only); re-picked before every line
var _voice := ""
var _speech_unlocked := false
## Per-game keys (in-game steps) already shown
var _seen: Dictionary = {}
## State keys already played automatically (saved)
var _seen_states: Array = []
var _lines: Array = []
var _queue: Array = []
var _index := 0
var _active_key := ""
var _replay_lines: Array = []
var _open := false
var _side := "right"
var _reflow := false
var _icon_allowed := false
var _speaking := false
var _line_gen := 0
## Modal tutorial (強制聚焦導覽) for first-time teaching states; compact corner card otherwise
var _modal := false
var _line_targets: Array = []
var _replay_targets: Array = []
var _line_t0 := 0.0
var _line_est := 1.0
var _line_ready := false
var _overlay: Control

var _card: Panel
var _portrait: TextureRect
var _heading: Label
var _subtitle: Label
var _skip: Button
var _mute: Button
var _icon: Button
var _type_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) == OK:
		configured = bool(cfg.get_value("guide", "configured", false))
		enabled = bool(cfg.get_value("guide", "enabled", false))
		role = str(cfg.get_value("guide", "role", "female"))
		secretary_id = str(cfg.get_value("guide", "secretary_id", SecretaryVoice.id_from_choice(enabled, role)))
		voice_on = bool(cfg.get_value("guide", "voice_on", true))
		var seen: Variant = cfg.get_value("guide", "seen_states", [])
		_seen_states = (seen as Array).duplicate() if seen is Array else []
		if int(cfg.get_value("guide", "tutorial_version", 1)) < TUTORIAL_VERSION:
			_seen_states = []
	# Above full-screen overlays inside the game (case setup sits at z 110)
	z_index = 120
	_build()
	resized.connect(_layout)
	var mm := get_node_or_null("/root/MusicManager")
	if mm and not mm.speech_ended.is_connected(_on_speech_ended):
		mm.speech_ended.connect(_on_speech_ended)


func _build() -> void:
	_card = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0D4038", 0.96)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 10
	sb.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", sb)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.clip_contents = true
	_card.visible = false
	add_child(_card)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_portrait)
	_heading = UI.label("", 13, UI.GOLD)
	_card.add_child(_heading)
	_subtitle = UI.label("", 15, UI.TEXT, true)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_card.add_child(_subtitle)
	_skip = _small_button("略過", _collapse)
	_card.add_child(_skip)
	_mute = _small_button("關閉語音", _toggle_voice)
	_card.add_child(_mute)

	_icon = Button.new()
	_icon.focus_mode = Control.FOCUS_NONE
	_icon.tooltip_text = "培訓秘書：再看一次提示"
	_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color("#0D4038")
	ring.set_corner_radius_all(64)
	ring.set_border_width_all(2)
	ring.border_color = UI.GOLD
	ring.anti_aliasing = true
	for st: String in ["normal", "hover", "pressed", "focus"]:
		_icon.add_theme_stylebox_override(st, ring)
	var face := TextureRect.new()
	face.name = "Face"
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.material = UI.get_circle_material()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.add_child(face)
	_icon.pressed.connect(replay)
	_icon.visible = false
	add_child(_icon)

	# Modal tutorial on the very top of the secretary layer
	_overlay = TutorialOverlay.new()
	add_child(_overlay)
	_overlay.skip_pressed.connect(func(): _close_modal(true))
	_overlay.continue_pressed.connect(_on_continue)
	_overlay.mute_pressed.connect(_toggle_voice)


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 13)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.0)
	n.set_corner_radius_all(8)
	n.set_border_width_all(1)
	n.border_color = Color(UI.TEXT, 0.35)
	n.content_margin_left = 10
	n.content_margin_right = 10
	n.content_margin_top = 2
	n.content_margin_bottom = 2
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.08)
	h.border_color = Color(UI.TEXT, 0.6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", UI.TEXT)
	b.pressed.connect(cb)
	return b


# --- Choice ------------------------------------------------------------------------------------

func choose(use_guide: bool, selected_role: String) -> void:
	# Stop the previous narration before changing the playback permission.
	dismiss()
	configured = true
	enabled = use_guide
	role = selected_role if selected_role in ["female", "male"] else "female"
	secretary_id = SecretaryVoice.id_from_choice(enabled, role)
	_speech_unlocked = use_guide
	_seen.clear()
	_save()
	_find_voice()
	_refresh_art()


## "female", "male" or "none" (自行挑戰): the secretary chosen on the selection screen
func selected_secretary() -> String:
	if not enabled:
		return "none"
	return "male" if role == "male" else "female"


func unlock_speech() -> void:
	# Called by the explicit cover enter button, including returning users.
	_speech_unlocked = enabled
	_find_voice()


func _find_voice() -> void:
	_voice = "" if not enabled else SecretaryVoice.pick(secretary_id)


## Merges into the saved file so other keys (seen states, voice) are kept
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("guide", "configured", configured)
	cfg.set_value("guide", "enabled", enabled)
	cfg.set_value("guide", "role", role)
	cfg.set_value("guide", "secretary_id", secretary_id)
	cfg.set_value("guide", "selected_secretary", selected_secretary())
	cfg.set_value("guide", "voice_on", voice_on)
	cfg.set_value("guide", "seen_states", _seen_states)
	cfg.set_value("guide", "tutorial_version", TUTORIAL_VERSION)
	if cfg.save(PREFS) != OK:
		push_warning("無法保存秘書偏好，本次選擇仍有效。")


# --- Showing lines -----------------------------------------------------------------------------

## State-driven lines (training_entry, first_assignment, …). Each state plays automatically once.
## States named together play in order; a later state replaces what is playing, so the secretary
## always talks about the screen the player is on (never lagging a step behind).
## targets: state → Controls to keep bright; modal: first-time teaching shown as the 強制聚焦導覽
## (locks the interface until 「我知道了」 or 「跳過」), otherwise a compact corner card.
func show_states(states: Array, targets: Dictionary = {}, modal := true, side := "right", reflow := false) -> void:
	if not enabled:
		return
	var lines: Array = []
	var line_targets: Array = []
	var replay_lines: Array = []
	var replay_targets: Array = []
	for st: String in states:
		var l := SecretaryLines.lines(st)
		var t: Array = targets.get(st, [])
		for line in l:
			replay_lines.append(line)
			replay_targets.append(t)
		if _seen_states.has(st):
			continue
		_seen_states.append(st)
		for line in l:
			lines.append(line)
			line_targets.append(t)
	if not replay_lines.is_empty():
		_replay_lines = replay_lines
		_replay_targets = replay_targets if modal else []
	if lines.is_empty():
		return
	_save()
	_play("state:" + ",".join(states), lines, side, reflow, modal, line_targets)


## Plays these states again (corner portrait / 再看一次), seen or not, as the modal tutorial
func replay_states(states: Array, targets: Dictionary = {}) -> void:
	if not enabled:
		return
	var lines: Array = []
	var line_targets: Array = []
	for st: String in states:
		var t: Array = targets.get(st, [])
		for line in SecretaryLines.lines(st):
			lines.append(line)
			line_targets.append(t)
	if lines.is_empty():
		return
	_replay_lines = lines.duplicate()
	_replay_targets = line_targets.duplicate()
	_play("replay:" + ",".join(states), lines, "right", false, true, line_targets)


## In-game step lines keyed by turn; shown once per key and reflowing the screen
func show_lines(key: String, lines: Array, side := "right", reflow := true) -> void:
	if not enabled or key == _active_key:
		return
	dismiss()
	_active_key = key
	if _seen.has(key):
		return
	_seen[key] = true
	_replay_lines = lines.duplicate()
	_replay_targets = []
	_play(key, lines, side, reflow)


## Tapping the round portrait: the current hint again (with voice unless it is off)
func replay() -> void:
	if not enabled or _replay_lines.is_empty():
		return
	var modal := not _replay_targets.is_empty()
	_play("replay", _replay_lines.duplicate(), _side, _reflow, modal, _replay_targets.duplicate())


func is_open() -> bool:
	return _open


func _play(key: String, lines: Array, side: String, reflow: bool, modal := false, targets: Array = []) -> void:
	_stop_voice()
	if _modal and not modal:
		_overlay.close(true)
	_active_key = key
	_lines = lines
	_line_targets = targets
	_queue.clear()
	_index = 0
	_side = side
	_modal = modal
	_reflow = (reflow or UI.is_portrait()) and not modal
	_open = true
	visible = true
	_refresh_art()
	_icon.visible = false
	if modal:
		_card.visible = false
		# Keyboard focus off the screen behind: nothing there may be activated meanwhile
		if get_viewport():
			get_viewport().gui_release_focus()
		_overlay.show_overlay(_portrait.texture)
		_update_line()
		return
	_card.visible = true
	_layout()
	if _reflow:
		dock_changed.emit(_card.size.y + 16.0)
	if not UI.is_animation_disabled():
		_card.modulate.a = 0.0
		create_tween().tween_property(_card, "modulate:a", 1.0, 0.2)
	_update_line()


func _update_line() -> void:
	_find_voice()
	_line_gen += 1
	var gen := _line_gen
	var line := str(_lines[_index])
	var who := "女性培訓秘書 · Aly" if secretary_id != "kevin" else "男性培訓秘書 · Kevin"
	_heading.text = who + ("" if voice_on and _voice != "" else " · 字幕")
	_mute.text = "關閉語音" if voice_on else "開啟語音"
	_subtitle.text = line
	_speaking = false
	_line_ready = false
	if _modal:
		_overlay.set_line(_heading.text, line)
		_overlay.set_mute_label(_mute.text)
		_overlay.set_targets(_line_targets[_index] if _index < _line_targets.size() else [])
	if voice_on and _speech_unlocked and _voice != "":
		_speaking = SecretaryVoice.speak(secretary_id, line)
	# Subtitles typed in step with the voice (or at reading pace without it)
	var dur := line.length() / (CPS_VOICE if _speaking else CPS_READ)
	_line_t0 = Time.get_ticks_msec() / 1000.0
	_line_est = maxf(dur, 0.3)
	var label: Label = _overlay.text_label() if _modal else _subtitle
	if _type_tween:
		_type_tween.kill()
	if UI.is_animation_disabled():
		label.visible_ratio = 1.0
	else:
		label.visible_ratio = 0.0
		_type_tween = create_tween()
		_type_tween.tween_property(label, "visible_ratio", 1.0, dur)
	# Without a voice report (or no voice) the line ends after typing plus reading time
	var wait := (line.length() * 0.32 + 1.5) if _speaking else (dur + 1.2)
	get_tree().create_timer(wait).timeout.connect(func():
		if gen == _line_gen and _open:
			_line_done()
	)


func _on_speech_ended() -> void:
	if _open and _speaking:
		_speaking = false
		_line_done()


func _line_done() -> void:
	var gen := _line_gen
	if _type_tween:
		_type_tween.kill()
	_subtitle.visible_ratio = 1.0
	if _modal:
		# Spoken: offer 「繼續」 / 「我知道了」 and wait for the player
		_line_ready = true
		_overlay.set_progress(1.0, "語音完成" if voice_on and _voice != "" else "字幕完成")
		_overlay.show_continue("繼續" if _index < _lines.size() - 1 else "我知道了")
		return
	_line_gen += 1
	gen = _line_gen
	_index += 1
	if _index < _lines.size() or not _queue.is_empty():
		if _index >= _lines.size():
			_lines = _queue.duplicate()
			_queue.clear()
			_index = 0
		get_tree().create_timer(0.4).timeout.connect(func():
			if gen == _line_gen and _open:
				_update_line()
		)
		return
	# Last line: shrink to the corner portrait 1 s after it ends
	get_tree().create_timer(1.0).timeout.connect(func():
		if gen == _line_gen and _open:
			_collapse()
	)


## Next line now (kept for the step-through test and keyboard use)
func _advance() -> void:
	if _modal:
		_on_continue()
		return
	_stop_voice()
	_line_gen += 1
	_index += 1
	if _index >= _lines.size():
		if _queue.is_empty():
			dismiss()
			return
		_lines = _queue.duplicate()
		_queue.clear()
		_index = 0
	_update_line()


func _toggle_voice() -> void:
	voice_on = not voice_on
	_save()
	if not voice_on:
		_stop_voice()
		_speaking = false
	_mute.text = "關閉語音" if voice_on else "開啟語音"
	if _overlay:
		_overlay.set_mute_label(_mute.text)
	_heading.text = _heading.text.trim_suffix(" · 字幕") + ("" if voice_on and _voice != "" else " · 字幕")


## 「略過」 / end of the lines: dialog shrinks to the round portrait in the bottom-right
func _collapse() -> void:
	if _modal:
		_close_modal(false)
		return
	_stop_voice()
	_line_gen += 1
	_queue.clear()
	_open = false
	_card.visible = false
	if _reflow:
		dock_changed.emit(0.0)
	_icon.visible = _icon_allowed and enabled and not _replay_lines.is_empty()
	_layout()
	if _icon.visible and not UI.is_animation_disabled():
		UI.pop_in(_icon, 0.2)


func dismiss() -> void:
	_stop_voice()
	_line_gen += 1
	_queue.clear()
	if _modal and _overlay:
		_overlay.close(true)
	_modal = false
	_open = false
	if _card:
		_card.visible = false
	dock_changed.emit(0.0)
	if _icon:
		_icon.visible = _icon_allowed and enabled and not _replay_lines.is_empty()


## 「繼續」 / 「我知道了」: next line, or close and give the interface back
func _on_continue() -> void:
	if not _open or not _modal:
		return
	_stop_voice()
	_line_gen += 1
	_index += 1
	if _index < _lines.size():
		_update_line()
	else:
		_close_modal(false)


## Ends the modal tutorial — finished or 「跳過」 — and always unlocks the interface
func _close_modal(instant: bool) -> void:
	_stop_voice()
	_line_gen += 1
	if _type_tween:
		_type_tween.kill()
	_queue.clear()
	_open = false
	_modal = false
	_line_ready = false
	if _overlay:
		_overlay.close(instant)
	_icon.visible = _icon_allowed and enabled and not _replay_lines.is_empty()
	_layout()


func _process(_delta: float) -> void:
	if not (_open and _modal and _overlay) or _line_ready:
		return
	var t := Time.get_ticks_msec() / 1000.0 - _line_t0
	var p := clampf(t / _line_est, 0.0, 0.98)
	var speaking := voice_on and _speaking
	_overlay.set_progress(p, ("語音播放中 %d%%" if speaking else "字幕 %d%%") % roundi(p * 100.0))


## Esc skips, Enter / Space continues once the line has been spoken; nothing reaches the screen
func _input(event: InputEvent) -> void:
	if not (_open and _modal) or not event is InputEventKey or not event.pressed:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_modal(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _line_ready:
			_on_continue()
		get_viewport().set_input_as_handled()


func _stop_voice() -> void:
	# Clear first: stopping reports "speech ended", which must not count as this line finishing
	var was := _speaking
	_speaking = false
	if _speech_unlocked or was:
		SecretaryVoice.stop()


func screen_changed(kind: String) -> void:
	dismiss()
	_active_key = ""
	# The corner portrait belongs to training screens; the hall and setup screens have their own
	_icon_allowed = kind in ["game", "report"]
	_icon.visible = _icon_allowed and enabled and not _replay_lines.is_empty()
	_refresh_art()
	_layout()
	if kind == "report":
		show_lines("report", ["本次培訓已完成。看看能力表現與建議，再回顧自己的關鍵決策。"])


func observe(state: Dictionary) -> void:
	if not enabled or str(state.get("phase", "")) != "playing":
		return
	# Case setup (assignment → clues → briefcase) drives its own states
	var me: Dictionary = Net.me()
	if not me.is_empty() and me.get("mainCase") == null:
		return
	if not Net.is_my_turn():
		if _active_key != "" and not _active_key.begins_with("state:") and _open:
			dismiss()
			_active_key = ""
		return
	var turn_key := "%s/%s/%s" % [state.get("round", 1), state.get("turn", 0), state.get("turnStage", "")]
	var sess: Variant = state.get("session")
	if sess is Dictionary:
		var step := str(sess.get("step", ""))
		var key := turn_key + "/" + str(sess.get("client", {}).get("id", "")) + "/" + step
		var messages := {
			"discover": ["先了解客戶的生活與需求。觀察線索，再提出合適的問題。", "別急著推薦商品，找出客戶真正擔心的風險。"],
			"plan": ["依照已發現的需求配置方案，兼顧保障缺口與客戶預算。"],
			"objection": ["先理解客戶的疑慮，再清楚說明方案的價值與限制。"],
			"result": ["檢視這次決策的結果與回饋，看看下一次可以如何改善。"]
		}
		if messages.has(step):
			show_lines(key, messages[step])
		elif key != _active_key:
			if _open:
				dismiss()
			_active_key = key
	elif str(state.get("turnStage", "")) == "roll":
		show_lines(turn_key, ["輪到你了！擲出骰子，前往城市中的下一個培訓任務。"])
	else:
		if _open and not _active_key.begins_with("state:"):
			dismiss()
		_active_key = turn_key


func begin_training() -> void:
	_seen.clear()
	_active_key = ""
	dismiss()


# --- Art & layout ------------------------------------------------------------------------------

func _refresh_art() -> void:
	if _portrait == null:
		return
	var male := secretary_id == "kevin"
	var a := AtlasTexture.new()
	a.atlas = MALE if male else FEMALE
	a.region = CROP_M if male else CROP_F
	_portrait.texture = a
	var f := AtlasTexture.new()
	f.atlas = MALE if male else FEMALE
	f.region = FACE_M if male else FACE_F
	(_icon.get_node("Face") as TextureRect).texture = f


func _layout() -> void:
	if _card == null or size.x < 10:
		return
	var portrait_screen := UI.is_portrait()
	var k := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.75, 1.5) if not portrait_screen else clampf(size.x / 480.0, 0.8, 1.3)
	var margin := 18.0 * k
	# At most 20% of the screen height
	var h := minf(size.y * 0.2, 128.0 * k)
	var w := minf(392.0 * k, size.x - margin * 2) if not portrait_screen else size.x - margin * 2
	_card.size = Vector2(w, h)
	var x := size.x - margin - w if _side != "left" or portrait_screen else margin
	_card.position = Vector2(x, size.y - margin - h)
	var pw := h * 0.74
	_portrait.size = Vector2(pw, h)
	_portrait.position = Vector2.ZERO
	var pad := 12.0 * k
	var tx := pw + pad
	var tw := w - tx - pad
	_heading.add_theme_font_size_override("font_size", roundi(13 * k))
	_heading.position = Vector2(tx, pad * 0.7)
	_heading.size = Vector2(tw, 0)
	_subtitle.add_theme_font_size_override("font_size", roundi(15 * k))
	_subtitle.position = Vector2(tx, pad * 0.7 + 20.0 * k)
	_subtitle.size = Vector2(tw, h - pad * 0.7 - 20.0 * k - 34.0 * k)
	_subtitle.custom_minimum_size = Vector2(tw, 0)
	for b: Button in [_skip, _mute]:
		b.add_theme_font_size_override("font_size", roundi(13 * k))
		b.reset_size()
	_mute.position = Vector2(w - pad - _mute.size.x, h - pad * 0.8 - _mute.size.y)
	_skip.position = Vector2(_mute.position.x - 8.0 * k - _skip.size.x, _mute.position.y)
	var a := 56.0 * k
	_icon.size = Vector2(a, a)
	_icon.position = Vector2(size.x - margin - a, size.y - margin - a)
	var face: TextureRect = _icon.get_node("Face")
	face.position = Vector2(3, 3)
	face.size = Vector2(a - 6, a - 6)


func _exit_tree() -> void:
	if _speech_unlocked:
		SecretaryVoice.stop()
