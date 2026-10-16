@tool
extends Control
## Aerial HQ map board: cinematic night aerial of Taipei with 101, the 24 stations as labelled chips
## (icon + number + name) on a dashed loop. The current station is the large gold chip; the main
## action button is docked right under it (see get_inner_rect). Positions are computed from this
## control's own size every frame, so chips stay on the route at any window size.
## Same API as board.gd / board_hq.gd: set_data / freeze_movement / get_inner_rect / current_index.

const ToolIcon := preload("res://scripts/ui/board_hq.gd").ToolIcon
## A clean aerial without text dropped here replaces the default map
const MAP_PATHS := ["res://assets/hq/hq_aerial.webp", "res://assets/unified/board.webp"]
## Image point kept near the board centre (101 sits right of centre in the default map)
const FOCUS := Vector2(0.6, 0.52)

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
const C_RED := Color("#D9685F")
const AHEAD := 6

var tiles: Array = []
var players: Array = []
var territory: Dictionary = {}
var current_id := ""
## Line under the title (round / whose turn), set by game.gd
var title_sub := ""
var _shown: Dictionary = {}
var _freeze_timer := 0.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _hover := -1
var _selected := -1
var _pulse := 0.0
var _map: Texture2D
var _tools: HBoxContainer
var _chips: Array = []
var _dots: Array = []
var _img_at := Vector2.ZERO
var _img_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	for path: String in MAP_PATHS:
		if ResourceLoader.exists(path):
			_map = load(path)
			break
	_tools = HBoxContainer.new()
	_tools.add_theme_constant_override("separation", 6)
	add_child(_tools)
	for spec: Array in [["in", "放大"], ["out", "縮小"], ["reset", "復位"]]:
		var b: Button = ToolIcon.new(spec[0], spec[1])
		b.pressed.connect(_tool_action.bind(spec[0]))
		_tools.add_child(b)
	resized.connect(_layout)
	mouse_exited.connect(func(): _hover = -1)
	_layout()


func _layout() -> void:
	if _tools == null:
		return
	_tools.reset_size()
	_tools.position = Vector2(size.x - _tools.size.x - 14, 14)
	_clamp_pan()


# ───────── Public API ─────────

func set_data(board: Array, ps: Array, current: String, terr: Dictionary = {}) -> void:
	tiles = board.duplicate(true)
	players = ps
	current_id = current
	territory = terr
	var live_ids: Array = []
	for p: Dictionary in ps:
		var id := str(p.get("id", ""))
		live_ids.append(id)
		if not _shown.has(id):
			_shown[id] = float(p.get("pos", 0))
	for id: String in _shown.keys():
		if not live_ids.has(id):
			_shown.erase(id)


func freeze_movement(duration: float) -> void:
	_freeze_timer = maxf(duration, 0.0)


func current_index() -> int:
	return int(floorf(float(_shown.get(current_id, 0.0)) + 0.001)) % 24


## Dock for the main action button: just under the current station chip, kept inside the board
func get_inner_rect() -> Rect2:
	var w := 220.0
	var h := 56.0
	if _chips.size() != 24:
		return Rect2(Vector2((size.x - w) * 0.5, size.y - h - 24), Vector2(w, h))
	var chip: Rect2 = _chips[current_index()]
	# Below the chip on the upper half of the loop, above it (towards the map centre) on the lower half
	var lower := chip.get_center().y > size.y * 0.5
	var at := Vector2(chip.get_center().x - w * 0.5, chip.position.y - h - 10 if lower else chip.end.y + 10)
	if at.y < 8 or at.y + h > size.y - 8:
		at.y = chip.end.y + 10 if lower else chip.position.y - h - 10
	at.x = clampf(at.x, 8, size.x - w - 8)
	return Rect2(at, Vector2(w, h))


## View of the map around a station, for the task card picture
func station_crop(i: int) -> Texture2D:
	if _map == null or _dots.size() != 24:
		return _map
	var img := _map.get_size()
	var center: Vector2 = ((_dots[i] as Vector2) - _img_at) / maxf(0.001, _img_scale)
	var region_size := Vector2(img.x * 0.34, img.x * 0.34 / 3.0)
	var region := Rect2(center - region_size * 0.5, region_size)
	region.position = region.position.clamp(Vector2.ZERO, img - region_size)
	var atlas := AtlasTexture.new()
	atlas.atlas = _map
	atlas.region = region
	return atlas


