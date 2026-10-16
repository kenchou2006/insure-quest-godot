@tool
extends Node3D
## Procedural city diorama, compatible with the Web GL renderer.
const RADIUS := 13.0
@export var high_quality_lighting := false
var grid: Node3D
var traffic: Node3D
var _camera: Camera3D
var _nodes := Node3D.new()
var _pawns := Node3D.new()
var _count := 0
var _markers: Array[MeshInstance3D] = []
var _pawn_map: Dictionary = {}
var _materials: Dictionary = {}
var _selection: MeshInstance3D
var _active: MeshInstance3D
var _time := 0.0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("142d37")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a5c2cd")
	settings.ambient_light_energy = 0.48
	settings.glow_enabled = true
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.ssao_enabled = true
	settings.ssao_radius = 1.5
	settings.ssao_intensity = 1.3
	if high_quality_lighting and RenderingServer.get_current_rendering_method() == "forward_plus":
		settings.sdfgi_enabled = true
		settings.glow_enabled = true
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.light_color = Color("ffddb0")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	add_child(sun)
	_camera = preload("res://scripts/city/city_camera.gd").new()
	add_child(_camera)
	_camera.current = true
	_build_city()
	grid = preload("res://scripts/city/city_grid.gd").new()
	add_child(grid)
	_reserve_landmarks()
	traffic = preload("res://scripts/city/city_traffic.gd").new()
	add_child(traffic)
	traffic.setup(self)
	add_child(_nodes)
	add_child(_pawns)
	_selection = _cylinder(self, Vector3(0, -2, 0), 0.85, 0.035, Color.WHITE, true)
	_selection.visible = false
	_active = _cylinder(self, Vector3(0, -2, 0), 0.88, 0.035, UI.GOLD, true)

func fit_camera(area: Vector2) -> void:
	if _camera != null:
		_camera.fit(area)

func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + str(glow)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.2
	_materials[key] = material
	return material

