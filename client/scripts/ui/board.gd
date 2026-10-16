@tool
extends Control
## Real 3D city board; server tile order remains authoritative.
const City := preload("res://scripts/ui/board_city.gd")
@export var construction_enabled := false
var tiles: Array = []
var players: Array = []
var territory: Dictionary = {}
var current_id := ""
var _shown: Dictionary = {}
var _freeze_timer := 0.0
var _surface: SubViewportContainer
var _view: SubViewport
var _city: Node3D
var _caption: Label
var _selected := -1
var _toolbar: HBoxContainer
var _building := false
var _turns := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_surface = SubViewportContainer.new()
	_surface.stretch = true
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	_surface.add_child(_view)
	_city = City.new()
	_view.add_child(_city)
	_caption = Label.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_size_override("font_size", 13)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_caption)
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	add_child(_toolbar)
	for text: String in ["＋", "－", "復位", "邊移"]:
		var button := Button.new()
		button.text = text
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size = Vector2(34, 30)
		button.pressed.connect(_camera_action.bind(text))
		_toolbar.add_child(button)
	if construction_enabled:
		var build_button := Button.new()
		build_button.text = "放置建築"
		build_button.toggle_mode = true
		build_button.toggled.connect(_toggle_build)
		_toolbar.add_child(build_button)
		var rotate := Button.new()
		rotate.text = "旋轉"
		rotate.pressed.connect(_rotate_build)
		_toolbar.add_child(rotate)
	mouse_exited.connect(func(): _city._camera.pointer(Vector2.ZERO, false))
	resized.connect(_layout)
	_layout()
	_city.set_tiles(tiles)
	_city.set_territory(territory, players)
	_update_caption()

func get_inner_rect() -> Rect2:
	var city := _city_rect()
	return Rect2(city.position.x + 6, city.end.y - 96, city.size.x - 12, 90)

func _city_rect() -> Rect2:
	if construction_enabled:
		return Rect2(size.x * 0.3, 4, size.x * 0.7 - 4, size.y - 8)
	return Rect2(size.x / 7.0 + 4, size.y / 7.0 + 4, size.x * 5.0 / 7.0 - 8, size.y * 5.0 / 7.0 - 8)

func tile_rect(index: int) -> Rect2:
	var cell := Vector2(size.x / 7.0, size.y / 7.0)
	var at: Vector2
	if index <= 6:
		at = Vector2(index, 0)
	elif index <= 11:
		at = Vector2(6, index - 6)
	elif index <= 18:
		at = Vector2(18 - index, 6)
	else:
		at = Vector2(0, 24 - index)
	return Rect2(at * cell + Vector2(3, 3), cell - Vector2(6, 6))

func _layout() -> void:
	if _surface == null:
		return
	var area := _city_rect()
	_surface.position = area.position
	_surface.size = area.size.max(Vector2(2, 2))
	_city.fit_camera(_surface.size)
	_caption.position = area.position + Vector2(10, 8)
	_caption.size = Vector2(maxf(20, area.size.x - 20), 48)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_outline_size", 2)
	_toolbar.position = area.position + Vector2(8, 58)
	queue_redraw()

func set_data(board: Array, ps: Array, current: String, terr: Dictionary = {}) -> void:
	var changed := tiles != board
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
	if _city != null:
		if changed:
			_city.set_tiles(tiles)
		_city.set_territory(territory, players)
	_update_caption()

func freeze_movement(duration: float) -> void:
	_freeze_timer = maxf(duration, 0.0)

