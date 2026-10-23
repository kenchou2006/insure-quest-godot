@tool
extends RefCounted
## Architectural models based on the supplied city reference, all in world space.
var city: Node3D
var rng := RandomNumberGenerator.new()
var facade: StandardMaterial3D
const STONE := Color("c6c9bc")
const TRIM := Color("dddfce")
const DARK := Color("273e42")
const GLASS := Color("285e64")
const WARM := Color("c39a5c")

func box(p: Vector3, s: Vector3, c: Color, glow: bool = false) -> MeshInstance3D:
	return city._box(city, p, s, c, glow)

func disk(p: Vector3, r: float, h: float, c: Color, glow: bool = false) -> MeshInstance3D:
	return city._cylinder(city, p, r, h, c, glow)

func build(target: Node3D) -> void:
	city = target
	rng.seed = 1042026
	facade = StandardMaterial3D.new()
	facade.albedo_texture = load("res://assets/city/glass-facade.png")
	facade.roughness = 0.24
	facade.metallic = 0.25
	facade.emission_enabled = true
	facade.emission_texture = facade.albedo_texture
	facade.emission = Color.WHITE
	facade.emission_energy_multiplier = 0.25
	landscape()
	tower_101()
	# Six distinct Xinyi neighbourhoods around the central landmark.
	office(Vector3(-7.5,0.35,-7),Vector3(3.8,4.0,3.4),true)
	office(Vector3(7.3,0.35,-7),Vector3(3.1,6.4,3.1),true)
	office(Vector3(10.2,0.35,-6),Vector3(1.8,3.6,2.7),false)
	hospital()
	retail()
	residences()
	civic_center()
	planting()
	street_details()

func landscape() -> void:
	box(Vector3(0,-0.28,-26),Vector3(75,0.5,22),Color("344c46"))
	box(Vector3(0,-0.6,0),Vector3(85,0.1,75),Color("153c48"))
	# An extended city peninsula, with asymmetric masonry riverbank.
	var outline := PackedVector2Array([Vector2(-20,-15),Vector2(-14,-18),Vector2(15,-17),Vector2(20,-10),Vector2(19,9),Vector2(13,16),Vector2(3,18),Vector2(-12,16),Vector2(-20,8)])
	land_prism(outline,-0.5,0.18,Color("607575"))
	land_prism(outline,0.18,0.26,Color("506a52"))
	# A civic plaza and six rectangular blocks, separated by broad boulevards.
	for z: float in [-11,-3.6,4.0,11.8]:
		box(Vector3(0,0.30,z),Vector3(33,0.10,1.8),Color("343f42"))
	for x: float in [-12,-4,4,12]:
		box(Vector3(x,0.30,0),Vector3(1.8,0.10,28),Color("343f42"))
	for x: float in [-7.8,7.8]:
		for z: float in [-7.3,0,8]:
			box(Vector3(x,0.34,z),Vector3(6,0.15,5.3),STONE)
	box(Vector3(0,0.35,0),Vector3(5.7,0.18,6.3),STONE)
	for i: int in range(128):
		var angle := TAU*i/128.0
		var road := box(Vector3(sin(angle)*13,0.29,cos(angle)*13),Vector3(0.74,0.1,2.4),Color("343f42"))
		road.rotation.y = angle
		if i%2 == 0:
			var line := box(Vector3(sin(angle)*12.2,0.36,cos(angle)*12.2),Vector3(0.3,0.015,0.04),Color("b7bead"))
			line.rotation.y = angle
	for side: int in [-1,1]:
		box(Vector3(side*19.5,0.28,4),Vector3(15,0.35,2.4),Color("6c7b7c"))
		box(Vector3(side*19.5,0.47,4),Vector3(15,0.03,1.8),Color("343f42"))
		for z: float in [2.85,5.15]:
			box(Vector3(side*19.5,0.75,z),Vector3(15,0.08,0.1),TRIM)
		for x: float in [17,21,25]:
			box(Vector3(side*x,-0.25,4),Vector3(0.6,1.4,2.3),STONE)
	for i: int in range(26):
		var x := -23.0+(i%13)*3.8
		var z := -20.0-int(i/13.0)*4.5
		office(Vector3(x,0,z),Vector3(2.5,rng.randf_range(2.0,5.0),2.5),false,true)
	for i: int in range(outline.size()):
		var start := outline[i]
		var finish := outline[(i+1)%outline.size()]
		var count := maxi(1,int(start.distance_to(finish)/0.8))
		for j: int in range(count):
			var point := start.lerp(finish,(j+0.5)/count)
			var wall := box(Vector3(point.x,0.38,point.y),Vector3(0.8,0.24,0.18),STONE)
			wall.rotation.y = -atan2(finish.y-start.y,finish.x-start.x)