func _mesh(parent: Node3D, geometry: Mesh, pos: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = geometry
	node.material_override = _mat(color, glow)
	node.position = pos
	parent.add_child(node)
	return node

func _box(parent: Node3D, pos: Vector3, dimensions: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var geometry := BoxMesh.new()
	geometry.size = dimensions
	return _mesh(parent, geometry, pos, color, glow)

func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, glow: bool = false) -> MeshInstance3D:
	var geometry := CylinderMesh.new()
	geometry.top_radius = radius
	geometry.bottom_radius = radius
	geometry.height = height
	geometry.radial_segments = 32
	return _mesh(parent, geometry, pos, color, glow)

func _sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var geometry := SphereMesh.new()
	geometry.radius = radius
	geometry.height = radius * 2
	geometry.radial_segments = 12
	geometry.rings = 6
	return _mesh(parent, geometry, pos, color)

func _build_city() -> void:
	preload("res://scripts/ui/city_architecture.gd").new().build(self)
	_batch_static()

func point_on_ring(index: float) -> Vector3:
	var angle := TAU * index / maxf(_count, 1) + PI
	return Vector3(sin(angle) * RADIUS, 0.38, cos(angle) * RADIUS)

func set_tiles(tiles: Array) -> void:
	if not is_inside_tree():
		return
	for child in _nodes.get_children():
		_nodes.remove_child(child)
		child.queue_free()
	_markers.clear()
	_count = tiles.size()
	for i: int in range(_count):
		var pos := point_on_ring(i)
		_markers.append(_cylinder(_nodes, pos, 0.57, 0.035, Color("e3e5cb")))
		_cylinder(_nodes, pos + Vector3(0, 0.025, 0), 0.50, 0.02, Color("2f8068"))
		_cylinder(_nodes, pos + Vector3(0, 0.04, 0), 0.43, 0.015, Color("bbdace"))
		_cylinder(_nodes, pos + Vector3(0, 0.05, 0), 0.39, 0.015, Color("2c715e"))
		var type_key := str(tiles[i].get("type", ""))
		_cylinder(_nodes, pos + Vector3(0.35, 0.08, 0.25), 0.10, 0.025, UI.TILE_COLORS.get(type_key, UI.GOLD), true)
		var label := Label3D.new()
		label.text = "%02d" % i
		label.visible = false # Full tile names and numbers live on the perimeter UI.
		label.font = load("res://assets/fonts/regular.tres")
		label.font_size = 64
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = pos + Vector3(0, 0.52, 0)
		label.outline_size = 4
		_nodes.add_child(label)

func set_territory(territory: Dictionary, players: Array) -> void:
	for i: int in range(_markers.size()):
		var color := Color("e3e5cb")
		var owner: Variant = territory.get(str(i), territory.get(i, null))
		if owner is Dictionary:
			for pi: int in range(players.size()):
				if str(players[pi].get("id", "")) == str(owner.get("playerId", "")):
					color = UI.PLAYER_COLORS[pi % 4]
		_markers[i].material_override = _mat(color)

func update_players(players: Array, shown: Dictionary, current: String, delta: float) -> void:
	_time += 0.0 if UI.reduce_motion else delta
	var live_ids: Array = []
	_active.visible = false
	for i: int in range(players.size()):
		var player: Dictionary = players[i]
		var id := str(player.get("id", ""))
		live_ids.append(id)
		if not _pawn_map.has(id):
			var pawn := Node3D.new()
			_pawns.add_child(pawn)
			var color: Color = UI.PLAYER_COLORS[i % 4]
			_cylinder(pawn, Vector3(0, 0.1, 0), 0.24, 0.17, UI.GOLD)
			_cylinder(pawn, Vector3(0, 0.38, 0), 0.16, 0.42, color)
			_sphere(pawn, Vector3(0, 0.72, 0), 0.23, color)
			_pawn_map[id] = pawn
		var f: float = shown.get(id, 0.0)
		var pos := point_on_ring(f)
		pos += Vector3((i % 2) * 0.48 - 0.24, 0.21 + (0.0 if UI.reduce_motion else sin(fposmod(f, 1.0) * PI) * 0.65), int(i / 2.0) * 0.38 - 0.2)
		_pawn_map[id].position = pos
		if id == current:
			_active.visible = true
			_active.position = point_on_ring(f) + Vector3(0, -0.06, 0)
			_active.scale = Vector3.ONE if UI.reduce_motion else Vector3.ONE * (1.0 + sin(_time * 4) * 0.06)
	for id: String in _pawn_map.keys():
		if not live_ids.has(id):
			_pawn_map[id].queue_free()
			_pawn_map.erase(id)

func nearest_tile(screen_pos: Vector2) -> int:
	var result := -1
	var distance := 30.0
	for i: int in range(_count):
		var projected := _camera.unproject_position(point_on_ring(i))
		var candidate := projected.distance_to(screen_pos)
		if candidate < distance:
			distance = candidate
			result = i
	return result

func select_tile(index: int) -> void:
	_selection.visible = index >= 0
	if index >= 0:
		_selection.position = point_on_ring(index) + Vector3(0, -0.07, 0)


func _batch_static() -> void:
	# Merge static architecture by material to keep Web draw calls bounded.
	var surfaces: Dictionary = {}
	var materials: Dictionary = {}
	for child: Node in get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var key: int = child.material_override.get_instance_id()
			if not surfaces.has(key):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				surfaces[key] = surface
				materials[key] = child.material_override
			surfaces[key].append_from(child.mesh, 0, child.transform)
			remove_child(child)
			child.queue_free()
	for key: int in surfaces:
		var combined := MeshInstance3D.new()
		combined.mesh = surfaces[key].commit()
		combined.material_override = materials[key]
		combined.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(combined)

func _reserve_landmarks() -> void:
	grid.bounds = Rect2i(-18,-15,36,31)
	for lot: Rect2i in [Rect2i(-3,-3,6,7),Rect2i(-11,-10,7,6),Rect2i(5,-10,7,6),Rect2i(-11,-3,7,7),Rect2i(5,-3,7,7),Rect2i(-11,5,7,6),Rect2i(5,5,7,6)]:
		grid.reserve(lot.position,lot.size)
	for x: int in range(-18,18):
		for z: int in range(-15,16):
			var radius := Vector2(x+0.5,z+0.5).length()
			var road := radius > 11.6 and radius < 14.4
			for road_x: float in [-12,-4,4,12]:
				road = road or absf(x+0.5-road_x) < 1.1
			for road_z: float in [-11,-3.6,4,11.8]:
				road = road or absf(z+0.5-road_z) < 1.1
			if road or radius > 17:
				grid.occupied[Vector2i(x,z)] = "road / riverfront"

func focus_tile(index: int, animate: bool = true) -> void:
	if _camera != null and index >= 0 and index < _count:
		_camera.focus_on(point_on_ring(index),animate)

func ground_at(screen_pos: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.4).intersects_ray(_camera.project_ray_origin(screen_pos), _camera.project_ray_normal(screen_pos))

