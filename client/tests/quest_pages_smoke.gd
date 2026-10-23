extends SceneTree
## Run: godot --headless --path client --script res://tests/quest_pages_smoke.gd
## The ten mission pages on a simulated server state, real mouse events, no network:
## arrival → dialogue (2–4 shuffled options, reaction after the answer) → clue board (verdicts,
## time cost, disabled reason) → proposal (over budget, coverage ring, critical decision) →
## objection (three steps, reveal) → compliance scan → result → life event (responses change
## state) → back to the map with nothing left catching the mouse. Also: the meeting clock and its
## 60 / 30 / 10 / 3 s states, holds (settings, pause, critical), tension levels, sound slots that
## never stack, and the pages at desktop and phone sizes.

var failures := 0
var actions: Array = []
var host: Control
var layer: Control
var net: Node
var gs: Node
const FILES := ["user://quest_state.cfg", "user://quest_guides.cfg", "user://quest_profile.cfg", "user://quest_settings.cfg", "user://player_profile.cfg", "user://prefs.json"]
var saved := {}
var _restored := false


## The player's own files come back even when a check stalls
func _restore() -> void:
	if _restored:
		return
	_restored = true
	for path in saved:
		if saved[path] == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(saved[path])
			f.close()


func _watchdog() -> void:
	await create_timer(240.0).timeout
	printerr("FAIL: watchdog — the test stalled")
	_restore()
	quit(1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _frames(n := 3) -> void:
	for i in range(n):
		await process_frame


func _move(pos: Vector2) -> void:
	var w: Vector2 = root.get_final_transform() * pos
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	root.push_input(m)
	await process_frame


func _click(pos: Vector2) -> void:
	await _move(pos)
	var w: Vector2 = root.get_final_transform() * pos
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = w
		e.global_position = w
		root.push_input(e)
		await process_frame


func _all_text(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "", true, false):
		if c is Label:
			out += (c as Label).text + " "
		elif c is Button:
			out += (c as Button).text + " "
	return out


func page() -> Control:
	var p: Variant = layer.get("page")
	return p if p is Control and is_instance_valid(p) else null


func btn(n: String) -> Button:
	for r in [page(), layer]:
		if r == null:
			continue
		for c in (r as Node).find_children(n, "Button", true, false):
			if (c as Button).is_visible_in_tree():
				return c
	return null


## Real click on a named button after checking the pointer actually lands on it
func press(n: String) -> bool:
	var b := btn(n)
	if b == null:
		check(false, "button %s present" % n)
		return false
	# Like a player: scroll the column until the button is in view
	var sc: Node = b.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc is ScrollContainer:
		(sc as ScrollContainer).ensure_control_visible(b)
		await _frames(2)
	var c := b.get_global_rect().get_center()
	await _move(c)
	var hov := root.gui_get_hovered_control()
	check(hov == b or (hov != null and b.is_ancestor_of(hov)), "%s takes the hover (got %s)" % [n, str(hov)])
	check(b.mouse_default_cursor_shape in [Control.CURSOR_POINTING_HAND, Control.CURSOR_FORBIDDEN, Control.CURSOR_WAIT] or b is CheckBox, "%s shows a pointer cursor" % n)
	await _click(c)
	return true


func _settle() -> void:
	var stm := root.get_node("SceneTransitionManager")
	var t := 0.0
	while (stm.get("active") or layer.get("_switching")) and t < 5.0:
		await _wait(0.05)
		t += 0.05
	await _frames(4)


func push(s: Dictionary) -> void:
	net.set("state", s)
	net.state_changed.emit(s)
	layer.call("route", s)
	await _frames(3)


func _capture() -> void:
	var p := page()
	if p and not p.is_connected("act", _on_act):
		p.connect("act", _on_act)


func _on_act(a: Dictionary) -> void:
	actions.append(a)


func last_action() -> Dictionary:
	return actions.back() if not actions.is_empty() else {}


# --- Simulated server state ---------------------------------------------------------------------

func _static() -> Dictionary:
	var board: Array = []
	var types := ["start", "client", "training", "client", "market", "life"]
	for i in range(24):
		board.append({"type": types[i % types.size()], "name": "站點%02d" % i})
	return {
		"board": board,
		"questions": [
			{"id": "income", "text": "如果收入中斷一個月，哪些支出仍然必須支付？", "coach": "把抽象風險轉成生活問題。"},
			{"id": "goal", "text": "這個人生目標裡，哪一部分是你最不願意犧牲的？", "coach": "先確認想保住的目標。"},
			{"id": "coverage", "text": "目前遇到醫療或無法工作時，有哪些資源可以使用？", "coach": "盤點現況。"},
			{"id": "risk", "text": "這筆目標資金在使用前，你最多能接受多少波動？", "coach": "風險承受度要和時間一起看。"},
			{"id": "premium", "text": "你一個月願意拿多少錢買保險？", "coach": "太早問預算會讓客戶覺得你只想成交。"},
		],
		"cards": [
			{"id": "medical", "tag": "醫療支出", "title": "醫療費用分擔", "detail": "降低治療支出衝擊。"},
			{"id": "income", "tag": "收入中斷", "title": "工作能力防線", "detail": "無法工作時的現金。"},
			{"id": "accident", "tag": "意外風險", "title": "意外支出防線", "detail": "突發事故的成本。"},
			{"id": "tools", "tag": "營業中斷", "title": "器材與營運防線", "detail": "設備中斷的緩衝。"},
			{"id": "legacy", "tag": "家庭責任", "title": "家庭責任防線", "detail": "家人的生活與教育。"},
			{"id": "care", "tag": "長期照顧", "title": "長期照顧準備", "detail": "未來的照顧需求。"},
		],
	}


func _client() -> Dictionary:
	return {"id": "yuqing", "name": "林雨晴", "short": "雨晴", "age": 29, "gender": "女", "job": "自由接案插畫家", "tag": "收入波動型", "difficulty": "入門", "portrait": null, "goal": "兩年內成立個人工作室", "amount": "NT$ 600,000", "incomeInfo": "月收入 3–8 萬不等", "family": "單身、與室友合租", "intro": "接案收入起伏大，想在兩年內開工作室。", "quote": "", "generated": false, "scene": null}


func _state(step: String) -> Dictionary:
	return {
		"phase": "playing", "turn": 0, "round": 2, "turnStage": "session", "lastRoll": 3,
		"settings": {"rounds": 6, "aiClients": false},
		"players": [{"id": "p1", "name": "測試顧問", "isBot": false, "pos": 1, "reputation": 10, "commission": 0, "book": [], "decisions": [],
			"mainCase": {"clientId": "yuqing", "clientName": "林雨晴", "job": "自由接案插畫家", "amount": "NT$ 600,000", "visits": 1, "meetings": 3, "done": false, "inMeeting": true, "step": step, "metrics": null},
			"briefcase": ["cashflow", "gap_sheet", "compliance_check"], "contacts": []}],
		"caseOptions": [_client()],
		"session": {
			"playerId": "p1", "referral": false, "step": step, "asked": [], "freeLeft": 1, "talkLeft": 3,
			"twist": {"id": "t1", "title": "接案量突然減少", "hint": "多留意現金流。"},
			"metrics": {"trust": 50, "insight": 20, "fit": 50, "risk": 30, "compliance": 100}, "aiBusy": false,
			"clues": [{"title": "投資帳戶", "observed": false}, {"title": "固定護腕", "observed": false}, {"title": "工作室紙箱", "observed": false}, {"title": "窗外風景", "observed": false}],
			"predictions": {"count": 0, "mine": null}, "stress": null, "ready": false, "covered": [],
			"client": _client(), "objection": null, "objectionReply": null, "hintUsed": false, "hint": null,
			"staged": true, "toolHints": {"coreCards": ["income", "medical"]}, "plan": null, "result": null, "tileIndex": 1,
		},
		"event": null, "log": [], "quests": [], "version": 1, "deckLeft": 10, "territory": {},
	}


# --- Run ----------------------------------------------------------------------------------------

func _run() -> void:
	net = root.get_node("Net")
	gs = root.get_node("GameState")
	var audio := root.get_node("AudioManager")
	var tension := root.get_node("TensionManager")
	var stm := root.get_node("SceneTransitionManager")
	# Keep the player's real files untouched
	for path in FILES:
		saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_watchdog()
	gs.call("reset_for_tests")
	gs.set("classic_ui", false)
	# The advisor from 新人顧問報到 (its portrait, name and level show on the pages)
	var pp: Node = root.get_node("PlayerProfile")
	pp.reset_for_tests()
	check(pp.create("林小安", "player_04", "blue"), "test advisor profile created")
	net.set("player_id", "p1")
	net.set("room_code", "QTEST1")
	net.set("static_data", _static())
	host = Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	layer = load("res://scripts/quest/quest_layer.gd").new()
	host.add_child(layer)
	await _frames(2)

	# 1. Arrival brief
	var s := _state("discover")
	await push(s)
	check(layer.get("current") == "arrival", "new meeting opens the arrival brief (got %s)" % layer.get("current"))
	check(gs.call("client_name") == "林雨晴", "client data from the state")
	await _wait(0.6)
	await press("StartMeeting")
	await _settle()
	check(layer.get("current") == "dialogue", "開始會談 → dialogue page")
	var chip: Node = layer.find_child("PlayerChip", true, false)
	check(chip != null and (chip as Control).is_visible_in_tree(), "header shows the player advisor")
	check(chip != null and _all_text(chip).contains("林小安") and _all_text(chip).contains("Lv.1 新人顧問"), "header: advisor name and real level (%s)" % (_all_text(chip) if chip else ""))
	check(not stm.get("active") and not (stm.call("veil") as ColorRect).visible, "transition veil gone after the switch")
	_capture()

	# 2. Dialogue: 2–4 options, real Buttons, neutral look, shuffled order across visits
	var opts: Array = page().find_children("Option_*", "Button", true, false)
	check(opts.size() >= 2 and opts.size() <= 4, "2–4 reply options (got %d)" % opts.size())
	var firsts := {}
	for k in range(6):
		page().call("_build_options", gs.call("my_session"))
		await _frames(1)
		var o: Array = page().find_children("Option_*", "Button", true, false)
		if not o.is_empty():
			firsts[(o[0] as Button).name] = true
	check(firsts.size() > 1, "option order changes between rounds (%s)" % str(firsts.keys()))
	gs.set("timed_page", true)
	var before_clock: float = gs.call("remaining_time")
	await _wait(0.5)
	check(gs.call("remaining_time") < before_clock, "meeting clock runs on the dialogue page")
	var ob: Button = page().find_children("Option_*", "Button", true, false)[0]
	var qid := ob.name.substr(7)
	await _click(ob.get_global_rect().get_center())
	check(str(last_action().get("type", "")) == "ask" and str(last_action().get("qid", "")) == qid, "option sends ask %s" % qid)
	for b in page().find_children("Option_*", "Button", true, false):
		check((b as Button).disabled, "options locked while the client answers")
	# Server answers: trust +8, a key found
	s.session.asked = [{"qid": qid, "question": "問題", "answer": "「我每月固定支出大概四萬五。」", "key": "收入中斷時的固定支出"}]
	s.session.covered = [qid]
	s.session.metrics = {"trust": 58, "insight": 33, "fit": 50, "risk": 30, "compliance": 100}
	await push(s)
	await _wait(2.6)
	var reaction: Control = page().get("_reaction")
	check(reaction.visible, "reaction shown after the client's words")
	var rtext := ""
	for l in reaction.find_children("*", "Label", true, false):
		rtext += (l as Label).text
	check(rtext.contains("信任 +8") and rtext.contains("取得線索"), "reaction: trust change and reason (%s)" % rtext)
	# A question without a key costs time
	var t0: float = gs.call("remaining_time")
	s.session.asked.append({"qid": "premium", "question": "預算？", "answer": "「怎麼已經在問要付多少？」", "key": null})
	s.session.covered = [qid, "premium"]
	s.session.metrics = {"trust": 49, "insight": 34, "fit": 50, "risk": 30, "compliance": 100}
	page().set("_pending", true)
	page().set("_before", {"trust": 58, "insight": 33, "compliance": 100})
	await push(s)
	await _wait(2.6)
	check(t0 - float(gs.call("remaining_time")) >= 19.0, "question without a clue costs meeting time")
	check(gs.call("decision_history").size() >= 2, "decisions recorded with reasons")

	# 3. Clue board
	await press("NextStep")
	await _settle()
	check(layer.get("current") == "clues", "下一步 → clue board")
	_capture()
	var confirm: Button = btn("ConfirmClues")
	check(confirm.disabled and str(confirm.tooltip_text).contains("沒有分類"), "確認需求判斷 closed with its reason (%s)" % confirm.tooltip_text)
	var card0: Button = page().find_child("Clue_0", true, false)
	await _click(card0.get_global_rect().get_center())
	check(btn("PlaceHere_need") != null, "selecting a card arms the boxes")
	await press("PlaceHere_need")
	check(str(last_action().get("type", "")) == "observe" and int(last_action().get("index", -1)) == 0, "need box investigates the card (observe)")
	s.session.clues[0] = {"title": "投資帳戶", "detail": "工作室資金多放在波動型投資。", "fact": "資產集中，短期現金偏少", "real": true, "observed": true}
	await push(s)
	await _wait(0.4)
	check(str((gs.get("record").get("clue_results", {}) as Dictionary).get("0", "")) == "correct", "real clue in a need box: correct")
	var t1: float = gs.call("remaining_time")
	await _click((page().find_child("Clue_3", true, false) as Button).get_global_rect().get_center())
	await press("PlaceHere_risk")
	s.session.clues[3] = {"title": "窗外風景", "detail": "很美的景色，但和財務需求無關。", "fact": "", "real": false, "observed": true}
	await push(s)
	await _wait(0.4)
	check(str((gs.get("record").get("clue_results", {}) as Dictionary).get("3", "")) == "wrong", "decoy in a need box: wrong")
	check(t1 - float(gs.call("remaining_time")) >= 19.0, "misjudged clue costs time")
	await _click((page().find_child("Clue_1", true, false) as Button).get_global_rect().get_center())
	await press("PlaceHere_need")
	s.session.clues[1] = {"title": "線索1", "detail": "細節", "fact": "需求1", "real": true, "observed": true}
	await push(s)
	# Three investigations are used up: the fourth card cannot be investigated, only set aside
	var n_obs := actions.size()
	await _click((page().find_child("Clue_2", true, false) as Button).get_global_rect().get_center())
	await press("PlaceHere_need")
	check(actions.size() == n_obs and not (gs.call("selected_clues") as Dictionary).has("2"), "a fourth investigation is refused")
	await press("PlaceHere_none")
	check(str((gs.call("selected_clues") as Dictionary).get("2", "")) == "none", "set aside in 暫時無關 without investigating")
	check(btn("ConfirmClues").disabled and btn("ConfirmClues").tooltip_text.contains("3 個問題"), "still closed until the interview has 3 questions")
	s.session.ready = true
	s.session.covered = [qid, "premium", "goal"]
	await push(s)
	page().call("_sync")
	check(not btn("ConfirmClues").disabled, "確認需求判斷 opens when all placed and ready")
	await press("ConfirmClues")
	await _wait(0.6)
	check(str(last_action().get("type", "")) == "to_plan", "confirm sends to_plan")

	# 4. Proposal
	s.session.step = "plan"
	s.players[0].mainCase.step = "plan"
	await push(s)
	await _settle()
	check(layer.get("current") == "proposal", "plan step → proposal page")
	_capture()
	var submit: Button = btn("SubmitPlan")
	check(submit.disabled and submit.tooltip_text.contains("單位"), "提交 closed: budget not allocated (%s)" % submit.tooltip_text)
	for k in range(4):
		await press("Plus_cash")
	for k in range(4):
		await press("Plus_protect")
	for k in range(3):
		await press("Plus_growth")
	await _frames(2)
	check(btn("SubmitPlan").tooltip_text.contains("超出"), "over budget: reason says it (%s)" % btn("SubmitPlan").tooltip_text)
	check(tension.get("state") == 2, "over budget raises Danger (state %d)" % tension.get("state"))
	check(audio.call("last_played", "budget_over") > 0.0, "budget warning sound played")
	await press("Minus_growth")
	await press("Card_income")
	await press("Card_medical")
	await _frames(2)
	var ring = page().get("_ring")
	check(ring.broken, "coverage ring broken while needs are uncovered")
	var cover_n: int = page().find_children("Cover_*", "OptionButton", true, false).size()
	check(cover_n >= 1, "needs from the meeting appear as rows to cover")
	for k in range(cover_n):
		var o: OptionButton = page().find_children("Cover_*", "OptionButton", true, false)[k]
		o.select(1)
		o.item_selected.emit(1)
		await _frames(1)
		check(is_instance_valid(o) and o.is_inside_tree(), "the dropdown stays in place after a choice")
	await _frames(2)
	ring = page().get("_ring")
	check(not ring.broken and is_equal_approx(ring.ratio, 1.0), "ring closes when needs and budget balance")
	check(not btn("SubmitPlan").disabled, "提交 opens (%s)" % btn("SubmitPlan").tooltip_text)
	check(btn("UseTool_gap_sheet") != null, "briefcase tool usable on the plan page")
	await press("UseTool_gap_sheet")
	await press("SubmitPlan")
	await _frames(3)
	var focus: Control = layer.get("focus")
	check(focus.visible, "提交 opens the critical decision")
	check(tension.call("is_critical"), "Critical Decision state")
	var clock_a: float = gs.call("remaining_time")
	await _wait(0.4)
	check(is_equal_approx(clock_a, gs.call("remaining_time")), "clock holds during the critical decision")
	var n_actions := actions.size()
	await press("CriticalConfirm")
	await _wait(0.2)
	check(actions.size() == n_actions, "result is not sent before the 0.4–0.7 s pause")
	await _wait(0.6)
	check(str(last_action().get("type", "")) == "plan" and int((last_action().alloc as Dictionary).cash) == 4, "plan sent after the pause")
	check(not focus.visible and focus.mouse_filter == Control.MOUSE_FILTER_IGNORE, "critical overlay released")

	# 5. Objection
	s.session.step = "objection"
	s.session.plan = {"alloc": {"cash": 4, "protect": 4, "growth": 2}, "cards": ["income", "medical"], "quality": "good", "notes": []}
	s.session.objection = {"text": "「保障是在花錢。」", "options": ["投資照樣保留成長的位置……", "我理解。那你覺得三個月不能畫圖……", "你現在不做安排，以後一定會後悔。", "照我這樣配置，保證不會失敗。"]}
	await push(s)
	await _settle()
	check(layer.get("current") == "objection", "objection step → objection page")
	_capture()
	check(btn("SendReply").disabled, "送出 closed until three steps are chosen")
	await press("Seg1_0")
	await press("Seg2_0")
	await press("Seg3_0")
	await _frames(2)
	check(not btn("SendReply").disabled, "送出 opens with three steps")
	await press("SendReply")
	await _frames(3)
	await press("CriticalConfirm")
	await _wait(1.3)
	check(str(last_action().get("type", "")) == "objection", "objection sent")
	s.session.step = "result"
	s.session.objectionReply = {"text": "…", "title": "你把保障連回她在乎的目標", "body": "客戶知道這項安排如何保留選擇。", "quality": "good"}
	s.session.metrics = {"trust": 66, "insight": 40, "fit": 70, "risk": 50, "compliance": 100}
	s.session.result = {"signed": true, "score": 84, "grade": "A", "caps": [], "commission": 10, "summary": "雨晴簽下了方案。", "predictionHits": [], "epilogue": {"headline": "兩年後工作室順利開張", "title": "", "list": [], "noPlan": []}}
	await push(s)
	await _wait(3.0)
	check(layer.get("current") == "objection", "the reaction stays on screen before the scan")
	check(btn("ToCompliance") != null, "evaluation shown, next step offered")

	# 5b. The free reply (AI graded) stays available on the same page
	check(btn("SendFreeReply") != null, "用自己的話回應 (AI) is offered")

	# 6. Compliance scan
	await press("ToCompliance")
	await _settle()
	check(layer.get("current") == "compliance", "→ compliance scan")
	_capture()
	check(btn("FinishScan").disabled, "完成檢核 closed until something is marked")
	var lines: Array = page().get("_lines")
	var risk_rows := 0
	for i in range(lines.size()):
		if bool(lines[i].get("risk", false)):
			risk_rows += 1
			var cb: Button = page().find_child("Line_%d" % i, true, false).find_child("Mark", true, false)
			await _click(cb.get_global_rect().get_center())
			var under: Control = page().find_child("Line_%d" % i, true, false).find_child("Underline", true, false)
			check(under.visible, "a marked risk shows its red underline")
	check(risk_rows >= 2, "at least two risks to find")
	await press("FinishScan")
	await _frames(3)
	await press("CriticalConfirm")
	await _wait(1.0)
	var scan: Dictionary = gs.get("record").get("scan", {})
	check(int(scan.get("score", -1)) == 100, "all risks found, none wrong: 100 (got %s)" % str(scan.get("score")))

	# 7. Result
	await press("ToResult")
	await _settle()
	check(layer.get("current") == "result", "→ mission result")
	var adv_chip: Node = page().find_child("AdvisorChip", true, false)
	check(adv_chip != null and _all_text(adv_chip).contains("林小安"), "result shows the player advisor (%s)" % (_all_text(adv_chip) if adv_chip else ""))
	_capture()
	await _wait(4.4)
	var rows: Array = page().get("_rows")
	check(rows.size() == 9, "nine result items (got %d)" % rows.size())
	var all_shown := true
	for r in rows:
		if (r as Control).modulate.a < 0.99:
			all_shown = false
	check(all_shown, "items revealed one by one")
	check(gs.call("game_xp") > 0, "experience awarded")
	var verdict: Node = page().find_child("ResultVerdict", true, false)
	check(verdict != null and (_all_text(verdict).contains("任務完成") or _all_text(verdict).contains("需要加強")), "任務完成／需要加強 shown")
	check(page().find_child("LevelProgress", true, false) is ProgressBar, "advisor level progress bar")
	var result_text := _all_text(page())
	for item in ["時間管理", "新增人脈", "獲得經驗值", "合規表現", "客戶信任變化"]:
		check(result_text.contains(item), "result item " + item)
	# 查看決策回顧 opens the review and closes again
	await press("ReviewDecisions")
	await _frames(3)
	var review: Node = page().find_child("DecisionReview", false, false)
	check(review != null and (review.find_child("DecisionList", true, false) as Node).get_child_count() > 0, "decision review lists this game's choices")
	if review:
		await _click((review.find_child("ReviewDone", true, false) as Control).get_global_rect().get_center())
		await _frames(2)
	check(page().find_child("DecisionReview", false, false) == null, "decision review closes")
	check(btn("ResultHome") != null, "返回主頁 on the result card")
	var flow: Node = root.get_node("QuestFlow")
	check((btn("ResultContinue") as Button).text == "前往下一站", "前往下一站 on a mid-game result")
	await press("ResultContinue")
	check(str(last_action().get("type", "")) == "continue", "前往下一站 sends continue")
	check(bool(flow.get("unlock_pending")), "前往下一站 asks for the unlock animation on the map")
	flow.set("unlock_pending", false)

	# 8. Life event of the primary client: responses change state
	s.session = null
	s.turnStage = "event"
	s.players[0].mainCase.step = "objection"
	s.event = {"kind": "life", "playerId": "p1", "title": "人生事件｜林雨晴", "body": "林雨晴：接案量突然減少", "lines": [{"text": "多留意現金流。", "tone": "info"}]}
	await push(s)
	await _settle()
	check(layer.get("current") == "event", "life event modal")
	_capture()
	check(btn("EventContinue").disabled, "繼續 closed until a response is chosen")
	var t2: float = gs.call("remaining_time")
	await press("Twist_plan")
	await _frames(2)
	check(bool(gs.call("flag", "twist_plan", false)), "response changes what comes next (plan must carry it)")
	check(t2 - float(gs.call("remaining_time")) >= 59.0, "response costs its time")
	check(not btn("EventContinue").disabled, "繼續 opens after choosing")
	await press("EventContinue")
	check(str(last_action().get("type", "")) == "continue", "event continue sent")

	# 8b. Every other station event: its 繼續 is on screen and works once a choice is made
	var kinds := [
		{"kind": "quiz", "title": "合規訓練", "body": "客戶說只想要保證高報酬的商品，你會？", "lines": [], "quiz": {"id": "q1", "q": "客戶說只想要保證高報酬的商品，你會？", "options": ["推薦報酬最高的商品", "說明沒有商品能保證報酬，並了解目標", "說保險都保證報酬", "請他去找別人"]}},
		{"kind": "dilemma", "title": "業績與合規", "body": "主管要你本週衝業績。", "lines": [], "dilemma": {"id": "d1", "title": "業績與合規", "prompt": "主管要你本週衝業績。", "choices": [{"id": "A:x", "text": "照客戶需求慢慢來"}, {"id": "B:y", "text": "先賣再說"}], "picked": null, "outcome": null}},
		{"kind": "review", "title": "王小明｜家中添了新成員", "body": "客戶最近有了第二個孩子。", "lines": [], "review": {"clientId": "c1", "clientName": "王小明", "change": {"title": "家中添了新成員", "body": "客戶最近有了第二個孩子。"}, "current": {"alloc": {"cash": 3, "protect": 4, "growth": 3}, "cards": ["medical"]}, "picked": null, "outcome": null}},
		{"kind": "life", "title": "理賠服務｜王小明", "body": "手腕受傷，停止接案六週。", "lines": [{"text": "理賠 12 萬已撥付", "tone": "good"}, {"text": "防線承接力 12 / 需求 11 → 承接", "tone": "good"}, {"text": "客戶滿意度 +12，聲望 +3", "tone": "good"}], "claim": {"clientId": "c1", "clientName": "王小明", "event": "手腕受傷", "tag": "收入", "result": "broken", "loss": 180000, "covered": 40000, "outOfPocket": 140000}},
		{"kind": "market", "title": "全球股市單月下跌 20%", "body": "景氣衰退疑慮升高，風險資產全面修正。這段說明刻意寫長一點，看看事件卡在較長的內容下按鈕是否仍然在畫面內可以按到，不會被擠到畫面外面。", "lines": [{"text": "測試顧問：0 位客戶穩住、1 位受到重創（聲望 -2）", "tone": "bad"}, {"text": "學習重點：有足夠預備金的客戶不必在低點賣出；短期要用的錢不該放在高波動資產。", "tone": "info"}]},
		{"kind": "audit", "title": "合規稽核", "body": "稽核人員抽查你的客戶紀錄。", "lines": [{"text": "王小明：紀錄完整、配置適合，聲望 +1", "tone": "good"}]},
		{"kind": "settlement", "title": "季度結算", "body": "檢視你的客戶簿。", "lines": [{"text": "本季沒有續約或解約。", "tone": "info"}]},
		{"kind": "seminar", "title": "顧問研討會", "body": "資深顧問針對你的表現給予建議。", "lines": [{"text": "先問收入中斷與人生目標，再談預算。", "tone": "info"}, {"text": "持續學習，聲望 +2", "tone": "good"}]},
		{"kind": "checkup", "title": "保單健檢｜王小明", "body": "定期檢視保障狀況。", "lines": [{"text": "滿意度 +5", "tone": "good"}], "checkup": {"clientId": "c1", "clientName": "王小明", "referral": false}},
		{"kind": "info", "title": "人脈事件", "body": "你在活動中交換了名片。", "lines": [{"text": "拓展人脈，聲望 +1", "tone": "good"}]},
	]
	for ev in kinds:
		ev["playerId"] = "p1"
		s.event = ev
		await push(s)
		await _settle()
		await _wait(0.5)
		check(layer.get("current") == "event", "%s: event modal" % ev.kind)
		_capture()
		for pick in ["Quiz_1", "Dilemma_A", "Review_none"]:
			if btn(pick) != null:
				await press(pick)
				# The server answers the choice
				if ev.has("quiz"):
					ev.quiz["picked"] = 1
					ev.quiz["answer"] = 1
					ev.quiz["explain"] = "任何投資都不能保證報酬。"
				elif ev.has("dilemma"):
					ev.dilemma["picked"] = "A:x"
					ev.dilemma["outcome"] = {"title": "守住了合規", "body": "客戶信任上升。", "tone": "good", "effects": "聲望 +2"}
				elif ev.has("review"):
					ev.review["picked"] = "none"
					ev.review["outcome"] = {"title": "確認現有規劃", "body": "客戶安心。", "tone": "ok"}
				s.event = ev
				await push(s)
				await _wait(0.3)
		var cont := btn("EventContinue")
		check(cont != null, "%s: 繼續 present" % ev.kind)
		if cont:
			var cr := cont.get_global_rect()
			check(Rect2(Vector2.ZERO, host.size).grow(1).encloses(cr), "%s: 繼續 inside the screen (%s, card %s)" % [ev.kind, str(cr), str((page().get("card") as Control).get_global_rect())])
			check(not cont.disabled, "%s: 繼續 open (%s)" % [ev.kind, cont.tooltip_text])
			var n0 := actions.size()
			await press("EventContinue")
			check(actions.size() > n0 and str(last_action().get("type", "")) == "continue", "%s: 繼續 sends continue" % ev.kind)

	# 9. Back to the map: nothing left over catching the mouse
	s.event = null
	s.turnStage = "roll"
	await push(s)
	await _settle()
	check(layer.get("current") == "", "no page on the map")
	check(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "layer lets the map through")
	await _move(Vector2(300, 300))
	var hov := root.gui_get_hovered_control()
	check(hov == null or not layer.is_ancestor_of(hov), "map area not covered (%s)" % str(hov))

	# 10. Clock marks, holds and tension levels
	gs.set("timed_page", true)
	tension.call("set_active", true)
	var rec: Dictionary = gs.get("record")
	rec["remaining"] = 61.0
	rec["marks"] = {}
	gs.set("_marks_fired", {})
	await _wait(1.3)
	check((gs.get("_marks_fired") as Dictionary).has("60"), "60 s mark")
	rec["remaining"] = 30.4
	await _wait(0.6)
	check(audio.call("last_played", "timer_warn") > 0.0, "30 s warning tone")
	rec["remaining"] = 10.3
	await _wait(0.5)
	check(audio.call("last_played", "timer_tick") > 0.0, "last ten seconds: low beat")
	rec["remaining"] = 0.4
	await _wait(0.7)
	check(gs.call("remaining_time") == 0.0 and gs.call("overtime") > 0.0, "time up: overtime counted, play continues")
	await _wait(0.4)
	check((tension.get("reasons") as Array).has("會談時間結束，請完成目前決策"), "time-up message")
	check(tension.get("state") == 2, "time up is Danger")
	rec["remaining"] = 240.0
	rec["overtime"] = 0.0
	await _wait(0.5)
	check(tension.get("state") == 1, "under half the time: Warning (state %d)" % tension.get("state"))
	var settings: Control = layer.get("settings")
	settings.call("open")
	var c0: float = gs.call("remaining_time")
	await _wait(0.4)
	check(is_equal_approx(c0, gs.call("remaining_time")), "clock holds while settings are open")
	await press("PauseButton")
	check(settings.call("is_paused"), "pause")
	await _wait(0.3)
	check(is_equal_approx(c0, gs.call("remaining_time")), "clock holds while paused")
	await press("ResumeButton")
	check(not settings.visible and (gs.get("holds") as Dictionary).is_empty(), "resume releases every hold")

	# 11. Sound slots never stack
	audio.call("play", "ui_click")
	var first: float = audio.call("last_played", "ui_click")
	audio.call("play", "ui_click")
	check(is_equal_approx(first, audio.call("last_played", "ui_click")), "a repeat inside the cooldown is dropped")

	# 12a. Objection answered in the advisor's own words (AI grading through objection_free)
	gs.call("set_flag", "hold_objection", false)
	var s3 := _state("objection")
	s3.session.client.id = "boting"
	s3.session.client.name = "周柏霆"
	s3.caseOptions = [s3.session.client]
	s3.players[0].mainCase.clientId = "boting"
	s3.session.objection = {"text": "「保費太貴了。」", "options": ["A", "B", "C", "D"]}
	gs.call("set_flag", "arrived", true)
	await push(s3)
	gs.call("set_flag", "arrived", true)
	await push(s3)
	await _settle()
	check(layer.get("current") == "objection", "objection page for the second client")
	check(gs.call("client_name") == "周柏霆", "client data swapped to the new client")
	_capture()
	var fin: LineEdit = page().get("_free_input")
	fin.text = "我理解保費是壓力，我們先看哪一項保障最重要，其他可以慢慢補。"
	await press("SendFreeReply")
	await _frames(3)
	await press("CriticalConfirm")
	await _wait(1.3)
	check(str(last_action().get("type", "")) == "objection_free" and str(last_action().get("text", "")).begins_with("我理解"), "free reply sent for AI grading")
	s3.session.step = "result"
	s3.session.objectionReply = {"text": fin.text, "title": "先處理客戶的壓力", "body": "回應接住了客戶的擔心。", "quality": "good"}
	s3.session.metrics = {"trust": 60, "insight": 25, "fit": 55, "risk": 30, "compliance": 100}
	await push(s3)
	await _wait(3.2)
	check(btn("ToCompliance") != null, "free reply: reaction and evaluation shown")
	gs.call("set_flag", "hold_objection", false)

	# 12. Pages at desktop and phone sizes: key button inside the screen and reachable
	for spec in [["desktop", Vector2i(1280, 720)], ["phone_landscape", Vector2i(800, 450)], ["phone_portrait", Vector2i(480, 854)]]:
		UI.set_layout_profile(spec[0], spec[1])
		host.size = Vector2(spec[1])
		root.content_scale_size = spec[1]
		await _frames(2)
		for st in [["plan", "proposal", "SubmitPlan"], ["discover", "dialogue", "NextStep"]]:
			var s2 := _state(st[0])
			gs.call("set_flag", "arrived", true)
			gs.call("set_flag", "discover_page", "dialogue")
			await push(s2)
			await _settle()
			var b := btn(st[2])
			check(b != null, "%s: %s present on %s" % [spec[0], st[2], st[1]])
			if b:
				var r := b.get_global_rect()
				check(Rect2(Vector2.ZERO, host.size).grow(1).encloses(r), "%s: %s inside the screen (%s)" % [spec[0], st[2], str(r)])
				check(r.size.y >= 36.0, "%s: %s tall enough to tap (%.0f)" % [spec[0], st[2], r.size.y])
	UI.set_layout_profile("desktop", Vector2i(1280, 720))

	_restore()
	if failures == 0:
		print("quest_pages_smoke: OK")
	else:
		printerr("quest_pages_smoke: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
