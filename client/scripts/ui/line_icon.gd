@tool
extends Control
## 2px rounded line icons for the training hall (drawn, no image files).
## kind: user, users, chat_user, robot, doc, chart, chevron_r, chevron_l, chevron_d, speaker, speaker_off, question,
## replay, door, search, briefcase, doc_check, lock, unlock, gear, book, check, calculator,
## shield, gauge, stamp, house, wallet, expand, compress

var kind := "user"
var color := Color("#F3F0E7")
var width := 2.0


func _init(icon_kind := "user", icon_color := Color("#F3F0E7"), line_width := 2.0) -> void:
	kind = icon_kind
	color = icon_color
	width = line_width
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _l(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, color, width, true)
	draw_circle(a, width * 0.5, color)
	draw_circle(b, width * 0.5, color)


func _arc(c: Vector2, r: float, a0: float, a1: float) -> void:
	draw_arc(c, r, a0, a1, 32, color, width, true)


func _round_rect(r: Rect2, rad: float) -> void:
	_l(r.position + Vector2(rad, 0), Vector2(r.end.x - rad, r.position.y))
	_l(Vector2(r.end.x, r.position.y + rad), Vector2(r.end.x, r.end.y - rad))
	_l(Vector2(r.end.x - rad, r.end.y), Vector2(r.position.x + rad, r.end.y))
	_l(Vector2(r.position.x, r.end.y - rad), r.position + Vector2(0, rad))
	_arc(r.position + Vector2(rad, rad), rad, PI, PI * 1.5)
	_arc(Vector2(r.end.x - rad, r.position.y + rad), rad, PI * 1.5, TAU)
	_arc(r.end - Vector2(rad, rad), rad, 0, PI * 0.5)
	_arc(Vector2(r.position.x + rad, r.end.y - rad), rad, PI * 0.5, PI)


