@tool
extends Control
## Fixed artwork; all progression, markers and motion are separate live layers.
const Layer := preload("res://scripts/map/map_layer.gd")
const GREEN := Color("00a86b")
const GOLD := Color("c6a15b")
const INK := Color("062f2a")
const TEXT := Color("f3f0e7")
const LOCATIONS := [
	{"id":"hq", "name":"台北101・法巴總部", "position":[0.326,0.715]},
	{"id":"bank", "name":"銀行通路", "position":[0.55,0.50]},
	{"id":"cafe", "name":"社區咖啡", "position":[0.585,0.485]},
	{"id":"hospital", "name":"醫療照護", "position":[0.806,0.286]},
	{"id":"market", "name":"商圈拜訪", "position":[0.81,0.46]},
	{"id":"housing", "name":"住宅生活圈", "position":[0.72,0.78]},
	{"id":"park", "name":"家庭生活圈", "position":[0.585,0.275]},
	{"id":"civic", "name":"顧問研討", "position":[0.17,0.235]}
]
const ROAD := [[.326,.715],[.39,.65],[.43,.617],[.47,.577],[.485,.558],[.487,.545],[.55,.50],[.585,.485],[.65,.45],[.72,.39],[.735,.33],[.77,.295],[.806,.286],[.84,.32],[.88,.37],[.86,.415],[.81,.46],[.77,.52],[.72,.58],[.665,.63],[.61,.68],[.55,.735],[.47,.79],[.39,.77]]
const ROUTES := [
	[[.326,.715],[.39,.65],[.43,.617],[.47,.577],[.485,.558],[.487,.545],[.55,.50]],
	[[.55,.50],[.585,.485]],
	[[.585,.485],[.65,.45],[.72,.39],[.735,.33],[.77,.295],[.806,.286]],
	[[.806,.286],[.84,.32],[.88,.37],[.86,.415],[.81,.46]],
	[[.81,.46],[.77,.52],[.72,.58],[.665,.63],[.72,.70],[.72,.78]],
	[[.72,.78],[.665,.63],[.72,.39],[.735,.33],[.68,.29],[.585,.275]],
	[[.585,.275],[.52,.235],[.40,.205],[.28,.20],[.17,.235]]
]
signal location_selected(id: String)
var tiles: Array = []
var players: Array = []
var territory: Dictionary = {}
var current_id := ""
var title_sub := ""
var _shown: Dictionary = {}
var _freeze_timer := 0.0
var _layers: Dictionary = {}
var _buttons: Dictionary = {}
var _map_rect := Rect2()
var _background: TextureRect
var _progress: Dictionary = {}
var _completed: Array = []
var _unlocked: Array = ["hq", "bank"]
var _current := "bank"
var _route_amount := 1.0
var _mask_alpha: Dictionary = {}
var _route_tween: Tween
var _locations: Array = LOCATIONS.duplicate(true)

func _ready() -> void:
	name = "MapRoot"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_background = TextureRect.new()
	_background.name = "MapBackground"
	_background.texture = load("res://assets/maps/taipei101.png")
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	for layer_name in ["LockedZoneLayer", "RouteLayer", "LocationLayer", "CustomerLayer", "EventLayer", "PlayerLayer", "EffectLayer", "HUDLayer"]:
		var layer := Layer.new()
		layer.name = layer_name
		layer.kind = layer_name
		layer.board = self
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		_layers[layer_name] = layer
	for loc: Dictionary in _locations:
		var b := Button.new()
		b.name = str(loc.id)
		b.text = "●"
		b.tooltip_text = str(loc.name)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(32,32)
		b.add_theme_font_size_override("font_size",18)
		b.mouse_entered.connect(_animate_marker.bind(b,1.03))
		b.mouse_exited.connect(_animate_marker.bind(b,1.0))
		b.button_down.connect(_animate_marker.bind(b,.96))
		b.button_up.connect(_animate_marker.bind(b,1.0))
		b.pressed.connect(func(): location_selected.emit(str(loc.id)))
		_layers.LocationLayer.add_child(b)
		_buttons[loc.id] = b
	resized.connect(_layout)
	_layout()
	_update_markers()

