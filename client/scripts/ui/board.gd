@tool
extends Control
## Life board: 24-tile ring (7x7 outer perimeter), drawing tiles and player pawns that hop along tiles with adaptive sizing.
## Card-style tiles with category color bands, client territory badges, coin/pawn tokens with gold rims, and landing rings.

const COLS := 7
var tiles: Array = []
var players: Array = []
var territory: Dictionary = {}
var current_id := ""
var _shown: Dictionary = {}   # playerId -> float position (continuous value along the ring)
var _target: Dictionary = {}  # playerId -> int
var _pulse := 0.0
var _freeze_timer := 0.0
var _center_texture: Texture2D = null
var _landing_rings: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for path: String in ["res://assets/board_center.png", "res://assets/board_center.webp", "res://assets/title.jpg"]:
		if ResourceLoader.exists(path):
			_center_texture = load(path)
			break


func _ready() -> void:
	if not Engine.is_editor_hint():
		Portraits.add_player_avatar_callback(_on_player_avatar_loaded)
		if Net != null:
			Net.avatar_loaded.connect(_on_player_avatar_loaded)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		Portraits.remove_player_avatar_callback(_on_player_avatar_loaded)
		if Net != null and Net.avatar_loaded.is_connected(_on_player_avatar_loaded):
			Net.avatar_loaded.disconnect(_on_player_avatar_loaded)


func _on_player_avatar_loaded(_arg1: Variant = null, _arg2: Variant = null) -> void:
	queue_redraw()


func freeze_movement(duration: float) -> void:
	_freeze_timer = duration


func set_data(board: Array, ps: Array, current: String, terr: Dictionary = {}) -> void:
	tiles = board
	players = ps
	current_id = current
	territory = terr
	for p: Dictionary in ps:
		var id: String = str(p.get("id", ""))
		_target[id] = int(p.get("pos", 0))
		if not _shown.has(id):
			_shown[id] = float(p.get("pos", 0))
	queue_redraw()


func _spawn_landing_ring(pos: Vector2, color: Color, rad: float) -> void:
	_landing_rings.append({
		"pos": pos,
		"color": color,
		"elapsed": 0.0,
		"duration": 0.35,
		"radius": rad
	})


