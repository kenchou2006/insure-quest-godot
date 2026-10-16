@tool
extends Control
## Taipei 101 Advisor HQ, 3D isometric board.
## The HQ campus itself is the board: 24 tiles are slabs set into the walkway around the plaza (clockwise,
## four training zones, large corner nodes 1/7/13/19), the 101 tower stands behind the back corner.
## Layers: SubViewport (3D campus, tiles, pawns) under a 2D overlay (2px line icons, zone labels, captions)
## whose positions are projected from the 3D tiles every frame, so they stay on the ground at any size.
## Same API as board.gd / board_hq.gd: set_data / freeze_movement / get_inner_rect / current_index.

const ToolIcon := preload("res://scripts/ui/board_hq.gd").ToolIcon

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
const C_RED := Color("#D9685F")

## Ring half-size (world units) and walkway width
const L := 10.0
const WALK := 3.4
const TILE := 2.3
const CORNER_TILE := 3.1
## Upcoming tiles highlighted ahead of the current player
const AHEAD := 6
const ZONES := [
	{"key": "A", "name": "會前準備區"},
	{"key": "B", "name": "客戶洞察區"},
	{"key": "C", "name": "方案設計區"},
	{"key": "D", "name": "合規成長區"},
]
## Camera: 45° yaw, high angle
const YAW := 45.0
const PITCH := -52.0
const TOWER_AT := Vector3(-14.8, 0, -14.8)
## Tower top (spire tip), used for camera framing
const TOWER_TOP := 21.6

var tiles: Array = []
var players: Array = []
var territory: Dictionary = {}
var current_id := ""
var _shown: Dictionary = {}
var _freeze_timer := 0.0
var _selected := -1
var _hover := -1
var _zoom := 1.0
var _pan := Vector2.ZERO
var _pulse := 0.0

var _container: SubViewportContainer
var _view: SubViewport
var _world: Node3D
var _cam: Camera3D
var _overlay: Control
var _tools: HBoxContainer
var _tile_nodes: Array = []
var _tile_mats: Array = []
var _rim_mats: Array = []
var _pawns: Dictionary = {}
var _mats: Dictionary = {}
var _fit_center := Vector3.ZERO
var _fit_size := 30.0


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
			if _pawns.has(id):
				(_pawns[id] as Node3D).queue_free()
				_pawns.erase(id)


func freeze_movement(duration: float) -> void:
	_freeze_timer = maxf(duration, 0.0)


func current_index() -> int:
	return int(floorf(float(_shown.get(current_id, 0.0)) + 0.001)) % 24


## Strip reserved for the HUD card at the bottom of the board (game.gd places its dock here)
func get_inner_rect() -> Rect2:
	var w := clampf(size.x - 32.0, 240.0, 820.0)
	var h := 196.0 if size.x < 520.0 else clampf(size.y * 0.24, 112.0, 168.0)
	return Rect2(Vector2((size.x - w) * 0.5, size.y - h - 16.0), Vector2(w, h))


## Display name with its zone, for the task panel
static func tile_label(index: int, name: String) -> String:
	var z: Dictionary = ZONES[clampi(index / 6, 0, 3)]
	return "%s %s｜第 %d 站 %s" % [z.key, z.name, index + 1, name]


# ───────── Build ─────────

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	_view.transparent_bg = false
	_container.add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	_build_environment()
	_build_campus()
	_build_tower()
	_build_tiles()

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

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


func _mat(key: String, color: Color, metallic := 0.0, rough := 0.85) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	_mats[key] = m
	return m


func _box(parent: Node3D, sz: Vector3, at: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation.y = deg_to_rad(rot_y)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, at: Vector3, mat: Material, segments := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = h
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = C_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9fc4bb")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe2b8")
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#7fb6c9")
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-35, 150, 0)
	_world.add_child(fill)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.rotation_degrees = Vector3(PITCH, YAW, 0)
	_cam.near = 0.1
	_cam.far = 400.0
	_world.add_child(_cam)


