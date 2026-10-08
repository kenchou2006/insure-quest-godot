extends Control
## 人生棋盤：24 格環狀（7×7 外圈），繪製格子與玩家棋子，棋子沿格子彈跳移動並自適應尺寸。
## 支援中央精美羅盤主視覺、格子圖示層次辨識與擲骰過場凍結機制。

const COLS := 7
var tiles: Array = []
var players: Array = []
var current_id := ""
var _shown: Dictionary = {}   # playerId -> float 位置（沿環狀的連續值）
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


func get_inner_rect() -> Rect2:
	var s: float = minf(size.x, size.y)
	var cw: float = s / COLS
	var ox: float = (size.x - s) * 0.5
	var oy: float = (size.y - s) * 0.5
	return Rect2(ox + cw + 4.0, oy + cw + 4.0, cw * 5.0 - 8.0, cw * 5.0 - 8.0)


func tile_rect(i: int) -> Rect2:
	var s: float = minf(size.x, size.y)
	var cw: float = s / COLS
	var ch: float = cw
	var ox: float = (size.x - s) * 0.5
	var oy: float = (size.y - s) * 0.5
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
	return Rect2(ox + c * cw, oy + r * ch, cw, ch).grow(-3)


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
	var s: float = minf(size.x, size.y)
	var cw: float = s / COLS
	var fs: int = int(clampf(cw * 0.13, 9, 15))
	var n: int = tiles.size()

	# 1. 棋盤中央區域主視覺（底色、同心羅盤與裝飾星芒）
	var inner := get_inner_rect()
	draw_rect(inner, Color("#091a24"), true)
	draw_rect(inner, Color("#153a4c"), false, 1.5)

	if _center_texture != null:
		var tex_s: Vector2 = inner.size * 0.88
		var tex_pos: Vector2 = inner.position + (inner.size - tex_s) * 0.5
		draw_texture_rect(_center_texture, Rect2(tex_pos, tex_s), false, Color(1, 1, 1, 0.28))

	# 繪製中央微光星芒羅盤
	var center_pt: Vector2 = inner.get_center()
	var compass_rad: float = minf(inner.size.x, inner.size.y) * 0.38
	draw_arc(center_pt, compass_rad, 0, TAU, 48, Color("#1e4b60", 0.4), 1.5)
	draw_arc(center_pt, compass_rad * 0.75, 0, TAU, 36, Color("#1e4b60", 0.3), 1.0)
	draw_arc(center_pt, compass_rad * 0.35, 0, TAU, 24, Color("#f2c14e", 0.25), 1.0)

	# 旋轉四向星芒
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

	# 2. 繪製 24 格人生格子（含清楚色帶、圖示與地點名稱）
	var is_compact: bool = cw < 70.0 or UI.is_phone_portrait()
	for i: int in tiles.size():
		var t: Dictionary = tiles[i]
		var r: Rect2 = tile_rect(i)
		var type_key: String = str(t.get("type", ""))
		var col: Color = UI.TILE_COLORS.get(type_key, UI.PANEL_2)

		# 格子主體底色（深色底帶圓角）
		draw_style_box(UI.box(Color("#0d2432"), 8, col.darkened(0.35), 0), r)

		# 頂部主題色帶（Ribbon）
		var ribbon_h: float = clampf(r.size.y * (0.28 if is_compact else 0.25), 14.0, 22.0)
		var ribbon_r := Rect2(r.position.x, r.position.y, r.size.x, ribbon_h)
		draw_style_box(UI.box(col.darkened(0.15), 6, col.lightened(0.15), 0), ribbon_r)

		# 色帶文字與格子序號
		var cat_name: String = {
			"client": "客 客戶", "market": "市 市場", "life": "✚ 人生", "training": "訓 合規",
			"audit": "稽 稽核", "referral": "♥ 轉介", "seminar": "研 研討", "start": "★ 結算"
		}.get(type_key, "事件")
		if is_compact:
			cat_name = cat_name.substr(0, 1)

		var cat_fs: int = int(clampf(ribbon_h * 0.65, 9, 12))
		draw_string(font, Vector2(ribbon_r.position.x + 4, ribbon_r.get_center().y + cat_fs * 0.38), cat_name, HORIZONTAL_ALIGNMENT_LEFT, int(ribbon_r.size.x - 18), cat_fs, Color.WHITE)
		draw_string(font, Vector2(ribbon_r.end.x - 16, ribbon_r.get_center().y + cat_fs * 0.38), str(i), HORIZONTAL_ALIGNMENT_RIGHT, 14, int(cat_fs * 0.9), Color(1, 1, 1, 0.75))

		# 格子中央向量符號繪製
		var body_center := Vector2(r.get_center().x, r.position.y + ribbon_h + (r.size.y - ribbon_h) * 0.42)
		_draw_tile_symbol(type_key, body_center, cw * 0.16, col.lightened(0.35))

		# 格子下緣地點文字（非緊湊時顯示）
		if not is_compact:
			var name_str: String = str(t.get("name", ""))
			var name_fs: int = int(clampf(cw * 0.14, 10, 13))
			draw_string(font, Vector2(r.position.x + 3, r.end.y - 6), name_str, HORIZONTAL_ALIGNMENT_CENTER, int(r.size.x - 6), name_fs, UI.TEXT)

	# 3. 當前輪到者所在格子的外框呼吸發光提示
	if current_id != "" and _shown.has(current_id):
		var cur_tile_idx: int = int(floorf(float(_shown[current_id]) + 0.1)) % n
		var cur_r: Rect2 = tile_rect(cur_tile_idx)
		var glow_alpha: float = 0.60 + sin(_pulse * 1.5) * 0.35
		var glow_col := Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, glow_alpha)
		draw_style_box(UI.box(Color(0, 0, 0, 0), 10, glow_col, 0, false), cur_r.grow(3))

	# 4. 繪製玩家棋子（動態跳躍、落地壓縮與當前玩家呼吸光暈）
	var idx: int = 0
	for p: Dictionary in players:
		var id: String = str(p.get("id", ""))
		var f: float = float(_shown.get(id, float(p.get("pos", 0))))
		var base: Vector2 = _point_on_ring(f)
		var off: Vector2 = Vector2((idx % 2) * 2 - 1, int(idx / 2.0) * 2 - 1) * cw * 0.13
		var c: Color = UI.PLAYER_COLORS[idx % 4]
		var rad: float = cw * 0.13

		var frac: float = f - floorf(f)
		var hop_sin: float = sin(frac * PI)
		var jump_y: float = -hop_sin * (cw * 0.34)
		var ground_pos: Vector2 = base + off

		# 地面影子（越跳越高影子變小淡化，著地時展開）
		var shadow_scale_x: float = clampf(1.15 - hop_sin * 0.45, 0.5, 1.25)
		var shadow_scale_y: float = clampf(0.55 - hop_sin * 0.25, 0.25, 0.65)
		var shadow_alpha: float = clampf(0.40 - hop_sin * 0.22, 0.12, 0.45)
		# Godot 4.7 內建 draw_ellipse(center, 長半軸, 短半軸, color)
		draw_ellipse(ground_pos + Vector2(0, rad * 0.4), rad * shadow_scale_x, rad * shadow_scale_y, Color(0, 0, 0, shadow_alpha))

		# 跳躍壓縮與拉伸（落地壓縮，升空拉伸）
		var stretch_y: float = 1.0 + hop_sin * 0.25
		var squash_x: float = 1.0 - hop_sin * 0.18
		if hop_sin < 0.05 and _target.has(id) and absf(float(_target[id]) - f) > 0.02:
			# 著地剎那微壓縮形變
			stretch_y = 0.82
			squash_x = 1.22

		var pawn_pos: Vector2 = ground_pos + Vector2(0, jump_y)

		# 當前玩家呼吸光暈（Breathing Aura）
		if id == current_id:
			var aura_rad_x: float = (rad * squash_x + 5.0) + sin(_pulse * 2.2) * 2.5
			var aura_rad_y: float = (rad * stretch_y + 5.0) + sin(_pulse * 2.2) * 2.5
			var aura_alpha: float = 0.45 + sin(_pulse * 2.2) * 0.25
			draw_ellipse(pawn_pos, aura_rad_x, aura_rad_y, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, aura_alpha))
			draw_ellipse(pawn_pos, rad * squash_x + 2.5, rad * stretch_y + 2.5, Color.WHITE)
		else:
			draw_ellipse(pawn_pos, rad * squash_x + 1.8, rad * stretch_y + 1.8, Color("#0b1f2a"))

		# 棋子本體（應用形變）
		draw_ellipse(pawn_pos, rad * squash_x, rad * stretch_y, c)

		# 棋子上緣琺瑯立體反光
		draw_arc(pawn_pos + Vector2(0, -rad * stretch_y * 0.15), rad * squash_x * 0.65, -PI * 0.8, -PI * 0.2, 16, Color(1, 1, 1, 0.40), 2.0)

		# 玩家姓名首字頭像
		var initial_char: String = str(p.get("name", "顧")).substr(0, 1)
		var char_fs: int = int(rad * 1.15)
		# 陰影字
		draw_string(font, pawn_pos + Vector2(-rad, char_fs * 0.38 + 1), initial_char, HORIZONTAL_ALIGNMENT_CENTER, int(rad * 2), char_fs, Color(0, 0, 0, 0.75))
		# 主文字
		draw_string(font, pawn_pos + Vector2(-rad, char_fs * 0.38), initial_char, HORIZONTAL_ALIGNMENT_CENTER, int(rad * 2), char_fs, Color.WHITE)

		idx += 1


