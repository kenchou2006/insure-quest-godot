@tool
extends Control
## Taipei 101 Advisor HQ board: painted HQ map with the 24 server tiles drawn as small itinerary nodes
## on a loop around the plaza. Tile order, positions and territory remain server-authoritative.
## Same public API as board.gd (set_data / freeze_movement / get_inner_rect), so game.gd can swap boards.

const MAP := preload("res://assets/hq/hq_map.webp")

## Route loop in board-normalized coordinates (kept inside the visible area at any aspect ratio).
const ROUTE_CENTER := Vector2(0.5, 0.45)
const ROUTE_RADIUS := Vector2(0.40, 0.27)
## How many nodes ahead of the current player stay highlighted as "upcoming route".
const AHEAD := 6

const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
const C_RED := Color("#D9685F")

var tiles: Array = []
var players: Array = []
var territory: Dictionary = {}
var current_id := ""
var _shown: Dictionary = {}
var _freeze_timer := 0.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _selected := -1
var _hover := -1
var _pulse := 0.0
var _tools: HBoxContainer


class ToolIcon extends Button:
	## Small line icon (2px strokes) for map controls: "in", "out", "reset".
	var kind := ""

	func _init(icon_kind: String, tip: String) -> void:
		kind = icon_kind
		tooltip_text = tip
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(34, 34)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("#0D4038", 0.82 if state != "hover" else 0.95)
			sb.set_corner_radius_all(10)
			sb.set_border_width_all(1)
			sb.border_color = Color(1, 1, 1, 0.12)
			add_theme_stylebox_override(state, sb)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.24
		var col := Color("#F3F0E7")
		match kind:
			"in":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 2, true)
				draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 2, true)
			"out":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 2, true)
			"reset":
				draw_arc(c, r, deg_to_rad(-60), deg_to_rad(240), 20, col, 2, true)
				var tip := c + Vector2(cos(deg_to_rad(-60)), sin(deg_to_rad(-60))) * r
				draw_line(tip, tip + Vector2(-r * 0.55, -r * 0.05), col, 2, true)
				draw_line(tip, tip + Vector2(0.05 * r, r * 0.55), col, 2, true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_tools = HBoxContainer.new()
	_tools.add_theme_constant_override("separation", 6)
	add_child(_tools)
	for spec: Array in [["in", "放大"], ["out", "縮小"], ["reset", "復位"]]:
		var b := ToolIcon.new(spec[0], spec[1])
		b.pressed.connect(_tool_action.bind(spec[0]))
		_tools.add_child(b)
	resized.connect(_layout)
	mouse_exited.connect(func():
		_hover = -1
		queue_redraw()
	)
	_layout()


func _layout() -> void:
	if _tools == null:
		return
	_tools.reset_size()
	_tools.position = Vector2(size.x - _tools.size.x - 14, 14)
	_clamp_pan()
	queue_redraw()


## Area reserved for the HUD card (bottom of the map); game.gd places its control dock here.
func get_inner_rect() -> Rect2:
	var w := clampf(size.x - 32.0, 240.0, 820.0)
	var h := 196.0 if size.x < 520.0 else clampf(size.y * 0.24, 112.0, 168.0)
	return Rect2(Vector2((size.x - w) * 0.5, size.y - h - 16.0), Vector2(w, h))


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
	queue_redraw()


func freeze_movement(duration: float) -> void:
	_freeze_timer = maxf(duration, 0.0)


## Tile index the current player is standing on (as displayed, i.e. after pawn animation).
func current_index() -> int:
	if tiles.is_empty():
		return -1
	return int(floorf(float(_shown.get(current_id, 0.0)) + 0.001)) % tiles.size()


func _process(delta: float) -> void:
	if tiles.is_empty():
		return
	_pulse += delta
	_freeze_timer = maxf(0, _freeze_timer - delta)
	for p: Dictionary in players:
		var id := str(p.get("id", ""))
		var before: float = _shown.get(id, float(p.get("pos", 0)))
		var diff := fposmod(float(p.get("pos", 0)) - before, tiles.size())
		if _freeze_timer <= 0 and diff > 0.001:
			var after := fposmod(before + minf(diff, delta * 6), tiles.size())
			_shown[id] = after
			if int(floorf(before)) != int(floorf(after)) and id == current_id and not Engine.is_editor_hint():
				Sound.play("step", self)
	queue_redraw()


# ───────── Geometry ─────────

## Map image rect: covers the board (no bars), then zoom/pan applied around the board center.
func _map_rect() -> Rect2:
	var img := MAP.get_size()
	var s := maxf(size.x / img.x, size.y / img.y) * _zoom
	var sz := img * s
	return Rect2((size - sz) * 0.5 + _pan, sz)


## Board-normalized point -> screen, following map zoom/pan.
func _to_screen(n: Vector2) -> Vector2:
	var base := n * size
	return (base - size * 0.5) * _zoom + size * 0.5 + _pan


func _route_point(t: float) -> Vector2:
	var count := maxi(tiles.size(), 1)
	var a := PI * 0.5 + TAU * t / count
	# Narrow (phone) boards keep the loop higher so the taller HUD card does not cover it
	var center := ROUTE_CENTER if size.x >= 520.0 else Vector2(0.5, 0.39)
	var radius := ROUTE_RADIUS if size.x >= 520.0 else Vector2(0.42, 0.24)
	return _to_screen(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))


