extends Node
## SceneTransitionManager (autoload): one way to change pages inside the game.
## 1 lock clicks → 2 deep-green veil fades in (0.3 s) → 3/4 the swap callback builds the next page
## under the veil (data first, so nothing old or empty flashes) → 5 veil fades out (0.3 s) → 6 unlock.
## A second request while one runs waits for it; the veil never stays up (watchdog).

signal started
signal finished

const COLOR := Color("#062F2A")
const FADE := 0.3

var active := false
var _layer: CanvasLayer
var _veil: ColorRect
var _queue: Array = []
var _since := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.name = "TransitionLayer"
	_layer.layer = 95
	add_child(_layer)
	_veil = ColorRect.new()
	_veil.name = "TransitionVeil"
	_veil.color = COLOR
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	_veil.visible = false
	_layer.add_child(_veil)


## Runs swap under the veil. swap may be a coroutine (awaited).
func run(swap: Callable, fade_in := FADE, fade_out := FADE) -> void:
	if active:
		_queue.append([swap, fade_in, fade_out])
		return
	active = true
	_since = 0.0
	started.emit()
	_veil.visible = true
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	AudioManager.play("page_whoosh")
	var quick := UI.is_animation_disabled()
	if quick:
		_veil.modulate.a = 1.0
	else:
		var tw := create_tween()
		tw.tween_property(_veil, "modulate:a", 1.0, fade_in).set_trans(Tween.TRANS_SINE)
		await tw.finished
	if swap.is_valid():
		await swap.call()
	# Two frames: the new page is built and drawn before the veil lifts
	await get_tree().process_frame
	await get_tree().process_frame
	if quick:
		_veil.modulate.a = 0.0
	else:
		var tw2 := create_tween()
		tw2.tween_property(_veil, "modulate:a", 0.0, fade_out).set_trans(Tween.TRANS_SINE)
		await tw2.finished
	_release()
	if not _queue.is_empty():
		var next: Array = _queue.pop_front()
		run(next[0], next[1], next[2])


func _release() -> void:
	_veil.visible = false
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	active = false
	finished.emit()


func _process(delta: float) -> void:
	if not active:
		return
	_since += delta
	# A swap that never returns must not leave the screen locked
	if _since > 6.0:
		push_warning("SceneTransitionManager: watchdog released the veil")
		_queue.clear()
		_release()


func veil() -> ColorRect:
	return _veil
