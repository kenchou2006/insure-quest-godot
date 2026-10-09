@tool
extends Node
## Web Chinese input (Autoload "WebText").
## The Godot web canvas does not receive text submitted after IME composition, so on web:
## when any LineEdit gains focus, a real HTML <input> is overlaid directly above it,
## synchronizing input back to LineEdit in real time and triggering LineEdit text_submitted on Enter.

const JS_SETUP := """
(function () {
  if (window.iqOpenInput) return;
  window.iqOpenInput = function (x, y, w, h, val, ph, maxLen, fsRatio) {
    var canvas = document.getElementById('canvas');
    var c = canvas.getBoundingClientRect();
    var el = document.getElementById('iq-input');
    if (!el) {
      el = document.createElement('input');
      el.id = 'iq-input';
      el.type = 'text';
      el.autocomplete = 'off';
      el.style.cssText = 'position:fixed;z-index:10;box-sizing:border-box;display:none;' +
        'background:#0e2633;color:#eef6f3;border:2px solid #2fd197;border-radius:10px;padding:0 10px;outline:none;' +
        'font-family:"PingFang TC","Noto Sans TC","Microsoft JhengHei",sans-serif;';
      var stop = function (e) { e.stopPropagation(); };
      el.addEventListener('keyup', stop);
      el.addEventListener('keypress', stop);
      el.addEventListener('keydown', function (e) {
        e.stopPropagation();
        if (e.key === 'Enter' && !e.isComposing) {
          window.iqTextCallback(el.value, true);
          el.value = '';
          el.blur();
        } else if (e.key === 'Escape') {
          el.blur();
        }
      });
      el.addEventListener('input', function () { window.iqTextCallback(el.value, false); });
      el.addEventListener('blur', function () {
        // Programmatic temporary hiding (field scrolled out of view, tab switched) is not considered end of input
        if (el._iqHiding) return;
        // When Godot toggles IME (set_ime_active), it calls canvas.focus(), which steals focus if it occurs after our focus:
        // reclaim focus if stolen shortly after opening; window-level blur (switching to another app) does not count as ending input
        if (performance.now() - (el._iqOpenedAt || 0) < 600 || !document.hasFocus()) {
          setTimeout(function () { if (el.style.display !== 'none') el.focus(); }, 30);
          return;
        }
        el.style.display = 'none';
        canvas.focus();
        window.iqTextCallback(el.value, false, true);
      });
      document.body.appendChild(el);
    }
    el.style.left = (c.left + x * c.width) + 'px';
    el.style.top = (c.top + y * c.height) + 'px';
    el.style.width = (w * c.width) + 'px';
    el.style.height = (h * c.height) + 'px';
    el.style.fontSize = (fsRatio && fsRatio > 0 ? Math.max(12, Math.round(fsRatio * c.height)) : Math.max(14, h * c.height * 0.42)) + 'px';
    el.maxLength = maxLen > 0 ? maxLen : 524288;
    el.value = val;
    el.placeholder = ph;
    el.style.display = 'block';
    el._iqOpenedAt = performance.now();
    // Slightly delay focus to avoid canvas.focus() when Godot yields focus
    setTimeout(function () { el.focus(); el.select(); }, 60);
    // When the page first loads, Godot steals focus later: reclaim within the first 0.6s if stolen (without re-selecting to avoid overwriting typed text)
    [200, 350, 500, 650].forEach(function (ms) {
      setTimeout(function () { if (el.style.display !== 'none' && document.activeElement !== el) el.focus(); }, ms);
    });
  };
  // Moving to a new field after screen rebuild: only update position, preserving user input and focus
  window.iqMoveInput = function (x, y, w, h, fsRatio) {
    var canvas = document.getElementById('canvas');
    var c = canvas.getBoundingClientRect();
    var el = document.getElementById('iq-input');
    if (!el) return '';
    el.style.left = (c.left + x * c.width) + 'px';
    el.style.top = (c.top + y * c.height) + 'px';
    el.style.width = (w * c.width) + 'px';
    el.style.height = (h * c.height) + 'px';
    if (fsRatio && fsRatio > 0) el.style.fontSize = Math.max(12, Math.round(fsRatio * c.height)) + 'px';
    return el.value;
  };
  // Temporarily hide/restore: preserve text and target field
  window.iqSetVisible = function (v) {
    var el = document.getElementById('iq-input');
    if (!el) return;
    if (v) {
      el.style.display = 'block';
      el._iqHiding = false;
      setTimeout(function () { el.focus(); }, 0);
    } else {
      el._iqHiding = true;
      el.style.display = 'none';
      el.blur();
    }
  };
  window.iqCloseInput = function () {
    var el = document.getElementById('iq-input');
    if (el) { el.style.display = 'none'; el.blur(); }
  };
})();
"""