func land_prism(outline: PackedVector2Array, low: float, high: float, color: Color) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(outline.size()):
		var a := Vector3(outline[i].x,high,outline[i].y)
		var b := Vector3(outline[(i+1)%outline.size()].x,high,outline[(i+1)%outline.size()].y)
		for vertex: Vector3 in [Vector3(0,high,0),b,a,a,b,Vector3(b.x,low,b.z),a,Vector3(b.x,low,b.z),Vector3(a.x,low,a.z)]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	city._mesh(city,surface.commit(),Vector3.ZERO,color)

func tower_101() -> void:
	# Eight flared bamboo-like sections with green curtain walls and golden cornices.
	var base := Vector3(0,0.45,0)
	office(base,Vector3(4.6,1.1,4.8),true)
	office(base+Vector3(0,1.1,0),Vector3(2.25,1.6,2.25),true)
	for section: int in range(8):
		var bottom := 2.7+section*1.08
		for tier: int in range(4):
			var width := 2.15+tier*0.16
			box(base+Vector3(0,bottom+tier*0.24,0),Vector3(width,0.25,width),Color("1f6a67"))
			box(base+Vector3(0,bottom+tier*0.24+0.13,0),Vector3(width+0.04,0.028,width+0.04),Color("739e8a"))
		for side: int in [-1,1]:
			for line: int in range(7):
				box(base+Vector3(-1.08+line*0.36,bottom+0.40,side*1.34),Vector3(0.035,0.86,0.04),Color("8bbba5"))
				box(base+Vector3(side*1.34,bottom+0.40,-1.08+line*0.36),Vector3(0.04,0.86,0.035),Color("8bbba5"))
		box(base+Vector3(0,bottom+0.91,0),Vector3(2.82,0.08,2.82),Color("d6b879"),true)
		for side: int in [-1,1]:
			box(base+Vector3(side*1.3,bottom+0.98,0),Vector3(0.14,0.22,0.5),Color("b8b68c"))
	box(base+Vector3(0,11.75,0),Vector3(1.35,1.1,1.35),GLASS)
	box(base+Vector3(0,12.38,0),Vector3(0.72,0.18,0.72),Color("dfc68b"),true)
	disk(base+Vector3(0,13.2,0),0.06,1.5,Color("edca83"),true)

func retail() -> void:
	var p := Vector3(8,0.38,0)
	office(p,Vector3(5,2.3,3.8),true)
	box(p+Vector3(0,2.55,-0.3),Vector3(4.4,0.35,3),Color("a7a396"))
	for x: float in [-2.2,-0.75,0.75,2.2]:
		box(p+Vector3(x,1.4,2),Vector3(0.18,2.8,0.2),TRIM)
	box(p+Vector3(0,2.1,2.08),Vector3(4.5,0.3,0.06),Color("bd9867"),true)

func civic_center() -> void:
	var p := Vector3(7.8,0.35,8)
	office(p,Vector3(5.0,1.8,3.4),false)
	for x: float in [-2,-1,0,1,2]:
		box(p+Vector3(x,1,1.9),Vector3(0.23,2,0.25),TRIM)
	disk(p+Vector3(1,2.0,-0.2),1.25,0.3,Color("c7c8b9"))
	box(p+Vector3(-1.6,2.3,-0.6),Vector3(1.4,1,1.7),GLASS)

