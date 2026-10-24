extends RefCounted
## Fullscreen for 設定 › 全螢幕 and the hall's top-bar button. On the web it is the browser's
## Fullscreen API on the whole page, not just the canvas, so the HTML text box used for Chinese
## input (web_text.gd) stays visible; it is hidden where the browser has no Fullscreen API (e.g.
## iPhone Safari). Esc or the browser's own control can leave it at any time, so the state is
## always read back, never remembered.
## Installed as an app (PWA) it goes fullscreen by itself: the manifest asks for display: fullscreen
## (Android), and a standalone window (desktop) enters fullscreen on the first tap or key of each
## launch — browsers allow that only inside a user gesture. Leaving with Esc is respected.


static func _web() -> bool:
	return OS.has_feature("web") and not Engine.is_editor_hint()


## Launched fullscreen by the manifest: the Fullscreen API has nothing to toggle then
static func _app_fullscreen() -> bool:
	return _web() and bool(JavaScriptBridge.eval("window.matchMedia('(display-mode: fullscreen)').matches", true))


static func is_supported() -> bool:
	if Engine.is_editor_hint():
		return false
	if _web():
		return not _app_fullscreen() and bool(JavaScriptBridge.eval("!!(document.fullscreenEnabled || document.webkitFullscreenEnabled)", true))
	return true


## Call once at start: in an installed app window, the first tap or key of this launch enters fullscreen
static func auto_enter_in_app() -> void:
	if not _web():
		return
	JavaScriptBridge.eval("""(function() {
		if (window.__iqAutoFullscreen) return;
		window.__iqAutoFullscreen = true;
		var mq = function(m) { return window.matchMedia('(display-mode: ' + m + ')').matches; };
		if (!(mq('standalone') || mq('minimal-ui')) || mq('fullscreen')) return;
		var el = document.documentElement;
		var req = el.requestFullscreen || el.webkitRequestFullscreen;
		if (!req || !(document.fullscreenEnabled || document.webkitFullscreenEnabled)) return;
		var once = function() {
			window.removeEventListener('pointerdown', once, true);
			window.removeEventListener('keydown', once, true);
			if (document.fullscreenElement || document.webkitFullscreenElement) return;
			var p = req.call(el);
			if (p && p.catch) p.catch(function() {});
		};
		window.addEventListener('pointerdown', once, true);
		window.addEventListener('keydown', once, true);
	})()""", true)


static func is_on() -> bool:
	if _web():
		return bool(JavaScriptBridge.eval("!!(document.fullscreenElement || document.webkitFullscreenElement)", true))
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]


## Call from a click: browsers only allow entering fullscreen right after a user gesture
static func set_on(on: bool) -> void:
	if not is_supported() or on == is_on():
		return
	if _web():
		if on:
			JavaScriptBridge.eval("""(function() {
				var el = document.documentElement;
				var req = el.requestFullscreen || el.webkitRequestFullscreen;
				if (req) { var p = req.call(el); if (p && p.catch) p.catch(function() {}); }
			})()""", true)
		else:
			JavaScriptBridge.eval("""(function() {
				var exit = document.exitFullscreen || document.webkitExitFullscreen;
				if (exit) { var p = exit.call(document); if (p && p.catch) p.catch(function() {}); }
			})()""", true)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


static func toggle() -> void:
	set_on(not is_on())