func _animate_marker(b: Button, amount: float) -> void:
	if b.has_meta("motion"):
		var old: Tween = b.get_meta("motion")
		if old.is_valid(): old.kill()
	var motion := create_tween()
	motion.tween_property(b,"scale",Vector2.ONE * amount, .15)
	b.set_meta("motion",motion)

func get_inner_rect() -> Rect2:
	return Rect2(8,maxf(0,size.y-90),maxf(1,size.x-16),86)

func _layout() -> void:
	if _background == null: return
	var available := Vector2(size.x,maxf(1,size.y-96))
	var texture_size := _background.texture.get_size()
	var ratio := minf(available.x / texture_size.x, available.y / texture_size.y)
	_map_rect = Rect2((available-texture_size*ratio)*.5, texture_size*ratio)
	_background.position = _map_rect.position
	_background.size = _map_rect.size
	for layer: Control in _layers.values(): layer.size = size
	for loc: Dictionary in _locations:
		var b: Button = _buttons[loc.id]
		b.size = Vector2(30,30)
		b.position = map_point(loc.position) - b.size*.5
		b.pivot_offset = b.size*.5
	_redraw_layers()

func map_point(point: Array) -> Vector2:
	return _map_rect.position + Vector2(float(point[0]),float(point[1])) * _map_rect.size

func set_data(board: Array, ps: Array, current: String, terr: Dictionary = {}) -> void:
	tiles = board.duplicate(true)
	players = ps
	current_id = current
	territory = terr
	var live: Array = []
	for p: Dictionary in players:
		var id := str(p.get("id",""))
		live.append(id)
		if not _shown.has(id): _shown[id] = float(p.get("pos",0))
	for id in _shown.keys():
		if not live.has(id): _shown.erase(id)
	_redraw_layers()

func current_index() -> int:
	for p: Dictionary in players:
		if str(p.get("id","")) == current_id: return int(p.get("pos",0))
	return 0

func freeze_movement(duration: float) -> void:
	_freeze_timer = maxf(0,duration)

func set_progress(state: Dictionary) -> void:
	var next: Dictionary = state.get("mapProgress",{})
	if next.is_empty():
		for p: Dictionary in state.get("players",[]):
			if str(p.get("id","")) == current_id: next = p.get("mapProgress",{})
	if next.is_empty() or next == _progress: return
	var first := _progress.is_empty()
	var previous_unlocked := _unlocked.duplicate()
	var previous_current := _current
	_progress = next.duplicate(true)
	_completed = next.get("completedLocations",[])
	_unlocked = next.get("unlockedLocations",["hq","bank"])
	_current = str(next.get("currentLocation","bank"))
	if not first:
		for id in _unlocked:
			if not previous_unlocked.has(id):
				_mask_alpha[id] = .68
				create_tween().tween_method(func(value:float): _mask_alpha[id]=value; _redraw_layers(),.68,0.0,.6)
	if first or _current != previous_current:
		if _route_tween != null and _route_tween.is_valid(): _route_tween.kill()
		_route_amount = 1.0 if first or UI.reduce_motion else 0.0
		if _route_amount == 0:
			_route_tween = create_tween()
			_route_tween.tween_property(self,"_route_amount",1.0,.8)
	_update_markers()
	_redraw_layers()