var _callback: JavaScriptObject = null
var _target: LineEdit = null
## Current position of overlay box (checked every frame; moves with field movement, scrolling, or window resize)
var _shown_rect := Rect2()
var _hidden := false
var _retargeting := false


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(JS_SETUP, true)
	_callback = JavaScriptBridge.create_callback(_on_js_text)
	JavaScriptBridge.get_interface("window").iqTextCallback = _callback
	get_viewport().gui_focus_changed.connect(_on_focus)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not OS.has_feature("web") or _target == null or _retargeting:
		return
	if not is_instance_valid(_target):
		_target = null
		return
	# When field is not on screen (switched to another tab, scrolled out of view), temporarily hide overlay and restore upon return
	var r := _visible_rect(_target)
	if r.size.x <= 1.0:
		if not _hidden:
			_hidden = true
			JavaScriptBridge.eval("window.iqSetVisible(false)", true)
		return
	if _hidden:
		_hidden = false
		_shown_rect = Rect2()
		JavaScriptBridge.eval("window.iqSetVisible(true)", true)
	if not r.is_equal_approx(_shown_rect):
		_shown_rect = r
		var vp := _target.get_viewport().get_visible_rect().size
		var le_fs: int = _target.get_theme_font_size("font_size")
		if le_fs <= 0:
			le_fs = UI.fs(16)
		var fs_ratio: float = float(le_fs) / maxf(1.0, vp.y)
		JavaScriptBridge.eval("window.iqMoveInput(%f,%f,%f,%f,%f)" % [
			r.position.x / vp.x, r.position.y / vp.y, r.size.x / vp.x, r.size.y / vp.y, fs_ratio], true)


## The actually visible area of the field; returns empty rect if invisible, not yet laid out, or clipped by scroll container
func _visible_rect(le: LineEdit) -> Rect2:
	if not le.is_visible_in_tree() or le.size.x <= 1.0:
		return Rect2()
	var r := le.get_global_rect()
	# Check visibility using field center point: requiring full containment is too strict (field border at bottom of scroll area often exceeds by 1-2px, causing false hiding)
	var center := r.get_center()
	var p := le.get_parent()
	while p != null:
		if p is ScrollContainer and p is Control:
			if not (p as Control).get_global_rect().has_point(center):
				return Rect2()
		p = p.get_parent()
	return r if le.get_viewport().get_visible_rect().has_point(center) else Rect2()


func _on_focus(c: Control) -> void:
	if c is LineEdit and c.editable:
		_open(c)


func _open(le: LineEdit) -> void:
	_target = le
	_hidden = false
	_shown_rect = le.get_global_rect()
	# Field is freed during screen rebuild; close HTML input here to prevent sending input to non-existent field
	if not le.tree_exiting.is_connected(_on_target_exiting):
		le.tree_exiting.connect(_on_target_exiting.bind(le))
	var vp := le.get_viewport().get_visible_rect().size
	var r := le.get_global_rect()
	var le_fs: int = le.get_theme_font_size("font_size")
	if le_fs <= 0:
		le_fs = UI.fs(16)
	var fs_ratio: float = float(le_fs) / maxf(1.0, vp.y)
	var js := "window.iqOpenInput(%f,%f,%f,%f,%s,%s,%d,%f)" % [
		r.position.x / vp.x, r.position.y / vp.y, r.size.x / vp.x, r.size.y / vp.y,
		JSON.stringify(le.text), JSON.stringify(le.placeholder_text), le.max_length, fs_ratio]
	JavaScriptBridge.eval(js, true)
	# Release Godot focus so subsequent clicks on the same field will trigger again
	le.release_focus.call_deferred()


func _on_js_text(args: Array) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var text := str(args[0])
	# User clicked elsewhere to end input: stop tracking this field
	if args.size() > 2 and bool(args[2]):
		_target.text = text
		_target = null
		return
	if _target.max_length > 0:
		text = text.substr(0, _target.max_length)
	_target.text = text
	_target.text_changed.emit(text)
	if args.size() > 1 and bool(args[1]):
		_target.text_submitted.emit(text)


func _on_target_exiting(le: LineEdit) -> void:
	if _target == le:
		_target = null
		# Screen rebuilds entirely when new state arrives (e.g. actions by other players in multiplayer):
		# after new screen is built, find the same field (matched by placeholder) to take over, preventing typed text loss
		_retarget.call_deferred(le.placeholder_text)


func _retarget(placeholder: String) -> void:
	if _target != null or _retargeting:
		return
	_retargeting = true
	# Screen rebuilds on layout switch (desktop <-> phone): wait a few frames for new field layout, up to ~0.5s
	var found: LineEdit = null
	for _i in 30:
		await get_tree().process_frame
		if placeholder == "":
			break
		for n in get_tree().root.find_children("*", "LineEdit", true, false):
			var le := n as LineEdit
			if le.placeholder_text == placeholder and le.editable and le.is_visible_in_tree() and not le.is_queued_for_deletion() and le.size.x > 1.0:
				found = le
				break
		if found != null:
			break
	_retargeting = false
	if found == null:
		JavaScriptBridge.eval("window.iqCloseInput && window.iqCloseInput()", true)
		return
	_target = found
	if not found.tree_exiting.is_connected(_on_target_exiting):
		found.tree_exiting.connect(_on_target_exiting.bind(found))
	# Scroll position resets after rebuild: scroll field into view and let _process align overlay
	var p := found.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(found)
			break
		p = p.get_parent()
	var val: Variant = JavaScriptBridge.eval("(document.getElementById('iq-input') || {}).value || ''", true)
	found.text = str(val) if val != null else ""
	_shown_rect = Rect2()
	_hidden = true  # Let _process reposition, display, and focus