func _draw_tile_symbol(type_key: String, c: Vector2, sz: float, col: Color) -> void:
	match type_key:
		"client":
			# 咖啡杯／人物拜訪：小茶杯圖案
			draw_arc(c + Vector2(0, sz * 0.2), sz * 0.6, 0, PI, 16, col, 2.0)
			draw_line(c + Vector2(-sz * 0.6, sz * 0.2), c + Vector2(sz * 0.6, sz * 0.2), col, 2.0)
			draw_arc(c + Vector2(sz * 0.6, 0), sz * 0.3, -PI * 0.5, PI * 0.5, 12, col, 1.5)
		"market":
			# 市場行情趨勢：三根長條圖
			draw_rect(Rect2(c.x - sz * 0.7, c.y + sz * 0.1, sz * 0.35, sz * 0.6), col, true)
			draw_rect(Rect2(c.x - sz * 0.15, c.y - sz * 0.6, sz * 0.35, sz * 1.3), col, true)
			draw_rect(Rect2(c.x + sz * 0.4, c.y - sz * 0.2, sz * 0.35, sz * 0.9), col, true)
		"life":
			# 人生十字防線：醫療與愛心十字
			draw_rect(Rect2(c.x - sz * 0.2, c.y - sz * 0.7, sz * 0.4, sz * 1.4), col, true)
			draw_rect(Rect2(c.x - sz * 0.7, c.y - sz * 0.2, sz * 1.4, sz * 0.4), col, true)
		"training":
			# 合規防護盾牌
			var pts := PackedVector2Array([
				c + Vector2(0, sz * 0.8),
				c + Vector2(-sz * 0.7, sz * 0.1),
				c + Vector2(-sz * 0.7, -sz * 0.6),
				c + Vector2(sz * 0.7, -sz * 0.6),
				c + Vector2(sz * 0.7, sz * 0.1)
			])
			draw_polyline(pts, col, 2.0, true)
		"audit":
			# 稽核放大鏡
			draw_arc(c + Vector2(-sz * 0.2, -sz * 0.2), sz * 0.55, 0, TAU, 18, col, 2.0)
			draw_line(c + Vector2(sz * 0.18, sz * 0.18), c + Vector2(sz * 0.75, sz * 0.75), col, 3.0)
		"referral":
			# 轉介紹連結／雙環
			draw_arc(c + Vector2(-sz * 0.3, 0), sz * 0.45, 0, TAU, 16, col, 2.0)
			draw_arc(c + Vector2(sz * 0.3, 0), sz * 0.45, 0, TAU, 16, col, 2.0)
		"seminar":
			# 顧問研討會書本
			draw_line(c + Vector2(-sz * 0.7, sz * 0.3), c + Vector2(0, -sz * 0.3), col, 2.0)
			draw_line(c + Vector2(0, -sz * 0.3), c + Vector2(sz * 0.7, sz * 0.3), col, 2.0)
			draw_line(c + Vector2(-sz * 0.7, sz * 0.7), c + Vector2(0, sz * 0.1), col, 2.0)
			draw_line(c + Vector2(0, sz * 0.1), c + Vector2(sz * 0.7, sz * 0.7), col, 2.0)
			draw_line(c + Vector2(0, -sz * 0.3), c + Vector2(0, sz * 0.6), col, 1.5)
		"start":
			# 結算四角星芒
			var sp := PackedVector2Array([
				c + Vector2(0, -sz * 0.8), c + Vector2(sz * 0.25, -sz * 0.25),
				c + Vector2(sz * 0.8, 0), c + Vector2(sz * 0.25, sz * 0.25),
				c + Vector2(0, sz * 0.8), c + Vector2(-sz * 0.25, sz * 0.25),
				c + Vector2(-sz * 0.8, 0), c + Vector2(-sz * 0.25, -sz * 0.25)
			])
			draw_colored_polygon(sp, col)
		_:
			draw_circle(c, sz * 0.4, col)
