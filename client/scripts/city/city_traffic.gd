@tool
extends Node3D
## Decorative traffic follows directed AStar3D roads independently of game turns.
var graph := AStar3D.new()
var cars: Array[Dictionary] = []
const ROAD_POINTS := 96
var _city: Node3D

func setup(city: Node3D) -> void:
	_city = city
	for i: int in range(ROAD_POINTS):
		var angle := TAU * i / ROAD_POINTS
		graph.add_point(i, Vector3(sin(angle) * 12.0, 0.40, cos(angle) * 12.0))
	for i: int in range(ROAD_POINTS):
		graph.connect_points(i, (i + 1) % ROAD_POINTS, false)
	# Bridges join the roundabout; graph connections are junctions, not teleports.
	for side: int in [-1, 1]:
		var id := 100 if side == -1 else 101
		var p := Vector3(side * 22.0, 0.51, 4.0)
		var join_id := graph.get_closest_point(Vector3(side * 10.7, 0.34, 5.5))
		graph.add_point(id, p)
		graph.connect_points(join_id, id, true)
	for i: int in range(5):
		var car := Node3D.new()
		add_child(car)
		var color: Color = [Color("ddd9c7"), Color("345762"), Color("bfa271"), Color("6c7883"), Color("813d37")][i]
		_city._box(car, Vector3(0, 0.16, 0), Vector3(0.38, 0.20, 0.85), color)
		_city._box(car, Vector3(0, 0.31, -0.03), Vector3(0.30, 0.14, 0.44), Color("283f4b"))
		for x: float in [-0.14, 0.14]:
			_city._box(car, Vector3(x, 0.18, -0.43), Vector3(0.08, 0.06, 0.025), Color("e5d6a0"), true)
		var start := i * 18
		car.position = graph.get_point_position(start)
		cars.append({"node": car, "path": graph.get_point_path(start, (start + 35) % ROAD_POINTS), "index": 1, "destination": (start + 35) % ROAD_POINTS, "speed": 1.2 + i * 0.12, "trips": 0})

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or UI.reduce_motion:
		return
	for data: Dictionary in cars:
		var car: Node3D = data.node
		var path: PackedVector3Array = data.path
		var budget := delta * float(data.speed)
		while budget > 0 and int(data.index) < path.size():
			var target: Vector3 = path[int(data.index)]
			var difference := target - car.position
			var distance := difference.length()
			if distance > 0.001:
				car.rotation.y = lerp_angle(car.rotation.y, atan2(-difference.x, -difference.z), minf(1, delta * 7))
			var step := minf(distance, budget)
			car.position = car.position.move_toward(target, step)
			budget -= step
			if distance <= step + 0.001:
				data.index = int(data.index) + 1
		if int(data.index) >= path.size():
			var origin := int(data.destination)
			data.trips = int(data.trips) + 1
			var destination := (origin + 35) % ROAD_POINTS if origin < ROAD_POINTS else 48
			if int(data.trips) % 3 == 0:
				destination = 100 + int(data.trips) % 2
			data.destination = destination
			data.path = graph.get_point_path(origin, destination)
			data.index = 1