## Ground, walkway ring with gold inlays, inner plaza, zone pavilions, perimeter buildings and trees
func _build_campus() -> void:
	var ground := _mat("ground", Color("#0b3a33"))
	var lawn := _mat("lawn", Color("#164a3a"))
	var stone := _mat("stone", Color("#8f8b7c"), 0.0, 0.9)
	var plaza := _mat("plaza", Color("#6f6c60"), 0.0, 0.9)
	var gold := _mat("gold", C_GOLD, 0.7, 0.35)
	var inlay := _mat("inlay", Color("#0D4038"), 0.0, 0.6)
	var glass := _mat("glass", Color("#3f7f78"), 0.55, 0.25)
	var facade := _mat("facade", Color("#4e4b42"), 0.0, 0.9)
	var dark := _mat("dark", Color("#24433d"), 0.1, 0.8)
	var water := _mat("water", Color("#2c6f7a"), 0.2, 0.15)

	_box(_world, Vector3(320, 0.2, 320), Vector3(0, -0.1, 0), ground)
	# Inner plaza and lawn inside the ring
	_box(_world, Vector3(2 * L - WALK, 0.04, 2 * L - WALK), Vector3(0, 0.02, 0), lawn)
	_box(_world, Vector3(7.5, 0.05, 7.5), Vector3(0, 0.03, 0), plaza)
	# Walkway ring
	for side in range(4):
		var horizontal := side % 2 == 0
		var offset := L if side < 2 else -L
		var sz := Vector3(2 * L + WALK, 0.06, WALK) if horizontal else Vector3(WALK, 0.06, 2 * L + WALK)
		var at := Vector3(0, 0.03, offset) if horizontal else Vector3(offset, 0.03, 0)
		_box(_world, sz, at, stone)
		# Dark green and champagne gold ground inlays along both edges of the walkway
		for edge: float in [-1.0, 1.0]:
			var e_off := edge * (WALK * 0.5 - 0.18)
			var e_sz := Vector3(sz.x, 0.07, 0.07) if horizontal else Vector3(0.07, 0.07, sz.z)
			var e_at := at + (Vector3(0, 0.01, e_off) if horizontal else Vector3(e_off, 0.01, 0))
			_box(_world, e_sz, e_at, gold)
			var i_sz := Vector3(sz.x, 0.065, 0.22) if horizontal else Vector3(0.22, 0.065, sz.z)
			var i_at := at + (Vector3(0, 0.005, e_off - edge * 0.2) if horizontal else Vector3(e_off - edge * 0.2, 0.005, 0))
			_box(_world, i_sz, i_at, inlay)
	# Central fountain
	_cyl(_world, 2.0, 2.1, 0.35, Vector3(0, 0.18, 0), gold, 32)
	_cyl(_world, 1.8, 1.8, 0.37, Vector3(0, 0.2, 0), water, 32)
	_cyl(_world, 0.25, 0.35, 1.0, Vector3(0, 0.5, 0), facade, 16)
	# Zone pavilions: training buildings facing each side of the walkway
	var pav_at := [Vector3(0, 0, L - 4.6), Vector3(-L + 4.6, 0, 0), Vector3(0, 0, -L + 4.6), Vector3(L - 4.6, 0, 0)]
	for i in range(4):
		var rot := 0.0 if i % 2 == 0 else 90.0
		var base: Vector3 = pav_at[i]
		_box(_world, Vector3(6.2, 1.9, 2.4), base + Vector3(0, 0.95, 0), glass, rot)
		_box(_world, Vector3(6.6, 0.18, 2.8), base + Vector3(0, 1.95, 0), facade, rot)
		_box(_world, Vector3(6.6, 0.05, 0.06), base + Vector3(0, 2.06, 0) + (Vector3(0, 0, 1.38) if i % 2 == 0 else Vector3(1.38, 0, 0)) * (1 if i < 2 else -1), gold, rot)
	# Trees around the plaza
	var trunk := _mat("trunk", Color("#4a3a2c"))
	var leaf := _mat("leaf", Color("#2f6b4a"), 0.0, 0.95)
	for k in range(12):
		var a := TAU * k / 12.0
		var at := Vector3(cos(a) * 5.4, 0, sin(a) * 5.4)
		_cyl(_world, 0.08, 0.1, 0.7, at + Vector3(0, 0.35, 0), trunk, 6)
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.55
		sm.height = 1.0
		sm.radial_segments = 10
		sm.rings = 5
		crown.mesh = sm
		crown.material_override = leaf
		crown.position = at + Vector3(0, 1.1, 0)
		_world.add_child(crown)
	# Perimeter: HQ office wings flanking the tower at the back, lower blocks and lawns elsewhere
	var wings := [
		[Vector3(-L - 5.8, 0, -1.5), Vector3(4.5, 3.2, 8)], [Vector3(-1.5, 0, -L - 5.8), Vector3(8, 3.2, 4.5)],
		[Vector3(-L - 5.8, 0, 8.5), Vector3(4.5, 2.1, 5.5)], [Vector3(8.5, 0, -L - 5.8), Vector3(5.5, 2.1, 4.5)],
	]
	for w: Array in wings:
		var at: Vector3 = w[0]
		var sz: Vector3 = w[1]
		_box(_world, sz, at + Vector3(0, sz.y * 0.5, 0), facade)
		for f in range(int(sz.y / 1.05)):
			_box(_world, Vector3(sz.x + 0.04, 0.42, sz.z + 0.04), at + Vector3(0, 0.55 + f * 1.05, 0), glass)
		_box(_world, Vector3(sz.x * 0.7, 0.12, sz.z * 0.7), at + Vector3(0, sz.y + 0.06, 0), lawn)
	# Outer lawns and tree rows along the front boulevards
	_box(_world, Vector3(4, 0.03, 26), Vector3(L + 4.4, 0.015, 3), lawn)
	_box(_world, Vector3(26, 0.03, 4), Vector3(3, 0.015, L + 4.4), lawn)
	for k in range(9):
		for side in range(2):
			var at := Vector3(L + 4.4, 0, -6 + k * 2.6) if side == 0 else Vector3(-6 + k * 2.6, 0, L + 4.4)
			_cyl(_world, 0.07, 0.09, 0.6, at + Vector3(0, 0.3, 0), trunk, 6)
			var crown := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.45
			sm.height = 0.85
			sm.radial_segments = 10
			sm.rings = 5
			crown.mesh = sm
			crown.material_override = leaf
			crown.position = at + Vector3(0, 0.95, 0)
			_world.add_child(crown)
	_box(_world, Vector3(90, 0.02, 1.2), Vector3(0, 0.01, L + 7.2), dark)
	_box(_world, Vector3(1.2, 0.02, 90), Vector3(L + 7.2, 0.01, 0), dark)
	# Forecourt linking the back corner of the ring to the tower
	_box(_world, Vector3(5, 0.05, 5), (Vector3(-L, 0, -L) + TOWER_AT) * 0.5 + Vector3(0, 0.03, 0), plaza)