func _process(delta: float) -> void:
	if _city == null or tiles.is_empty():
		return
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
	_city.update_players(players, _shown, current_id, delta)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not construction_enabled:
		for i in range(tiles.size()):
			if tile_rect(i).has_point(event.position):
				_selected = i
				_city.select_tile(i)
				if _city.has_method("focus_tile"):
					_city.focus_tile(i, not UI.reduce_motion)
				_update_caption()
				accept_event()
				return
	var local: Vector2 = event.position - _surface.position
	var inside := Rect2(Vector2.ZERO, _surface.size).has_point(local)
	_city._camera.pointer(local, inside)
	if not inside:
		return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_city._camera.pan_pixels(event.relative)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_city._camera.orbit(event.relative)
		if _building:
			var ground: Variant = _city.ground_at(local)
			if ground is Vector3:
				_city.grid.update_preview(ground, _turns)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_city._camera.zoom_by(0.9)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_city._camera.zoom_by(1.1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _building:
				var ground: Variant = _city.ground_at(local)
				if ground is Vector3:
					_city.grid.update_preview(ground, _turns)
					var placed: Node3D = _city.grid.commit_preview()
					_caption.text = "建築已放置" if placed != null else "無法放置：建築重疊、道路或超出範圍"
				return
			_selected = _city.nearest_tile(local)
			_city.select_tile(_selected)
			_update_caption()

func _camera_action(action: String) -> void:
	match action:
		"＋": _city._camera.zoom_by(0.85)
		"－": _city._camera.zoom_by(1.15)
		"復位": _city._camera.reset_view()
		"邊移":
			_city._camera.edge_pan_enabled = not _city._camera.edge_pan_enabled
			_caption.text = "滑鼠邊緣平移：" + ("開啟" if _city._camera.edge_pan_enabled else "關閉")

func _toggle_build(enabled: bool) -> void:
	_building = enabled
	if enabled:
		_city.grid.begin_preview(preload("res://scenes/city/neighborhood_office.tscn"), Vector2i(2, 2))
		_caption.text = "配置預覽：綠色可放置，紅色表示重疊或超出範圍；點選放置"
	else:
		_city.grid.cancel_preview()
		_update_caption()

func _rotate_build() -> void:
	_turns = (_turns + 1) % 4
	if _building:
		_city.grid.update_preview(_city.grid.cell_to_world(_city.grid._preview_cell), _turns)

func _update_caption() -> void:
	if _caption == null:
		return
	var index := _selected
	if index < 0:
		for p: Dictionary in players:
			if str(p.get("id", "")) == current_id:
				index = int(p.get("pos", 0))
	if index >= 0 and index < tiles.size():
		var tile: Dictionary = tiles[index]
		var owner: Variant = territory.get(str(index), territory.get(index, null))
		var detail := ""
		if owner is Dictionary:
			detail = " · 客戶：" + str(owner.get("clientName", "已簽約"))
		_caption.text = "◆ 信義區客戶生活圈 ◆\n%02d  %s · %s%s" % [index + 1, str(tile.get("name", "")), UI.tile_name(str(tile.get("type", ""))), detail]
	else:
		_caption.text = "◆ 信義區客戶生活圈 ◆\n法國巴黎人壽 · 新人顧問培訓"

func _draw() -> void:
	if construction_enabled:
		return
	var font := get_theme_default_font()
	for i in range(tiles.size()):
		var rect := tile_rect(i)
		var tile: Dictionary = tiles[i]
		var kind := str(tile.get("type", "client"))
		var col: Color = UI.TILE_COLORS.get(kind, UI.ACCENT_2)
		var active := i == _selected
		for p: Dictionary in players:
			if str(p.get("id", "")) == current_id and int(_shown.get(current_id, 0)) == i:
				active = true
		draw_style_box(UI.box(Color("174438") if active else Color("0b302b"), 7, UI.GOLD if active else col.darkened(0.45), 0, false), rect)
		draw_style_box(UI.box(col, 3, Color.TRANSPARENT, 0, false), Rect2(rect.position + Vector2(3, 2), Vector2(rect.size.x - 6, 4)))
		var small := rect.size.x < 80
		var font_size := 11 if small else 15
		var name_text := str(tile.get("name", ""))
		if small and name_text.length() > 4:
			name_text = name_text.replace("社區咖啡廳", "社區咖啡").replace("公司說明會", "公司說明").replace("共同工作空間", "共同工作")
		var icon_kind := kind
		if name_text.contains("公司") or name_text.contains("商圈") or name_text.contains("市場") and kind == "client":
			icon_kind = "building"
		_draw_tile_icon(icon_kind, rect.get_center() + Vector2(0, -8), minf(rect.size.x * 0.22, rect.size.y * 0.23), col)
		var text_width := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if text_width > rect.size.x - 4:
			font_size = maxi(9, int(font_size * (rect.size.x - 4) / text_width))
		draw_string(font, Vector2(rect.position.x, rect.end.y - 10), name_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, UI.TEXT)
		draw_string(font, rect.position + Vector2(6, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.MUTED)
		var badge := 0
		for p: Dictionary in players:
			var pid := str(p.get("id", ""))
			if int(_shown.get(pid, 0)) == i:
				draw_circle(rect.position + Vector2(rect.size.x - 10 - badge * 12, 14), 5, UI.PLAYER_COLORS[players.find(p) % 4])
				badge += 1

func _draw_tile_icon(kind: String, c: Vector2, r: float, col: Color) -> void:
	match kind:
		"building":
			for j in range(2):
				var at := c + Vector2(-r + j * r, -r * (0.5 + j * 0.5))
				draw_rect(Rect2(at, Vector2(r * 0.85, r * (1.5 + j * 0.5))), col, false, 2)
				for k in range(3):
					draw_line(at + Vector2(3, 5 + k * r * 0.35), at + Vector2(r * 0.85 - 3, 5 + k * r * 0.35), col, 2)
		"seminar":
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), col, false, 2)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r), col, 2)
			for j in range(3):
				draw_line(c + Vector2(-r * 0.8, -r * 0.5 + j * r * 0.5), c + Vector2(-r * 0.2, -r * 0.5 + j * r * 0.5), col, 1.5)
				draw_line(c + Vector2(r * 0.2, -r * 0.5 + j * r * 0.5), c + Vector2(r * 0.8, -r * 0.5 + j * r * 0.5), col, 1.5)
		"client", "referral":
			draw_circle(c + Vector2(0, -r * 0.5), r * 0.35, col)
			draw_style_box(UI.box(col, int(r * 0.5), Color.TRANSPARENT, 0, false), Rect2(c + Vector2(-r * 0.65, 0), Vector2(r * 1.3, r * 0.85)))
		"life":
			draw_rect(Rect2(c - Vector2(r * 0.28, r), Vector2(r * 0.56, r * 2)), col)
			draw_rect(Rect2(c - Vector2(r, r * 0.28), Vector2(r * 2, r * 0.56)), col)
		"market":
			for j in range(3):
				draw_rect(Rect2(c + Vector2(-r + j * r * 0.7, r - r * (j + 1) * 0.6), Vector2(r * 0.45, r * (j + 1) * 0.6)), col)
		"audit":
			draw_arc(c - Vector2(r * 0.2, r * 0.2), r * 0.7, 0, TAU, 24, col, 2, true)
			draw_line(c + Vector2.ONE * r * 0.3, c + Vector2.ONE * r, col, 3, true)
		"training":
			var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.7, r * 0.4), c + Vector2(0, r), c + Vector2(-r * 0.7, r * 0.4), c + Vector2(-r * 0.8, -r * 0.6), c + Vector2(0, -r)])
			draw_polyline(points, col, 2, true)
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.35, 0), c + Vector2(-r * 0.05, r * 0.3), c + Vector2(r * 0.4, -r * 0.3)]), col, 2, true)
		_:
			draw_string(get_theme_default_font(), c + Vector2(-r, r * 0.65), UI.tile_icon(kind), HORIZONTAL_ALIGNMENT_CENTER, r * 2, int(r * 2), col)
