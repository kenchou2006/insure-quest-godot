@tool
extends Node
## Automation bridge for scripted recording (active on web when ?automation=1).
## Exposes window.iqAuto (list, screen, find) for headless/Playwright test driving and automated recording.

var main: Node = null

var _cb_list: JavaScriptObject = null
var _cb_screen: JavaScriptObject = null
var _cb_find: JavaScriptObject = null


static func is_active() -> bool:
	if Engine.is_editor_hint() or not OS.has_feature("web"):
		return false
	var res = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('automation') === '1'", true)
	return bool(res)


static func get_url_demo() -> String:
	if Engine.is_editor_hint() or not OS.has_feature("web"):
		return ""
	var res = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('demo') || ''", true)
	return str(res).strip_edges() if typeof(res) == TYPE_STRING else ""


static func is_tutorial_disabled() -> bool:
	if not is_active():
		return false
	var res = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('tutorial') === '1'", true)
	return not bool(res)


func _ready() -> void:
	if Engine.is_editor_hint() or not OS.has_feature("web"):
		return
	if not is_active():
		return
	_setup_bridge()


func _setup_bridge() -> void:
	_cb_list = JavaScriptBridge.create_callback(_on_js_list)
	_cb_screen = JavaScriptBridge.create_callback(_on_js_screen)
	_cb_find = JavaScriptBridge.create_callback(_on_js_find)

	var js_window = JavaScriptBridge.get_interface("window")
	if js_window:
		js_window._iqAuto_list_raw = _cb_list
		js_window._iqAuto_screen_raw = _cb_screen
		js_window._iqAuto_find_raw = _cb_find

		JavaScriptBridge.eval("""(function() {
			function call(fn, arg) {
				window._iqAutoRet = 'null';
				fn(arg);
				try { return JSON.parse(window._iqAutoRet); } catch (e) { return null; }
			}
			window.iqAuto = {
				// UI labels use non-breaking spaces; normalise so scripts can match plain text
				all: function() { return (call(window._iqAuto_list_raw) || []).map(function(x) { x.text = String(x.text).replace(/\u00a0/g, ' '); return x; }); },
				list: function() { return this.all().filter(function(x) { return x.kind !== 'label'; }); },
				// Any visible text, including labels (for waiting on screen state)
				findText: function(t) { t = String(t).replace(/\u00a0/g, ' '); return this.all().find(function(x) { return String(x.text).indexOf(t) >= 0; }) || null; },
				screen: function() { return call(window._iqAuto_screen_raw); },
				// Match in JS: some non-ASCII characters (e.g. ▶) do not survive the JS → Godot string argument
				find: function(t) { t = String(t).replace(/\u00a0/g, ' '); return this.list().find(function(x) { return String(x.text).indexOf(t) >= 0; }) || null; }
			};
		})()""")


# JavaScriptBridge callbacks cannot return values to JS, so each one stores its JSON in window._iqAutoRet
func _ret(json: String) -> void:
	var w = JavaScriptBridge.get_interface("window")
	if w:
		w._iqAutoRet = json


func _on_js_list(_args: Array) -> void:
	_ret(JSON.stringify(get_all_elements()))


func _on_js_screen(_args: Array) -> void:
	var s: Variant = get_current_screen()
	_ret(JSON.stringify(s) if s is Dictionary else JSON.stringify(str(s)))


func _on_js_find(args: Array) -> void:
	var query := str(args[0]) if args.size() > 0 else ""
	var item = find_element(query)
	_ret("null" if item == null else JSON.stringify(item))


## Calculates bounding rect of canvas element in page CSS pixels
func _get_canvas_metrics() -> Dictionary:
	if not OS.has_feature("web") or Engine.is_editor_hint():
		return {"left": 0.0, "top": 0.0, "width": 1280.0, "height": 720.0}
	var raw = JavaScriptBridge.eval("""(function() {
		var c = document.getElementById('canvas');
		if (!c) return JSON.stringify({ left: 0, top: 0, width: window.innerWidth, height: window.innerHeight });
		var r = c.getBoundingClientRect();
		return JSON.stringify({ left: r.left, top: r.top, width: r.width, height: r.height });
	})()""", true)
	if typeof(raw) == TYPE_STRING:
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {"left": 0.0, "top": 0.0, "width": 1280.0, "height": 720.0}


