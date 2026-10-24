extends SceneTree
## Run: godot --headless --path client --script res://tests/report_timeline_smoke.gd
## Verifies that TrainingReportView correctly embeds the 10-year financial timeline card
## (TimelineChart, switcher, worst-year metrics, and letter excerpt) when timelines exist,
## and correctly omits the card when no timeline exists.

var failures := 0
var host: Control


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	printerr("FAIL: watchdog — report_timeline_smoke stalled")
	quit(1)


func _mock_client() -> Dictionary:
	return {
		"id": "yuqing",
		"name": "林雨晴",
		"short": "雨晴",
		"age": 29,
		"gender": "女",
		"job": "自由接案插畫家",
		"tag": "收入波動型",
		"difficulty": "入門",
	}


func _mock_timeline(c_name: String, adopted: bool, worst_with: int, worst_no: int, prem: int) -> Dictionary:
	return {
		"clientName": c_name,
		"years": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
		"withPlan": [500000, 520000, 540000, worst_with, 600000, 650000, 700000, 750000, 800000, 850000, 900000],
		"noPlan": [500000, 480000, worst_no, 300000, 320000, 350000, 370000, 400000, 420000, 440000, 460000],
		"adopted": adopted,
		"events": [
			{"year": 2, "title": "突發疾病醫療支出", "tag": "醫療", "loss": 300000, "covered": 250000, "outOfPocket": 50000, "noPlanOutOfPocket": 300000}
		],
		"worstWith": worst_with,
		"worstNo": worst_no,
		"premiumTotal": prem,
	}


func _state_with_timelines() -> Dictionary:
	var tm1 := _mock_timeline("林雨晴", true, 540000, -200000, 360000)
	var tm2 := _mock_timeline("周柏霆", true, 800000, 150000, 480000)
	return {
		"phase": "ended",
		"round": 3,
		"final": [
			{
				"playerId": "p1",
				"name": "測試顧問",
				"isBot": false,
				"score": 85,
				"grade": "A",
				"caps": [],
				"skill": {"insight": 80, "fit": 75, "compliance": 90},
				"service": 80,
				"protection": 85,
				"reputation": 20,
				"commission": 50,
				"clients": 2,
				"coach": "這局整體規劃周全，保障卡配置得宜。",
				"timeline": tm2,
				"timelines": [tm1, tm2],
				"letters": [
					{
						"clientId": "yuqing",
						"clientName": "林雨晴",
						"outcome": "thanks",
						"content": "謝謝顧問十年前為我們全家做的財務規劃，讓我們在生病時不用擔心收入中斷，全家平安度過難關。"
					},
					{
						"clientId": "boting",
						"clientName": "周柏霆",
						"outcome": "mixed",
						"content": "雖然每年繳保費是一筆負擔，但有了保障確實讓家人安心不少。"
					}
				]
			}
		],
		"caseOptions": [_mock_client()]
	}


func _state_without_timelines() -> Dictionary:
	return {
		"phase": "ended",
		"round": 3,
		"final": [
			{
				"playerId": "p1",
				"name": "測試顧問",
				"isBot": false,
				"score": 70,
				"grade": "B",
				"caps": [],
				"skill": {"insight": 60, "fit": 60, "compliance": 70},
				"service": 60,
				"protection": 50,
				"reputation": 10,
				"commission": 20,
				"clients": 0,
				"coach": "持續練習。",
				"timeline": null,
				"timelines": [],
				"letters": []
			}
		],
		"caseOptions": [_mock_client()]
	}


func _state_unadopted() -> Dictionary:
	var tm := _mock_timeline("林雨晴", false, -300000, -300000, 0)
	return {
		"phase": "ended",
		"round": 3,
		"final": [
			{
				"playerId": "p1",
				"name": "測試顧問",
				"isBot": false,
				"score": 55,
				"grade": "C",
				"caps": [],
				"skill": {"insight": 50, "fit": 40, "compliance": 60},
				"service": 40,
				"protection": 30,
				"reputation": 5,
				"commission": 0,
				"clients": 1,
				"coach": "需要更精準掌握客戶需求。",
				"timeline": tm,
				"timelines": [tm],
				"letters": [
					{
						"clientId": "yuqing",
						"clientName": "林雨晴",
						"outcome": "regret",
						"content": "當初要是聽從顧問的建議買了保險，現在就不會為了醫療費用負債了……"
					}
				]
			}
		],
		"caseOptions": [_mock_client()]
	}


