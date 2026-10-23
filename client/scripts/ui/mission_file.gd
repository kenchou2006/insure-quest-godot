extends Control
## Assigned-client training file (首次培訓任務). Closed: deep-green cover with a gold hairline frame,
## a client silhouette and a document mark. play_unlock() runs the "task data unlocking" sequence on
## this same file — scale up, gold frame lights, a thin green scan, the cover opens ~22° to the left,
## the inner page shows the assigned client's portrait outline and data lines — then emits `unlocked`.
## Nothing is drawn or picked at random: the client comes from set_client().

signal unlocked

const COVER_SHADER := preload("res://assets/startup/mission_cover.gdshader")
const FONT := preload("res://assets/fonts/regular.tres")
const LineIcon := preload("res://scripts/ui/line_icon.gd")
const CARD := Color("#0D4038")
const PAGE := Color("#134A41")
const GREEN := Color("#00A86B")
const GOLD := Color("#C6A15B")
const GOLD_LIGHT := Color("#E2C489")
const CREAM := Color("#F3F0E7")
const MUTED := Color("#AABCB5")

var _page: Control
var _avatar: TextureRect
var _cover: Control
var _cover_mat: ShaderMaterial
var _clip: Control
var _scan: TextureRect
var _outline: Control
var _trails: Control
var _unlock_icon: Control
var _seq: Tween
var _done := false

## 0..1 animation channels (driven by tweens)
var open_amount := 0.0:
	set(v):
		open_amount = v
		if _cover_mat:
			_cover_mat.set_shader_parameter("open_amount", v)
var reveal := 0.0:
	set(v):
		reveal = v
		if _page:
			_page.queue_redraw()
			_avatar.modulate.a = clampf(v * 1.4, 0.0, 1.0)
var glow := 0.0:
	set(v):
		glow = v
		if _outline:
			_outline.queue_redraw()
		if _cover:
			_cover.queue_redraw()
