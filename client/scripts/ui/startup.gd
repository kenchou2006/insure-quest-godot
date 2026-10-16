extends Control
## Layered Life Advisor Bureau cover, shown after loading finishes.

signal entered

const BACKGROUND := preload("res://assets/startup/loading.png")
const TITLE := preload("res://assets/startup/title.png")
const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")

var _stage: Control
var _enter: Button
var _button_material: ShaderMaterial

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("0d231e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_stage = Control.new()
	_stage.clip_contents = true
	add_child(_stage)
	_add_art(BACKGROUND, Vector2.ZERO, Vector2.ONE)
	_add_art(FEMALE, Vector2(-0.035, 0.055), Vector2(0.36, 0.97))
	_add_art(MALE, Vector2(0.675, 0.055), Vector2(0.36, 0.97))
	_add_art(TITLE, Vector2(0.275, 0.30), Vector2(0.45, 0.30))
	_enter = Button.new()
	_enter.text = "進 入 顧 問 培 訓"
	_enter.pressed.connect(_on_entered)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		_enter.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		_enter.add_theme_color_override(state, Color("fffbea"))
	_enter.add_theme_color_override("font_shadow_color", Color("003c30"))
	_enter.add_theme_constant_override("shadow_offset_y", 2)
	var gloss := TextureRect.new()
	var fill := GradientTexture2D.new()
	gloss.texture = fill
	gloss.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gloss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.show_behind_parent = true
	_button_material = ShaderMaterial.new()
	_button_material.shader = preload("res://assets/startup/entry_button.gdshader")
	gloss.material = _button_material
	_enter.add_child(gloss)
	_enter.mouse_entered.connect(func(): _button_material.set_shader_parameter("highlight", 1.0))
	_enter.mouse_exited.connect(func(): _button_material.set_shader_parameter("highlight", 0.0))
	_enter.tooltip_text = "進入顧問培訓（Enter／空白鍵）"
	_enter.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_stage.add_child(_enter)
	resized.connect(_layout_cover)
	_layout_cover()
	_enter.grab_focus()

func _add_art(texture: Texture2D, origin: Vector2, extent: Vector2) -> void:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.anchor_left = origin.x
	art.anchor_top = origin.y
	art.anchor_right = origin.x + extent.x
	art.anchor_bottom = origin.y + extent.y
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(art)

func _layout_cover() -> void:
	var image_size := BACKGROUND.get_size()
	var scale_factor := minf(size.x / image_size.x, size.y / image_size.y)
	_stage.size = image_size * scale_factor
	_stage.position = (size - _stage.size) * 0.5
	_enter.custom_minimum_size = Vector2.ZERO
	_enter.add_theme_font_size_override("font_size", maxi(14, int(_stage.size.y * 0.04)))
	_enter.position = _stage.size * Vector2(0.35, 0.65)
	_enter.size = Vector2(_stage.size.x * 0.30, maxf(44.0, _stage.size.y * 0.11))
	_button_material.set_shader_parameter("button_size", _enter.size)

func _on_entered() -> void:
	_enter.disabled = true
	entered.emit()