func _person(c: Vector2, s: float) -> void:
	_arc(c + Vector2(0, -s * 0.32), s * 0.2, 0, TAU)
	_arc(c + Vector2(0, s * 0.42), s * 0.36, PI * 1.05, PI * 1.95)
	_l(c + Vector2(-s * 0.36, s * 0.42), c + Vector2(s * 0.36, s * 0.42))


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := o + Vector2(s, s) * 0.5
	match kind:
		"user":
			_person(c, s * 0.9)
		"users":
			_person(c + Vector2(0, s * 0.02), s * 0.62)
			_person(c + Vector2(-s * 0.3, s * 0.08), s * 0.5)
			_person(c + Vector2(s * 0.3, s * 0.08), s * 0.5)
		"chat_user":
			_person(c + Vector2(-s * 0.16, s * 0.12), s * 0.62)
			var b := Rect2(o + Vector2(s * 0.5, s * 0.06), Vector2(s * 0.44, s * 0.32))
			_round_rect(b, s * 0.07)
			_l(Vector2(b.position.x + s * 0.1, b.end.y), Vector2(b.position.x + s * 0.04, b.end.y + s * 0.1))
		"robot":
			var head := Rect2(o + Vector2(s * 0.2, s * 0.3), Vector2(s * 0.6, s * 0.48))
			_round_rect(head, s * 0.1)
			_l(c + Vector2(0, -s * 0.2), c + Vector2(0, -s * 0.32))
			draw_circle(c + Vector2(0, -s * 0.36), width * 1.2, color)
			draw_circle(c + Vector2(-s * 0.13, s * 0.06), width * 1.3, color)
			draw_circle(c + Vector2(s * 0.13, s * 0.06), width * 1.3, color)
			_l(c + Vector2(-s * 0.36, s * 0.04), c + Vector2(-s * 0.36, s * 0.16))
			_l(c + Vector2(s * 0.36, s * 0.04), c + Vector2(s * 0.36, s * 0.16))
		"doc":
			var x0 := o.x + s * 0.24
			var x1 := o.x + s * 0.76
			var y0 := o.y + s * 0.12
			var y1 := o.y + s * 0.88
			var fold := s * 0.16
			_l(Vector2(x0, y0), Vector2(x1 - fold, y0))
			_l(Vector2(x1 - fold, y0), Vector2(x1, y0 + fold))
			_l(Vector2(x1, y0 + fold), Vector2(x1, y1))
			_l(Vector2(x1, y1), Vector2(x0, y1))
			_l(Vector2(x0, y1), Vector2(x0, y0))
			for k in range(3):
				var y := y0 + s * (0.3 + k * 0.14)
				_l(Vector2(x0 + s * 0.1, y), Vector2(x1 - s * (0.1 if k < 2 else 0.2), y))
		"chart":
			var base := o.y + s * 0.84
			_l(Vector2(o.x + s * 0.14, base), Vector2(o.x + s * 0.86, base))
			var hs := [0.26, 0.42, 0.58, 0.72]
			for k in range(4):
				var x := o.x + s * (0.24 + k * 0.17)
				_l(Vector2(x, base - s * 0.08), Vector2(x, base - s * float(hs[k])))
		"chevron_r":
			_l(c + Vector2(-s * 0.14, -s * 0.28), c + Vector2(s * 0.14, 0))
			_l(c + Vector2(s * 0.14, 0), c + Vector2(-s * 0.14, s * 0.28))
		"chevron_d":
			_l(c + Vector2(-s * 0.26, -s * 0.12), c + Vector2(0, s * 0.14))
			_l(c + Vector2(0, s * 0.14), c + Vector2(s * 0.26, -s * 0.12))
		"speaker":
			var pts := PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.12), c + Vector2(-s * 0.18, -s * 0.12), c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.3), c + Vector2(-s * 0.18, s * 0.12), c + Vector2(-s * 0.36, s * 0.12), c + Vector2(-s * 0.36, -s * 0.12)])
			draw_polyline(pts, color, width, true)
			_arc(c + Vector2(s * 0.02, 0), s * 0.2, -PI * 0.3, PI * 0.3)
			_arc(c + Vector2(s * 0.02, 0), s * 0.36, -PI * 0.3, PI * 0.3)
		"question":
			_arc(c, s * 0.44, 0, TAU)
			_arc(c + Vector2(0, -s * 0.1), s * 0.14, PI * 1.05, PI * 2.3)
			_l(c + Vector2(s * 0.03, s * 0.02), c + Vector2(0, s * 0.1))
			draw_circle(c + Vector2(0, s * 0.24), width * 0.9, color)
		"replay":
			_arc(c, s * 0.34, -PI * 0.1, PI * 1.35)
			var tip := c + Vector2(cos(-PI * 0.1), sin(-PI * 0.1)) * s * 0.34
			_l(tip, tip + Vector2(-s * 0.2, -s * 0.06))
			_l(tip, tip + Vector2(s * 0.04, -s * 0.2))
		"door":
			_round_rect(Rect2(o + Vector2(s * 0.22, s * 0.12), Vector2(s * 0.42, s * 0.76)), s * 0.05)
			_l(c + Vector2(s * 0.3, 0), c + Vector2(s * 0.46, 0))
			_l(c + Vector2(s * 0.38, -s * 0.08), c + Vector2(s * 0.46, 0))
			_l(c + Vector2(s * 0.38, s * 0.08), c + Vector2(s * 0.46, 0))
		"chevron_l":
			_l(c + Vector2(s * 0.14, -s * 0.28), c + Vector2(-s * 0.14, 0))
			_l(c + Vector2(-s * 0.14, 0), c + Vector2(s * 0.14, s * 0.28))
		"speaker_off":
			var sp := PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.12), c + Vector2(-s * 0.18, -s * 0.12), c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.3), c + Vector2(-s * 0.18, s * 0.12), c + Vector2(-s * 0.36, s * 0.12), c + Vector2(-s * 0.36, -s * 0.12)])
			draw_polyline(sp, color, width, true)
			_l(c + Vector2(s * 0.14, -s * 0.12), c + Vector2(s * 0.38, s * 0.12))
			_l(c + Vector2(s * 0.38, -s * 0.12), c + Vector2(s * 0.14, s * 0.12))
		"search":
			_arc(c + Vector2(-s * 0.08, -s * 0.08), s * 0.26, 0, TAU)
			_l(c + Vector2(s * 0.12, s * 0.12), c + Vector2(s * 0.36, s * 0.36))
		"briefcase":
			_round_rect(Rect2(o + Vector2(s * 0.12, s * 0.32), Vector2(s * 0.76, s * 0.52)), s * 0.07)
			_round_rect(Rect2(o + Vector2(s * 0.36, s * 0.16), Vector2(s * 0.28, s * 0.16)), s * 0.04)
			_l(c + Vector2(-s * 0.38, s * 0.04), c + Vector2(s * 0.38, s * 0.04))
		"doc_check":
			var x0 := o.x + s * 0.22
			var x1 := o.x + s * 0.72
			var y0 := o.y + s * 0.1
			var y1 := o.y + s * 0.86
			var fold := s * 0.14
			_l(Vector2(x0, y0), Vector2(x1 - fold, y0))
			_l(Vector2(x1 - fold, y0), Vector2(x1, y0 + fold))
			_l(Vector2(x1, y0 + fold), Vector2(x1, y0 + s * 0.4))
			_l(Vector2(x0, y1), Vector2(x0 + s * 0.3, y1))
			_l(Vector2(x0, y1), Vector2(x0, y0))
			_l(Vector2(x0 + s * 0.1, y0 + s * 0.24), Vector2(x1 - s * 0.12, y0 + s * 0.24))
			_l(Vector2(x0 + s * 0.1, y0 + s * 0.38), Vector2(x1 - s * 0.2, y0 + s * 0.38))
			var cc := Vector2(o.x + s * 0.68, o.y + s * 0.7)
			_arc(cc, s * 0.18, 0, TAU)
			_l(cc + Vector2(-s * 0.08, 0), cc + Vector2(-s * 0.02, s * 0.06))
			_l(cc + Vector2(-s * 0.02, s * 0.06), cc + Vector2(s * 0.09, -s * 0.06))
		"lock", "unlock":
			_round_rect(Rect2(o + Vector2(s * 0.22, s * 0.44), Vector2(s * 0.56, s * 0.42)), s * 0.07)
			if kind == "lock":
				# Closed shackle resting on the body
				_arc(c + Vector2(0, -s * 0.06), s * 0.18, PI, TAU)
			else:
				# Open shackle: left leg in the body, right leg lifted free
				_arc(c + Vector2(0, -s * 0.2), s * 0.18, PI, TAU)
				_l(c + Vector2(-s * 0.18, -s * 0.2), c + Vector2(-s * 0.18, -s * 0.06))
			draw_circle(c + Vector2(0, s * 0.18), width * 1.1, color)
		"gear":
			_arc(c, s * 0.16, 0, TAU)
			for k in range(8):
				var a := TAU * k / 8.0
				_l(c + Vector2(cos(a), sin(a)) * s * 0.28, c + Vector2(cos(a), sin(a)) * s * 0.4)
			_arc(c, s * 0.28, 0, TAU)
		"book":
			_l(c + Vector2(0, -s * 0.26), c + Vector2(0, s * 0.32))
			_l(c + Vector2(0, -s * 0.26), c + Vector2(-s * 0.4, -s * 0.32))
			_l(c + Vector2(-s * 0.4, -s * 0.32), c + Vector2(-s * 0.4, s * 0.26))
			_l(c + Vector2(-s * 0.4, s * 0.26), c + Vector2(0, s * 0.32))
			_l(c + Vector2(0, -s * 0.26), c + Vector2(s * 0.4, -s * 0.32))
			_l(c + Vector2(s * 0.4, -s * 0.32), c + Vector2(s * 0.4, s * 0.26))
			_l(c + Vector2(s * 0.4, s * 0.26), c + Vector2(0, s * 0.32))
		"check":
			_l(c + Vector2(-s * 0.26, 0), c + Vector2(-s * 0.06, s * 0.2))
			_l(c + Vector2(-s * 0.06, s * 0.2), c + Vector2(s * 0.3, -s * 0.22))
		"calculator":
			_round_rect(Rect2(o + Vector2(s * 0.24, s * 0.1), Vector2(s * 0.52, s * 0.8)), s * 0.06)
			_round_rect(Rect2(o + Vector2(s * 0.32, s * 0.18), Vector2(s * 0.36, s * 0.16)), s * 0.03)
			for row in range(3):
				for col in range(3):
					draw_circle(o + Vector2(s * (0.36 + col * 0.14), s * (0.46 + row * 0.13)), width * 0.9, color)
		"shield":
			var sh := PackedVector2Array([c + Vector2(0, -s * 0.4), c + Vector2(s * 0.32, -s * 0.28), c + Vector2(s * 0.28, s * 0.1), c + Vector2(0, s * 0.4), c + Vector2(-s * 0.28, s * 0.1), c + Vector2(-s * 0.32, -s * 0.28), c + Vector2(0, -s * 0.4)])
			draw_polyline(sh, color, width, true)
			_l(c + Vector2(-s * 0.12, 0), c + Vector2(-s * 0.02, s * 0.1))
			_l(c + Vector2(-s * 0.02, s * 0.1), c + Vector2(s * 0.14, -s * 0.1))
		"gauge":
			_arc(c + Vector2(0, s * 0.12), s * 0.38, PI, TAU)
			_l(c + Vector2(-s * 0.38, s * 0.12), c + Vector2(s * 0.38, s * 0.12))
			_l(c + Vector2(0, s * 0.12), c + Vector2(s * 0.2, -s * 0.12))
			draw_circle(c + Vector2(0, s * 0.12), width * 1.2, color)
		"stamp":
			_round_rect(Rect2(o + Vector2(s * 0.2, s * 0.62), Vector2(s * 0.6, s * 0.14)), s * 0.03)
			_l(c + Vector2(-s * 0.1, s * 0.12), c + Vector2(-s * 0.1, -s * 0.06))
			_l(c + Vector2(s * 0.1, s * 0.12), c + Vector2(s * 0.1, -s * 0.06))
			_arc(c + Vector2(0, -s * 0.2), s * 0.15, 0, TAU)
			_l(c + Vector2(-s * 0.3, s * 0.42), c + Vector2(s * 0.3, s * 0.42))
		"house":
			var roof := PackedVector2Array([c + Vector2(-s * 0.4, -s * 0.02), c + Vector2(0, -s * 0.38), c + Vector2(s * 0.4, -s * 0.02)])
			draw_polyline(roof, color, width, true)
			_l(c + Vector2(-s * 0.3, -s * 0.1), c + Vector2(-s * 0.3, s * 0.36))
			_l(c + Vector2(s * 0.3, -s * 0.1), c + Vector2(s * 0.3, s * 0.36))
			_l(c + Vector2(-s * 0.3, s * 0.36), c + Vector2(s * 0.3, s * 0.36))
			_round_rect(Rect2(c + Vector2(-s * 0.08, s * 0.1), Vector2(s * 0.16, s * 0.26)), s * 0.02)
		"wallet":
			_round_rect(Rect2(o + Vector2(s * 0.14, s * 0.28), Vector2(s * 0.72, s * 0.5)), s * 0.07)
			_l(o + Vector2(s * 0.22, s * 0.28), o + Vector2(s * 0.62, s * 0.16))
			_round_rect(Rect2(o + Vector2(s * 0.56, s * 0.44), Vector2(s * 0.3, s * 0.18)), s * 0.05)
			draw_circle(o + Vector2(s * 0.66, s * 0.53), width, color)
		"expand", "compress":
			# Four corner brackets: pointing out (enter fullscreen) or in (leave it)
			var a := s * 0.34
			var b := s * 0.14
			for d: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var corner := c + d * (a if kind == "expand" else b)
				var arm := -d.x * (a - b) if kind == "expand" else d.x * (a - b)
				var arm_y := -d.y * (a - b) if kind == "expand" else d.y * (a - b)
				_l(corner, corner + Vector2(arm, 0))
				_l(corner, corner + Vector2(0, arm_y))