## Taipei 101 as the HQ landmark: podium, trunk, eight flared stacked segments, crown and spire
func _build_tower() -> void:
	var glass := _mat("tower_glass", Color("#2f6f63"), 0.6, 0.22)
	var gold := _mat("gold", C_GOLD, 0.7, 0.35)
	var podium := _mat("facade", Color("#4e4b42"), 0.0, 0.9)
	var t := Node3D.new()
	t.position = TOWER_AT
	_world.add_child(t)
	_box(t, Vector3(7, 1.3, 7), Vector3(0, 0.65, 0), podium)
	_box(t, Vector3(7.1, 0.3, 7.1), Vector3(0, 0.85, 0), glass)
	_box(t, Vector3(2.4, 3.2, 2.4), Vector3(0, 2.9, 0), glass, 45)
	var y := 4.5
	for i in range(8):
		var seg := _cyl(t, 1.75, 1.3, 1.35, Vector3(0, y + 0.675, 0), glass, 4)
		seg.rotation.y = deg_to_rad(45)
		_box(t, Vector3(1.8, 0.07, 1.8), Vector3(0, y + 0.035, 0), gold, 45)
		y += 1.35
	_cyl(t, 1.1, 1.4, 1.4, Vector3(0, y + 0.7, 0), glass, 4).rotation.y = deg_to_rad(45)
	_cyl(t, 0.5, 0.75, 1.2, Vector3(0, y + 2.0, 0), glass, 4).rotation.y = deg_to_rad(45)
	_cyl(t, 0.06, 0.16, 3.6, Vector3(0, y + 4.4, 0), gold, 8)


