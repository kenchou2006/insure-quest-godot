extends RefCounted
## Lock / unlock trace for everything that can stop the player from clicking. Every change prints
## one line (the browser console on the web build):
## [UI-LOCK] event | current_scene | overlay.visible | overlay.mouse_filter | input_locked |
## is_transitioning | secretary_state | api_request_state
## The screen state comes from main.ui_snapshot(); api_request_state is kept here by whoever is
## waiting on the server (idle / waiting:<what> / failed:<what>).

static var api_request_state := "idle"
static var enabled := true
## Per-click trace: debug builds, or ?uidebug=1 on the web
static var click_trace := _want_click_trace()


static func _want_click_trace() -> bool:
	if Engine.is_editor_hint():
		return false
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('uidebug') === '1'", true))
	return OS.is_debug_build()


static func set_api(state: String, event := "") -> void:
	api_request_state = state
	log_event(event if event != "" else "api:" + state)


static func log_event(event: String) -> void:
	if not enabled:
		return
	var s := snapshot()
	print("[UI-LOCK] %s | current_scene=%s | overlay.visible=%s | overlay.mouse_filter=%s | input_locked=%s | is_transitioning=%s | secretary_state=%s | api_request_state=%s" % [
		event, s.current_scene, s.overlay_visible, s.overlay_mouse_filter, s.input_locked,
		s.is_transitioning, s.secretary_state, s.api_request_state])


static func snapshot() -> Dictionary:
	var out := {
		"current_scene": "?", "overlay_visible": false, "overlay_mouse_filter": "none",
		"input_locked": false, "is_transitioning": false, "secretary_state": "?",
		"api_request_state": api_request_state,
	}
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = tree.current_scene if tree else null
	if main and main.has_method("ui_snapshot"):
		out.merge(main.ui_snapshot(), true)
		out.api_request_state = api_request_state
	return out


static func filter_name(f: int) -> String:
	return {Control.MOUSE_FILTER_STOP: "STOP", Control.MOUSE_FILTER_PASS: "PASS", Control.MOUSE_FILTER_IGNORE: "IGNORE"}.get(f, str(f))
