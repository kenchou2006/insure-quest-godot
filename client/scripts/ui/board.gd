@tool
extends Control
## Life board: 24-tile ring (7x7 outer perimeter), drawing tiles and player pawns that hop along tiles with adaptive sizing.
## Supports center compass key visual, layered tile icon recognition, and dice roll cutscene freeze mechanism.

const COLS := 7
var tiles: Array = []
var players: Array = []
var current_id := ""
var _shown: Dictionary = {}   # playerId -> float position (continuous value along the ring)
var _target: Dictionary = {}  # playerId -> int
var _pulse := 0.0
var _freeze_timer := 0.0
var _center_texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for path: String in ["res://assets/board_center.png", "res://assets/board_center.webp", "res://assets/title.jpg"]:
		if ResourceLoader.exists(path):
			_center_texture = load(path)
			break


func freeze_movement(duration: float) -> void:
	_freeze_timer = duration


func set_data(board: Array, ps: Array, current: String) -> void:
	tiles = board
	players = ps
	current_id = current
	for p: Dictionary in ps:
		var id: String = str(p.get("id", ""))
		_target[id] = int(p.get("pos", 0))
		if not _shown.has(id):
			_shown[id] = float(p.get("pos", 0))
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta * 4.0
	var n: int = tiles.size()
	if n == 0:
		return

	if _freeze_timer > 0.0:
		_freeze_timer -= delta
		queue_redraw()
		return

	var moving: bool = false
	for id: String in _target.keys():
		var cur: float = float(_shown.get(id, 0.0))
		var tgt: float = float(_target[id])
		var diff: float = fposmod(tgt - cur, n)
		if diff > 0.01:
			var prev_step: int = int(floorf(cur))
			cur = fposmod(cur + minf(diff, delta * 6.0), n)
			if fposmod(tgt - cur, n) > n - 0.5:
				cur = tgt
			var new_step: int = int(floorf(cur))
			if new_step != prev_step and id == current_id:
				Sound.play("step", self)
			_shown[id] = cur
			moving = true
	if moving or current_id != "":
		queue_redraw()


## Cell size follows the available area (non-square board), with the tile aspect ratio capped at MAX_CELL_ASPECT.
const MAX_CELL_ASPECT := 1.7


func _cell_size() -> Vector2:
	var cw: float = size.x / COLS
	var ch: float = size.y / COLS
	cw = minf(cw, ch * MAX_CELL_ASPECT)
	ch = minf(ch, cw * MAX_CELL_ASPECT)
	return Vector2(cw, ch)


func _board_origin(cs: Vector2) -> Vector2:
	return Vector2((size.x - cs.x * COLS) * 0.5, (size.y - cs.y * COLS) * 0.5)


func get_inner_rect() -> Rect2:
	var cs := _cell_size()
	var o := _board_origin(cs)
	var inset: float = 2.0 if UI.is_phone_portrait() else 4.0
	return Rect2(o.x + cs.x + inset, o.y + cs.y + inset, cs.x * 5.0 - inset * 2.0, cs.y * 5.0 - inset * 2.0)


func tile_rect(i: int) -> Rect2:
	var cs := _cell_size()
	var o := _board_origin(cs)
	var c: int = 0
	var r: int = 0
	if i <= 6:
		c = i; r = 0
	elif i <= 11:
		c = 6; r = i - 6
	elif i <= 18:
		c = 6 - (i - 12); r = 6
	else:
		c = 0; r = 6 - (i - 18)
	var grow_pad: float = -1.5 if UI.is_phone_portrait() else -3.0
	return Rect2(o.x + c * cs.x, o.y + r * cs.y, cs.x, cs.y).grow(grow_pad)


func _point_on_ring(f: float) -> Vector2:
	var n: int = tiles.size()
	var a: int = int(floorf(f)) % n
	var b: int = (a + 1) % n
	var t: float = f - floorf(f)
	return tile_rect(a).get_center().lerp(tile_rect(b).get_center(), t)


