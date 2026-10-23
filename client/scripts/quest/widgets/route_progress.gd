extends Control
## RouteProgress：右側「目前任務」裡的主線路線進度。以目前位置為中心列出 8 個站：已完成打勾、
## 目前位置金圈放大、下一站綠圈、超出一次擲骰範圍的站上鎖；站與站之間的線，走過的部分是綠色。
## 只讀 GameState（後端位置與本局走過的站），不攔截滑鼠。

const C_GREEN := Color("#00A86B")
const C_GOLD := Color("#C6A15B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const COUNT := 8


func _init() -> void:
	name = "RouteProgress"
	custom_minimum_size = Vector2(0, 54)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 顯示的站號（目前位置往前 4 站、往後 3 站）
func stations() -> Array:
	if Engine.is_editor_hint() or GameState.board().size() != 24:
		return range(COUNT)
	var cur := GameState.current_node()
	var out: Array = []
	for k in range(-4, COUNT - 4):
		out.append(posmod(cur + k, 24))
	return out


func _draw() -> void:
	var ids := stations()
	if ids.is_empty():
		return
	var font := get_theme_default_font()
	var cur := -1 if Engine.is_editor_hint() else GameState.current_node()
	var next := -1 if Engine.is_editor_hint() else GameState.next_node()
	var done: Array = [] if Engine.is_editor_hint() else GameState.completed_nodes()
	var locked: Array = [] if Engine.is_editor_hint() else GameState.locked_nodes()
	var step := size.x / float(ids.size())
	var y := 16.0
	var cur_k := ids.find(cur)
	for k in range(ids.size() - 1):
		var a := Vector2(step * (k + 0.5), y)
		var b := Vector2(step * (k + 1.5), y)
		var walked := cur_k >= 0 and k < cur_k
		if walked:
			draw_line(a, b, C_GREEN, 3.0, true)
		else:
			# 虛線：還沒走到的路
			var d := 0.0
			var length := a.distance_to(b)
			while d < length:
				draw_line(a.lerp(b, d / length), a.lerp(b, minf(d + 4.0, length) / length), Color(C_MUTED, 0.6), 1.5, true)
				d += 8.0
	for k in range(ids.size()):
		var i: int = ids[k]
		var c := Vector2(step * (k + 0.5), y)
		var is_cur := i == cur
		var r := 11.0 * (1.08 if is_cur else 1.0)
		if is_cur:
			draw_circle(c, r + 3.0, Color(C_GOLD, 0.25))
			draw_circle(c, r, Color("#0D4038"))
			draw_arc(c, r, 0, TAU, 28, C_GOLD, 2.5, true)
			draw_circle(c, 4.0, C_GOLD)
		elif done.has(i):
			draw_circle(c, r, Color(C_GREEN, 0.85))
			draw_polyline(PackedVector2Array([c + Vector2(-4.5, 0), c + Vector2(-1.2, 3.4), c + Vector2(5, -3.5)]), C_TEXT, 2.0, true)
		elif locked.has(i):
			draw_circle(c, r, Color(1, 1, 1, 0.08))
			draw_arc(c, r, 0, TAU, 24, Color(C_MUTED, 0.5), 1.0, true)
			draw_rect(Rect2(c + Vector2(-4, -1), Vector2(8, 6)), Color(C_MUTED, 0.8), false, 1.2)
			draw_arc(c + Vector2(0, -1), 2.8, PI, TAU, 8, Color(C_MUTED, 0.8), 1.2, true)
		else:
			draw_circle(c, r, Color("#0D4038"))
			draw_arc(c, r, 0, TAU, 24, Color(C_GREEN if i == next else C_MUTED, 0.9), 1.5, true)
		var label := "%02d" % i
		var fs := 12
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - tw * 0.5, y + 34.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_GOLD if is_cur else (C_TEXT if not locked.has(i) else C_MUTED))