func _node_radius() -> float:
	return clampf(minf(size.x, size.y) * 0.026, 11.0, 17.0) * sqrt(_zoom)


func _tile_at(p: Vector2) -> int:
	var r := _node_radius() * 1.4
	for i in range(tiles.size()):
		if _route_point(i).distance_to(p) <= r:
			return i
	return -1


func _clamp_pan() -> void:
	var limit := size * (_zoom - 1.0) * 0.5
	_pan = _pan.clamp(-limit, limit)


# ───────── Input ─────────

func _tool_action(kind: String) -> void:
	match kind:
		"in": _set_zoom(_zoom * 1.25)
		"out": _set_zoom(_zoom / 1.25)
		"reset":
			_zoom = 1.0
			_pan = Vector2.ZERO
			_selected = -1
	queue_redraw()


func _set_zoom(z: float) -> void:
	var old := _zoom
	_zoom = clampf(z, 1.0, 2.6)
	_pan *= _zoom / old
	_clamp_pan()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT) and _zoom > 1.0:
			_pan += event.relative
			_clamp_pan()
			accept_event()
		var h := _tile_at(event.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom * 1.1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom / 1.1)
				accept_event()
			MOUSE_BUTTON_LEFT:
				var t := _tile_at(event.position)
				_selected = -1 if t == _selected else t
				queue_redraw()