func _process(delta: float) -> void:
	_pulse += delta * 4.0
	var n: int = tiles.size()
	if n == 0:
		return

	if not _landing_rings.is_empty():
		var ri: int = _landing_rings.size() - 1
		while ri >= 0:
			var ring: Dictionary = _landing_rings[ri]
			ring["elapsed"] = float(ring["elapsed"]) + delta
			if float(ring["elapsed"]) >= float(ring["duration"]):
				_landing_rings.remove_at(ri)
			ri -= 1
		queue_redraw()

	if _freeze_timer > 0.0:
		_freeze_timer -= delta
		queue_redraw()
		return

	var moving: bool = false
	var cs := _cell_size()
	var c_min: float = minf(cs.x, cs.y)
	var p_idx: int = 0
	for id: String in _target.keys():
		var cur: float = float(_shown.get(id, 0.0))
		var tgt: float = float(_target[id])
		var diff: float = fposmod(tgt - cur, n)
		if diff > 0.01:
			var prev_step: int = int(floorf(cur))
			cur = fposmod(cur + minf(diff, delta * 6.0), n)
			var reached: bool = false
			if fposmod(tgt - cur, n) > n - 0.5:
				cur = tgt
				reached = true
			var new_step: int = int(floorf(cur))
			var off: Vector2 = Vector2((p_idx % 2) * 2 - 1, int(p_idx / 2.0) * 2 - 1) * c_min * 0.13
			var p_col: Color = UI.PLAYER_COLORS[p_idx % 4]
			var p_rad: float = c_min * 0.13
			if new_step != prev_step:
				if id == current_id:
					Sound.play("step", self)
				var ground_p: Vector2 = _point_on_ring(float(new_step)) + off
				_spawn_landing_ring(ground_p, p_col, p_rad)
			elif reached:
				var ground_p: Vector2 = _point_on_ring(tgt) + off
				_spawn_landing_ring(ground_p, UI.GOLD, p_rad)
			_shown[id] = cur
			moving = true
		p_idx += 1
	if moving or current_id != "" or not _landing_rings.is_empty():
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
	draw_rect(inner, Color("#0d231e"), true)
	draw_rect(inner, Color("#1a4239"), false, 1.5)

	if _center_texture != null:
		# Cover the whole inner frame: crop the centred region of the texture that matches its aspect
		var tex_sz: Vector2 = _center_texture.get_size()
		var cover: float = maxf(inner.size.x / tex_sz.x, inner.size.y / tex_sz.y)
		var src_sz: Vector2 = inner.size / cover
		var src_rect := Rect2((tex_sz - src_sz) * 0.5, src_sz)
		var dst := inner.grow(-1.5)
		draw_texture_rect_region(_center_texture, dst, src_rect, Color(1, 1, 1, 0.20))
		draw_rect(inner, Color("#1a4239"), false, 1.5)

	# Draw center subtle glowing star-ray compass
	var center_pt: Vector2 = inner.get_center()
	var compass_rad: float = minf(inner.size.x, inner.size.y) * 0.38
	draw_arc(center_pt, compass_rad, 0, TAU, 48, Color("#1a4239", 0.4), 1.5)
	draw_arc(center_pt, compass_rad * 0.75, 0, TAU, 36, Color("#1a4239", 0.3), 1.0)
	draw_arc(center_pt, compass_rad * 0.35, 0, TAU, 24, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.25), 1.0)

	# Rotating four-pointed star rays
	var star_rot: float = _pulse * 0.05
	for arm: int in range(4):
		var ang: float = star_rot + float(arm) * (PI * 0.5)
		var p_out: Vector2 = center_pt + Vector2(cos(ang), sin(ang)) * (compass_rad * 0.95)
		var p_left: Vector2 = center_pt + Vector2(cos(ang + 0.25), sin(ang + 0.25)) * (compass_rad * 0.22)
		var p_right: Vector2 = center_pt + Vector2(cos(ang - 0.25), sin(ang - 0.25)) * (compass_rad * 0.22)
		var tri: PackedVector2Array = PackedVector2Array([center_pt, p_left, p_out])
		draw_colored_polygon(tri, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.14))
		var tri2: PackedVector2Array = PackedVector2Array([center_pt, p_right, p_out])
		draw_colored_polygon(tri2, Color(UI.ACCENT_2.r, UI.ACCENT_2.g, UI.ACCENT_2.b, 0.10))

	# 2. Draw 24 life tiles as cards
	var deferred_names: Array = []
	for i: int in tiles.size():
		var t: Dictionary = tiles[i]
		var r: Rect2 = tile_rect(i)
		var type_key: String = str(t.get("type", ""))
		var col: Color = UI.TILE_COLORS.get(type_key, UI.PANEL_2)
		var is_corner: bool = (i == 0 or i == 6 or i == 12 or i == 18)

		# Tile card base: rounded rect base (PANEL_2)
		draw_style_box(UI.box(UI.PANEL_2, 8, Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.22), 0), r)

		# Category colour band: corner tiles use single L-shaped band hugging outer corner; edge tiles use inset rounded band
		var band_sz: float = 7.0
		if is_corner:
			_draw_corner_tile_band(r, i, col, band_sz)
		else:
			var inset: float = 5.0
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(int(band_sz * 0.5))
			sb.anti_aliasing = true
			if i <= 6:
				draw_style_box(sb, Rect2(r.position.x + inset, r.position.y, r.size.x - inset * 2.0, band_sz))
			elif i <= 11:
				draw_style_box(sb, Rect2(r.end.x - band_sz, r.position.y + inset, band_sz, r.size.y - inset * 2.0))
			elif i <= 18:
				draw_style_box(sb, Rect2(r.position.x + inset, r.end.y - band_sz, r.size.x - inset * 2.0, band_sz))
			else:
				draw_style_box(sb, Rect2(r.position.x, r.position.y + inset, band_sz, r.size.y - inset * 2.0))

		# Tile index number in subtle outer corner (top corner away from bottom name area across all layouts)
		var idx_str: String = str(i)
		var is_phone := UI.is_phone()
		var idx_fs: int = 9 if is_phone else 10
		var idx_w: float = font.get_string_size(idx_str, HORIZONTAL_ALIGNMENT_LEFT, -1, idx_fs).x
		var idx_pos: Vector2
		if i == 6:
			idx_pos = Vector2(r.position.x + 3, r.position.y + band_sz + idx_fs * 0.85)
		elif i <= 6:
			idx_pos = Vector2(r.end.x - idx_w - 3, r.position.y + band_sz + idx_fs * 0.85)
		elif i <= 11:
			idx_pos = Vector2(r.position.x + 3, r.position.y + idx_fs * 0.85 + 2)
		elif i == 18:
			idx_pos = Vector2(r.end.x - idx_w - 3, r.position.y + idx_fs * 0.85 + 2)
		elif i <= 18:
			idx_pos = Vector2(r.position.x + 3, r.position.y + idx_fs * 0.85 + 2)
		else:
			idx_pos = Vector2(r.end.x - idx_w - 3, r.position.y + idx_fs * 0.85 + 2)
		draw_string(font, idx_pos, idx_str, HORIZONTAL_ALIGNMENT_LEFT, -1, idx_fs, Color(1, 1, 1, 0.45))

		# Territory overlay: owner player colour inner border + corner client portrait badge
		var terr_val: Variant = territory.get(i, territory.get(str(i), null))
		if terr_val is Dictionary:
			var owner_pid: String = str(terr_val.get("playerId", ""))
			var owner_col: Color = UI.GOLD
			for pi: int in range(players.size()):
				if str(players[pi].get("id", "")) == owner_pid:
					owner_col = UI.PLAYER_COLORS[pi % 4]
					break
			# Rounded inner border matching tile card radius 8
			var terr_sb := StyleBoxFlat.new()
			terr_sb.bg_color = Color(0, 0, 0, 0)
			terr_sb.set_corner_radius_all(8)
			terr_sb.set_border_width_all(3)
			terr_sb.border_color = owner_col
			draw_style_box(terr_sb, r.grow(-1.5))

			# Small circular client portrait badge in tile corner
			var badge_rad: float = clampf(c_min * 0.17, 9.0, 14.0)
			var badge_c: Vector2 = Vector2(r.position.x + badge_rad + 4.0, r.position.y + badge_rad + 4.0)
			if i <= 6:
				badge_c.y += band_sz
			elif i >= 19:
				badge_c.x += band_sz
			var c_id: String = str(terr_val.get("clientId", ""))
			var c_name: String = str(terr_val.get("clientName", ""))
			var port_tex: Texture2D = Portraits.get_texture(c_id)

			draw_circle(badge_c, badge_rad, owner_col)
			if port_tex != null:
				_draw_circle_texture(badge_c, badge_rad, badge_rad, port_tex)
				draw_arc(badge_c, badge_rad, 0, TAU, 24, owner_col, 2.0)
				draw_arc(badge_c, badge_rad + 1.0, 0, TAU, 24, UI.GOLD, 1.0)
			else:
				var initial_c: String = c_name.substr(0, 1)
				var b_fs: int = UI.fs(int(badge_rad * 1.1))
				draw_string(font, badge_c + Vector2(-badge_rad, b_fs * 0.36), initial_c, HORIZONTAL_ALIGNMENT_CENTER, int(badge_rad * 2), b_fs, Color.WHITE)
				draw_arc(badge_c, badge_rad, 0, TAU, 24, UI.GOLD, 1.5)

		# Active player tile frame highlight (rounded rect matching tile card)
		for pi: int in range(players.size()):
			if str(players[pi].get("id", "")) == current_id and int(players[pi].get("pos", 0)) == i:
				var active_sb := StyleBoxFlat.new()
				active_sb.bg_color = Color(0, 0, 0, 0)
				active_sb.set_corner_radius_all(8)
				active_sb.set_border_width_all(2)
				var pulse_alpha: float = 0.6 + sin(_pulse * 2.0) * 0.35
				active_sb.border_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, pulse_alpha)
				draw_style_box(active_sb, r.grow(0.5))
				break

		# Larger symbol (~40% of tile), corner tiles slightly larger
		var sym_sz: float = c_min * (0.30 if UI.is_phone_portrait() else (0.28 if UI.is_phone_landscape() else 0.38))
		if is_corner:
			sym_sz *= 1.15
		var sym_center := Vector2(r.get_center().x, r.position.y + r.size.y * (0.35 if UI.is_phone_portrait() else (0.38 if UI.is_phone_landscape() else 0.42)))
		_draw_tile_symbol(type_key, sym_center, sym_sz, col.lightened(0.25))

		# Name label under symbol
		var name_str: String = str(t.get("name", ""))
		var max_name_w: float = r.size.x - 4.0
		if name_str != "":
			if UI.is_phone_portrait():
				var single_fs: int = 11
				while single_fs >= 10 and font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, single_fs).x > max_name_w:
					single_fs -= 1

				var fits_single: bool = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, single_fs).x <= max_name_w
				if fits_single:
					var name_y: float = r.end.y - (band_sz + 2.0 if (i >= 12 and i <= 18) else 3.0)
					draw_string(font, Vector2(r.position.x + 2, name_y), name_str, HORIZONTAL_ALIGNMENT_CENTER, int(max_name_w), single_fs, UI.TEXT)
				else:
					var mid: int = 2 if name_str.length() == 5 else int(ceilf(float(name_str.length()) / 2.0))
					var line1: String = name_str.substr(0, mid)
					var line2: String = name_str.substr(mid)
					var wrap_fs: int = 10
					while wrap_fs > 9 and (font.get_string_size(line1, HORIZONTAL_ALIGNMENT_CENTER, -1, wrap_fs).x > max_name_w or font.get_string_size(line2, HORIZONTAL_ALIGNMENT_CENTER, -1, wrap_fs).x > max_name_w):
						wrap_fs -= 1
					var y2: float = r.end.y - (band_sz + 2.0 if (i >= 12 and i <= 18) else 3.0)
					var y1: float = y2 - wrap_fs * 1.05
					draw_string(font, Vector2(r.position.x + 2, y1), line1, HORIZONTAL_ALIGNMENT_CENTER, int(max_name_w), wrap_fs, UI.TEXT)
					draw_string(font, Vector2(r.position.x + 2, y2), line2, HORIZONTAL_ALIGNMENT_CENTER, int(max_name_w), wrap_fs, UI.TEXT)
			else:
				var min_fs: int = 10 if is_phone else 11
				var name_fs: int = 11 if is_phone else 12
				while name_fs > min_fs and font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w:
					name_fs -= 1
				var display_name: String = name_str
				if font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w:
					while display_name.length() > 1 and font.get_string_size(display_name + "…", HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs).x > max_name_w:
						display_name = display_name.substr(0, display_name.length() - 1)
					display_name += "…"
				var name_y: float = r.end.y - (band_sz + 2.0 if (i >= 12 and i <= 18) else (4.0 if is_phone else 6.0))
				if UI.is_phone_landscape():
					deferred_names.append([Vector2(r.position.x + 2, name_y), display_name, int(max_name_w), name_fs])
				else:
					draw_string(font, Vector2(r.position.x + 2, name_y), display_name, HORIZONTAL_ALIGNMENT_CENTER, int(max_name_w), name_fs, UI.TEXT)

	# 3. Active player tile breathing aura
	if current_id != "" and _shown.has(current_id):
		var cur_tile_idx: int = int(floorf(float(_shown[current_id]) + 0.1)) % n
		var cur_r: Rect2 = tile_rect(cur_tile_idx)
		var glow_alpha: float = 0.60 + sin(_pulse * 1.5) * 0.35
		var glow_col := Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, glow_alpha)
		draw_style_box(UI.box(Color(0, 0, 0, 0), 10, glow_col, 0, false), cur_r.grow(3))

	# 4. Draw landing expanding rings
	for ring: Dictionary in _landing_rings:
		var prog: float = clampf(float(ring["elapsed"]) / float(ring["duration"]), 0.0, 1.0)
		var r_pos: Vector2 = ring["pos"]
		var r_rad: float = lerpf(float(ring["radius"]), float(ring["radius"]) * 2.4, prog)
		var r_alpha: float = (1.0 - prog) * 0.85
		var r_col: Color = ring["color"]
		r_col.a *= r_alpha
		var r_width: float = maxf(1.0, 2.5 * (1.0 - prog))
		draw_arc(r_pos, r_rad, 0.0, TAU, 32, r_col, r_width)

	# 5. Draw player tokens (coin/pawn with 2 px gold rim, drop shadow, hop animation)
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

		# Ground drop shadow
		var shadow_scale_x: float = clampf(1.15 - hop_sin * 0.45, 0.5, 1.25)
		var shadow_scale_y: float = clampf(0.55 - hop_sin * 0.25, 0.25, 0.65)
		var shadow_alpha: float = clampf(0.40 - hop_sin * 0.22, 0.12, 0.45)
		draw_ellipse(ground_pos + Vector2(0, rad * 0.4), rad * shadow_scale_x, rad * shadow_scale_y, Color(0, 0, 0, shadow_alpha))

		# Jump squash and stretch
		var stretch_y: float = 1.0 + hop_sin * 0.25
		var squash_x: float = 1.0 - hop_sin * 0.18
		if hop_sin < 0.05 and _target.has(id) and absf(float(_target[id]) - f) > 0.02:
			stretch_y = 0.82
			squash_x = 1.22

		var pawn_pos: Vector2 = ground_pos + Vector2(0, jump_y)
		var rx: float = rad * squash_x
		var ry: float = rad * stretch_y

		# Active player breathing aura
		if id == current_id:
			var aura_rad_x: float = (rx + 5.0) + sin(_pulse * 2.2) * 2.5
			var aura_rad_y: float = (ry + 5.0) + sin(_pulse * 2.2) * 2.5
			var aura_alpha: float = 0.45 + sin(_pulse * 2.2) * 0.25
			draw_ellipse(pawn_pos, aura_rad_x, aura_rad_y, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, aura_alpha))
			draw_ellipse(pawn_pos, rx + 3.0, ry + 3.0, Color.WHITE)

		# 2 px gold rim on coin token
		draw_ellipse(pawn_pos, rx + 2.0, ry + 2.0, UI.GOLD)

		# Pawn body (applying deformation) / player color ring
		draw_ellipse(pawn_pos, rx, ry, c)

		# Player avatar texture (Google photo URL)
		var av_tex: Texture2D = null
		if not Engine.is_editor_hint():
			if id == Net.player_id and Net.avatar_tex != null:
				av_tex = Net.avatar_tex
			else:
				var av_url: String = str(p.get("avatar", ""))
				if av_url != "" and av_url != "null" and av_url.begins_with("https://"):
					av_tex = Portraits.get_player_avatar(av_url)

		if av_tex != null:
			# Photo clipped to pawn circle (with squash/stretch radii), thin ring in player colour c between photo and gold rim
			var inner_rx: float = maxf(rx - 2.0, 1.0)
			var inner_ry: float = maxf(ry - 2.0, 1.0)
			_draw_circle_texture(pawn_pos, inner_rx, inner_ry, av_tex)
			# Top enamel glossy highlight
			draw_arc(pawn_pos + Vector2(0, -ry * 0.15), rx * 0.65, -PI * 0.8, -PI * 0.2, 16, Color(1, 1, 1, 0.40), 2.0)
		else:
			# Top enamel glossy highlight
			draw_arc(pawn_pos + Vector2(0, -ry * 0.15), rx * 0.65, -PI * 0.8, -PI * 0.2, 16, Color(1, 1, 1, 0.40), 2.0)

			# Player initial avatar
			var initial_char: String = str(p.get("name", "顧")).substr(0, 1)
			var char_fs: int = mini(UI.fs(int(rad * 1.15)), int(rad * 1.5))
			# Drop shadow text
			draw_string(font, pawn_pos + Vector2(-rad, char_fs * 0.38 + 1), initial_char, HORIZONTAL_ALIGNMENT_CENTER, int(rad * 2), char_fs, Color(0, 0, 0, 0.75))
			# Main text
			draw_string(font, pawn_pos + Vector2(-rad, char_fs * 0.38), initial_char, HORIZONTAL_ALIGNMENT_CENTER, int(rad * 2), char_fs, Color.WHITE)

		idx += 1

	# 6. Phone landscape: place names on top of pawns, outlined so they stay readable
	for dn: Array in deferred_names:
		draw_string_outline(font, dn[0], dn[1], HORIZONTAL_ALIGNMENT_CENTER, dn[2], dn[3], 5, Color("#0d231e"))
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