var trail := 0.0:
	set(v):
		trail = v
		if _trails:
			_trails.queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trails = Trails.new(self)
	add_child(_trails)
	_page = Page.new(self)
	add_child(_page)
	_avatar = TextureRect.new()
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar.material = UI.get_circle_material()
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.modulate.a = 0.0
	_page.add_child(_avatar)
	_cover = Cover.new(self)
	_cover_mat = ShaderMaterial.new()
	_cover_mat.shader = COVER_SHADER
	_cover.material = _cover_mat
	add_child(_cover)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_scan = TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(GREEN, 0.0), Color(GREEN, 0.55), Color(GREEN, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	_scan.texture = gt
	_scan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scan.stretch_mode = TextureRect.STRETCH_SCALE
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan.visible = false
	_clip.add_child(_scan)
	_outline = Outline.new(self)
	add_child(_outline)
	_unlock_icon = LineIcon.new("unlock", GOLD_LIGHT, 2.0)
	_unlock_icon.visible = false
	add_child(_unlock_icon)
	resized.connect(_layout)
	_layout()


## The assigned client: portrait for the inner page (missing art keeps the silhouette)
func set_client(c: Dictionary) -> void:
	var tex: Texture2D = null
	var id := str(c.get("id", ""))
	if id != "" and Portraits.has_portrait(id):
		tex = Portraits.get_texture(id)
	_avatar.texture = tex


func _layout() -> void:
	for n: Control in [_trails, _page, _cover, _clip, _outline]:
		n.position = Vector2.ZERO
		n.size = size
	_cover_mat.set_shader_parameter("rect_size", size)
	pivot_offset = size * 0.5
	var a := size.x * 0.42
	_avatar.size = Vector2(a, a)
	_avatar.position = Vector2((size.x - a) * 0.5, size.y * 0.14)
	_scan.size = Vector2(size.x, maxf(14.0, size.y * 0.07))
	# Unlock mark sits in the top-right corner like a status stamp
	var u := size.x * 0.15
	_unlock_icon.size = Vector2(u, u)
	_unlock_icon.position = Vector2(size.x - u - 16.0, 16.0)


## Runs the unlock sequence (relative to the accept click: starts at 0.15 s, ends at 1.30 s)
func play_unlock() -> void:
	if _seq or _done:
		return
	if UI.is_animation_disabled():
		open_amount = 1.0
		reveal = 1.0
		_cover.modulate.a = 0.25
		_unlock_icon.visible = true
		_finish()
		return
	_seq = create_tween().set_parallel(true)
	# 0.15–0.45: lift to 102%, gold frame lights, thin green scan top → bottom
	_seq.tween_callback(func(): Sound.play("scan", self)).set_delay(0.15)
	_seq.tween_property(self, "scale", Vector2.ONE * 1.02, 0.3).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_seq.tween_property(self, "glow", 1.0, 0.3).set_delay(0.15)
	_seq.tween_callback(func():
		_scan.visible = true
		_scan.position.y = -_scan.size.y
	).set_delay(0.15)
	_seq.tween_property(_scan, "position:y", size.y, 0.3).set_delay(0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 0.45–1.00: cover opens to the left, inner page shows the client outline and data lines
	_seq.tween_property(self, "open_amount", 1.0, 0.55).set_delay(0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_seq.tween_property(_cover, "modulate:a", 0.25, 0.55).set_delay(0.45)
	_seq.tween_property(self, "reveal", 1.0, 0.5).set_delay(0.5)
	_seq.tween_property(self, "trail", 1.0, 0.3).set_delay(0.45)
	_seq.tween_property(self, "trail", 0.0, 0.3).set_delay(0.85)
	# 1.00–1.30: scan complete, unlock mark
	_seq.tween_callback(func():
		_scan.visible = false
		_unlock_icon.visible = true
		_unlock_icon.modulate.a = 0.0
		_unlock_icon.pivot_offset = _unlock_icon.size * 0.5
		_unlock_icon.scale = Vector2.ONE * 0.8
		Sound.play("unlock", self)
	).set_delay(1.0)
	_seq.tween_property(_unlock_icon, "modulate:a", 1.0, 0.18).set_delay(1.0)
	_seq.tween_property(_unlock_icon, "scale", Vector2.ONE, 0.2).set_delay(1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_seq.tween_property(self, "glow", 0.4, 0.3).set_delay(1.0)
	_seq.chain().tween_callback(_finish)


func _finish() -> void:
	if _done:
		return
	_done = true
	unlocked.emit()


static func _silhouette(ci: CanvasItem, c: Vector2, s: float, fill: Color, line: Color) -> void:
	ci.draw_circle(c + Vector2(0, -s * 0.34), s * 0.2, fill)
	ci.draw_arc(c + Vector2(0, -s * 0.34), s * 0.2, 0, TAU, 40, line, 1.2, true)
	var body := PackedVector2Array()
	for k in range(17):
		var a := PI + PI * k / 16.0
		body.append(c + Vector2(0, s * 0.42) + Vector2(cos(a) * s * 0.42, sin(a) * s * 0.4))
	ci.draw_colored_polygon(body, fill)
	body.append(body[0])
	ci.draw_polyline(body, line, 1.2, true)


## Closed cover (drawn in one item so the perspective shader bends all of it together)
class Cover extends Control:
	var f: Control

	func _init(owner_file: Control) -> void:
		f = owner_file
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = CARD
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var g := float(f.get("glow"))
		var gold := GOLD.lerp(GOLD_LIGHT, g)
		var inset := r.grow(-9.0)
		var frame := StyleBoxFlat.new()
		frame.draw_center = false
		frame.set_border_width_all(1)
		frame.border_color = Color(gold, 0.85)
		frame.set_corner_radius_all(8)
		frame.anti_aliasing = true
		draw_style_box(frame, inset)
		# Corner ornaments
		var o := 7.0
		var l := minf(size.x, size.y) * 0.1
		for corner: Vector2 in [inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]:
			var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
			var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
			var p := corner + Vector2(o * sx, o * sy)
			draw_line(p, p + Vector2(l * sx, 0), Color(gold, 0.7), 1.0, true)
			draw_line(p, p + Vector2(0, l * sy), Color(gold, 0.7), 1.0, true)
		# Client silhouette
		var c := Vector2(size.x * 0.5, size.y * 0.4)
		f._silhouette(self, c, size.x * 0.46, Color("#0A3530"), Color(gold, 0.55))
		# Document mark and label
		var d := Vector2(size.x * 0.5, size.y * 0.74)
		var w := size.x * 0.13
		var h := w * 1.25
		var page := PackedVector2Array([d + Vector2(-w * 0.5, -h * 0.5), d + Vector2(w * 0.25, -h * 0.5), d + Vector2(w * 0.5, -h * 0.25), d + Vector2(w * 0.5, h * 0.5), d + Vector2(-w * 0.5, h * 0.5), d + Vector2(-w * 0.5, -h * 0.5)])
		draw_polyline(page, gold, 1.6, true)
		for k in range(3):
			var y := d.y - h * 0.12 + k * h * 0.2
			draw_line(Vector2(d.x - w * 0.3, y), Vector2(d.x + w * (0.3 if k < 2 else 0.05), y), gold, 1.4, true)
		var fs := maxi(11, roundi(size.x * 0.06))
		var label := "任務檔案"
		var tw := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(FONT, Vector2((size.x - tw) * 0.5, size.y * 0.9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(gold, 0.85))


## Inner page: portrait outline (TextureRect child) plus data lines that write in with `reveal`
class Page extends Control:
	var f: Control

	func _init(owner_file: Control) -> void:
		f = owner_file
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PAGE
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var v := float(f.get("reveal"))
		if v <= 0.0:
			return
		var a := size.x * 0.42
		var c := Vector2(size.x * 0.5, size.y * 0.14 + a * 0.5)
		draw_arc(c, a * 0.5 + 3.0, -PI * 0.5, -PI * 0.5 + TAU * v, 48, Color(GOLD, 0.9), 1.4, true)
		# Data lines (name, job, family, budget...) as abstract rows
		var widths := [0.62, 0.48, 0.7, 0.4, 0.56]
		for k in range(widths.size()):
			var t := clampf(v * 1.6 - k * 0.12, 0.0, 1.0)
			if t <= 0.0:
				continue
			var y := size.y * 0.62 + k * size.y * 0.06
			var x0 := size.x * 0.16
			var full := size.x * float(widths[k])
			draw_line(Vector2(x0, y), Vector2(x0 + full * t, y), Color(CREAM if k == 0 else MUTED, 0.75 if k == 0 else 0.5), 2.0 if k == 0 else 1.4, true)


## Hairline gold frame that brightens during the unlock
class Outline extends Control:
	var f: Control

	func _init(owner_file: Control) -> void:
		f = owner_file
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var g := float(f.get("glow"))
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(1)
		sb.border_color = Color(GOLD.lerp(GOLD_LIGHT, g), 0.55 + 0.45 * g)
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size).grow(1.0 + g))


## A few green and gold data trails beside the file (no particles)
class Trails extends Control:
	var f: Control

	func _init(owner_file: Control) -> void:
		f = owner_file
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var t := float(f.get("trail"))
		if t <= 0.0:
			return
		var rows := [0.3, 0.46, 0.62]
		for side: float in [-1.0, 1.0]:
			for k in range(rows.size()):
				var y := size.y * float(rows[k])
				var x0 := size.x * 0.5 + side * (size.x * 0.5 + 8.0)
				var span := size.x * (0.34 - k * 0.06) * t
				var col := Color(GREEN if k != 1 else GOLD, 0.55 * t)
				var dots := int(span / 7.0)
				for d in range(dots):
					var x := x0 + side * d * 7.0
					draw_circle(Vector2(x, y), 1.2, col)
