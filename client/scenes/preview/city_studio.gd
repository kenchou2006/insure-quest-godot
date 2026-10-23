@tool
extends Control
## F6 architectural sandbox. Construction is local and never changes a game room.
const Board := preload("res://scripts/ui/board_3d.gd")
func _ready() -> void:
	theme = UI.make_theme()
	var background := ColorRect.new()
	background.color = UI.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var board := Board.new()
	board.construction_enabled = true
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/preview/states.json"))
	board.set_data(data.get("static", {}).get("board", []), [], "")
	var note := Label.new()
	note.text = "城市建模工作室\n\n環形道路與 24 個任務節點\n中央弧形玻璃顧問中心\n商辦 / 醫院 / 幼兒園\n會館 / 住宅 / 建築工地\n\n操作\n滾輪：縮放\n中鍵拖曳：平移\n右鍵拖曳：旋轉\n邊移：切換邊緣平移\n復位：回到初始視角\n\n放置建築\n點選綠色空地可放置\n紅色表示占用或超出範圍\n旋轉：轉向 90 度\n\n此處配置僅供本次預覽"
	note.position = Vector2(20, 60)
	note.add_theme_font_size_override("font_size", 15)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(note)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await get_tree().create_timer(4).timeout
			get_viewport().get_texture().get_image().save_png(arg.substr(10))
			get_tree().quit()
