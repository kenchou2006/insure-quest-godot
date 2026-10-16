@tool
extends Camera3D
## Input is routed by the board Control, so menus and other panels never pan the city.
@export var edge_pan_enabled := false
@export var pan_speed := 11.0
@export var min_zoom := 0.5
@export var max_zoom := 1.5
var focus := Vector3(0,2,-1)
var _focus_tween: Tween
var _base_size := 38.0
var _zoom := 1.0
var _yaw := 0.0
var _tilt := 0.64
var _area := Vector2(800, 600)
var _pointer := Vector2(-100, -100)
var _inside := false

func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	keep_aspect = Camera3D.KEEP_HEIGHT
	_sync()

func fit(area: Vector2) -> void:
	_area = area.max(Vector2.ONE)
	_base_size = maxf(35, 43 / (_area.x / _area.y))
	_sync()

func _sync() -> void:
	size = _base_size * _zoom
	position = focus + Vector3(sin(_yaw) * cos(_tilt), sin(_tilt), cos(_yaw) * cos(_tilt)) * 48
	look_at(focus)

func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, min_zoom, max_zoom)
	_sync()

func pan_pixels(relative: Vector2) -> void:
	_stop_focus()
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var forward := Vector3(sin(_yaw), 0, cos(_yaw))
	focus -= (right * relative.x + forward * relative.y / sin(_tilt)) * size / _area.y
	focus.x = clampf(focus.x, -12, 12)
	focus.z = clampf(focus.z, -12, 12)
	_sync()

func orbit(relative: Vector2) -> void:
	_stop_focus()
	_yaw -= relative.x * 0.006
	_tilt = clampf(_tilt + relative.y * 0.004, 0.42, 1.1)
	_sync()

func pointer(pos: Vector2, inside: bool) -> void:
	_pointer = pos
	_inside = inside

func reset_view() -> void:
	_stop_focus()
	focus = Vector3(0,2,-1)
	_zoom = 1
	_yaw = 0
	_tilt = 0.64
	_sync()

func _process(delta: float) -> void:
	if not edge_pan_enabled or not _inside or Engine.is_editor_hint():
		return
	var direction := Vector2.ZERO
	if _pointer.x < 18: direction.x = 1
	elif _pointer.x > _area.x - 18: direction.x = -1
	if _pointer.y < 18: direction.y = 1
	elif _pointer.y > _area.y - 18: direction.y = -1
	pan_pixels(direction * delta * pan_speed * _area.y / size)

func _stop_focus() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()

func focus_on(world: Vector3, animate: bool = true) -> void:
	_stop_focus()
	# A small compositional nudge retains the central tower and surrounding blocks.
	var destination := Vector3(world.x*0.12,2,-1+world.z*0.10)
	if not animate or UI.reduce_motion:
		focus = destination
		_sync()
		return
	_focus_tween = create_tween()
	_focus_tween.tween_method(_set_focus,focus,destination,0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_focus(value: Vector3) -> void:
	focus = value
	_sync()
