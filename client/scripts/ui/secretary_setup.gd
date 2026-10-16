extends Control
## Explicit, remembered opt-in. Portraits are the current cover artwork.
signal selected(enabled: bool, role: String)
const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 20
	scroll.offset_right = -20
	scroll.offset_top = 20
	scroll.offset_bottom = -20
	add_child(scroll)
	var content := UI.vbox(14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	content.add_child(UI.label("你的法巴培訓旅程", 26, UI.GOLD, true))
	content.add_child(UI.label("需要語音秘書陪你探索嗎？", 22, UI.TEXT, true))
	content.add_child(UI.label("選擇秘書後，會提供簡短字幕與中文朗讀；也可以自行探索。設定會保留，可在主選單的設定中重新選擇。", 16, UI.MUTED, true))
	var row := UI.hbox(12)
	content.add_child(row)
	for role: String in ["female", "male"]:
		var card := UI.vbox(8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var art := TextureRect.new()
		art.texture = FEMALE if role == "female" else MALE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size.y = 180 if UI.is_phone_landscape() else 250
		card.add_child(art)
		var role_name := "女性" if role == "female" else "男性"
		card.add_child(UI.button("選擇" + role_name + "培訓秘書", func(): selected.emit(true, role), 16, UI.ACCENT))
	content.add_child(UI.button("自行探索 · 不需要語音秘書", func(): selected.emit(false, "female"), 18, UI.PANEL_2))
	content.add_child(UI.label("自行探索時，後續不會出現秘書或語音。若裝置沒有中文語音，啟用秘書後會以字幕導覽。", 14, UI.MUTED, true))