## Tile centers around the ring, clockwise on screen from the front corner (tile 1)
func _tile_center(i: int) -> Vector3:
	var side := i / 6
	var f := float(i % 6) / 6.0
	var corners := [Vector3(L, 0, L), Vector3(-L, 0, L), Vector3(-L, 0, -L), Vector3(L, 0, -L), Vector3(L, 0, L)]
	return (corners[side] as Vector3).lerp(corners[side + 1], f)


func _route_point(t: float) -> Vector3:
	var a := int(floorf(t)) % 24
	var b := (a + 1) % 24
	return _tile_center(a).lerp(_tile_center(b), t - floorf(t))


func _is_corner(i: int) -> bool:
	return i % 6 == 0


func _build_tiles() -> void:
	for i in range(24):
		var corner := _is_corner(i)
		var s := CORNER_TILE if corner else TILE
		var rim := StandardMaterial3D.new()
		rim.albedo_color = C_GOLD if corner else Color("#1f5b50")
		rim.metallic = 0.7 if corner else 0.0
		rim.roughness = 0.4 if corner else 0.8
		var top := StandardMaterial3D.new()
		top.albedo_color = C_CARD
		top.roughness = 0.7
		var node := Node3D.new()
		node.position = _tile_center(i)
		_world.add_child(node)
		_box(node, Vector3(s + 0.22, 0.075, s + 0.22), Vector3(0, 0.07, 0), rim)
		_box(node, Vector3(s, 0.085, s), Vector3(0, 0.075, 0), top)
		_tile_nodes.append(node)
		_tile_mats.append(top)
		_rim_mats.append(rim)


func _pawn_for(id: String, color: Color) -> Node3D:
	if _pawns.has(id):
		return _pawns[id]
	var p := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	_cyl(p, 0.36, 0.42, 0.1, Vector3(0, 0.05, 0), _mat("pawn_base", Color("#F3F0E7")), 20)
	_cyl(p, 0.2, 0.3, 0.75, Vector3(0, 0.47, 0), mat, 16)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	head.mesh = sm
	head.material_override = mat
	head.position = Vector3(0, 1.05, 0)
	p.add_child(head)
	_world.add_child(p)
	_pawns[id] = p
	return p


# ───────── Camera fit, zoom and pan ─────────

func _layout() -> void:
	if _cam == null or size.x < 4 or size.y < 4:
		return
	_tools.reset_size()
	_tools.position = Vector2(size.x - _tools.size.x - 14, 14)
	# Fit the campus and tower into the area above the HUD card
	var basis := Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(YAW), 0))
	var right := basis.x
	var up := basis.y
	var pts: Array[Vector3] = []
	for c: Vector3 in [Vector3(L + 2.5, 0, L + 2.5), Vector3(-L - 2.5, 0, L + 2.5), Vector3(L + 2.5, 0, -L - 2.5), Vector3(-L - 2.5, 0, -L - 2.5)]:
		pts.append(c)
	pts.append(TOWER_AT + Vector3(0, TOWER_TOP, 0))
	pts.append(TOWER_AT + Vector3(-3.5, 0, 3.5))
	pts.append(TOWER_AT + Vector3(3.5, 0, -3.5))
	var min_r := INF
	var max_r := -INF
	var min_u := INF
	var max_u := -INF
	for p: Vector3 in pts:
		min_r = minf(min_r, p.dot(right))
		max_r = maxf(max_r, p.dot(right))
		min_u = minf(min_u, p.dot(up))
		max_u = maxf(max_u, p.dot(up))
	var hud := get_inner_rect()
	var avail_h := maxf(80.0, hud.position.y - 6.0)
	var frac := avail_h / size.y
	var aspect := size.x / size.y
	_fit_size = maxf((max_u - min_u) / frac, (max_r - min_r) / aspect) * 1.1
	# Content centre sits at the centre of the free area (above the HUD), not of the whole board
	var shift := (size.y * 0.5 - avail_h * 0.5) / size.y * _fit_size
	_fit_center = right * ((min_r + max_r) * 0.5) + up * ((min_u + max_u) * 0.5 - shift)
	_apply_camera()