func _run() -> void:
	_watchdog()

	# Await process_frame so Autoloads (Net, GameState, PlayerProfile, etc.) are fully initialized in the SceneTree
	await process_frame

	var net: Node = root.get_node("Net")
	var gs: Node = root.get_node("GameState")
	var pp: Node = root.get_node("PlayerProfile")

	var TrainingReportViewClass: GDScript = load("res://scripts/quest/pages/training_report_view.gd")
	var TimelineChartClass: GDScript = load("res://scripts/ui/timeline_chart.gd")

	gs.call("reset_for_tests")
	gs.set("classic_ui", false)
	pp.call("reset_for_tests")
	pp.call("create", "測試顧問", "player_04", "blue")
	net.set("player_id", "p1")
	net.set("room_code", "QTEST_REPORT")

	host = Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	await process_frame

	var dummy_main := Node.new()

	# --- 1. Test state WITH timelines and letters ---
	var s1 := _state_with_timelines()
	var v1: Control = TrainingReportViewClass.new()
	v1.set("main", dummy_main)
	host.add_child(v1)
	v1.call("refresh", s1)
	await process_frame

	check(v1.find_child("DecisionsCard", true, false) != null, "DecisionsCard renamed and present")
	var ftc1: Node = v1.find_child("FinanceTimelineCard", true, false)
	check(ftc1 != null, "FinanceTimelineCard present when timelines exist")
	var tc1: Node = v1.find_child("TimelineChart", true, false)
	check(tc1 != null, "TimelineChart node exists inside FinanceTimelineCard")
	check(tc1 != null and tc1.get_script() == TimelineChartClass, "TimelineChart script matches TimelineChartClass")

	# Assertion (a): Refreshing with identical state must preserve TimelineChart instance (not rebuilt)
	v1.call("refresh", s1)
	await process_frame
	var tc1_after: Node = v1.find_child("TimelineChart", true, false)
	check(tc1_after == tc1, "TimelineChart node instance preserved across refresh with unchanged state")

	var switcher: Node = v1.find_child("TimelineSwitcher", true, false)
	check(switcher != null, "TimelineSwitcher present when multiple clients exist")

	var worst_lbl1: Label = v1.find_child("WorstYearLabel", true, false) as Label
	check(worst_lbl1 != null, "WorstYearLabel exists")
	if worst_lbl1:
		check(worst_lbl1.text.contains("最糟一年：有規劃") and worst_lbl1.text.contains("vs 沒規劃"), "WorstYearLabel displays with vs without plan metrics (%s)" % worst_lbl1.text)

	var prem_lbl1: Label = v1.find_child("PremiumTotalLabel", true, false) as Label
	check(prem_lbl1 != null, "PremiumTotalLabel exists when plan adopted")
	if prem_lbl1:
		check(prem_lbl1.text.contains("十年保費合計："), "PremiumTotalLabel contains premium text (%s)" % prem_lbl1.text)

	var letter_box1: Node = v1.find_child("LetterExcerptBox", true, false)
	check(letter_box1 != null, "LetterExcerptBox exists for matched client")
	var letter_lbl1: Label = v1.find_child("LetterExcerptLabel", true, false) as Label
	check(letter_lbl1 != null and letter_lbl1.text.contains("家人安心不少"), "LetterExcerptLabel shows matched letter excerpt")

	# Test client switcher interaction
	var btn0: Button = v1.find_child("ClientTimelineBtn_0", true, false) as Button
	check(btn0 != null and btn0.text == "林雨晴", "ClientTimelineBtn_0 represents first client Lin Yuqing")
	if btn0:
		btn0.pressed.emit()
		await process_frame
		var letter_lbl_switched: Label = v1.find_child("LetterExcerptLabel", true, false) as Label
		check(letter_lbl_switched != null and letter_lbl_switched.text.contains("生病時不用擔心收入中斷"), "Switching client updates letter excerpt to Lin Yuqing's letter")

	# Test report_text()
	var report_str: String = str(v1.call("report_text"))
	check(report_str.contains("十年最糟一年：有規劃 ") and report_str.contains("／沒規劃 "), "report_text() includes '十年最糟一年：有規劃 X／沒規劃 Y' (%s)" % report_str)

	host.remove_child(v1)
	v1.queue_free()
	await process_frame

	# --- 2. Test state WITHOUT timelines ---
	var s2 := _state_without_timelines()
	var v2: Control = TrainingReportViewClass.new()
	v2.set("main", dummy_main)
	host.add_child(v2)
	v2.call("refresh", s2)
	await process_frame

	check(v2.find_child("FinanceTimelineCard", true, false) == null, "FinanceTimelineCard absent when no timeline exists")
	check(v2.find_child("TimelineChart", true, false) == null, "TimelineChart absent when no timeline exists")

	# Assertion (b): Build page with no timeline, then refresh to state with timeline -> card appears
	v2.call("refresh", s1)
	await process_frame
	var ftc2_added: Node = v2.find_child("FinanceTimelineCard", true, false)
	check(ftc2_added != null, "FinanceTimelineCard appears after refreshing from no-timeline to with-timeline state")
	var tc2_added: Node = v2.find_child("TimelineChart", true, false)
	check(tc2_added != null and tc2_added.get_script() == TimelineChartClass, "TimelineChart exists after refresh brings timelines")
	var slot2: Node = v2.find_child("FinanceTimelineSlot", true, false)
	check(slot2 != null and ftc2_added.get_parent() == slot2, "FinanceTimelineCard is positioned inside FinanceTimelineSlot (between row1 and row2)")

	host.remove_child(v2)
	v2.queue_free()
	await process_frame

	# --- 3. Test state with unadopted plan ---
	var s3 := _state_unadopted()
	var v3: Control = TrainingReportViewClass.new()
	v3.set("main", dummy_main)
	host.add_child(v3)
	v3.call("refresh", s3)
	await process_frame

	check(v3.find_child("FinanceTimelineCard", true, false) != null, "FinanceTimelineCard present for unadopted timeline")
	var worst_lbl3: Label = v3.find_child("WorstYearLabel", true, false) as Label
	check(worst_lbl3 != null and worst_lbl3.text.contains("客戶沒有採用這份規劃"), "WorstYearLabel shows '客戶沒有採用這份規劃' when adopted == false (%s)" % (worst_lbl3.text if worst_lbl3 else ""))
	check(v3.find_child("PremiumTotalLabel", true, false) == null, "PremiumTotalLabel omitted when plan not adopted")

	# Test letter matching fallback removed: if the only letter belongs to someone else, do NOT display it
	var s_mismatched := _state_unadopted()
	(s_mismatched["final"][0] as Dictionary)["letters"] = [
		{
			"clientId": "other",
			"clientName": "非本局客戶",
			"outcome": "regret",
			"content": "這是其他人的信"
		}
	]
	var v4: Control = TrainingReportViewClass.new()
	v4.set("main", dummy_main)
	host.add_child(v4)
	v4.call("refresh", s_mismatched)
	await process_frame
	check(v4.find_child("LetterExcerptBox", true, false) == null, "LetterExcerptBox omitted when single letter has mismatched clientName (no fallback)")
	host.remove_child(v4)
	v4.queue_free()
	await process_frame

	host.remove_child(v3)
	v3.queue_free()
	dummy_main.queue_free()
	host.queue_free()

	if failures == 0:
		print("report_timeline_smoke: OK")
	else:
		printerr("report_timeline_smoke: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
