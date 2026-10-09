@tool
extends Control
class_name TimelineChart
## Reusable 10-year financial timeline chart.
## Visualizes 10-year net worth trajectories (with advisor plan vs without plan)
## and life stress event impacts across years 0–10.

var timeline_data: Dictionary = {}
var compact: bool = false

const COLOR_PLAN := Color("#3ddc97")       # Accent green
const COLOR_NO_PLAN := Color("#e76f51")    # Muted red
const COLOR_ZERO_LINE := Color("#7a4646")  # Zero debt boundary
const COLOR_DEBT_BG := Color(0.9, 0.2, 0.2, 0.09)
const COLOR_GRID := Color(0.18, 0.35, 0.45, 0.3)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_update_min_size()


func _update_min_size() -> void:
	if compact:
		custom_minimum_size = Vector2(0, 90)
	elif UI.is_phone_portrait():
		custom_minimum_size = Vector2(0, 180)
	else:
		custom_minimum_size = Vector2(0, 220)


func set_data(data: Dictionary, is_compact: bool = false) -> void:
	timeline_data = data
	compact = is_compact
	_update_min_size()
	queue_redraw()


func _draw() -> void:
	if timeline_data.is_empty():
		return

	var years: Array = timeline_data.get("years", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	var no_plan: Array = timeline_data.get("noPlan", [])
	var with_plan: Array = timeline_data.get("withPlan", [])
	var adopted: bool = bool(timeline_data.get("adopted", true))
	var events: Array = timeline_data.get("events", [])

	if no_plan.is_empty():
		return

	var font: Font = get_theme_default_font()
	var font_size: int = 11 if (compact or UI.is_phone_portrait()) else 12

	# 1. Margins and plot area
	var pad_left: float = 8.0 if compact else (52.0 if UI.is_phone_portrait() else 58.0)
	var pad_right: float = 8.0 if compact else 24.0
	var pad_top: float = 8.0 if compact else 26.0
	var pad_bottom: float = 8.0 if compact else 28.0

	var plot_rect := Rect2(pad_left, pad_top, size.x - pad_left - pad_right, size.y - pad_top - pad_bottom)
	if plot_rect.size.x <= 10.0 or plot_rect.size.y <= 10.0:
		return

	# 2. Value bounds across years 0..10
	var min_val: float = 0.0
	var max_val: float = 100000.0  # at least 10萬 range

	for v in no_plan:
		var f := float(v)
		min_val = minf(min_val, f)
		max_val = maxf(max_val, f)

	if adopted:
		for v in with_plan:
			var f := float(v)
			min_val = minf(min_val, f)
			max_val = maxf(max_val, f)

	# Include padding buffer
	var val_span: float = max_val - min_val
	if val_span <= 0.0:
		val_span = 100000.0
	var y_max: float = max_val + val_span * 0.12
	var y_min: float = min_val - (val_span * 0.12 if min_val < 0.0 else 0.0)

	var to_y: Callable = func(val: float) -> float:
		var ratio: float = (val - y_min) / maxf(1.0, y_max - y_min)
		return plot_rect.end.y - ratio * plot_rect.size.y

	var to_x: Callable = func(yr: int) -> float:
		var ratio: float = float(yr) / 10.0
		return plot_rect.position.x + ratio * plot_rect.size.x

	# 3. Debt below zero shaded & zero line
	if y_min < 0.0 and y_max > 0.0:
		var zero_y: float = to_y.call(0.0)
		var debt_h: float = plot_rect.end.y - zero_y
		if debt_h > 0.0:
			draw_rect(Rect2(plot_rect.position.x, zero_y, plot_rect.size.x, debt_h), COLOR_DEBT_BG)
		draw_line(Vector2(plot_rect.position.x, zero_y), Vector2(plot_rect.end.x, zero_y), COLOR_ZERO_LINE, 1.2)

	# 4. Grid lines and Y axis in 萬元 (normal mode only)
	if not compact:
		var y_ticks: Array = [0.0]
		if y_max > 200000.0:
			y_ticks.append(roundf(y_max * 0.5 / 100000.0) * 100000.0)
			y_ticks.append(roundf(y_max * 0.95 / 100000.0) * 100000.0)
		else:
			y_ticks.append(roundf(y_max * 0.8 / 10000.0) * 10000.0)
		if y_min < -50000.0:
			y_ticks.append(roundf(y_min * 0.8 / 100000.0) * 100000.0)

		for t_val in y_ticks:
			var gy: float = to_y.call(t_val)
			if gy >= plot_rect.position.y and gy <= plot_rect.end.y:
				draw_line(Vector2(plot_rect.position.x, gy), Vector2(plot_rect.end.x, gy), COLOR_GRID, 1.0)
				var wan_val: int = int(round(float(t_val) / 10000.0))
				var tick_txt: String = "%d萬" % wan_val
				draw_string(font, Vector2(6, gy + font_size * 0.35), tick_txt, HORIZONTAL_ALIGNMENT_RIGHT, int(pad_left - 10), font_size, UI.MUTED)

		# X axis labels
		for yr in [0, 2, 5, 8, 10]:
			var gx: float = to_x.call(yr)
			var yr_txt: String = "%d年" % yr
			draw_string(font, Vector2(gx - 18, plot_rect.end.y + 18), yr_txt, HORIZONTAL_ALIGNMENT_CENTER, 36, font_size, UI.MUTED)

	# 5. Polylines
	var no_plan_pts := PackedVector2Array()
	var count_pts: int = min(years.size(), no_plan.size())
	for i in range(count_pts):
		var yr: int = int(years[i])
		no_plan_pts.append(Vector2(to_x.call(yr), to_y.call(float(no_plan[i]))))

	if no_plan_pts.size() >= 2:
		draw_polyline(no_plan_pts, COLOR_NO_PLAN, 2.0 if compact else 2.5, true)

	var with_plan_pts := PackedVector2Array()
	if adopted and not with_plan.is_empty():
		var wp_count: int = min(years.size(), with_plan.size())
		for i in range(wp_count):
			var yr: int = int(years[i])
			with_plan_pts.append(Vector2(to_x.call(yr), to_y.call(float(with_plan[i]))))
		if with_plan_pts.size() >= 2:
			draw_polyline(with_plan_pts, COLOR_PLAN, 2.0 if compact else 2.5, true)

	# 6. Event markers
	for ev in events:
		var yr: int = int(ev.get("year", 0))
		if yr >= 0 and yr <= 10:
			var ex: float = to_x.call(yr)
			var ey: float = to_y.call(float(no_plan[yr]) if yr < no_plan.size() else 0.0)
			if adopted and yr < with_plan.size():
				ey = to_y.call(float(with_plan[yr]))
			# Marker circle
			draw_circle(Vector2(ex, ey), 3.5 if compact else 4.5, COLOR_PLAN if adopted else COLOR_NO_PLAN)
			draw_arc(Vector2(ex, ey), 5.5 if compact else 6.5, 0, TAU, 16, Color.WHITE, 1.2)

			if not compact:
				var ev_label: String = str(ev.get("title", ev.get("tag", "事件")))
				if ev_label.length() > 5:
					ev_label = ev_label.substr(0, 4) + "…"
				var lbl_y: float = ey - 10.0 if ey > plot_rect.position.y + 30.0 else ey + 18.0
				draw_string(font, Vector2(ex - 35, lbl_y), ev_label, HORIZONTAL_ALIGNMENT_CENTER, 70, font_size - 1, UI.GOLD)

	# 7. One-line legend & adopted check
	if not compact:
		if not adopted:
			draw_string(font, Vector2(plot_rect.position.x, pad_top - 8), "※ 客戶沒有採納你的建議（維持現況）", HORIZONTAL_ALIGNMENT_LEFT, int(plot_rect.size.x), font_size, UI.MUTED)
		else:
			# Legend: [― 有規劃]  [― 沒有規劃]
			var leg_y: float = pad_top - 8
			var leg_x: float = plot_rect.end.x - 180.0
			draw_line(Vector2(leg_x, leg_y - 4), Vector2(leg_x + 16, leg_y - 4), COLOR_PLAN, 2.5)
			draw_string(font, Vector2(leg_x + 20, leg_y), "有規劃", HORIZONTAL_ALIGNMENT_LEFT, 50, font_size, UI.TEXT)

			var leg_x2: float = leg_x + 85.0
			draw_line(Vector2(leg_x2, leg_y - 4), Vector2(leg_x2 + 16, leg_y - 4), COLOR_NO_PLAN, 2.5)
			draw_string(font, Vector2(leg_x2 + 20, leg_y), "沒有規劃", HORIZONTAL_ALIGNMENT_LEFT, 65, font_size, UI.TEXT)
