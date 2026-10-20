extends HBoxContainer
## MissionProgress: 第 N / M 站 with one dot per station (gold = now, green = done).

var _num: Label
var _of: Label
var _dots: HBoxContainer
var compact := false


func _init(is_compact := false) -> void:
	compact = is_compact
	name = "MissionProgress"
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not compact:
		add_child(QuestUI.label("第", 15, QuestUI.TEXT))
	_num = QuestUI.label("1", 24 if not compact else 17, QuestUI.GOLD, false, true)
	add_child(_num)
	_of = QuestUI.label("/6 站", 15 if not compact else 12, QuestUI.TEXT)
	add_child(_of)
	_dots = QuestUI.hbox(5)
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not compact:
		add_child(_dots)


func refresh() -> void:
	var cur := GameState.current_stage()
	var total := maxi(1, GameState.total_stages())
	# 全部回合結束後後端的回合數會是 總數 + 1：顯示停在最後一站，圓點全部標為完成
	_num.text = str(mini(cur, total))
	_of.text = "/%d 站" % total
	if compact:
		return
	UI.clear(_dots)
	for i in range(total):
		var d := Dot.new()
		d.state = 2 if i + 1 < cur else (1 if i + 1 == cur else 0)
		_dots.add_child(d)


class Dot extends Control:
	var state := 0

	func _init() -> void:
		custom_minimum_size = Vector2(9, 9)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		match state:
			1:
				draw_circle(c, 4.5, QuestUI.GOLD)
			2:
				draw_circle(c, 3.5, QuestUI.GREEN)
			_:
				draw_arc(c, 3.5, 0, TAU, 16, Color(1, 1, 1, 0.45), 1.5, true)