func get_all_elements() -> Array:
	var root: Window = get_tree().root
	var vp_size: Vector2 = Vector2(root.get_visible_rect().size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = Vector2(1280, 720)

	var cm: Dictionary = _get_canvas_metrics()
	var c_left: float = float(cm.get("left", 0.0))
	var c_top: float = float(cm.get("top", 0.0))
	var c_w: float = float(cm.get("width", vp_size.x))
	var c_h: float = float(cm.get("height", vp_size.y))

	var scale_x: float = c_w / vp_size.x
	var scale_y: float = c_h / vp_size.y

	var raw_elements: Array = []
	_collect_nodes(root, raw_elements)

	# Hotspot fallback if in interview discover step and no hotspot node had meta
	_check_hotspot_fallback(root, raw_elements)

	var out: Array = []
	for item: Dictionary in raw_elements:
		var gr: Rect2 = item.get("rect", Rect2())
		var css_x: float = c_left + gr.position.x * scale_x
		var css_y: float = c_top + gr.position.y * scale_y
		var css_w: float = gr.size.x * scale_x
		var css_h: float = gr.size.y * scale_y
		out.append({
			"text": str(item.get("text", "")),
			"x": snappedf(css_x, 0.5),
			"y": snappedf(css_y, 0.5),
			"w": snappedf(css_w, 0.5),
			"h": snappedf(css_h, 0.5),
			"kind": str(item.get("kind", "button"))
		})
	return out


func _collect_nodes(node: Node, out: Array) -> void:
	if not (node is CanvasItem):
		for child in node.get_children():
			_collect_nodes(child, out)
		return

	var ci := node as CanvasItem
	if not ci.is_visible_in_tree():
		return

	# 1. Hotspot node detection via metadata or naming convention
	# Note: Part A sets meta 'hotspot_index' on hotspot buttons/nodes
	if ci.has_meta("hotspot_index"):
		var h_idx = ci.get_meta("hotspot_index")
		if ci is Control:
			out.append({"text": "hotspot:%s" % str(h_idx), "rect": (ci as Control).get_global_rect()})
	elif ci.has_meta("clue_index"):
		var c_idx = ci.get_meta("clue_index")
		if ci is Control:
			out.append({"text": "hotspot:%s" % str(c_idx), "rect": (ci as Control).get_global_rect()})
	elif ci.name.begins_with("hotspot_") or ci.name.begins_with("Hotspot_"):
		var sub_name := ci.name.substr(ci.name.find("_") + 1)
		if ci is Control:
			out.append({"text": "hotspot:%s" % sub_name, "rect": (ci as Control).get_global_rect()})

	# 2. BaseButton detection (Buttons, OptionButtons, etc.)
	if ci is BaseButton:
		var btn := ci as BaseButton
		if not btn.disabled and btn.size.x > 0 and btn.size.y > 0:
			var txt := ""
			if btn is Button:
				txt = (btn as Button).text
			elif btn is OptionButton:
				txt = (btn as OptionButton).text
			if txt == "":
				for ch in btn.get_children():
					if ch is Label and ch.is_visible_in_tree():
						txt = (ch as Label).text
						break
			if txt == "" and btn.tooltip_text != "":
				txt = btn.tooltip_text
			if txt != "":
				out.append({"text": txt, "rect": btn.get_global_rect()})

	# 3. Plain text (labels) so scripts can wait for on-screen text; never used as click targets by find()
	elif ci is Label or ci is RichTextLabel:
		var lt: String = (ci as Label).text if ci is Label else (ci as RichTextLabel).get_parsed_text()
		if lt != "" and (ci as Control).size.x > 0:
			out.append({"text": lt, "rect": (ci as Control).get_global_rect(), "kind": "label"})

	# 4. LineEdit detection
	elif ci is LineEdit:
		var le := ci as LineEdit
		if le.editable and le.size.x > 0 and le.size.y > 0:
			var txt := le.placeholder_text if le.text == "" else le.text
			if txt == "":
				txt = le.name
			out.append({"text": txt, "rect": le.get_global_rect()})

	for child in ci.get_children():
		_collect_nodes(child, out)


func _check_hotspot_fallback(root: Node, out: Array) -> void:
	if not Net.state.has("session") or not (Net.state["session"] is Dictionary):
		return
	var sess: Dictionary = Net.state["session"]
	if str(sess.get("step", "")) != "discover":
		return
	var clues: Array = sess.get("clues", [])
	if clues.is_empty():
		return

	# Check if any hotspot was already discovered via metadata
	for item in out:
		if str(item.get("text", "")).begins_with("hotspot:"):
			return

	# Fallback: locate scene box and project spot rects
	var scene_box := _find_scene_box(root)
	if scene_box and scene_box is Control:
		var s_rect: Rect2 = (scene_box as Control).get_global_rect()
		for i in clues.size():
			var cl: Dictionary = clues[i]
			var spot: Dictionary = cl.get("spot", {}) if cl.get("spot") is Dictionary else {}
			var sx: float = float(spot.get("x", 10.0 + i * 22.0)) / 100.0
			var sy: float = float(spot.get("y", 20.0 + (i % 2) * 30.0)) / 100.0
			var sw: float = float(spot.get("w", 18.0)) / 100.0
			var sh: float = float(spot.get("h", 20.0)) / 100.0
			var h_rect := Rect2(
				s_rect.position.x + sx * s_rect.size.x,
				s_rect.position.y + sy * s_rect.size.y,
				sw * s_rect.size.x,
				sh * s_rect.size.y
			)
			out.append({"text": "hotspot:%d" % i, "rect": h_rect})


func _find_scene_box(node: Node) -> Control:
	if node is AspectRatioContainer and (node as Control).is_visible_in_tree():
		for ch in node.get_children():
			if ch is Control and not (ch is AspectRatioContainer):
				return ch as Control
	for ch in node.get_children():
		var found = _find_scene_box(ch)
		if found:
			return found
	return null


func get_current_screen() -> Variant:
	var cur_kind := ""
	if main:
		cur_kind = str(main.get("_screen_kind"))
	if cur_kind == "":
		cur_kind = "menu"

	if cur_kind == "game":
		var sess: Dictionary = Net.state.get("session", {}) if Net.state.get("session") is Dictionary else {}
		return {
			"screen": "game",
			"step": str(sess.get("step", "")),
			"round": int(Net.state.get("round", 1)),
			"myTurn": Net.is_my_turn()
		}
	return cur_kind


func find_element(query: String) -> Variant:
	if query == "":
		return null
	var elements := get_all_elements()
	for el: Dictionary in elements:
		var t: String = str(el.get("text", ""))
		if query in t:
			return el
	return null
