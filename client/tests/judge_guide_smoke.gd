extends SceneTree
## Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path client --script res://tests/judge_guide_smoke.gd
## 評審導覽進度條（JudgeGuide）測試：
## 1. 直接 new 出 widget，檢查初始 6 個亮點、高亮與打勾狀態
## 2. 測試收合與展開可用
## 3. 模擬狀態與頁面序列（線索 → 提問 → 合規 → 保障 → result 停留 ⑤ 與提示 → 報告 6/6），檢查自動推進、高亮切換與打勾正確
## 4. 檢查非 judge 模式環境下 is_judge() 為 false

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var JudgeGuideClass: GDScript = load("res://scripts/quest/widgets/judge_guide.gd")
	check(JudgeGuideClass != null, "JudgeGuide class loaded")

	var guide: Control = JudgeGuideClass.new()
	root.add_child(guide)
	await process_frame

	# 1. 基本屬性與初始狀態檢查
	check(guide != null, "JudgeGuide instantiated")
	check(guide.name == "JudgeGuide", "Node name is JudgeGuide")
	check(guide.get_current_step() == 0, "Initial current step is 0 (場景找線索)")
	check(not guide.is_collapsed(), "Initially expanded")

	var title_lbl: Label = guide.find_child("JudgeGuideTitle", true, false) as Label
	check(title_lbl != null and title_lbl.text == "評審導覽", "Title label shows '評審導覽'")

	var count_lbl: Label = guide.find_child("JudgeGuideCount", true, false) as Label
	check(count_lbl != null and count_lbl.text == "(0/6)", "Count label shows '(0/6)'")

	var expected_names := [
		"場景找線索",
		"需求提問",
		"合規紅燈與法條",
		"保障配置",
		"十年時間軸",
		"十年後的信",
	]

	for i in range(6):
		check(not guide.is_step_completed(i), "Step %d initially not completed" % i)
		var lbl: Label = guide.find_child("StepLabel_%d" % i, true, false) as Label
		check(lbl != null and lbl.text == expected_names[i], "Step %d label matches '%s'" % [i, expected_names[i]])

	var mark0: Label = guide.find_child("StepMark_0", true, false) as Label
	check(mark0 != null and mark0.text == "▶", "Step 0 mark shows '▶' (highlighted)")

	# 2. 測試收合與展開
	var items_box: Control = guide.find_child("JudgeGuideItems", true, false) as Control
	check(items_box != null and items_box.visible, "Items box visible initially")

	guide.toggle_collapse()
	check(guide.is_collapsed(), "toggle_collapse collapses the guide")
	check(not items_box.visible, "Items box hidden when collapsed")

	guide.toggle_collapse()
	check(not guide.is_collapsed(), "toggle_collapse expands the guide")
	check(items_box.visible, "Items box visible when expanded")

	guide.set_collapsed(true)
	check(guide.is_collapsed(), "set_collapsed(true) works")
	guide.set_collapsed(false)
	check(not guide.is_collapsed(), "set_collapsed(false) works")

	# 3. 模擬狀態與頁面序列推進
	# 3.1 進入 clues 頁面：維持 step 0
	guide.on_page_changed("clues")
	check(guide.get_current_step() == 0, "Still on step 0 for clues")
	check(not guide.is_step_completed(0), "Step 0 still active")

	# 3.2 進入 dialogue 頁面：step 0 完成打勾，step 1 高亮
	guide.on_page_changed("dialogue")
	check(guide.is_step_completed(0), "Step 0 (場景找線索) marked complete")
	check(mark0.text == "✓", "Step 0 mark shows '✓'")
	check(guide.get_current_step() == 1, "Advanced to step 1 (需求提問)")
	var mark1: Label = guide.find_child("StepMark_1", true, false) as Label
	check(mark1 != null and mark1.text == "▶", "Step 1 mark shows '▶'")
	check(not guide.is_step_completed(1), "Step 1 not yet completed")
	check(count_lbl.text == "(1/6)", "Count shows '(1/6)'")

	# 3.3 進入 compliance 頁面：step 0, 1 打勾，step 2 高亮
	guide.on_page_changed("compliance")
	check(guide.is_step_completed(1), "Step 1 (需求提問) marked complete")
	check(mark1.text == "✓", "Step 1 mark shows '✓'")
	check(guide.get_current_step() == 2, "Advanced to step 2 (合規紅燈與法條)")
	var mark2: Label = guide.find_child("StepMark_2", true, false) as Label
	check(mark2 != null and mark2.text == "▶", "Step 2 mark shows '▶'")
	check(not guide.is_step_completed(2), "Step 2 not yet completed")
	check(count_lbl.text == "(2/6)", "Count shows '(2/6)'")

	# 3.4 進入 proposal 頁面：step 0, 1, 2 打勾，step 3 高亮
	guide.on_page_changed("proposal")
	check(guide.is_step_completed(2), "Step 2 marked complete")
	check(guide.get_current_step() == 3, "Advanced to step 3 (保障配置)")
	var mark3: Label = guide.find_child("StepMark_3", true, false) as Label
	check(mark3 != null and mark3.text == "▶", "Step 3 mark shows '▶'")
	check(not guide.is_step_completed(3), "Step 3 not yet completed")
	check(count_lbl.text == "(3/6)", "Count shows '(3/6)'")

	# 3.5 進入 result 頁面：step 0..3 打勾，step 4 (⑤ 十年時間軸) 停留高亮，且顯示提示
	guide.on_page_changed("result")
	check(guide.is_step_completed(0), "Step 0 marked complete")
	check(guide.is_step_completed(1), "Step 1 marked complete")
	check(guide.is_step_completed(2), "Step 2 marked complete")
	check(guide.is_step_completed(3), "Step 3 marked complete")
	check(not guide.is_step_completed(4), "Step 4 (⑤ 十年時間軸) not completed yet")
	check(not guide.is_step_completed(5), "Step 5 (⑥ 十年後的信) not completed yet")
	check(guide.get_current_step() == 4, "Current step is 4 (⑤ 十年時間軸)")
	var mark4: Label = guide.find_child("StepMark_4", true, false) as Label
	check(mark4 != null and mark4.text == "▶", "Step 4 mark shows '▶'")
	check(count_lbl.text == "(4/6)", "Count shows '(4/6)' on result page")
	var hint_lbl: Label = guide.find_child("JudgeGuideHint", true, false) as Label
	check(hint_lbl != null and hint_lbl.visible and hint_lbl.text == "按『生成培訓報告』看十年時間軸與十年後的信", "Hint label shows '按『生成培訓報告』看十年時間軸與十年後的信' and is visible")

	# 3.6 進入培訓報告畫面：set_current_step(6) 使 6 個步驟全部完成 (6/6)
	guide.set_current_step(6)
	for i in range(6):
		check(guide.is_step_completed(i), "Step %d is completed after set_current_step(6)" % i)
		var m: Label = guide.find_child("StepMark_%d" % i, true, false) as Label
		check(m != null and m.text == "✓", "Step %d mark shows '✓'" % i)
	check(count_lbl.text == "(6/6)", "Count shows '(6/6)'")
	check(hint_lbl != null and not hint_lbl.visible, "Hint label is hidden after set_current_step(6)")

	# 4. 驗證非 judge 模式環境下 is_judge() 為 false
	var AutomationBridgeClass: GDScript = load("res://scripts/automation.gd")
	check(not AutomationBridgeClass.is_judge(), "AutomationBridge.is_judge() is false in non-web / headless environment")

	guide.queue_free()
	await process_frame

	if failures == 0:
		print("judge_guide_smoke: OK")
		quit(0)
	else:
		printerr("judge_guide_smoke: %d failure(s)" % failures)
		quit(1)
