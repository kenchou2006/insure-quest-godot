class_name DemoCodeDialog
## Dialog for entering reviewer / evaluation demo code.

static func open(host: Node, on_success: Callable = Callable()) -> void:
	if not host or not is_instance_valid(host):
		return
	for c in host.get_children():
		if c.name == "DemoCodeDialog":
			return
	var dim := ColorRect.new()
	dim.name = "DemoCodeDialog"
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var p := UI.panel(UI.PANEL, 14, 18)
	var max_w: float = 340.0 if UI.is_phone_portrait() else 420.0
	p.custom_minimum_size = Vector2(max_w, 0)
	var v := UI.vbox(10)
	p.add_child(v)

	var head := UI.hbox(8)
	head.add_child(UI.label("輸入評審體驗碼", 18, UI.ACCENT_2))
	head.add_child(UI.spacer())
	var close_btn := UI.button("×", func(): dim.queue_free(), 16, UI.PANEL_2)
	close_btn.custom_minimum_size = Vector2(36, 36)
	head.add_child(close_btn)
	v.add_child(head)

	v.add_child(UI.label("輸入評審體驗碼即可啟用完整 AI 功能。", 13, UI.MUTED, true))

	var err_lbl := UI.label("", 13, UI.BAD, true)
	err_lbl.visible = false
	v.add_child(err_lbl)

	var submitting := false
	var on_submit := func(code_text: String):
		if submitting:
			return
		submitting = true
		err_lbl.visible = false
		var res: Array = await Net.submit_demo_code(code_text)
		submitting = false
		if not is_instance_valid(dim):
			return
		if bool(res[0]):
			dim.queue_free()
			if on_success.is_valid():
				on_success.call()
		else:
			err_lbl.text = str(res[1])
			err_lbl.visible = true

	var input_row := UI.text_input("輸入體驗碼（如 CARDIF-DEMO-2026）", on_submit, 40)
	var submit_btn = input_row.get_child(1) as Button
	if submit_btn:
		submit_btn.text = "進入"
	v.add_child(input_row)

	center.add_child(p)
	host.add_child(dim)