# ───────── Geometry ─────────

func _compact() -> bool:
	return size.x < 520.0


## Loop as a rounded rectangle in board space (leaves the top-left for the title)
func _loop_rect() -> Rect2:
	var top := 0.24 if not _compact() else 0.16
	return Rect2(size * Vector2(0.1, top), size * Vector2(0.8, 0.8 - top))


func _loop_points() -> PackedVector2Array:
	var r := _loop_rect()
	var rad := minf(r.size.x, r.size.y) * 0.16
	var pts := PackedVector2Array()
	# Start at bottom centre and go left (clockwise on screen): bottom, left, top, right
	pts.append(Vector2(r.get_center().x, r.end.y))
	var corners := [
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
		[Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
	]
	for c: Array in corners:
		for k in range(9):
			var a: float = c[1] + PI * 0.5 * k / 8.0
			pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	pts.append(Vector2(r.get_center().x, r.end.y))
	return pts


func _to_view(p: Vector2) -> Vector2:
	return (p - size * 0.5) * _zoom + size * 0.5 + _pan


## Point at distance fraction t (0..1) along the loop
func _along(pts: PackedVector2Array, lengths: PackedFloat32Array, total: float, t: float) -> Vector2:
	var d := fposmod(t, 1.0) * total
	for i in range(lengths.size()):
		if d <= lengths[i] or i == lengths.size() - 1:
			var prev := lengths[i - 1] if i > 0 else 0.0
			var seg := maxf(0.001, lengths[i] - prev)
			return pts[i].lerp(pts[i + 1], clampf((d - prev) / seg, 0, 1))
	return pts[0]


# ───────── Input ─────────

func _tool_action(kind: String) -> void:
	match kind:
		"in": _set_zoom(_zoom * 1.25)
		"out": _set_zoom(_zoom / 1.25)
		"reset":
			_zoom = 1.0
			_pan = Vector2.ZERO
			_selected = -1


func _set_zoom(z: float) -> void:
	var old := _zoom
	_zoom = clampf(z, 1.0, 2.5)
	_pan *= _zoom / old
	_clamp_pan()


func _clamp_pan() -> void:
	var limit := size * (_zoom - 1.0) * 0.5
	_pan = _pan.clamp(-limit, limit)


func _chip_at(p: Vector2) -> int:
	for i in range(_chips.size()):
		if (_chips[i] as Rect2).grow(4).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT) and _zoom > 1.0:
			_pan += event.relative
			_clamp_pan()
			accept_event()
		var h := _chip_at(event.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom * 1.1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom / 1.1)
				accept_event()
			MOUSE_BUTTON_LEFT:
				var t := _chip_at(event.position)
				_selected = -1 if t == _selected else t


func _process(delta: float) -> void:
	_pulse += delta
	_freeze_timer = maxf(0.0, _freeze_timer - delta)
	for p: Dictionary in players:
		var id := str(p.get("id", ""))
		var before: float = _shown.get(id, float(p.get("pos", 0)))
		var diff := fposmod(float(p.get("pos", 0)) - before, 24.0)
		if _freeze_timer <= 0 and diff > 0.001:
			var after := fposmod(before + minf(diff, delta * 6.0), 24.0)
			_shown[id] = after
			if int(floorf(before)) != int(floorf(after)) and id == current_id and not Engine.is_editor_hint():
				Sound.play("step", self)
	queue_redraw()