func _draw_circle_texture(center: Vector2, rad_x: float, rad_y: float, tex: Texture2D) -> void:
	if tex == null:
		return
	var num_pts := 28
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var ts := tex.get_size()
	var tw: float = maxf(ts.x, 1.0)
	var th: float = maxf(ts.y, 1.0)
	var scale_u: float = 1.0
	var scale_v: float = 1.0
	if tw > th:
		scale_u = th / tw
	elif th > tw:
		scale_v = tw / th

	for k in range(num_pts):
		var angle: float = float(k) * TAU / float(num_pts)
		var cos_a: float = cos(angle)
		var sin_a: float = sin(angle)
		pts.append(center + Vector2(cos_a * rad_x, sin_a * rad_y))
		uvs.append(Vector2(0.5 + cos_a * 0.5 * scale_u, 0.5 + sin_a * 0.5 * scale_v))
		cols.append(Color.WHITE)
	draw_polygon(pts, cols, uvs, tex)


func _draw_corner_tile_band(r: Rect2, idx: int, col: Color, band_sz: float) -> void:
	var r_out: float = 8.0
	var r_in: float = 3.5
	var inset: float = 5.0
	var w: float = band_sz
	var len_u: float = r.size.x - inset - w * 0.5
	var len_v: float = r.size.y - inset - w * 0.5

	var p_corner: Vector2
	var sx: float = 1.0
	var sy: float = 1.0

	match idx:
		0:
			p_corner = Vector2(r.position.x, r.position.y)
			sx = 1.0
			sy = 1.0
		6:
			p_corner = Vector2(r.end.x, r.position.y)
			sx = -1.0
			sy = 1.0
		12:
			p_corner = Vector2(r.end.x, r.end.y)
			sx = -1.0
			sy = -1.0
		18:
			p_corner = Vector2(r.position.x, r.end.y)
			sx = 1.0
			sy = -1.0
		_:
			return

	var pts := PackedVector2Array()
	var segs := 8

	# 1. Outer corner arc from (0, r_out) to (r_out, 0)
	for k in range(segs + 1):
		var a: float = PI + (float(k) / float(segs)) * (PI * 0.5)
		var u: float = r_out + r_out * cos(a)
		var v: float = r_out + r_out * sin(a)
		pts.append(p_corner + Vector2(u * sx, v * sy))

	# 2. Horizontal arm rounded cap from (len_u, 0) to (len_u, w) around (len_u, w * 0.5)
	for k in range(segs + 1):
		var a: float = -PI * 0.5 + (float(k) / float(segs)) * PI
		var u: float = len_u + (w * 0.5) * cos(a)
		var v: float = (w * 0.5) + (w * 0.5) * sin(a)
		pts.append(p_corner + Vector2(u * sx, v * sy))

	# 3. Inner fillet arc from (w + r_in, w) to (w, w + r_in) around (w + r_in, w + r_in)
	for k in range(segs + 1):
		var a: float = -PI * 0.5 - (float(k) / float(segs)) * (PI * 0.5)
		var u: float = (w + r_in) + r_in * cos(a)
		var v: float = (w + r_in) + r_in * sin(a)
		pts.append(p_corner + Vector2(u * sx, v * sy))

	# 4. Vertical arm rounded cap from (w, len_v) to (0, len_v) around (w * 0.5, len_v)
	for k in range(segs + 1):
		var a: float = (float(k) / float(segs)) * PI
		var u: float = (w * 0.5) + (w * 0.5) * cos(a)
		var v: float = len_v + (w * 0.5) * sin(a)
		pts.append(p_corner + Vector2(u * sx, v * sy))

	draw_colored_polygon(pts, col)
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	draw_polyline(loop, col, 1.0, true)

