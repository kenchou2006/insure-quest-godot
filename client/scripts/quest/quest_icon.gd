@tool
extends Control
## 2px rounded line icons for the mission pages (drawn, no image files, no emoji).

var kind := "doc"
var color := Color("#F3F0E7")
var width := 2.0


func _init(icon_kind := "doc", sz := 22.0, col := Color("#F3F0E7")) -> void:
	kind = icon_kind
	color = col
	custom_minimum_size = Vector2(sz, sz)
	size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _l(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, color, width, true)


func _poly(pts: Array) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(v)
	draw_polyline(p, color, width, true)


func _arc(c: Vector2, r: float, a0: float, a1: float) -> void:
	draw_arc(c, r, a0, a1, 24, color, width, true)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.4
	match kind:
		"pin":
			_arc(c + Vector2(0, -r * 0.2), r * 0.62, PI * 0.82, PI * 2.18)
			_l(c + Vector2(-r * 0.55, r * 0.05), c + Vector2(0, r))
			_l(c + Vector2(r * 0.55, r * 0.05), c + Vector2(0, r))
			draw_circle(c + Vector2(0, -r * 0.2), r * 0.18, color)
		"user":
			_arc(c + Vector2(0, -r * 0.35), r * 0.38, 0, TAU)
			_arc(c + Vector2(0, r * 1.05), r * 0.85, PI * 1.15, PI * 1.85)
		"people":
			_arc(c + Vector2(-r * 0.4, -r * 0.35), r * 0.3, 0, TAU)
			_arc(c + Vector2(r * 0.45, -r * 0.3), r * 0.26, 0, TAU)
			_arc(c + Vector2(-r * 0.4, r * 0.85), r * 0.62, PI * 1.12, PI * 1.88)
			_arc(c + Vector2(r * 0.45, r * 0.8), r * 0.5, PI * 1.15, PI * 1.85)
		"clock":
			_arc(c, r, 0, TAU)
			_l(c, c + Vector2(0, -r * 0.6))
			_l(c, c + Vector2(r * 0.45, r * 0.15))
		"dice":
			var box := StyleBoxFlat.new()
			box.draw_center = false
			box.set_border_width_all(int(width))
			box.border_color = color
			box.set_corner_radius_all(int(r * 0.4))
			draw_style_box(box, Rect2(c - Vector2(r, r), Vector2(r, r) * 2))
			for d in [Vector2(-0.45, -0.45), Vector2(0, 0), Vector2(0.45, 0.45)]:
				draw_circle(c + d * r, r * 0.13, color)
		"chart", "bars":
			_l(c + Vector2(-r, r), c + Vector2(r, r))
			for k in range(3):
				var x := -r * 0.55 + k * r * 0.55
				_l(c + Vector2(x, r * 0.8), c + Vector2(x, r * 0.8 - r * (0.5 + k * 0.45)))
		"doc", "report":
			_poly([c + Vector2(-r * 0.7, -r), c + Vector2(r * 0.35, -r), c + Vector2(r * 0.7, -r * 0.65), c + Vector2(r * 0.7, r), c + Vector2(-r * 0.7, r), c + Vector2(-r * 0.7, -r)])
			for k in range(3):
				_l(c + Vector2(-r * 0.38, -r * 0.35 + k * r * 0.4), c + Vector2(r * 0.38, -r * 0.35 + k * r * 0.4))
		"shield":
			_poly([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.7, r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.7, r * 0.2), c + Vector2(-r * 0.8, -r * 0.6), c + Vector2(0, -r)])
		"shield_check":
			_poly([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.7, r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.7, r * 0.2), c + Vector2(-r * 0.8, -r * 0.6), c + Vector2(0, -r)])
			_poly([c + Vector2(-r * 0.32, 0), c + Vector2(-r * 0.05, r * 0.28), c + Vector2(r * 0.38, -r * 0.25)])
		"alert":
			_poly([c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8), c + Vector2(0, -r)])
			_l(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.25))
			draw_circle(c + Vector2(0, r * 0.55), width * 0.8, color)
		"star":
			var pts: Array = []
			for k in range(11):
				var a := -PI * 0.5 + k * PI / 5.0
				var rr := r if k % 2 == 0 else r * 0.45
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			_poly(pts)
		"heart":
			_arc(c + Vector2(-r * 0.42, -r * 0.2), r * 0.45, PI * 0.8, PI * 2.0)
			_arc(c + Vector2(r * 0.42, -r * 0.2), r * 0.45, PI, PI * 2.2)
			_l(c + Vector2(-r * 0.86, -r * 0.05), c + Vector2(0, r * 0.85))
			_l(c + Vector2(r * 0.86, -r * 0.05), c + Vector2(0, r * 0.85))
		"coins", "wallet":
			for k in range(3):
				var y := r * 0.55 - k * r * 0.5
				_arc(c + Vector2(0, y), r * 0.75, PI, TAU)
				_arc(c + Vector2(0, y), r * 0.75, 0, PI)
		"plus":
			_l(c + Vector2(-r * 0.6, 0), c + Vector2(r * 0.6, 0))
			_l(c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.6))
		"minus":
			_l(c + Vector2(-r * 0.6, 0), c + Vector2(r * 0.6, 0))
		"close":
			_l(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6))
			_l(c + Vector2(r * 0.6, -r * 0.6), c + Vector2(-r * 0.6, r * 0.6))
		"check":
			_poly([c + Vector2(-r * 0.6, 0), c + Vector2(-r * 0.15, r * 0.45), c + Vector2(r * 0.65, -r * 0.45)])
		"circle_check":
			_arc(c, r, 0, TAU)
			_poly([c + Vector2(-r * 0.45, 0), c + Vector2(-r * 0.1, r * 0.35), c + Vector2(r * 0.5, -r * 0.35)])
		"circle":
			_arc(c, r * 0.8, 0, TAU)
		"lock", "unlock":
			var body := StyleBoxFlat.new()
			body.draw_center = false
			body.set_border_width_all(int(width))
			body.border_color = color
			body.set_corner_radius_all(3)
			draw_style_box(body, Rect2(c + Vector2(-r * 0.7, -r * 0.1), Vector2(r * 1.4, r * 1.1)))
			if kind == "lock":
				_arc(c + Vector2(0, -r * 0.1), r * 0.45, PI, TAU)
			else:
				_arc(c + Vector2(r * 0.35, -r * 0.25), r * 0.4, PI * 1.05, PI * 2.0)
		"search", "scan":
			_arc(c + Vector2(-r * 0.15, -r * 0.15), r * 0.6, 0, TAU)
			_l(c + Vector2(r * 0.3, r * 0.3), c + Vector2(r * 0.85, r * 0.85))
		"briefcase":
			var bb := StyleBoxFlat.new()
			bb.draw_center = false
			bb.set_border_width_all(int(width))
			bb.border_color = color
			bb.set_corner_radius_all(3)
			draw_style_box(bb, Rect2(c + Vector2(-r, -r * 0.45), Vector2(r * 2, r * 1.35)))
			_poly([c + Vector2(-r * 0.35, -r * 0.45), c + Vector2(-r * 0.35, -r * 0.8), c + Vector2(r * 0.35, -r * 0.8), c + Vector2(r * 0.35, -r * 0.45)])
			_l(c + Vector2(-r, r * 0.1), c + Vector2(r, r * 0.1))
		"chat":
			var cb := StyleBoxFlat.new()
			cb.draw_center = false
			cb.set_border_width_all(int(width))
			cb.border_color = color
			cb.set_corner_radius_all(int(r * 0.45))
			draw_style_box(cb, Rect2(c + Vector2(-r, -r * 0.8), Vector2(r * 2, r * 1.35)))
			_poly([c + Vector2(-r * 0.4, r * 0.55), c + Vector2(-r * 0.55, r), c + Vector2(0, r * 0.55)])
			for k in range(3):
				draw_circle(c + Vector2(-r * 0.45 + k * r * 0.45, -r * 0.12), width * 0.8, color)
		"speaker", "speaker_off":
			_poly([c + Vector2(-r * 0.9, -r * 0.3), c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(r * 0.1, -r * 0.8), c + Vector2(r * 0.1, r * 0.8), c + Vector2(-r * 0.4, r * 0.3), c + Vector2(-r * 0.9, r * 0.3), c + Vector2(-r * 0.9, -r * 0.3)])
			if kind == "speaker":
				_arc(c + Vector2(r * 0.1, 0), r * 0.5, -PI * 0.3, PI * 0.3)
				_arc(c + Vector2(r * 0.1, 0), r * 0.85, -PI * 0.3, PI * 0.3)
			else:
				_l(c + Vector2(r * 0.4, -r * 0.35), c + Vector2(r * 0.95, r * 0.35))
				_l(c + Vector2(r * 0.95, -r * 0.35), c + Vector2(r * 0.4, r * 0.35))
		"gear":
			_arc(c, r * 0.55, 0, TAU)
			_arc(c, r * 0.2, 0, TAU)
			for k in range(8):
				var a := k * TAU / 8.0
				_l(c + Vector2(cos(a), sin(a)) * r * 0.62, c + Vector2(cos(a), sin(a)) * r * 0.95)
		"pause":
			_l(c + Vector2(-r * 0.35, -r * 0.7), c + Vector2(-r * 0.35, r * 0.7))
			_l(c + Vector2(r * 0.35, -r * 0.7), c + Vector2(r * 0.35, r * 0.7))
		"play":
			_poly([c + Vector2(-r * 0.45, -r * 0.75), c + Vector2(r * 0.7, 0), c + Vector2(-r * 0.45, r * 0.75), c + Vector2(-r * 0.45, -r * 0.75)])
		"back":
			_poly([c + Vector2(r * 0.3, -r * 0.7), c + Vector2(-r * 0.4, 0), c + Vector2(r * 0.3, r * 0.7)])
		"next":
			_poly([c + Vector2(-r * 0.3, -r * 0.7), c + Vector2(r * 0.4, 0), c + Vector2(-r * 0.3, r * 0.7)])
		"door", "exit":
			_poly([c + Vector2(r * 0.2, -r), c + Vector2(-r * 0.8, -r), c + Vector2(-r * 0.8, r), c + Vector2(r * 0.2, r)])
			_l(c + Vector2(-r * 0.2, 0), c + Vector2(r, 0))
			_poly([c + Vector2(r * 0.6, -r * 0.4), c + Vector2(r, 0), c + Vector2(r * 0.6, r * 0.4)])
		"house":
			_poly([c + Vector2(-r, -r * 0.05), c + Vector2(0, -r * 0.9), c + Vector2(r, -r * 0.05)])
			_poly([c + Vector2(-r * 0.7, -r * 0.3), c + Vector2(-r * 0.7, r * 0.9), c + Vector2(r * 0.7, r * 0.9), c + Vector2(r * 0.7, -r * 0.3)])
		"handshake":
			_poly([c + Vector2(-r, -r * 0.1), c + Vector2(-r * 0.4, -r * 0.5), c + Vector2(r * 0.1, -r * 0.15), c + Vector2(-r * 0.15, r * 0.25), c + Vector2(r * 0.35, r * 0.5), c + Vector2(r, 0)])
			_l(c + Vector2(r * 0.1, -r * 0.15), c + Vector2(r * 0.5, -r * 0.5))
		"gift":
			var g := StyleBoxFlat.new()
			g.draw_center = false
			g.set_border_width_all(int(width))
			g.border_color = color
			g.set_corner_radius_all(2)
			draw_style_box(g, Rect2(c + Vector2(-r * 0.8, -r * 0.25), Vector2(r * 1.6, r * 1.15)))
			_l(c + Vector2(0, -r * 0.25), c + Vector2(0, r * 0.9))
			_arc(c + Vector2(-r * 0.28, -r * 0.45), r * 0.25, PI * 0.2, PI * 1.9)
			_arc(c + Vector2(r * 0.28, -r * 0.45), r * 0.25, PI * 1.1, PI * 2.8)
		"trophy":
			_poly([c + Vector2(-r * 0.55, -r * 0.85), c + Vector2(r * 0.55, -r * 0.85), c + Vector2(r * 0.5, -r * 0.2), c + Vector2(r * 0.2, r * 0.18), c + Vector2(-r * 0.2, r * 0.18), c + Vector2(-r * 0.5, -r * 0.2), c + Vector2(-r * 0.55, -r * 0.85)])
			_arc(c + Vector2(-r * 0.62, -r * 0.45), r * 0.3, PI * 0.5, PI * 1.5)
			_arc(c + Vector2(r * 0.62, -r * 0.45), r * 0.3, -PI * 0.5, PI * 0.5)
			_l(c + Vector2(0, r * 0.18), c + Vector2(0, r * 0.62))
			_poly([c + Vector2(-r * 0.45, r * 0.9), c + Vector2(-r * 0.35, r * 0.62), c + Vector2(r * 0.35, r * 0.62), c + Vector2(r * 0.45, r * 0.9), c + Vector2(-r * 0.45, r * 0.9)])
		"target":
			_arc(c, r, 0, TAU)
			_arc(c, r * 0.55, 0, TAU)
			draw_circle(c, r * 0.14, color)
		"bulb":
			_arc(c + Vector2(0, -r * 0.2), r * 0.6, PI * 0.8, PI * 2.2)
			_l(c + Vector2(-r * 0.3, r * 0.45), c + Vector2(r * 0.3, r * 0.45))
			_l(c + Vector2(-r * 0.22, r * 0.8), c + Vector2(r * 0.22, r * 0.8))
		"map":
			_poly([c + Vector2(-r, -r * 0.7), c + Vector2(-r * 0.33, -r), c + Vector2(r * 0.33, -r * 0.7), c + Vector2(r, -r), c + Vector2(r, r * 0.7), c + Vector2(r * 0.33, r), c + Vector2(-r * 0.33, r * 0.7), c + Vector2(-r, r), c + Vector2(-r, -r * 0.7)])
			_l(c + Vector2(-r * 0.33, -r), c + Vector2(-r * 0.33, r * 0.7))
			_l(c + Vector2(r * 0.33, -r * 0.7), c + Vector2(r * 0.33, r))
		"refresh", "replay":
			_arc(c, r * 0.75, -PI * 0.2, PI * 1.5)
			_poly([c + Vector2(r * 0.5, -r * 0.9), c + Vector2(r * 0.65, -r * 0.4), c + Vector2(r * 0.15, -r * 0.35)])
		"send":
			_poly([c + Vector2(-r, -r * 0.1), c + Vector2(r, -r * 0.85), c + Vector2(r * 0.3, r * 0.9), c + Vector2(-r * 0.05, r * 0.1), c + Vector2(-r, -r * 0.1)])
			_l(c + Vector2(-r * 0.05, r * 0.1), c + Vector2(r, -r * 0.85))
		"trash":
			_l(c + Vector2(-r * 0.85, -r * 0.6), c + Vector2(r * 0.85, -r * 0.6))
			_poly([c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(-r * 0.45, r * 0.9), c + Vector2(r * 0.45, r * 0.9), c + Vector2(r * 0.6, -r * 0.6)])
			_poly([c + Vector2(-r * 0.25, -r * 0.6), c + Vector2(-r * 0.2, -r * 0.9), c + Vector2(r * 0.2, -r * 0.9), c + Vector2(r * 0.25, -r * 0.6)])
		"info":
			_arc(c, r, 0, TAU)
			_l(c + Vector2(0, -r * 0.1), c + Vector2(0, r * 0.5))
			draw_circle(c + Vector2(0, -r * 0.45), width * 0.8, color)
		"question":
			_arc(c, r, 0, TAU)
			_arc(c + Vector2(0, -r * 0.25), r * 0.32, PI * 1.1, PI * 2.4)
			_l(c + Vector2(r * 0.05, r * 0.05), c + Vector2(0, r * 0.25))
			draw_circle(c + Vector2(0, r * 0.55), width * 0.8, color)
		"flag":
			_l(c + Vector2(-r * 0.7, -r), c + Vector2(-r * 0.7, r))
			_poly([c + Vector2(-r * 0.7, -r * 0.9), c + Vector2(r * 0.8, -r * 0.55), c + Vector2(-r * 0.7, -r * 0.15)])
		"copy":
			var a := StyleBoxFlat.new()
			a.draw_center = false
			a.set_border_width_all(int(width))
			a.border_color = color
			a.set_corner_radius_all(3)
			draw_style_box(a, Rect2(c + Vector2(-r * 0.4, -r * 0.4), Vector2(r * 1.3, r * 1.3)))
			_poly([c + Vector2(-r * 0.75, r * 0.5), c + Vector2(-r * 0.75, -r * 0.85), c + Vector2(r * 0.5, -r * 0.85)])
		"export", "download":
			_l(c + Vector2(0, -r), c + Vector2(0, r * 0.35))
			_poly([c + Vector2(-r * 0.45, -r * 0.05), c + Vector2(0, r * 0.4), c + Vector2(r * 0.45, -r * 0.05)])
			_poly([c + Vector2(-r * 0.9, r * 0.3), c + Vector2(-r * 0.9, r * 0.9), c + Vector2(r * 0.9, r * 0.9), c + Vector2(r * 0.9, r * 0.3)])
		"spark":
			_l(c + Vector2(0, -r), c + Vector2(0, r))
			_l(c + Vector2(-r, 0), c + Vector2(r, 0))
			_l(c + Vector2(-r * 0.45, -r * 0.45), c + Vector2(r * 0.45, r * 0.45))
			_l(c + Vector2(r * 0.45, -r * 0.45), c + Vector2(-r * 0.45, r * 0.45))
		"secretary":
			_arc(c + Vector2(0, -r * 0.35), r * 0.38, 0, TAU)
			_arc(c + Vector2(0, r * 1.05), r * 0.85, PI * 1.15, PI * 1.85)
			_l(c + Vector2(r * 0.55, -r * 0.6), c + Vector2(r * 0.9, -r * 0.95))
		_:
			_arc(c, r * 0.6, 0, TAU)