func office(p: Vector3, s: Vector3, glass: bool, background: bool = false) -> void:
	box(p + Vector3(0, s.y / 2, 0), s, Color("304f59") if glass else Color("76838a"))
	var floors := maxi(2, int(s.y / 0.52))
	var columns := maxi(3, int(s.x / 0.48))
	for level: int in range(floors):
		var y := p.y + 0.26 + level * (s.y - 0.2) / floors
		for column: int in range(columns):
			var x := p.x - s.x / 2 + (column + 0.5) * s.x / columns
			var lit := rng.randf() > (0.68 if glass else 0.76)
			var c := WARM if lit else Color("365d6b").lightened(rng.randi_range(0, 4) * 0.035)
			for side: int in [-1, 1]:
				box(Vector3(x, y, p.z + side * (s.z / 2 + 0.015)), Vector3(s.x / columns * 0.80, 0.33, 0.025), c, lit)
		for side: int in [-1, 1]:
			box(Vector3(p.x + side * (s.x / 2 + 0.02), y, p.z), Vector3(0.035, 0.30, s.z * 0.85), Color("486879"))
		if glass:
			box(Vector3(p.x, y + 0.24, p.z + s.z / 2 + 0.05), Vector3(s.x, 0.035, 0.04), TRIM)
	if glass:
		glass_walls(p, s)
	box(p + Vector3(0, s.y + 0.05, 0), Vector3(s.x + 0.15, 0.14, s.z + 0.15), TRIM)
	box(p + Vector3(0.25, s.y + 0.22, 0), Vector3(s.x * 0.35, 0.3, s.z * 0.35), Color("7a8885"))
	if background:
		return
	for col: int in range(columns + 1):
		box(Vector3(p.x - s.x / 2 + col * s.x / columns, p.y + s.y / 2, p.z + s.z / 2 + 0.06), Vector3(0.045, s.y, 0.08), Color("9eaead"))
	box(p + Vector3(0, 0.9, s.z / 2 + 0.6), Vector3(s.x * 0.65, 0.10, 1.3), TRIM)
	for side: int in [-1, 1]:
		box(p + Vector3(side * s.x * 0.27, 0.45, s.z / 2 + 0.9), Vector3(0.08, 0.9, 0.08), STONE)
	stairs(p + Vector3(0, -0.04, s.z / 2 + 0.9), s.x * 0.8)

func stairs(p: Vector3, width: float) -> void:
	for i: int in range(5):
		box(p + Vector3(0, i * 0.045, -i * 0.16), Vector3(width, 0.08, 1.1 - i * 0.16), STONE)

func ring(p: Vector3, radius: float, thickness: float, color: Color) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thickness
	torus.outer_radius = radius
	torus.rings = 48
	torus.ring_segments = 6
	city._mesh(city, torus, p, color)

func hospital() -> void:
	var p := Vector3(-7.8, 0.35, 0)
	office(p, Vector3(3.4, 2.8, 2.8), true)
	for side: int in [-1, 1]:
		office(p + Vector3(side * 1.9, 0, 0.5), Vector3(1.25, 2.0, 2.9), false)
	disk(p + Vector3(0, 2.98, 0), 1.15, 0.10, Color("306a56"))
	ring(p + Vector3(0, 3.05, 0), 1.04, 0.045, Color("d2dfcb"))
	box(p + Vector3(0, 3.07, 0), Vector3(0.25, 0.025, 1.15), TRIM)
	box(p + Vector3(0, 3.08, 0), Vector3(1.15, 0.025, 0.25), TRIM)
	box(p + Vector3(0, 1.0, 2.3), Vector3(2.5, 0.12, 1.5), TRIM)
	car(p + Vector3(2, 0.1, 2.6), Color("d7dedb"))

func preschool() -> void:
	var p := Vector3(-7, 0.35, 4.1)
	office(p, Vector3(3.8, 1.6, 2.3), false)
	box(p + Vector3(-1.8, 0.7, 1.0), Vector3(0.7, 1.4, 2.1), Color("b99562"))
	box(p + Vector3(0, 0.05, 2.5), Vector3(4.5, 0.08, 2.5), Color("689054"))
	for i: int in range(16):
		box(p + Vector3(-2.2 + i * 0.3, 0.3, 3.6), Vector3(0.045, 0.6, 0.045), TRIM)
	box(p + Vector3(0, 0.6, 2.3), Vector3(0.8, 0.12, 0.8), Color("b65539"))
	for x: float in [-0.32, 0.32]:
		box(p + Vector3(x, 0.32, 2.3), Vector3(0.06, 0.6, 0.06), Color("c59748"))
	var slide := box(p + Vector3(0.8, 0.3, 2.3), Vector3(1.0, 0.08, 0.4), Color("588cac"))
	slide.rotation.z = -0.45

func clubhouse() -> void:
	var p := Vector3(0.8, 0.35, 8)
	office(p, Vector3(4.8, 1.6, 2.7), true)
	box(p + Vector3(-0.65, 1.8, 0), Vector3(2.4, 0.18, 1.5), STONE)
	box(p + Vector3(-0.65, 1.92, 0), Vector3(2.2, 0.04, 1.3), Color("427f9f"))
	for x: float in [-1.7, 0.4]:
		box(p + Vector3(x, 2.0, 0), Vector3(0.035, 0.3, 1.5), TRIM)
	box(p + Vector3(1.65, 2, -0.55), Vector3(1.15, 0.5, 1.5), Color("7d8173"))
	for i: int in range(5):
		box(p + Vector3(-2 + i * 0.9, 1.08, 1.9), Vector3(0.10, 0.13, 1.2), Color("776d58"))