func _draw() -> void:
	if tiles.is_empty():
		return
	var font: Font = get_theme_default_font()
	var cs := _cell_size()
	var cw: float = cs.x
	var ch: float = cs.y
	var c_min: float = minf(cw, ch)
	var n: int = tiles.size()

	# 1. Board center key visual (background, concentric compass, and decorative star rays)
	var inner := get_inner_rect()
	draw_rect(inner, Color("#091a24"), true)
	draw_rect(inner, Color("#153a4c"), false, 1.5)

	if _center_texture != null:
		# Fit inside the (possibly non-square) center area while keeping the texture's aspect ratio
		var tex_sz: Vector2 = _center_texture.get_size()
		var fit: float = minf(inner.size.x * 0.88 / tex_sz.x, inner.size.y * 0.88 / tex_sz.y)
		var tex_s: Vector2 = tex_sz * fit
		var tex_pos: Vector2 = inner.position + (inner.size - tex_s) * 0.5
		draw_texture_rect(_center_texture, Rect2(tex_pos, tex_s), false, Color(1, 1, 1, 0.28))

	# Draw center subtle glowing star-ray compass
	var center_pt: Vector2 = inner.get_center()
	var compass_rad: float = minf(inner.size.x, inner.size.y) * 0.38
	draw_arc(center_pt, compass_rad, 0, TAU, 48, Color("#1e4b60", 0.4), 1.5)
	draw_arc(center_pt, compass_rad * 0.75, 0, TAU, 36, Color("#1e4b60", 0.3), 1.0)
	draw_arc(center_pt, compass_rad * 0.35, 0, TAU, 24, Color("#f2c14e", 0.25), 1.0)

	# Rotating four-pointed star rays
	var star_rot: float = _pulse * 0.05
	for arm: int in range(4):
		var ang: float = star_rot + float(arm) * (PI * 0.5)
		var p_out: Vector2 = center_pt + Vector2(cos(ang), sin(ang)) * (compass_rad * 0.95)
		var p_left: Vector2 = center_pt + Vector2(cos(ang + 0.25), sin(ang + 0.25)) * (compass_rad * 0.22)
		var p_right: Vector2 = center_pt + Vector2(cos(ang - 0.25), sin(ang - 0.25)) * (compass_rad * 0.22)
		var tri: PackedVector2Array = PackedVector2Array([center_pt, p_left, p_out])
		draw_colored_polygon(tri, Color("#f2c14e", 0.14))
		var tri2: PackedVector2Array = PackedVector2Array([center_pt, p_right, p_out])
		draw_colored_polygon(tri2, Color("#2fd197", 0.10))

	# 2. Draw 24 life tiles (with distinct ribbons, icons, and location names)
	var is_compact: bool = cw < 60.0 and not UI.is_phone_portrait()
	# Phone landscape tiles have no room beside the name, so names are drawn after the pawns (with an outline) to stay readable
	var deferred_names: Array = []
	for i: int in tiles.size():
		var t: Dictionary = tiles[i]
		var r: Rect2 = tile_rect(i)
		var type_key: String = str(t.get("type", ""))
		var col: Color = UI.TILE_COLORS.get(type_key, UI.PANEL_2)

		# Tile main background (dark base with rounded corners)
		draw_style_box(UI.box(Color("#0d2432"), 8, col.darkened(0.35), 0), r)

		# Top category ribbon
		var ribbon_h: float
		if UI.is_phone_portrait():
			ribbon_h = clampf(r.size.y * 0.24, 18.0, 24.0)
		elif UI.is_phone_landscape():
			ribbon_h = clampf(r.size.y * 0.32, 18.0, 22.0)
		else:
			ribbon_h = clampf(r.size.y * (0.28 if is_compact else 0.25), 14.0, 22.0)
		var ribbon_r := Rect2(r.position.x, r.position.y, r.size.x, ribbon_h)
		draw_style_box(UI.box(col.darkened(0.15), 6, col.lightened(0.15), 0), ribbon_r)

		# Ribbon text and tile index: always show the full index without clipping
		var idx_str: String = str(i)
		var idx_fs: int = UI.fs(10 if not UI.is_phone() else 11)
		var idx_w: float = font.get_string_size(idx_str, HORIZONTAL_ALIGNMENT_LEFT, -1, idx_fs).x
		var pad_l: float = 3.0 if UI.is_phone_portrait() else 4.0
		var pad_r: float = 3.0 if UI.is_phone_portrait() else 4.0
		var idx_gap: float = 4.0 if UI.is_phone() else 3.0
		var idx_reserved_w: float = idx_w + idx_gap
		var max_cat_w: float = maxf(10.0, ribbon_r.size.x - pad_l - pad_r - idx_reserved_w)

		# Portrait ribbon: icon + full index (category word optional only if it fits)
		var full_cat: String = UI.tile_badge(type_key, false)
		var icon_cat: String = UI.tile_badge(type_key, true)
		var cat_name: String = ""
		var cat_fs: int = UI.fs(11 if UI.is_phone() else 10)

		if UI.is_portrait():
			if font.get_string_size(full_cat, HORIZONTAL_ALIGNMENT_LEFT, -1, cat_fs).x <= max_cat_w:
				cat_name = full_cat
			else:
				var test_fs: int = cat_fs
				while test_fs > UI.fs(9) and font.get_string_size(full_cat, HORIZONTAL_ALIGNMENT_LEFT, -1, test_fs).x > max_cat_w:
					test_fs -= 1
				if font.get_string_size(full_cat, HORIZONTAL_ALIGNMENT_LEFT, -1, test_fs).x <= max_cat_w:
					cat_name = full_cat
					cat_fs = test_fs
				else:
					cat_name = icon_cat
		else:
			cat_name = icon_cat if (is_compact and not UI.is_phone()) else full_cat
			while cat_fs > UI.fs(9) and font.get_string_size(cat_name, HORIZONTAL_ALIGNMENT_LEFT, -1, cat_fs).x > max_cat_w:
				cat_fs -= 1
			if font.get_string_size(cat_name, HORIZONTAL_ALIGNMENT_LEFT, -1, cat_fs).x > max_cat_w:
				cat_name = icon_cat

		if font.get_string_size(cat_name, HORIZONTAL_ALIGNMENT_LEFT, -1, cat_fs).x > max_cat_w:
			while cat_name.length() > 1 and font.get_string_size(cat_name + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, cat_fs).x > max_cat_w:
				cat_name = cat_name.substr(0, cat_name.length() - 1)
			cat_name += "…"

		draw_string(font, Vector2(ribbon_r.position.x + pad_l, ribbon_r.get_center().y + cat_fs * 0.38), cat_name, HORIZONTAL_ALIGNMENT_LEFT, int(max_cat_w), cat_fs, Color.WHITE)
		var idx_x: float = ribbon_r.end.x - pad_r - idx_w
		draw_string(font, Vector2(idx_x, ribbon_r.get_center().y + idx_fs * 0.38), idx_str, HORIZONTAL_ALIGNMENT_LEFT, -1, idx_fs, Color(1, 1, 1, 0.85))

		# Body area below ribbon
		var body_top: float = ribbon_r.end.y
		var body_h: float = r.end.y - body_top
		var name_str: String = str(t.get("name", ""))
		var min_fs: int = UI.fs(11)
		var name_fs: int = UI.fs(12)
		var max_name_w: float = r.size.x - 4.0

		# Check if tile has enough height for ribbon + icon + readable name (>= UI.fs(11))
		# If too short (e.g. phone landscape ~38px body), drop the icon first, keeping ribbon and name
		var can_fit_icon: bool = body_h >= 52.0 and not UI.is_phone_landscape()

		if can_fit_icon:
			var sym_sz: float = (c_min * 0.20) if UI.is_phone_portrait() else (cw * 0.16)
			var sym_center := Vector2(r.get_center().x, body_top + sym_sz + 4.0)
			_draw_tile_symbol(type_key, sym_center, sym_sz, col.lightened(0.35))

		if name_str != "":
			if UI.is_phone_portrait() and font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w:
				# Phone portrait: wrap long place names into 2 lines
				var mid: int = 2 if name_str.length() == 5 else int(ceilf(float(name_str.length()) / 2.0))
				var line1: String = name_str.substr(0, mid)
				var line2: String = name_str.substr(mid)
				while name_fs > min_fs and (font.get_string_size(line1, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w or font.get_string_size(line2, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w):
					name_fs -= 1
				var line_spacing: float = name_fs * 1.05
				var y2: float = r.end.y - 4.0
				var y1: float = y2 - line_spacing
				draw_string(font, Vector2(r.position.x + 2, y1), line1, HORIZONTAL_ALIGNMENT_CENTER, int(max_name_w), name_fs, UI.TEXT)
				draw_string(font, Vector2(r.position.x + 2, y2), line2, HORIZONTAL_ALIGNMENT_CENTER, int(max_name_w), name_fs, UI.TEXT)
			else:
				# Single line: shrink down to min_fs, then ellipsize
				while name_fs > min_fs and font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w:
					name_fs -= 1
				var display_name: String = name_str
				if font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w:
					while display_name.length() > 1 and font.get_string_size(display_name + "…", HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w:
						display_name = display_name.substr(0, display_name.length() - 1)
					display_name += "…"
				var name_y: float = (body_top + body_h * 0.5 + name_fs * 0.35) if not can_fit_icon else (r.end.y - (4.0 if UI.is_phone_portrait() else 6.0))
				if UI.is_phone_landscape():
					deferred_names.append([Vector2(r.position.x + 2, name_y), display_name, int(max_name_w), name_fs])
				else:
					draw_string(font, Vector2(r.position.x + 2, name_y), display_name, HORIZONTAL_ALIGNMENT_CENTER, int(max_name_w), name_fs, UI.TEXT)

	# 3. Breathing glow outline for tile of current active player
	if current_id != "" and _shown.has(current_id):
		var cur_tile_idx: int = int(floorf(float(_shown[current_id]) + 0.1)) % n
		var cur_r: Rect2 = tile_rect(cur_tile_idx)
		var glow_alpha: float = 0.60 + sin(_pulse * 1.5) * 0.35
		var glow_col := Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, glow_alpha)
		draw_style_box(UI.box(Color(0, 0, 0, 0), 10, glow_col, 0, false), cur_r.grow(3))

	# 4. Draw player pawns (dynamic hopping, squash on landing, and active player aura, scaled by min(cw, ch) without distortion)
	var idx: int = 0
	for p: Dictionary in players:
		var id: String = str(p.get("id", ""))
		var f: float = float(_shown.get(id, float(p.get("pos", 0))))
		var base: Vector2 = _point_on_ring(f)
		var off: Vector2 = Vector2((idx % 2) * 2 - 1, int(idx / 2.0) * 2 - 1) * c_min * 0.13
		var c: Color = UI.PLAYER_COLORS[idx % 4]
		var rad: float = c_min * 0.13

		var frac: float = f - floorf(f)
		var hop_sin: float = sin(frac * PI)
		var jump_y: float = -hop_sin * (c_min * 0.34)
		var ground_pos: Vector2 = base + off

		# Ground shadow (fades and shrinks higher in air, spreads on landing)
		var shadow_scale_x: float = clampf(1.15 - hop_sin * 0.45, 0.5, 1.25)
		var shadow_scale_y: float = clampf(0.55 - hop_sin * 0.25, 0.25, 0.65)
		var shadow_alpha: float = clampf(0.40 - hop_sin * 0.22, 0.12, 0.45)
		# Godot 4.7 built-in draw_ellipse(center, semi-major axis, semi-minor axis, color)
		draw_ellipse(ground_pos + Vector2(0, rad * 0.4), rad * shadow_scale_x, rad * shadow_scale_y, Color(0, 0, 0, shadow_alpha))

		# Jump squash and stretch (squash on landing, stretch ascending)
		var stretch_y: float = 1.0 + hop_sin * 0.25
		var squash_x: float = 1.0 - hop_sin * 0.18
		if hop_sin < 0.05 and _target.has(id) and absf(float(_target[id]) - f) > 0.02:
			# Slight squash deformation upon landing
			stretch_y = 0.82
			squash_x = 1.22

		var pawn_pos: Vector2 = ground_pos + Vector2(0, jump_y)

		# Active player breathing aura
		if id == current_id:
			var aura_rad_x: float = (rad * squash_x + 5.0) + sin(_pulse * 2.2) * 2.5
			var aura_rad_y: float = (rad * stretch_y + 5.0) + sin(_pulse * 2.2) * 2.5
			var aura_alpha: float = 0.45 + sin(_pulse * 2.2) * 0.25
			draw_ellipse(pawn_pos, aura_rad_x, aura_rad_y, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, aura_alpha))
			draw_ellipse(pawn_pos, rad * squash_x + 2.5, rad * stretch_y + 2.5, Color.WHITE)
		else:
			draw_ellipse(pawn_pos, rad * squash_x + 1.8, rad * stretch_y + 1.8, Color("#0b1f2a"))

		# Pawn body (applying deformation)
		draw_ellipse(pawn_pos, rad * squash_x, rad * stretch_y, c)

		# Top enamel glossy highlight
		draw_arc(pawn_pos + Vector2(0, -rad * stretch_y * 0.15), rad * squash_x * 0.65, -PI * 0.8, -PI * 0.2, 16, Color(1, 1, 1, 0.40), 2.0)

		# Player initial avatar
		var initial_char: String = str(p.get("name", "顧")).substr(0, 1)
		var char_fs: int = mini(UI.fs(int(rad * 1.15)), int(rad * 1.5))
		# Drop shadow text
		draw_string(font, pawn_pos + Vector2(-rad, char_fs * 0.38 + 1), initial_char, HORIZONTAL_ALIGNMENT_CENTER, int(rad * 2), char_fs, Color(0, 0, 0, 0.75))
		# Main text
		draw_string(font, pawn_pos + Vector2(-rad, char_fs * 0.38), initial_char, HORIZONTAL_ALIGNMENT_CENTER, int(rad * 2), char_fs, Color.WHITE)

		idx += 1

	# 5. Phone landscape: place names on top of pawns, outlined so they stay readable
	for dn: Array in deferred_names:
		draw_string_outline(font, dn[0], dn[1], HORIZONTAL_ALIGNMENT_CENTER, dn[2], dn[3], 5, Color("#0b1f2a"))
		draw_string(font, dn[0], dn[1], HORIZONTAL_ALIGNMENT_CENTER, dn[2], dn[3], UI.TEXT)


func _draw_tile_symbol(type_key: String, c: Vector2, sz: float, col: Color) -> void:
	match type_key:
		"client":
			# Client: figure (head + shoulders)
			draw_circle(c + Vector2(0, -sz * 0.35), sz * 0.32, col)
			var body := PackedVector2Array()
			for i in range(13):
				var a: float = PI + PI * float(i) / 12.0
				body.append(c + Vector2(cos(a) * sz * 0.7, sz * 0.75 + sin(a) * sz * 0.65))
			draw_colored_polygon(body, col)
		"market":
			# Market: 3 bars + baseline + upward trendline
			draw_rect(Rect2(c.x - sz * 0.7, c.y + sz * 0.15, sz * 0.32, sz * 0.55), col, true)
			draw_rect(Rect2(c.x - sz * 0.16, c.y - sz * 0.15, sz * 0.32, sz * 0.85), col, true)
			draw_rect(Rect2(c.x + sz * 0.38, c.y - sz * 0.45, sz * 0.32, sz * 1.15), col, true)
			draw_line(c + Vector2(-sz * 0.85, sz * 0.75), c + Vector2(sz * 0.85, sz * 0.75), col, 2.0)
			draw_polyline(PackedVector2Array([c + Vector2(-sz * 0.75, -sz * 0.15), c + Vector2(-sz * 0.1, -sz * 0.5), c + Vector2(sz * 0.6, -sz * 0.85)]), col, 1.5, true)
		"life":
			# Life defense: medical and heart cross
			draw_rect(Rect2(c.x - sz * 0.2, c.y - sz * 0.7, sz * 0.4, sz * 1.4), col, true)
			draw_rect(Rect2(c.x - sz * 0.7, c.y - sz * 0.2, sz * 1.4, sz * 0.4), col, true)
		"training":
			# Compliance: closed shield + checkmark
			var shield := PackedVector2Array([c + Vector2(0, -sz * 0.8), c + Vector2(sz * 0.7, -sz * 0.55), c + Vector2(sz * 0.62, sz * 0.15), c + Vector2(0, sz * 0.85), c + Vector2(-sz * 0.62, sz * 0.15), c + Vector2(-sz * 0.7, -sz * 0.55), c + Vector2(0, -sz * 0.8)])
			draw_polyline(shield, col, 2.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-sz * 0.32, 0), c + Vector2(-sz * 0.05, sz * 0.28), c + Vector2(sz * 0.36, -sz * 0.25)]), col, 2.5, true)
		"audit":
			# Audit: magnifying glass
			draw_arc(c + Vector2(-sz * 0.2, -sz * 0.2), sz * 0.55, 0, TAU, 18, col, 2.0)
			draw_line(c + Vector2(sz * 0.18, sz * 0.18), c + Vector2(sz * 0.75, sz * 0.75), col, 3.0)
		"referral":
			# Referral: interlinked rings
			draw_arc(c + Vector2(-sz * 0.3, 0), sz * 0.45, 0, TAU, 16, col, 2.0)
			draw_arc(c + Vector2(sz * 0.3, 0), sz * 0.45, 0, TAU, 16, col, 2.0)
		"seminar":
			# Advisor seminar: open book (pages + spine + page lines)
			draw_polyline(PackedVector2Array([c + Vector2(0, -sz * 0.45), c + Vector2(-sz * 0.8, -sz * 0.65), c + Vector2(-sz * 0.8, sz * 0.5), c + Vector2(0, sz * 0.7), c + Vector2(0, -sz * 0.45)]), col, 2.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(0, -sz * 0.45), c + Vector2(sz * 0.8, -sz * 0.65), c + Vector2(sz * 0.8, sz * 0.5), c + Vector2(0, sz * 0.7), c + Vector2(0, -sz * 0.45)]), col, 2.0, true)
			for k in range(3):
				var yy: float = -sz * 0.3 + sz * 0.3 * k
				draw_line(c + Vector2(-sz * 0.62, yy - sz * 0.05), c + Vector2(-sz * 0.18, yy + sz * 0.07), col, 1.2)
				draw_line(c + Vector2(sz * 0.18, yy + sz * 0.07), c + Vector2(sz * 0.62, yy - sz * 0.05), col, 1.2)
		"start":
			# Settlement: four-pointed star
			var sp := PackedVector2Array([
				c + Vector2(0, -sz * 0.8), c + Vector2(sz * 0.25, -sz * 0.25),
				c + Vector2(sz * 0.8, 0), c + Vector2(sz * 0.25, sz * 0.25),
				c + Vector2(0, sz * 0.8), c + Vector2(-sz * 0.25, sz * 0.25),
				c + Vector2(-sz * 0.8, 0), c + Vector2(-sz * 0.25, -sz * 0.25)
			])
			draw_colored_polygon(sp, col)
		_:
			draw_circle(c, sz * 0.4, col)