# ───────── Drawing ─────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#062F2A"))
	draw_texture_rect(MAP, _map_rect(), false)
	# Soft darkening toward the edges and the HUD so nodes and text read clearly
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.12, 0.11, 0.18))
	var fade_h := size.y * 0.32
	for k in range(8):
		var y := size.y - fade_h + fade_h * k / 8.0
		draw_rect(Rect2(0, y, size.x, fade_h / 8.0 + 1), Color(0.024, 0.184, 0.165, 0.07 * (k + 1)))
	if tiles.is_empty():
		return

	var n := tiles.size()
	var cur := current_index()
	var r := _node_radius()

	# Route line: full loop faint, upcoming stretch brighter
	var loop := PackedVector2Array()
	for k in range(n * 6 + 1):
		loop.append(_route_point(k / 6.0))
	draw_polyline(loop, Color(1, 1, 1, 0.16), 2.0, true)
	if cur >= 0:
		var ahead := PackedVector2Array()
		var from := float(_shown.get(current_id, cur))
		for k in range(AHEAD * 6 + 1):
			ahead.append(_route_point(from + k / 6.0))
		draw_polyline(ahead, Color(C_GREEN, 0.75), 2.5, true)

	# Nodes: current one large and bright, upcoming ones medium, the rest dimmed but visible
	for i in range(n):
		if i == cur:
			continue
		var steps := posmod(i - cur, n) if cur >= 0 else n
		var alpha := 0.9 if steps <= AHEAD else 0.5
		var emphasis := i == _hover or i == _selected
		_draw_node(i, _route_point(i), r * (1.12 if emphasis else 1.0), 1.0 if emphasis else alpha, false)
	if cur >= 0:
		var c := _route_point(cur)
		var halo := 0.5 + 0.5 * sin(_pulse * 2.4)
		if UI.reduce_motion:
			halo = 0.6
		draw_circle(c, r * (2.3 + halo * 0.25), Color(C_GREEN, 0.12 + halo * 0.06))
		_draw_node(cur, c, r * 1.55, 1.0, true)

	# Player pawns (offset when several share a node)
	var counts := {}
	for idx in range(players.size()):
		var p: Dictionary = players[idx]
		var pid := str(p.get("id", ""))
		var t: float = _shown.get(pid, float(p.get("pos", 0)))
		var key := int(roundf(t)) % n
		var slot: int = counts.get(key, 0)
		counts[key] = slot + 1
		var at := _route_point(t) + Vector2(-r * 1.05 + slot * r * 0.7, -r * 1.9 - (r * 0.6 if pid == current_id else 0.0))
		var col: Color = UI.PLAYER_COLORS[idx % UI.PLAYER_COLORS.size()]
		var pr := r * (0.62 if pid == current_id else 0.5)
		draw_circle(at + Vector2(0, 2), pr, Color(0, 0, 0, 0.25))
		draw_circle(at, pr, col)
		draw_arc(at, pr, 0, TAU, 24, C_TEXT, 2.0, true)
		if pid == current_id:
			var font := get_theme_default_font()
			var initial := str(p.get("name", "顧")).substr(0, 1)
			var fs := int(pr * 1.1)
			draw_string(font, at + Vector2(-pr, fs * 0.36), initial, HORIZONTAL_ALIGNMENT_CENTER, pr * 2, fs, Color("#062F2A"))

	# Caption chip for the hovered / selected node
	var show := _hover if _hover >= 0 else _selected
	if show >= 0:
		_draw_caption(show)


func _ring_color(kind: String) -> Color:
	match kind:
		"start": return C_GOLD
		"audit": return C_RED
		_: return C_GREEN


func _draw_node(i: int, c: Vector2, r: float, alpha: float, current: bool) -> void:
	var kind := str((tiles[i] as Dictionary).get("type", "client"))
	var ring := _ring_color(kind)
	draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.22 * alpha))
	draw_circle(c, r, Color(C_CARD, 0.94 * alpha))
	draw_arc(c, r, 0, TAU, 32, Color(ring.lightened(0.15) if current else ring, alpha), 2.5 if current else 2.0, true)
	_draw_icon(kind, str((tiles[i] as Dictionary).get("name", "")), c, r * 0.5, Color(C_TEXT, alpha))
	var owner: Variant = territory.get(str(i), territory.get(i, null))
	if owner is Dictionary:
		var oi := -1
		for k in range(players.size()):
			if str(players[k].get("id", "")) == str(owner.get("playerId", owner.get("owner", ""))):
				oi = k
		var oc: Color = UI.PLAYER_COLORS[oi % UI.PLAYER_COLORS.size()] if oi >= 0 else C_GREEN
		draw_circle(c + Vector2(r * 0.72, r * 0.72), maxf(3.0, r * 0.22), Color(oc, alpha))


