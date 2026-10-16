@tool
extends Node3D
## Integer XZ occupancy, with explicit footprints for both procedural and imported scenes.
@export var cell_size := 1.0
@export var bounds := Rect2i(-10, -10, 20, 20)
var occupied: Dictionary = {}
var _placements: Dictionary = {}
var _preview: Node3D
var _preview_cell := Vector2i.ZERO
var _preview_scene: PackedScene
var _preview_footprint := Vector2i.ONE
var _preview_turns := 0
var _valid_material: StandardMaterial3D
var _invalid_material: StandardMaterial3D
var _grid_lines: MeshInstance3D

func world_to_cell(world: Vector3) -> Vector2i:
	var local := to_local(world)
	return Vector2i(floori(local.x / cell_size), floori(local.z / cell_size))

func cell_to_world(cell: Vector2i, footprint := Vector2i.ONE) -> Vector3:
	return to_global(Vector3((cell.x + footprint.x * 0.5) * cell_size, 0.4, (cell.y + footprint.y * 0.5) * cell_size))

func rotated_footprint(footprint: Vector2i, quarter_turns: int) -> Vector2i:
	return Vector2i(footprint.y, footprint.x) if posmod(quarter_turns, 2) == 1 else footprint

func cells_for(cell: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x: int in range(footprint.x):
		for z: int in range(footprint.y):
			result.append(cell + Vector2i(x, z))
	return result

func can_place(cell: Vector2i, footprint: Vector2i, quarter_turns: int = 0) -> bool:
	if footprint.x <= 0 or footprint.y <= 0 or cell_size <= 0:
		return false
	for slot: Vector2i in cells_for(cell, rotated_footprint(footprint, quarter_turns)):
		if not bounds.has_point(slot) or occupied.has(slot):
			return false
	return true

func reserve(cell: Vector2i, footprint: Vector2i, owner: Variant = "landmark") -> bool:
	if not can_place(cell, footprint):
		return false
	for slot: Vector2i in cells_for(cell, footprint):
		occupied[slot] = owner
	return true

func place(scene: PackedScene, cell: Vector2i, footprint: Vector2i, quarter_turns: int = 0, animate: bool = true) -> Node3D:
	if scene == null or not can_place(cell, footprint, quarter_turns):
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	var shape := rotated_footprint(footprint, quarter_turns)
	reserve(cell, shape, instance.get_instance_id())
	add_child(instance)
	instance.global_position = cell_to_world(cell, shape)
	instance.rotation.y = posmod(quarter_turns, 4) * PI / 2
	_placements[instance.get_instance_id()] = cells_for(cell, shape)
	instance.tree_exiting.connect(_release.bind(instance.get_instance_id()))
	if animate and not Engine.is_editor_hint() and not UI.reduce_motion:
		var full_scale: Vector3 = instance.scale
		instance.scale = Vector3(full_scale.x, 0.01, full_scale.z)
		instance.create_tween().tween_property(instance, "scale", full_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return instance

func _release(id: int) -> void:
	for cell: Vector2i in _placements.get(id, []):
		if occupied.get(cell) == id:
			occupied.erase(cell)
	_placements.erase(id)

func begin_preview(scene: PackedScene, footprint: Vector2i) -> void:
	cancel_preview()
	if scene == null:
		return
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return
	_preview_scene = scene
	_preview_footprint = footprint
	_preview = instance
	add_child(_preview)
	_show_grid()
	_valid_material = _ghost_material(Color(0.15, 0.85, 0.6, 0.45))
	_invalid_material = _ghost_material(Color(1.0, 0.15, 0.12, 0.48))
	# Disable behavior and collision on imported GLB/PackedScene ghosts.
	_preview.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in _preview.find_children("*", "CollisionObject3D", true, false):
		child.collision_layer = 0
		child.collision_mask = 0
	update_preview(cell_to_world(Vector2i.ZERO))

func _ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func update_preview(world: Vector3, quarter_turns: int = 0) -> bool:
	if _preview == null:
		return false
	_preview_cell = world_to_cell(world)
	_preview_turns = quarter_turns
	var shape := rotated_footprint(_preview_footprint, quarter_turns)
	_preview.global_position = cell_to_world(_preview_cell, shape)
	_preview.rotation.y = posmod(quarter_turns, 4) * PI / 2
	var valid := can_place(_preview_cell, _preview_footprint, quarter_turns)
	var meshes: Array[Node] = _preview.find_children("*", "MeshInstance3D", true, false)
	if _preview is MeshInstance3D:
		meshes.append(_preview)
	for mesh: Node in meshes:
		mesh.material_override = _valid_material if valid else _invalid_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return valid

func commit_preview() -> Node3D:
	var instance := place(_preview_scene, _preview_cell, _preview_footprint, _preview_turns)
	update_preview(cell_to_world(_preview_cell), _preview_turns)
	return instance

func cancel_preview() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_preview_scene = null
	if is_instance_valid(_grid_lines):
		_grid_lines.visible = false

func _show_grid() -> void:
	if is_instance_valid(_grid_lines):
		_grid_lines.visible = true
		return
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for x: int in range(bounds.position.x, bounds.end.x + 1):
		lines.surface_add_vertex(Vector3(x * cell_size, 0.42, bounds.position.y * cell_size))
		lines.surface_add_vertex(Vector3(x * cell_size, 0.42, bounds.end.y * cell_size))
	for z: int in range(bounds.position.y, bounds.end.y + 1):
		lines.surface_add_vertex(Vector3(bounds.position.x * cell_size, 0.42, z * cell_size))
		lines.surface_add_vertex(Vector3(bounds.end.x * cell_size, 0.42, z * cell_size))
	lines.surface_end()
	_grid_lines = MeshInstance3D.new()
	_grid_lines.mesh = lines
	_grid_lines.material_override = _ghost_material(Color(0.5, 0.9, 0.75, 0.25))
	_grid_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_lines)