# ───────── Drawing ─────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	if _map:
		var img := _map.get_size()
		var s := maxf(size.x / img.x, size.y / img.y) * 1.08 * _zoom
		var at := size * 0.5 - img * FOCUS * s + _pan
		at = at.clamp(size - img * s, Vector2.ZERO)
		_img_at = at
		_img_scale = s
		draw_texture_rect(_map, Rect2(at, img * s), false)
	# Gentle grade toward the brand palette and a vignette so chips read clearly
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.16, 0.14, 0.22))
	var font := get_theme_default_font()
	if tiles.size() != 24:
		_draw_title(font)
		return

	var raw := _loop_points()
	var pts := PackedVector2Array()
	for p in raw:
		pts.append(_to_view(p))
	var lengths := PackedFloat32Array()
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
		lengths.append(total)
	# Dashed route
	var dash := 9.0
	var gap := 7.0
	var d := 0.0
	while d < total:
		var a := _along(pts, lengths, total, d / total)
		var b := _along(pts, lengths, total, minf(d + dash, total) / total)
		draw_line(a, b, Color(1, 1, 1, 0.6), 2.0, true)
		d += dash + gap

	var cur := current_index() if not players.is_empty() else -1
	var dots: Array = []
	for i in range(24):
		dots.append(_along(pts, lengths, total, float(i) / 24.0))
	_dots = dots
	_chips.resize(24)
	var r := _loop_rect()
	var compact := _compact()
	# Chips: horizontal edges alternate inside / outside, vertical edges sit inside the loop
	for i in range(24):
		var dot: Vector2 = dots[i]
		var tname := str((tiles[i] as Dictionary).get("name", ""))
		var is_cur := i == cur
		var label := "%02d %s" % [i, tname] if (not compact or is_cur) else "%02d" % i
		var fs := 16 if is_cur else (12 if not compact else 11)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon := 18.0 if is_cur else 14.0
		var w := tw + icon + 26.0
		var h := 40.0 if is_cur else 28.0
		var rel := Vector2((dot.x - _to_view(r.position).x) / maxf(1.0, r.size.x * _zoom), (dot.y - _to_view(r.position).y) / maxf(1.0, r.size.y * _zoom))
		var chip: Rect2
		if rel.x < 0.08:
			chip = Rect2(dot + Vector2(14, -h * 0.5), Vector2(w, h))
		elif rel.x > 0.92:
			chip = Rect2(dot + Vector2(-14 - w, -h * 0.5), Vector2(w, h))
		else:
			var up := (i % 2 == 0) == (rel.y > 0.5)
			chip = Rect2(dot + Vector2(-w * 0.5, -h - 14 if up else 14), Vector2(w, h))
		chip.position = chip.position.clamp(Vector2(4, 4), size - chip.size - Vector2(4, 4))
		_chips[i] = chip
	# Draw non-current chips first so the current one sits on top
	var order: Array = range(24)
	if cur >= 0:
		order.erase(cur)
		order.append(cur)
	for i: int in order:
		var steps := posmod(i - cur, 24) if cur >= 0 else 24
		var emphasis := i == cur or i == _hover or i == _selected
		var alpha := 1.0 if emphasis or steps <= AHEAD else 0.72
		_draw_chip(font, i, _chips[i], dots[i], i == cur, steps > 0 and steps <= AHEAD, alpha, compact)
	_draw_pawns(pts, lengths, total)
	_draw_title(font)