func _update_markers() -> void:
	for loc: Dictionary in _locations:
		if not _buttons.has(loc.id): continue
		var b: Button = _buttons[loc.id]
		var active := str(loc.id) == _current
		var unlocked := _unlocked.has(loc.id)
		b.disabled = not active
		b.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
		b.text = "✓" if _completed.has(loc.id) else ("●" if unlocked else "⌑")
		b.modulate = Color.WHITE if unlocked else Color(.7,.8,.75,.75)
		b.add_theme_color_override("font_color",TEXT)
		b.add_theme_color_override("font_disabled_color",GOLD if _completed.has(loc.id) else TEXT)
		for style in ["normal","hover","pressed","disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("0d4038")
			box.border_color = GOLD if active else GREEN.darkened(.35)
			box.set_border_width_all(1)
			box.set_corner_radius_all(16)
			b.add_theme_stylebox_override(style,box)

func _process(delta: float) -> void:
	_freeze_timer = maxf(0,_freeze_timer-delta)
	for p: Dictionary in players:
		var id := str(p.get("id",""))
		var before: float = _shown.get(id,float(p.get("pos",0)))
		var diff := fposmod(float(p.get("pos",0))-before,24)
		if _freeze_timer <= 0 and diff > .001:
			_shown[id] = fposmod(before+minf(diff,delta*6),24)
	_redraw_layers()

func _redraw_layers() -> void:
	for layer: Control in _layers.values(): layer.queue_redraw()

func _line(canvas: Control, points: Array, color: Color, amount: float=1.0) -> void:
	if points.size()<2: return
	var total := 0.0
	for i in range(1,points.size()): total += map_point(points[i-1]).distance_to(map_point(points[i]))
	var remaining := total*amount
	for i in range(1,points.size()):
		var a := map_point(points[i-1])
		var b := map_point(points[i])
		var length := a.distance_to(b)
		if remaining <= 0: break
		canvas.draw_line(a,a.lerp(b,minf(1,remaining/maxf(.001,length))),color,2.5,true)
		remaining -= length

func draw_layer(canvas: Control, kind: String) -> void:
	var font := get_theme_default_font()
	match kind:
		"LockedZoneLayer":
			for loc: Dictionary in _locations:
				if str(loc.id)=="hq": continue
				var alpha: float = _mask_alpha.get(loc.id,0.0 if _unlocked.has(loc.id) else .68)
				if alpha <= .001: continue
				var center := map_point(loc.position)
				var radius := _map_rect.size*Vector2(.105,.15)
				var polygon := PackedVector2Array()
				for j in range(8):
					var a := TAU*j/8.0
					polygon.append(center+Vector2(cos(a),sin(a))*radius)
				canvas.draw_colored_polygon(polygon,Color(INK,alpha))
		"RouteLayer":
			for i in range(ROUTES.size()):
				var destination: String = _locations[i+1].id
				if _completed.has(destination): _line(canvas,ROUTES[i],GREEN.darkened(.48))
				elif destination == _current and _unlocked.has(destination): _line(canvas,ROUTES[i],GREEN,_route_amount)
		"PlayerLayer":
			for i in range(players.size()):
				var p: Dictionary = players[i]
				var shown: float = _shown.get(str(p.get("id","")),0.0)
				var base := int(floorf(shown))%24
				var at := map_point(ROAD[base]).lerp(map_point(ROAD[(base+1)%24]),fposmod(shown,1.0)) + Vector2(i*9,-20)
				var color: Color = UI.PLAYER_COLORS[i%UI.PLAYER_COLORS.size()]
				canvas.draw_circle(at,5,color)
				canvas.draw_style_box(UI.box(color,4,INK,0,false),Rect2(at+Vector2(-6,6),Vector2(12,13)))
		"HUDLayer":
			for loc: Dictionary in _locations:
				if str(loc.id) == _current:
					var at := map_point(loc.position)+Vector2(-80,32)
					canvas.draw_style_box(UI.box(INK,4,GOLD,0,false),Rect2(at-Vector2(0,16),Vector2(160,25)))
					canvas.draw_string(font,at,str(loc.name),HORIZONTAL_ALIGNMENT_CENTER,160,13,TEXT)
		"CustomerLayer":
			for customer: Dictionary in _progress.get("customers",[]):
				_draw_content_marker(canvas,customer,true)
		"EventLayer":
			for event: Dictionary in _progress.get("events",[]):
				_draw_content_marker(canvas,event,false)

func _draw_content_marker(canvas:Control, data:Dictionary, customer:bool) -> void:
	var position_data: Array = data.get("mapPosition",[])
	if position_data.size()!=2: return
	var at := map_point(position_data)+Vector2(20,-14)
	var status := str(data.get("status","locked"))
	canvas.draw_circle(at,11,INK)
	canvas.draw_arc(at,11,0,TAU,24,GOLD if status=="current" else GREEN,1,true)
	var mark := "✓" if status=="completed" else ("?" if status=="hidden" else ("⌑" if status=="locked" else ("人" if customer else "!")))
	canvas.draw_string(get_theme_default_font(),at+Vector2(-10,5),mark,HORIZONTAL_ALIGNMENT_CENTER,20,13,TEXT)
