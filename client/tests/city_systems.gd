extends Node
var failures := 0
const Grid := preload("res://scripts/city/city_grid.gd")
const Board := preload("res://scripts/ui/board_3d.gd")
const Building := preload("res://scenes/city/neighborhood_office.tscn")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var grid := Grid.new()
	add_child(grid)
	check(grid.world_to_cell(Vector3(-0.1, 0, -0.1)) == Vector2i(-1, -1), "Negative coordinates must floor, not truncate")
	check(grid.reserve(Vector2i.ZERO, Vector2i(2, 3)), "Reserve initial building")
	check(not grid.can_place(Vector2i(1, 2), Vector2i.ONE), "Reject intersecting building footprints")
	check(not grid.can_place(Vector2i(9, 9), Vector2i(2, 2)), "Reject bounds overflow")
	check(not grid.can_place(Vector2i(-9, -9), Vector2i.ZERO), "Reject empty footprints")
	check(grid.rotated_footprint(Vector2i(2, 3), 1) == Vector2i(3, 2), "Rotation swaps occupancy dimensions")
	var built := grid.place(Building, Vector2i(-5, -5), Vector2i(2, 2), 1, false)
	check(built != null and not grid.can_place(Vector2i(-5, -5), Vector2i.ONE), "Placed scene owns its cells")
	built.free()
	check(grid.can_place(Vector2i(-5, -5), Vector2i(2, 2)), "Removed buildings release their cells")
	grid.begin_preview(Building, Vector2i(2, 2))
	check(not grid.update_preview(Vector3(0.1, 0.4, 0.1)), "Preview rejects reserved cells")
	check(grid.commit_preview() == null, "Invalid preview cannot commit")
	check(grid.update_preview(Vector3(-4.8, 0.4, -4.8)), "Preview accepts free cells")
	var animated := grid.commit_preview()
	check(animated != null and animated.scale.y < 0.1, "Placement animation begins below full height")
	await get_tree().create_timer(0.6).timeout
	check(is_equal_approx(animated.scale.y, 1), "Placement animation ends at original scale")
	grid.cancel_preview()
	grid.queue_free()
	var board := Board.new()
	board.size = Vector2(1000, 700)
	add_child(board)
	board.set_process(false)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/preview/states.json"))
	var tiles: Array = data.static.board
	var players: Array = [{"id": "p", "pos": 23, "name": "測試"}]
	board.set_data(tiles, players, "")
	check(board._city._markers.size() == 24, "All game tiles have 3D markers")
	players = [{"id": "p", "pos": 1, "name": "測試"}]
	board.set_data(tiles, players, "")
	board.freeze_movement(1)
	board._process(0.5)
	check(is_equal_approx(board._shown.p, 23), "Dice freeze retains old position")
	board._process(0.5)
	check(is_equal_approx(board._shown.p, 1), "Movement crosses 23 to 0 to 1 without overshoot")
	board.set_data(tiles, players, "", {"3": {"playerId": "p"}})
	check(board._city._markers[3].material_override.albedo_color == UI.PLAYER_COLORS[0], "String territory keys recolor the owner ring")
	var camera: Camera3D = board._city._camera
	camera.fit(Vector2(600, 600))
	var point: Vector2 = camera.unproject_position(board._city.point_on_ring(12))
	check(board._city.nearest_tile(point) == 12, "Projected picking matches tile index")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = board._surface.position + point
	board._gui_input(event)
	check(board._selected == 12, "Board pointer input selects the projected tile")
	camera.zoom_by(0.0001)
	check(is_equal_approx(camera._zoom, camera.min_zoom), "Zoom clamps to minimum")
	camera.pan_pixels(Vector2(100000, 100000))
	check(absf(camera.focus.x) <= 12 and absf(camera.focus.z) <= 12, "Pan stays inside map limits")
	camera.reset_view()
	var traffic: Node3D = board._city.traffic
	var path: PackedVector3Array = traffic.graph.get_point_path(100, 101)
	check(path.size() > 3, "AStar routes between bridges through roundabout junctions")
	var initial: Vector3 = traffic.cars[0].node.position
	traffic._process(1)
	check(traffic.cars[0].node.position.distance_to(initial) > 0.1, "Cars advance along graph paths")
	board.set_data(tiles, [], "")
	board._process(0.1)
	check(board._shown.is_empty() and board._city._pawn_map.is_empty(), "Departed players remove their pawn and movement state")
	print("CITY CHECKS: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	get_tree().quit(0 if failures == 0 else 1)
