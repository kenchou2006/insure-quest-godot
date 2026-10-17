extends SceneTree
## Run: godot --headless --path client --script res://tests/case_setup_smoke.gd
## First training case: unlock progress from records, assigned (never random) client, one-time
## accept with the unlock state, and the same client carried to the clues page and the setup action.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


class GameStub extends Control:
	var main: Node = null


func _options() -> Array:
	return [
		{"id": "yuqing", "name": "林雨晴", "age": 29, "job": "自由接案插畫家", "difficulty": "入門", "amount": "NT$ 600,000", "family": "單身", "goal": "存緊急預備金", "incomeInfo": "月收入不固定"},
		{"id": "boting", "name": "陳柏廷", "age": 36, "job": "半導體工程師", "difficulty": "進階", "amount": "NT$ 1,200,000"},
		{"id": "wanting", "name": "蘇婉婷", "age": 43, "job": "咖啡店老闆", "difficulty": "進階"},
		{"id": "ziyuan", "name": "周子安", "age": 25, "job": "研究生", "difficulty": "入門"},
		{"id": "zhiming", "name": "黃志明", "age": 58, "job": "計程車司機", "difficulty": "挑戰"},
	]


func _codex(n: int) -> Array:
	var out: Array = []
	for c: Dictionary in _options():
		out.append({"id": c.id, "name": c.name, "job": c.job})
	for i in range(n - out.size()):
		out.append({"id": "extra%d" % i, "name": "客戶%d" % i, "job": "職業"})
	return out


func _run() -> void:
	var CaseSetup: GDScript = load("res://scripts/ui/case_setup.gd")

	# 1. New advisor: only the tutorial client unlocked, total from the roster (not hardcoded)
	var info: Dictionary = CaseSetup.unlock_info(_options(), _codex(18), [], [])
	check((info.unlocked as Array) == ["yuqing"], "new advisor: 1 unlocked (%s)" % str(info.unlocked))
	check(int(info.total) == 18, "total from roster (18)")
	check(bool(info.first_time), "first training")
	check(str(info.assigned.get("id", "")) == "yuqing", "tutorial client assigned")
	check(int(CaseSetup.unlock_info(_options(), _codex(21), [], []).total) == 21, "total follows the roster size")

	# 2. Device records: a finished meeting unlocks that client; assignment stays deterministic
	var attempt := {"data": {"interviews": {
		"1:boting": {"step": "result", "client": {"id": "boting"}, "result": {"grade": "B"}},
		"2:wanting": {"step": "plan", "client": {"id": "wanting"}},
	}}}
	info = CaseSetup.unlock_info(_options(), _codex(18), [], [attempt])
	check((info.unlocked as Array).size() == 2 and (info.unlocked as Array).has("boting"), "finished meeting unlocks (%s)" % str(info.unlocked))
	check(not (info.unlocked as Array).has("wanting"), "unfinished meeting does not unlock")
	check(not bool(info.first_time), "not first training after a finished meeting")
	check(str(info.assigned.get("id", "")) == "yuqing", "least-practised unlocked case assigned")
	check(str((info.served.boting as Dictionary).best) == "B", "best grade kept")
	var again: Dictionary = CaseSetup.unlock_info(_options(), _codex(18), [], [attempt])
	check(str(again.assigned.id) == str(info.assigned.id), "same records → same client (no random draw)")

	# 3. Cloud profile counts
	var profile := [{"id": "yuqing", "served": 2, "bestGrade": "A"}, {"id": "zhiming", "served": 1, "bestGrade": "C"}]
	info = CaseSetup.unlock_info(_options(), _codex(18), profile, [])
	check((info.unlocked as Array).size() == 2, "profile: 2 unlocked")
	check(str(info.assigned.id) == "zhiming", "profile: least-practised unlocked case (zhiming)")

	# 4. Overlay flow
	var net: Node = root.get_node("Net")
	net.set("state", {"phase": "playing", "caseOptions": _options(), "codex": _codex(18), "briefcaseSize": 3, "tools": [
		{"id": "needs_form", "name": "需求訪談表", "effect": "a"}, {"id": "gap_sheet", "name": "缺口試算表", "effect": "b"},
		{"id": "compliance_check", "name": "合規檢核表", "effect": "c"}, {"id": "case_notes", "name": "案例筆記", "effect": "d"},
	]})
	var stub := GameStub.new()
	stub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stub)
	var cs: Control = CaseSetup.new()
	stub.add_child(cs)
	await _wait(0.3)
	var assigned_id := str(cs.client.get("id", ""))
	check(assigned_id != "", "a client is assigned")
	check(cs._step == 1, "starts on step 1")
	check(cs._strip_count.text.ends_with("／18"), "strip shows the real total (%s)" % cs._strip_count.text)
	check(not cs._accept.disabled, "accept enabled for guests")
	var sent: Array = []
	cs.setup_sent.connect(func(p: Dictionary): sent.append(p))
	cs._accept.pressed.emit()
	cs._accept.pressed.emit()
	cs._on_accept()
	check(cs._accepting and cs._accept.disabled, "accept locks the button")
	check(cs._accept._label.text == "任務資料解鎖中…", "button shows the unlocking text")
	check(cs._card_label.text.begins_with("正在開啟"), "file label switches to opening")
	check(cs._codex_link.disabled, "codex link disabled during the unlock")
	check(cs._step == 1, "does not switch page immediately")
	await _wait(1.65)
	check(cs._step == 2, "clues page within 1.5 s (step %d)" % cs._step)
	check(str(cs.client.get("id", "")) == assigned_id, "same client on the clues page")
	cs._go_step(3)
	await _wait(0.5)
	check(cs._step == 3, "tools step")
	cs._tools.assign(["needs_form", "gap_sheet", "compliance_check"])
	cs._sync_tools()
	cs._on_confirm()
	check(sent.size() == 1 and str(sent[0].clientId) == assigned_id, "setup sends the same client (%s)" % str(sent))
	cs._on_confirm()
	check(sent.size() == 1, "setup sent once")

	print("case_setup_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
