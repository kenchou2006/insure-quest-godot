extends Node
## 網頁版中文輸入（Autoload "WebText"）。
## Godot 網頁畫布收不到輸入法（IME）組字後送出的文字，因此在網頁版：
## 任何 LineEdit 取得焦點時，在它正上方覆蓋一個真正的 HTML <input>，
## 輸入內容即時同步回 LineEdit，按 Enter 時觸發 LineEdit 的 text_submitted。

const JS_SETUP := """
(function () {
  if (window.iqOpenInput) return;
  window.iqOpenInput = function (x, y, w, h, val, ph, maxLen) {
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
        el.style.display = 'none';
        canvas.focus();
      });
      document.body.appendChild(el);
    }
    el.style.left = (c.left + x * c.width) + 'px';
    el.style.top = (c.top + y * c.height) + 'px';
    el.style.width = (w * c.width) + 'px';
    el.style.height = (h * c.height) + 'px';
    el.style.fontSize = Math.max(14, h * c.height * 0.42) + 'px';
    el.maxLength = maxLen > 0 ? maxLen : 524288;
    el.value = val;
    el.placeholder = ph;
    el.style.display = 'block';
    setTimeout(function () { el.focus(); el.select(); }, 0);
  };
  window.iqCloseInput = function () {
    var el = document.getElementById('iq-input');
    if (el) { el.style.display = 'none'; el.blur(); }
  };
})();
"""

var _callback: JavaScriptObject = null
var _target: LineEdit = null


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(JS_SETUP, true)
	_callback = JavaScriptBridge.create_callback(_on_js_text)
	JavaScriptBridge.get_interface("window").iqTextCallback = _callback
	get_viewport().gui_focus_changed.connect(_on_focus)


func _on_focus(c: Control) -> void:
	if c is LineEdit and c.editable:
		_open(c)


func _open(le: LineEdit) -> void:
	_target = le
	# 畫面重建時欄位會被釋放；這時關閉 HTML 輸入框，避免輸入送到已不存在的欄位
	if not le.tree_exiting.is_connected(_on_target_exiting):
		le.tree_exiting.connect(_on_target_exiting.bind(le))
	var vp := le.get_viewport().get_visible_rect().size
	var r := le.get_global_rect()
	var js := "window.iqOpenInput(%f,%f,%f,%f,%s,%s,%d)" % [
		r.position.x / vp.x, r.position.y / vp.y, r.size.x / vp.x, r.size.y / vp.y,
		JSON.stringify(le.text), JSON.stringify(le.placeholder_text), le.max_length]
	JavaScriptBridge.eval(js, true)
	# 交出 Godot 焦點，下次點擊同一欄位才會再次觸發
	le.release_focus.call_deferred()


func _on_js_text(args: Array) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var text := str(args[0])
	if _target.max_length > 0:
		text = text.substr(0, _target.max_length)
	_target.text = text
	_target.text_changed.emit(text)
	if args.size() > 1 and bool(args[1]):
		_target.text_submitted.emit(text)


func _on_target_exiting(le: LineEdit) -> void:
	if _target == le:
		_target = null
		JavaScriptBridge.eval("window.iqCloseInput && window.iqCloseInput()", true)