func _apply_camera() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(YAW), 0))
	_cam.size = _fit_size / _zoom
	var world_per_px := _cam.size / maxf(1.0, size.y)
	var center := _fit_center - basis.x * (_pan.x * world_per_px) + basis.y * (_pan.y * world_per_px)
	# Orthographic: distance only needs to clear the scene
	_cam.position = center + basis.z * 120.0


func _tool_action(kind: String) -> void:
	match kind:
		"in": _set_zoom(_zoom * 1.25)
		"out": _set_zoom(_zoom / 1.25)
		"reset":
			_zoom = 1.0
			_pan = Vector2.ZERO
			_selected = -1
	_apply_camera()


func _set_zoom(z: float) -> void:
	var old := _zoom
	_zoom = clampf(z, 1.0, 3.0)
	_pan *= _zoom / old
	_clamp_pan()


func _clamp_pan() -> void:
	var limit := size * (_zoom - 1.0) * 0.5
	_pan = _pan.clamp(-limit, limit)


func _screen_of(p: Vector3) -> Vector2:
	return _cam.unproject_position(p)


func _tile_at(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in range(24):
		var d := _screen_of(_tile_center(i)).distance_to(pos)
		var r := _tile_px(i) * 0.75
		if d < r and d < best_d:
			best = i
			best_d = d
	return best


## On-screen half width of a tile (for icon size and hit tests)
func _tile_px(i: int) -> float:
	var c := _tile_center(i)
	var s := (CORNER_TILE if _is_corner(i) else TILE) * 0.5
	return _screen_of(c).distance_to(_screen_of(c + Vector3(s, 0, -s)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT) and _zoom > 1.0:
			_pan += event.relative
			_clamp_pan()
			_apply_camera()
			accept_event()
		var h := _tile_at(event.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom * 1.1)
				_apply_camera()
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom / 1.1)
				_apply_camera()
				accept_event()
			MOUSE_BUTTON_LEFT:
				var t := _tile_at(event.position)
				_selected = -1 if t == _selected else t


# ───────── Per-frame: pawns, tile states ─────────

func _process(delta: float) -> void:
	if _cam == null:
		return
	_pulse += delta
	_freeze_timer = maxf(0.0, _freeze_timer - delta)
	for p: Dictionary in players:
		var id := str(p.get("id", ""))
		var before: float = _shown.get(id, float(p.get("pos", 0)))
		var diff := fposmod(float(p.get("pos", 0)) - before, 24.0)
		if _freeze_timer <= 0 and diff > 0.001:
			var after := fposmod(before + minf(diff, delta * 5.0), 24.0)
			_shown[id] = after
			if int(floorf(before)) != int(floorf(after)) and id == current_id and not Engine.is_editor_hint():
				Sound.play("step", self)
	_update_tiles()
	_update_pawns()
	_overlay.queue_redraw()


func _update_tiles() -> void:
	var cur := current_index() if not players.is_empty() else -1
	for i in range(24):
		var top: StandardMaterial3D = _tile_mats[i]
		var rim: StandardMaterial3D = _rim_mats[i]
		var node: Node3D = _tile_nodes[i]
		var steps := posmod(i - cur, 24) if cur >= 0 else 24
		var is_cur := i == cur
		var corner := _is_corner(i)
		# Current tile: champagne gold marker, raised slightly; upcoming route a little lighter
		top.albedo_color = Color("#1d5a4f") if is_cur else (Color("#125047") if steps <= AHEAD else C_CARD)
		rim.albedo_color = C_GOLD if (is_cur or corner) else Color("#1f5b50")
		var target := 1.12 if is_cur else 1.0
		node.scale = node.scale.lerp(Vector3(target, 1.0, target), 0.2)
		node.position.y = lerpf(node.position.y, 0.04 if is_cur else 0.0, 0.2)


func _update_pawns() -> void:
	var slots := {}
	for idx in range(players.size()):
		var p: Dictionary = players[idx]
		var id := str(p.get("id", ""))
		var t: float = _shown.get(id, float(p.get("pos", 0)))
		var key := int(roundf(t)) % 24
		var slot: int = slots.get(key, 0)
		slots[key] = slot + 1
		var pawn := _pawn_for(id, UI.PLAYER_COLORS[idx % UI.PLAYER_COLORS.size()])
		var offsets := [Vector3(-0.45, 0, 0.45), Vector3(0.45, 0, -0.45), Vector3(-0.45, 0, -0.45), Vector3(0.45, 0, 0.45)]
		var hop := sin((t - floorf(t)) * PI) * 0.55 if fposmod(t, 1.0) > 0.01 else 0.0
		pawn.position = _route_point(t) + offsets[slot % 4] + Vector3(0, 0.12 + hop, 0)
		var s := 1.9 if id == current_id else 1.5
		pawn.scale = Vector3.ONE * s


# ───────── 2D overlay: icons on the ground, zone labels, caption ─────────

func _draw_overlay() -> void:
	if _cam == null:
		return
	var o := _overlay
	var cur := current_index() if not players.is_empty() else -1
	# Isometric ground squash so icons read as painted on the tile
	var squash := absf(sin(deg_to_rad(PITCH)))
	for i in range(24):
		var c := _screen_of(_tile_center(i) + Vector3(0, 0.13, 0))
		var r := _tile_px(i) * (0.42 if _is_corner(i) else 0.38)
		var steps := posmod(i - cur, 24) if cur >= 0 else 24
		var alpha := 1.0 if i == cur or i == _hover or i == _selected else (0.85 if steps <= AHEAD else 0.45)
		var col := Color(C_TEXT, alpha)
		if i < tiles.size() and str((tiles[i] as Dictionary).get("type", "")) == "audit":
			col = Color(C_RED.lightened(0.15), alpha)
		o.draw_set_transform(c, 0.0, Vector2(1.0, squash))
		_draw_icon(o, i, Vector2.ZERO, r, col)
		o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var owner: Variant = territory.get(str(i), territory.get(i, null))
		if owner is Dictionary:
			var oi := -1
			for k in range(players.size()):
				if str(players[k].get("id", "")) == str(owner.get("playerId", "")):
					oi = k
			o.draw_circle(c + Vector2(r * 1.1, r * 0.25), maxf(3.0, r * 0.18), UI.PLAYER_COLORS[oi % 4] if oi >= 0 else C_GREEN)
	# Zone labels on the pavilions
	var font := get_theme_default_font()
	var out := L + WALK * 0.5 + 1.6
	var pav := [Vector3(0, 0.1, out), Vector3(-out, 0.1, 0), Vector3(0, 0.1, -out), Vector3(out, 0.1, 0)]
	for z in range(4):
		var text := "%s %s" % [ZONES[z].key, ZONES[z].name]
		var fs := 12
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := _screen_of(pav[z])
		var box := Rect2(at - Vector2(w * 0.5 + 8, 11), Vector2(w + 16, 22))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(C_BG, 0.78)
		sb.set_corner_radius_all(11)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.12)
		o.draw_style_box(sb, box)
		o.draw_string(font, box.position + Vector2(8, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_MUTED)
	# Name caption for the hovered / selected node (normal nodes show icons only)
	var show := _hover if _hover >= 0 else _selected
	if show >= 0 and show < tiles.size():
		var title := "%d %s" % [show + 1, str((tiles[show] as Dictionary).get("name", ""))]
		var fs := 13
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c := _screen_of(_tile_center(show))
		var box := Rect2(c + Vector2(-tw * 0.5 - 10, _tile_px(show) * 0.6 + 6), Vector2(tw + 20, 26))
		box.position = box.position.clamp(Vector2(6, 6), size - box.size - Vector2(6, 6))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(C_CARD, 0.96)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.12)
		o.draw_style_box(sb, box)
		o.draw_string(font, box.position + Vector2(10, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)


## Flat 2px line icons; corner nodes get their own symbols (check-in, insight, design, compliance)
func _draw_icon(o: Control, i: int, c: Vector2, r: float, col: Color) -> void:
	var w := 2.0
	var kind := str((tiles[i] as Dictionary).get("type", "client")) if i < tiles.size() else "client"
	if _is_corner(i):
		match i:
			0:  # 新人報到: flag
				o.draw_line(c + Vector2(-r * 0.5, r), c + Vector2(-r * 0.5, -r), col, w, true)
				o.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, -r), c + Vector2(r * 0.7, -r * 0.6), c + Vector2(-r * 0.5, -r * 0.15)]), col, w, true)
			6:  # 需求探索: magnifier
				o.draw_arc(c - Vector2(r * 0.2, r * 0.2), r * 0.6, 0, TAU, 24, col, w, true)
				o.draw_line(c + Vector2.ONE * r * 0.25, c + Vector2.ONE * r * 0.85, col, w, true)
			12:  # 轉介紹: two people
				o.draw_arc(c + Vector2(-r * 0.4, -r * 0.35), r * 0.3, 0, TAU, 16, col, w, true)
				o.draw_arc(c + Vector2(r * 0.45, -r * 0.2), r * 0.3, 0, TAU, 16, col, w, true)
				o.draw_line(c + Vector2(-r * 0.9, r * 0.7), c + Vector2(r * 0.9, r * 0.7), col, w, true)
			18:  # 客戶決策: check in circle
				o.draw_arc(c, r * 0.85, 0, TAU, 28, col, w, true)
				o.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, 0), c + Vector2(-r * 0.08, r * 0.32), c + Vector2(r * 0.45, -r * 0.3)]), col, w, true)
		return
	match kind:
		"client":
			o.draw_arc(c + Vector2(0, -r * 0.4), r * 0.4, 0, TAU, 18, col, w, true)
			o.draw_arc(c + Vector2(0, r * 0.95), r * 0.8, PI * 1.12, PI * 1.88, 14, col, w, true)
		"referral":
			o.draw_arc(c + Vector2(-r * 0.4, -r * 0.35), r * 0.3, 0, TAU, 14, col, w, true)
			o.draw_arc(c + Vector2(r * 0.45, -r * 0.2), r * 0.3, 0, TAU, 14, col, w, true)
			o.draw_line(c + Vector2(-r * 0.9, r * 0.7), c + Vector2(r * 0.9, r * 0.7), col, w, true)
		"life":
			o.draw_line(c + Vector2(0, -r * 0.8), c + Vector2(0, r * 0.8), col, w, true)
			o.draw_line(c + Vector2(-r * 0.8, 0), c + Vector2(r * 0.8, 0), col, w, true)
		"market":
			o.draw_polyline(PackedVector2Array([c + Vector2(-r, r * 0.6), c + Vector2(-r * 0.3, -r * 0.05), c + Vector2(r * 0.15, r * 0.3), c + Vector2(r, -r * 0.6)]), col, w, true)
		"training":
			o.draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.7, r * 0.4), c + Vector2(0, r), c + Vector2(-r * 0.7, r * 0.4), c + Vector2(-r * 0.8, -r * 0.6), c + Vector2(0, -r)]), col, w, true)
		"audit":
			o.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.9), c + Vector2(r * 0.9, r * 0.75), c + Vector2(-r * 0.9, r * 0.75), c + Vector2(0, -r * 0.9)]), col, w, true)
			o.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.25), col, w, true)
		"seminar":
			o.draw_rect(Rect2(c + Vector2(-r, -r * 0.7), Vector2(r * 2, r * 1.25)), col, false, w)
			o.draw_line(c + Vector2(0, r * 0.55), c + Vector2(0, r), col, w, true)
		"start":
			o.draw_arc(c, r * 0.7, 0, TAU, 18, col, w, true)
		_:
			o.draw_arc(c, r * 0.6, 0, TAU, 18, col, w, true)
