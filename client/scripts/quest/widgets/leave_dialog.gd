extends Control
## 離開培訓 once the board game has started: 要離開本次培訓嗎？
##   繼續培訓 — close, nothing changes
##   儲存並返回主畫面 — leave without abandoning (training record kept; a multiplayer seat can
##                      be resumed from the hall while the room lasts)
##   放棄本次培訓 — give this training up (the previous 離開 behaviour)

var main: Node


func _init(main_node: Node = null) -> void:
	main = main_node
	name = "LeaveDialog"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 130


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(QuestUI.INK, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := QuestUI.card(null, 1.0, Color(QuestUI.GOLD, 0.55))
	card.custom_minimum_size = Vector2(minf(480.0, get_viewport_rect().size.x - 32.0), 0)
	center.add_child(card)
	var v := QuestUI.vbox(14)
	card.add_child(v)
	var head := QuestUI.hbox(10)
	head.add_child(QuestUI.icon("door", 26.0, QuestUI.GOLD))
	head.add_child(QuestUI.title("要離開本次培訓嗎？", 24 if not UI.is_phone() else 19))
	v.add_child(head)
	# Only a multiplayer seat can be resumed (solo rooms never keep one)
	var keep_note := "培訓紀錄會保存；房間還在時，可以從培訓大廳回到這一局。"
	if Net.is_local():
		keep_note = "培訓紀錄會保存在這台裝置；本機練習離開後無法接著玩。"
	elif Net.is_solo:
		keep_note = "已完成的會談會保存在培訓紀錄；單人實戰離開後無法從中途接著玩。"
	v.add_child(QuestUI.label(keep_note, 14, QuestUI.MUTED, true))
	var stay: Button = QuestUI.button("繼續培訓", close, "primary", "play")
	stay.name = "StayInTraining"
	v.add_child(stay)
	var keep: Button = QuestUI.button("儲存並返回主畫面", func(): _leave(true), "secondary", "house")
	keep.name = "SaveAndLeave"
	v.add_child(keep)
	var quit: Button = QuestUI.button("放棄本次培訓", func(): _leave(false), "danger", "close")
	quit.name = "AbandonTraining"
	v.add_child(quit)
	v.add_child(QuestUI.label("放棄後，這一局不會再繼續，成績不列入培訓證書。", 12, QuestUI.MUTED, true))
	GameState.hold("leave_dialog", true)
	QuestUI.fade_in(card, 0.0, 0.2, 0.0)
	stay.grab_focus.call_deferred()


func close() -> void:
	GameState.hold("leave_dialog", false)
	queue_free()


func _leave(keep: bool) -> void:
	GameState.hold("leave_dialog", false)
	var m := main
	queue_free()
	if m and m.has_method("leave_training"):
		m.leave_training(keep)
