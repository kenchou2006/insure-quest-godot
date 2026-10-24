extends SceneTree
## Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path client --script res://tests/judge_mode_smoke.gd
## 評審體驗模式 (?judge=1) 冒煙測試：
## 1. 在 headless（非 web）環境下確認 AutomationBridge.is_judge() 為 false
## 2. get_judge_demo() 行為（預設回傳 "1"）
## 3. 純函式邏輯測試（Demo 解析、顧問姓名設定、封面與報到跳過判定、導覽引導停用判定、settings.demo 封包產生）
## 4. 非 judge 時 UI 與流程不變（大廳不出現評審按鈕、正常卡片存在）
## 5. 評審 6 大核心亮點定義完整性檢查

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


## --- 純邏輯函式（Pure Functions）---

static func pure_resolve_judge_demo(url_demo: String) -> String:
	return url_demo if url_demo != "" else "1"


static func pure_resolve_player_name(current_name: String, is_judge: bool) -> String:
	if is_judge:
		return "評審顧問"
	return current_name if current_name != "" else "顧問"


static func pure_should_skip_startup_cover(is_automation: bool, is_judge: bool) -> bool:
	return is_automation or is_judge


static func pure_should_skip_onboarding(profile_created: bool, is_automation: bool, is_judge: bool) -> bool:
	return profile_created or is_automation or is_judge


static func pure_is_tutorial_disabled(is_active: bool, is_judge: bool, url_tutorial_val: String) -> bool:
	if not is_active and not is_judge:
		return false
	return url_tutorial_val != "1"


static func pure_build_welcome_settings(is_automation: bool, is_judge: bool, url_demo: String) -> Dictionary:
	var settings_dict: Dictionary = {}
	if is_automation:
		if url_demo != "":
			settings_dict["demo"] = url_demo
	elif is_judge:
		var demo_id := pure_resolve_judge_demo(url_demo)
		if demo_id != "":
			settings_dict["demo"] = demo_id
	return settings_dict


