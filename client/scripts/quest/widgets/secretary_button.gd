extends Button
## SecretaryButton: 培訓秘書 pill on every mission page. Pressing it plays this page's explanation
## through the one focus guide (clock held while she speaks). Hidden when no secretary was chosen.

var page_id := ""
var lines_provider: Callable
var highlight_provider: Callable


func _init(pid := "") -> void:
	page_id = pid
	name = "SecretaryButton"
	text = "培訓秘書"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, 44)
	add_theme_font_size_override("font_size", QuestUI.fs(15))
	add_theme_font_override("font", QuestUI.FONT_BOLD)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(999)
		s.set_border_width_all(1)
		s.content_margin_left = 40
		s.content_margin_right = 16
		s.content_margin_top = 4
		s.content_margin_bottom = 4
		s.bg_color = Color(QuestUI.CARD, 0.95) if st != "hover" else Color(QuestUI.CARD.lightened(0.08), 0.98)
		s.border_color = QuestUI.GOLD if st in ["hover", "focus"] else Color(QuestUI.GOLD, 0.5)
		if st == "focus":
			s.bg_color = Color(0, 0, 0, 0)
		add_theme_stylebox_override(st, s)
	add_theme_color_override("font_color", QuestUI.TEXT)
	var ic := QuestUI.icon("secretary", 22.0, QuestUI.GOLD)
	ic.position = Vector2(12, 11)
	add_child(ic)
	pressed.connect(_on_pressed)
	mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	button_down.connect(_press.bind(true))
	button_up.connect(_press.bind(false))


func _press(down: bool) -> void:
	if QuestUI.motion_off():
		return
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (0.97 if down else 1.0)


func _ready() -> void:
	visible = TutorialManager.secretary_on()


func _process(_delta: float) -> void:
	var on := TutorialManager.secretary_on()
	if visible != on:
		visible = on


func _on_pressed() -> void:
	AudioManager.play("ui_click")
	var lines: Array = lines_provider.call() if lines_provider.is_valid() else []
	var hl: Array = highlight_provider.call() if highlight_provider.is_valid() else []
	TutorialManager.explain(page_id, lines, hl)