## Title block drawn last, on a soft backdrop, so station chips never cover it
func _draw_title(font: Font) -> void:
	var t := "人生顧問局"
	var fs := 26 if not _compact() else 20
	var sub_w := font.get_string_size(title_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var back := StyleBoxFlat.new()
	back.bg_color = Color(C_BG, 0.72)
	back.set_corner_radius_all(12)
	draw_style_box(back, Rect2(Vector2(8, 8), Vector2(maxf(sub_w, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20) + 36, fs + (60 if title_sub != "" else 32))))
	draw_rect(Rect2(Vector2(18, 16), Vector2(2, fs + 14)), C_GOLD)
	draw_string(font, Vector2(30, 16 + fs), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_line(Vector2(18, 24 + fs + 6), Vector2(30 + tw + 20, 24 + fs + 6), Color(C_GOLD, 0.8), 1.0)
	if title_sub != "":
		draw_string(font, Vector2(30, 24 + fs + 26), title_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_MUTED)


func _draw_chip(font: Font, i: int, chip: Rect2, dot: Vector2, current: bool, upcoming: bool, alpha: float, compact: bool) -> void:
	var tile: Dictionary = tiles[i]
	var tname := str(tile.get("name", ""))
	var kind := str(tile.get("type", ""))
	# Connector from chip to its dot on the route
	var anchor := Vector2(clampf(dot.x, chip.position.x + 8, chip.end.x - 8), clampf(dot.y, chip.position.y, chip.end.y))
	draw_line(anchor, dot, Color(1, 1, 1, 0.45 * alpha), 1.0, true)
	if current:
		var halo := 0.5 + 0.5 * sin(_pulse * 2.6)
		if UI.reduce_motion:
			halo = 0.6
		draw_circle(dot, 11.0 + halo * 3.0, Color(C_GOLD, 0.25))
		draw_circle(dot, 6.0, C_GOLD)
	else:
		draw_circle(dot, 4.5, Color(C_GREEN if upcoming else C_TEXT, 0.9 * alpha))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_CARD.darkened(0.15), 0.94 * alpha)
	sb.set_corner_radius_all(10 if not current else 12)
	sb.set_border_width_all(2 if current else 1)
	sb.border_color = C_GOLD if current else (Color(C_GREEN, 0.9 * alpha) if upcoming else Color(1, 1, 1, 0.14 * alpha))
	if current:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
	draw_style_box(sb, chip)
	var icon := 18.0 if current else 14.0
	var ic := chip.position + Vector2(12 + icon * 0.5, chip.size.y * 0.5)
	var col := Color(C_TEXT, alpha)
	if kind == "audit":
		col = Color(C_RED.lightened(0.2), alpha)
	_draw_icon(tname, kind, ic, icon * 0.5, col)
	var label := "%02d %s" % [i, tname] if (not compact or current) else "%02d" % i
	var fs := 16 if current else (12 if not compact else 11)
	draw_string(font, Vector2(chip.position.x + icon + 18, chip.position.y + chip.size.y * 0.5 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(C_TEXT, alpha))
	var owner: Variant = territory.get(str(i), territory.get(i, null))
	if owner is Dictionary:
		var oi := -1
		for k in range(players.size()):
			if str(players[k].get("id", "")) == str(owner.get("playerId", "")):
				oi = k
		draw_circle(chip.end - Vector2(6, chip.size.y - 6), 4.0, UI.PLAYER_COLORS[oi % 4] if oi >= 0 else C_GREEN)


func _draw_pawns(pts: PackedVector2Array, lengths: PackedFloat32Array, total: float) -> void:
	var font := get_theme_default_font()
	var slots := {}
	for idx in range(players.size()):
		var p: Dictionary = players[idx]
		var id := str(p.get("id", ""))
		var t: float = _shown.get(id, float(p.get("pos", 0)))
		var key := int(roundf(t)) % 24
		var slot: int = slots.get(key, 0)
		slots[key] = slot + 1
		var at := _along(pts, lengths, total, t / 24.0) + Vector2(-9 + slot * 12, 12 + slot * 2)
		var col: Color = UI.PLAYER_COLORS[idx % UI.PLAYER_COLORS.size()]
		var r := 9.0 if id == current_id else 7.0
		draw_circle(at + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
		draw_circle(at, r, col)
		draw_arc(at, r, 0, TAU, 24, C_TEXT, 2.0, true)
		if id == current_id:
			var fs := 11
			draw_string(font, at + Vector2(-r, fs * 0.36), str(p.get("name", "顧")).substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, r * 2, fs, C_BG)


## Flat 2px line icons, one symbol per station
func _draw_icon(tname: String, kind: String, c: Vector2, r: float, col: Color) -> void:
	var w := 2.0
	if tname.contains("咖啡"):
		draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.5), Vector2(r * 1.3, r * 1.2)), col, false, w)
		draw_arc(c + Vector2(r * 0.6, 0.05 * r), r * 0.32, -PI * 0.5, PI * 0.5, 8, col, w, true)
		return
	if tname.contains("說明會") or tname.contains("研討會"):
		draw_rect(Rect2(c + Vector2(-r, -r * 0.8), Vector2(r * 2, r * 1.3)), col, false, w)
		draw_line(c + Vector2(0, r * 0.5), c + Vector2(0, r), col, w, true)
		draw_line(c + Vector2(-r * 0.5, r), c + Vector2(r * 0.5, r), col, w, true)
		return
	if tname.contains("聚餐"):
		draw_line(c + Vector2(-r * 0.45, -r), c + Vector2(-r * 0.45, r), col, w, true)
		draw_line(c + Vector2(-r * 0.75, -r), c + Vector2(-r * 0.75, -r * 0.3), col, w, true)
		draw_line(c + Vector2(-r * 0.15, -r), c + Vector2(-r * 0.15, -r * 0.3), col, w, true)
		draw_line(c + Vector2(r * 0.55, -r), c + Vector2(r * 0.55, r), col, w, true)
		draw_arc(c + Vector2(r * 0.55, -r * 0.45), r * 0.3, PI * 0.5, PI * 1.5, 8, col, w, true)
		return
	if tname.contains("商圈"):
		draw_rect(Rect2(c + Vector2(-r, -r * 0.45), Vector2(r * 2, r * 1.35)), col, false, w)
		draw_rect(Rect2(c + Vector2(-r * 0.4, -r * 0.85), Vector2(r * 0.8, r * 0.4)), col, false, w)
		return
	if tname.contains("線上") or tname.contains("工作空間"):
		draw_rect(Rect2(c + Vector2(-r, -r * 0.8), Vector2(r * 2, r * 1.25)), col, false, w)
		draw_line(c + Vector2(-r * 1.15, r * 0.75), c + Vector2(r * 1.15, r * 0.75), col, w, true)
		return
	if tname.contains("市場") and kind == "client":
		draw_polyline(PackedVector2Array([c + Vector2(-r, -r * 0.3), c + Vector2(r, -r * 0.3), c + Vector2(r * 0.7, r * 0.8), c + Vector2(-r * 0.7, r * 0.8), c + Vector2(-r, -r * 0.3)]), col, w, true)
		draw_arc(c + Vector2(0, -r * 0.3), r * 0.55, PI, TAU, 10, col, w, true)
		return
	if tname.contains("親子"):
		draw_arc(c + Vector2(-r * 0.4, -r * 0.5), r * 0.3, 0, TAU, 12, col, w, true)
		draw_arc(c + Vector2(r * 0.45, -r * 0.2), r * 0.22, 0, TAU, 12, col, w, true)
		draw_line(c + Vector2(-r * 0.4, -r * 0.1), c + Vector2(-r * 0.4, r), col, w, true)
		draw_line(c + Vector2(r * 0.45, r * 0.1), c + Vector2(r * 0.45, r), col, w, true)
		return
	if tname.contains("醫院"):
		draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.85), col, w + 1, true)
		draw_line(c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.85, 0), col, w + 1, true)
		return
	match kind:
		"start":
			draw_line(c + Vector2(-r * 0.6, r), c + Vector2(-r * 0.6, -r), col, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.8, -r * 0.55), c + Vector2(-r * 0.6, -r * 0.1)]), col, w, true)
		"training":
			draw_polyline(PackedVector2Array([c + Vector2(-r, -r * 0.2), c + Vector2(0, -r * 0.75), c + Vector2(r, -r * 0.2), c + Vector2(0, r * 0.3), c + Vector2(-r, -r * 0.2)]), col, w, true)
			draw_line(c + Vector2(r * 0.55, 0), c + Vector2(r * 0.55, r * 0.7), col, w, true)
		"market":
			for k in range(3):
				draw_line(c + Vector2(-r * 0.7 + k * r * 0.7, r * 0.85), c + Vector2(-r * 0.7 + k * r * 0.7, r * 0.85 - r * (0.6 + k * 0.5)), col, w + 1, true)
		"life":
			var pts := PackedVector2Array()
			for k in range(17):
				var a := PI * 2.0 * k / 16.0
				var x := 16.0 * pow(sin(a), 3)
				var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
				pts.append(c + Vector2(x, y) * r / 17.0)
			draw_polyline(pts, col, w, true)
		"audit":
			draw_rect(Rect2(c + Vector2(-r * 0.8, -r), Vector2(r * 1.3, r * 1.7)), col, false, w)
			draw_arc(c + Vector2(r * 0.25, r * 0.2), r * 0.35, 0, TAU, 12, col, w, true)
			draw_line(c + Vector2(r * 0.5, r * 0.45), c + Vector2(r * 0.9, r * 0.85), col, w, true)
		"referral", "seminar":
			draw_arc(c + Vector2(-r * 0.4, -r * 0.35), r * 0.3, 0, TAU, 12, col, w, true)
			draw_arc(c + Vector2(r * 0.45, -r * 0.35), r * 0.3, 0, TAU, 12, col, w, true)
			draw_arc(c + Vector2(-r * 0.4, r * 0.75), r * 0.55, PI * 1.1, PI * 1.9, 8, col, w, true)
			draw_arc(c + Vector2(r * 0.45, r * 0.75), r * 0.55, PI * 1.1, PI * 1.9, 8, col, w, true)
		_:
			draw_arc(c + Vector2(0, -r * 0.4), r * 0.4, 0, TAU, 14, col, w, true)
			draw_arc(c + Vector2(0, r * 0.95), r * 0.8, PI * 1.12, PI * 1.88, 12, col, w, true)