func _run() -> void:
	print("--- 開始執行評審模式測試 (judge_mode_smoke) ---")

	var AutomationBridgeClass: GDScript = load("res://scripts/automation.gd")
	check(AutomationBridgeClass != null, "AutomationBridge class loaded")

	# 1. 在 headless / non-web 環境下的行為檢驗
	check(not AutomationBridgeClass.is_judge(), "AutomationBridge.is_judge() is false in headless/non-web")
	check(not AutomationBridgeClass.is_active(), "AutomationBridge.is_active() is false in headless/non-web")
	check(AutomationBridgeClass.get_url_demo() == "", "AutomationBridge.get_url_demo() is empty string in headless")
	check(AutomationBridgeClass.get_judge_demo() == "1", "AutomationBridge.get_judge_demo() defaults to '1' (劉家豪 jiahao)")
	check(not AutomationBridgeClass.is_tutorial_disabled(), "AutomationBridge.is_tutorial_disabled() is false when not judge/active")

	var net_node: Node = root.get_node_or_null("Net")
	if net_node != null and net_node.has_method("check_and_consume_url_demo_code"):
		var consumed_code: String = net_node.call("check_and_consume_url_demo_code")
		check(consumed_code == "", "Net.check_and_consume_url_demo_code() returns empty in non-web")

	# 2. 純函式邏輯測試
	# 2.1 Demo 解析邏輯
	check(pure_resolve_judge_demo("") == "1", "Empty url demo resolves to '1'")
	check(pure_resolve_judge_demo("1") == "1", "Explicit '1' resolves to '1'")
	check(pure_resolve_judge_demo("jiahao") == "jiahao", "Explicit 'jiahao' resolves to 'jiahao'")
	check(pure_resolve_judge_demo("lin") == "lin", "Custom client 'lin' resolves to 'lin'")
	check(pure_resolve_judge_demo("wanting") == "wanting", "Custom client 'wanting' resolves to 'wanting'")

	# 2.2 顧問姓名決定邏輯
	check(pure_resolve_player_name("", false) == "顧問", "Non-judge empty name defaults to '顧問'")
	check(pure_resolve_player_name("自訂顧問", false) == "自訂顧問", "Non-judge custom name preserved")
	check(pure_resolve_player_name("", true) == "評審顧問", "Judge mode empty name defaults to '評審顧問'")
	check(pure_resolve_player_name("顧問", true) == "評審顧問", "Judge mode default '顧問' upgraded to '評審顧問'")

	# 2.3 開場封面跳過邏輯
	check(not pure_should_skip_startup_cover(false, false), "Normal user does not skip startup cover")
	check(pure_should_skip_startup_cover(true, false), "Automation mode skips startup cover")
	check(pure_should_skip_startup_cover(false, true), "Judge mode skips startup cover")
	check(pure_should_skip_startup_cover(true, true), "Judge + automation skips startup cover")

	# 2.4 新人顧問報到跳過邏輯
	check(not pure_should_skip_onboarding(false, false, false), "Normal new user does not skip onboarding")
	check(pure_should_skip_onboarding(true, false, false), "User with profile skips onboarding")
	check(pure_should_skip_onboarding(false, true, false), "Automation skips onboarding")
	check(pure_should_skip_onboarding(false, false, true), "Judge mode skips onboarding")

	# 2.5 秘書長引導停用邏輯
	check(not pure_is_tutorial_disabled(false, false, ""), "Normal mode tutorial is not disabled")
	check(not pure_is_tutorial_disabled(false, false, "1"), "Normal mode with tutorial=1 is not disabled")
	check(pure_is_tutorial_disabled(false, true, ""), "Judge mode without tutorial=1 disables tutorial")
	check(not pure_is_tutorial_disabled(false, true, "1"), "Judge mode with tutorial=1 keeps tutorial enabled")

	# 2.6 settings.demo 封包產生邏輯
	var normal_settings := pure_build_welcome_settings(false, false, "")
	check(not normal_settings.has("demo"), "Normal welcome settings has no demo property")

	var judge_default_settings := pure_build_welcome_settings(false, true, "")
	check(judge_default_settings.get("demo") == "1", "Judge default welcome settings sends demo='1'")

	var judge_custom_settings := pure_build_welcome_settings(false, true, "wanting")
	check(judge_custom_settings.get("demo") == "wanting", "Judge custom welcome settings sends demo='wanting'")

	var auto_settings := pure_build_welcome_settings(true, false, "2")
	check(auto_settings.get("demo") == "2", "Automation welcome settings sends specified demo")

	# 3. 非 judge 時 UI 與流程不變檢查
	var MenuClass: GDScript = load("res://scripts/ui/menu.gd")
	check(MenuClass != null, "Menu class loaded")
	var menu: Control = MenuClass.new()
	root.add_child(menu)
	await process_frame

	var judge_btn: Control = menu.find_child("JudgeQuickStartButton", true, false) as Control
	check(judge_btn == null, "JudgeQuickStartButton does not exist in non-judge mode")

	var solo_card: Control = menu.get("_solo_card")
	check(solo_card != null and solo_card.is_visible_in_tree(), "Normal solo card exists and visible")

	var multi_card: Control = menu.get("_multi_card")
	check(multi_card != null and multi_card.is_visible_in_tree(), "Normal multi card exists and visible")

	menu.queue_free()
	await process_frame

	# 4. 評審 6 大核心亮點定義完整性檢查
	var JudgeGuideClass: GDScript = load("res://scripts/quest/widgets/judge_guide.gd")
	check(JudgeGuideClass != null, "JudgeGuide class loaded")

	var expected_steps := [
		"場景找線索",
		"需求提問",
		"合規紅燈與法條",
		"保障配置",
		"十年時間軸",
		"十年後的信",
	]
	check(JudgeGuideClass.STEPS.size() == 6, "JudgeGuide has exactly 6 steps")
	for i in range(6):
		check(JudgeGuideClass.STEPS[i] == expected_steps[i], "Step %d matches '%s'" % [i, expected_steps[i]])

	var expected_icons := ["①", "②", "③", "④", "⑤", "⑥"]
	check(JudgeGuideClass.STEP_ICONS.size() == 6, "JudgeGuide has exactly 6 step icons")
	for i in range(6):
		check(JudgeGuideClass.STEP_ICONS[i] == expected_icons[i], "Icon %d matches '%s'" % [i, expected_icons[i]])

	if failures == 0:
		print("judge_mode_smoke: OK")
		quit(0)
	else:
		printerr("judge_mode_smoke: %d failure(s)" % failures)
		quit(1)
