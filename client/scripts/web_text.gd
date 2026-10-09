@tool
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
        // 程式暫時隱藏（欄位捲出畫面、切換分頁）時不算結束輸入
        if (el._iqHiding) return;
        // Godot 開關輸入法（set_ime_active）時會呼叫 canvas.focus()，若晚於我們聚焦就會搶走焦點：
        // 剛開啟的短時間內被搶走就搶回來；整個視窗失焦（切到別的程式）也不算結束輸入
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
    el.style.fontSize = Math.max(14, h * c.height * 0.42) + 'px';
    el.maxLength = maxLen > 0 ? maxLen : 524288;
    el.value = val;
    el.placeholder = ph;
    el.style.display = 'block';
    el._iqOpenedAt = performance.now();
    // 稍微延後聚焦，避開 Godot 交出焦點時對 canvas 的 focus()
    setTimeout(function () { el.focus(); el.select(); }, 60);
    // 頁面剛載入時 Godot 搶焦點的時間點較晚：前 0.6 秒內被搶走就搶回來（不再全選，避免蓋掉已輸入的字）
    [200, 350, 500, 650].forEach(function (ms) {
      setTimeout(function () { if (el.style.display !== 'none' && document.activeElement !== el) el.focus(); }, ms);
    });
  };
  // 畫面重建後換到新的欄位：只移動位置，保留使用者已輸入的文字與焦點
  window.iqMoveInput = function (x, y, w, h) {
    var canvas = document.getElementById('canvas');
    var c = canvas.getBoundingClientRect();
    var el = document.getElementById('iq-input');
    if (!el) return '';
    el.style.left = (c.left + x * c.width) + 'px';
    el.style.top = (c.top + y * c.height) + 'px';
    el.style.width = (w * c.width) + 'px';
    el.style.height = (h * c.height) + 'px';
    return el.value;
  };
  // 暫時隱藏／恢復：保留文字與目標欄位
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
## 覆蓋框目前的位置（每格比對，欄位移動、捲動或視窗縮放時跟著移動）
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
	# 欄位不在畫面上（切到其他分頁、被捲出可視範圍）時暫時隱藏覆蓋框，回來時恢復
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
		JavaScriptBridge.eval("window.iqMoveInput(%f,%f,%f,%f)" % [
			r.position.x / vp.x, r.position.y / vp.y, r.size.x / vp.x, r.size.y / vp.y], true)


## 欄位實際可見的區域；不可見、尚未排版或被捲動容器裁掉時回傳空矩形
func _visible_rect(le: LineEdit) -> Rect2:
	if not le.is_visible_in_tree() or le.size.x <= 1.0:
		return Rect2()
	var r := le.get_global_rect()
	# 以欄位中心點判斷是否可見：要求完整包含太嚴格（欄位在捲動區底部時邊框常超出 1–2 像素，會被誤判而隱藏輸入框）
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
	# 使用者點到別處結束輸入：之後不再追蹤這個欄位
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
		# 畫面收到新狀態時會整個重建（例如多人連線時其他玩家有動作）：
		# 等新畫面建好後，找同一個欄位（以提示文字比對）接手，避免打到一半的字消失
		_retarget.call_deferred(le.placeholder_text)


func _retarget(placeholder: String) -> void:
	if _target != null or _retargeting:
		return
	_retargeting = true
	# 版面切換（桌面↔手機）時整個畫面重建：新欄位要等幾格才排好版，最多等約半秒
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
	# 重建後捲動位置會歸零：把欄位捲進畫面，覆蓋框由 _process 跟上
	var p := found.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(found)
			break
		p = p.get_parent()
	var val: Variant = JavaScriptBridge.eval("(document.getElementById('iq-input') || {}).value || ''", true)
	found.text = str(val) if val != null else ""
	_shown_rect = Rect2()
	_hidden = true  # 讓 _process 重新定位並顯示、聚焦