func _draw_caption(i: int) -> void:
	var tile: Dictionary = tiles[i]
	var font := get_theme_default_font()
	var title := "%s｜%s" % [UI.tile_name(str(tile.get("type", ""))), str(tile.get("name", ""))]
	var owner: Variant = territory.get(str(i), territory.get(i, null))
	if owner is Dictionary:
		title += "・" + str(owner.get("clientName", "已簽約"))
	var fs := 13
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := _route_point(i)
	var box := Rect2(c + Vector2(-tw * 0.5 - 10, _node_radius() * 1.7 + 6), Vector2(tw + 20, 26))
	box.position.x = clampf(box.position.x, 6, size.x - box.size.x - 6)
	box.position.y = clampf(box.position.y, 6, size.y - box.size.y - 6)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_CARD, 0.96)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	draw_style_box(sb, box)
	draw_string(font, box.position + Vector2(10, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)


## Flat line icons, 2px strokes, one symbol per tile type.
func _draw_icon(kind: String, tile_name: String, c: Vector2, r: float, col: Color) -> void:
	var w := 2.0
	match kind:
		"start":
			var pts := PackedVector2Array()
			for k in range(11):
				var a := -PI * 0.5 + k * TAU / 10.0
				pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
			draw_polyline(pts, col, w, true)
		"client":
			if tile_name.contains("公司") or tile_name.contains("商圈") or tile_name.contains("空間"):
				draw_rect(Rect2(c + Vector2(-r * 0.7, -r), Vector2(r * 1.4, r * 2)), col, false, w)
				for k in range(3):
					draw_line(c + Vector2(-r * 0.35, -r * 0.5 + k * r * 0.5), c + Vector2(r * 0.35, -r * 0.5 + k * r * 0.5), col, w)
			else:
				draw_arc(c + Vector2(0, -r * 0.4), r * 0.42, 0, TAU, 18, col, w, true)
				draw_arc(c + Vector2(0, r * 0.95), r * 0.85, PI * 1.12, PI * 1.88, 14, col, w, true)
		"referral":
			draw_arc(c + Vector2(-r * 0.4, -r * 0.35), r * 0.32, 0, TAU, 14, col, w, true)
			draw_arc(c + Vector2(r * 0.45, -r * 0.2), r * 0.32, 0, TAU, 14, col, w, true)
			draw_line(c + Vector2(-r * 0.9, r * 0.75), c + Vector2(r * 0.9, r * 0.75), col, w, true)
		"life":
			draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.85), col, w, true)
			draw_line(c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.85, 0), col, w, true)
		"market":
			draw_polyline(PackedVector2Array([c + Vector2(-r, r * 0.6), c + Vector2(-r * 0.3, -r * 0.05), c + Vector2(r * 0.15, r * 0.3), c + Vector2(r, -r * 0.6)]), col, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(r * 0.45, -r * 0.6), c + Vector2(r, -r * 0.6), c + Vector2(r, -r * 0.1)]), col, w, true)
		"training":
			draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.7, r * 0.4), c + Vector2(0, r), c + Vector2(-r * 0.7, r * 0.4), c + Vector2(-r * 0.8, -r * 0.6), c + Vector2(0, -r)]), col, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.35, 0), c + Vector2(-r * 0.05, r * 0.3), c + Vector2(r * 0.4, -r * 0.3)]), col, w, true)
		"audit":
			draw_arc(c - Vector2(r * 0.2, r * 0.2), r * 0.62, 0, TAU, 20, col, w, true)
			draw_line(c + Vector2.ONE * r * 0.25, c + Vector2.ONE * r * 0.9, col, w, true)
		"seminar":
			draw_rect(Rect2(c + Vector2(-r, -r * 0.75), Vector2(r * 2, r * 1.3)), col, false, w)
			draw_line(c + Vector2(0, r * 0.55), c + Vector2(0, r), col, w, true)
			draw_line(c + Vector2(-r * 0.5, r), c + Vector2(r * 0.5, r), col, w, true)
		_:
			draw_arc(c, r * 0.7, 0, TAU, 18, col, w, true)
