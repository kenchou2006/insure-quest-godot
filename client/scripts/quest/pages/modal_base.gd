extends "res://scripts/quest/pages/page_base.gd"
## Modal mission page over the map: the map dims (it stays visible behind), the card rises from
## below with a fade. The card scrolls on short screens so its buttons are always reachable.

var dim: ColorRect
var card: PanelContainer
var card_body: VBoxContainer
## Pinned under the scrolling body: the modal's main buttons are always on screen
var card_footer: VBoxContainer
var _scroll: ScrollContainer
var max_card_width := 860.0


func _init() -> void:
	super()
	modal = true


## Dim + centred card; returns the card's content box
func add_card(border := Color(QuestUI.GOLD, 0.55)) -> VBoxContainer:
	dim = ColorRect.new()
	dim.name = "MapDim"
	dim.color = Color(QuestUI.INK, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	card = PanelContainer.new()
	card.name = "ModalCard"
	var sb := QuestUI.card_box(0.97, border, 16, 14 if phone() else 24)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	var outer := QuestUI.vbox(10)
	card.add_child(outer)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	card_body = QuestUI.vbox(10 if phone() else 14)
	card_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(card_body)
	card_footer = QuestUI.vbox(6)
	outer.add_child(card_footer)
	resized.connect(_place_card)
	# Wrapped text re-measures once it has its width: place the card again whenever content changes
	card_body.minimum_size_changed.connect(_queue_place)
	card_footer.minimum_size_changed.connect(_queue_place)
	return card_body


var _place_queued := false


func _queue_place() -> void:
	if _place_queued:
		return
	_place_queued = true
	_do_queued_place.call_deferred()


func _do_queued_place() -> void:
	_place_queued = false
	if is_instance_valid(card):
		_place_card()


func _place_card() -> void:
	if card == null:
		return
	var vs := size
	var margin := 8.0 if phone() else 24.0
	var w := minf(max_card_width, vs.x - margin * 2)
	card_body.custom_minimum_size.x = w - (28 if phone() else 48)
	var sb := card.get_theme_stylebox("panel")
	var pad := (sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)) if sb else (28.0 if phone() else 40.0)
	var foot := card_footer.get_combined_minimum_size().y + (10.0 if card_footer.get_child_count() > 0 else 0.0)
	var body_h := card_body.get_combined_minimum_size().y
	var want := body_h + foot + pad
	var h := minf(want, vs.y - margin * 2)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if want > h + 1 else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, maxf(40.0, h - pad - foot))
	card.size = Vector2(w, h)
	# Never taller than the screen: if the minimum still wins, the card is clamped to the screen
	h = minf(card.size.y, vs.y - margin * 2)
	card.size.y = h
	card.position = Vector2((vs.x - w) * 0.5, maxf(margin, (vs.y - card.size.y) * 0.5))


## Map darkens, card fades in and rises 24 px
func enter() -> void:
	_place_card()
	await get_tree().process_frame
	_place_card()
	if QuestUI.motion_off():
		dim.color.a = 0.5
		card.modulate.a = 1.0
		return
	var final_y := card.position.y
	card.position.y = final_y + 24.0
	card.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim, "color:a", 0.5, 0.3)
	tw.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(0.06)
	tw.tween_property(card, "position:y", final_y, 0.34).set_delay(0.06)


func relayout() -> void:
	await get_tree().process_frame
	_place_card()