func residences() -> void:
	for i: int in range(3):
		var p := Vector3(-9.4 + (i % 2) * 2.2, 0.35, 6.2 + int(i / 2.0) * 2.5)
		office(p, Vector3(1.7, 3.6 + i * 0.5, 1.8), false)
		for floor_index: int in range(6):
			box(p + Vector3(0, 0.6 + floor_index * 0.52, 1.02), Vector3(1.8, 0.07, 0.4), TRIM)
	# Open construction frame and a tower crane.
	var p := Vector3(-6.7, 0.35, 8.5)
	for level: int in range(5):
		box(p + Vector3(0, level * 0.65, 0), Vector3(1.7, 0.12, 1.8), Color("959a8e"))
	for x: float in [-0.7, 0.7]:
		for z: float in [-0.7, 0.7]:
			box(p + Vector3(x, 1.5, z), Vector3(0.14, 3.2, 0.14), STONE)
	var gold := Color("b89444")
	box(p + Vector3(0.8, 2.6, -0.8), Vector3(0.14, 5.2, 0.14), gold)
	box(p + Vector3(-0.3, 5.2, -0.8), Vector3(4.5, 0.15, 0.15), gold)
	box(p + Vector3(-2.2, 4.1, -0.8), Vector3(0.025, 2.2, 0.025), DARK)
	for i: int in range(10):
		box(p + Vector3(0.8, 0.3 + i * 0.48, -0.8), Vector3(0.35, 0.035, 0.35), gold)

func tree(p: Vector3, height: float = 1.2) -> void:
	box(p + Vector3(0, height * 0.35, 0), Vector3(0.09, height * 0.7, 0.09), Color("655b46"))
	for i: int in range(7):
		var offset := Vector3(rng.randf_range(-0.30, 0.30), rng.randf_range(0.65, 1.1), rng.randf_range(-0.30, 0.30)) * height
		var leaf: MeshInstance3D = city._sphere(city, p + offset, height * rng.randf_range(0.22, 0.36), Color("244f37").lightened(rng.randi_range(0, 4) * 0.03))
		leaf.scale.y = 1.15

func planting() -> void:
	for side: int in [-1,1]:
		for i: int in range(12):
			for x: float in [3,13.5,16.5]:
				var z := -13+i*2.3
				if absf(z-4) > 1.5:
					tree(Vector3(side*x,0.35,z),rng.randf_range(0.65,1))
	for i: int in range(22):
		tree(Vector3(-15+i*1.4,0.35,14),rng.randf_range(0.7,1.1))

func car(p: Vector3, color: Color) -> void:
	box(p + Vector3(0, 0.13, 0), Vector3(0.40, 0.19, 0.85), color)
	box(p + Vector3(0, 0.28, 0), Vector3(0.32, 0.16, 0.45), Color("314b57"))
	for side: int in [-1, 1]:
		for z: float in [-0.28, 0.28]:
			box(p + Vector3(side * 0.21, 0.08, z), Vector3(0.06, 0.15, 0.15), Color("20292c"))

func street_details() -> void:
	for i: int in range(24):
		var a := TAU * (i + 0.5) / 24.0
		var p := Vector3(sin(a) * 14.9, 0.24, cos(a) * 14.9)
		box(p + Vector3(0, 0.9, 0), Vector3(0.05, 1.8, 0.05), DARK)
		box(p + Vector3(0.16, 1.8, 0), Vector3(0.4, 0.04, 0.06), DARK)
		box(p + Vector3(0.30, 1.77, 0), Vector3(0.18, 0.05, 0.12), Color("e0bc78"), true)
		if i % 4 == 1:
			car(Vector3(sin(a) * 11.9, 0.26, cos(a) * 11.9), Color("c7c8b8"))
	for side: int in [-1, 1]:
		for i: int in range(7):
			box(Vector3(side * 12.6, 0.25, -0.8 + i * 0.26), Vector3(2.9, 0.015, 0.13), Color("c3c5b7"))



func glass_walls(p: Vector3, s: Vector3) -> void:
	for side: int in [-1, 1]:
		var front := QuadMesh.new()
		front.size = Vector2(s.x, s.y)
		var wall: MeshInstance3D = city._mesh(city, front, p + Vector3(0, s.y / 2, side * (s.z / 2 + 0.035)), Color.WHITE)
		wall.rotation.y = 0 if side == 1 else PI
		wall.material_override = facade
		var flank := QuadMesh.new()
		flank.size = Vector2(s.z, s.y)
		var other: MeshInstance3D = city._mesh(city, flank, p + Vector3(side * (s.x / 2 + 0.04), s.y / 2, 0), Color.WHITE)
		other.rotation.y = side * PI / 2
		other.material_override = facade
