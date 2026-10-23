extends SceneTree
## Run: godot --headless --path client --script res://tests/briefcase_smoke.gd
## 顧問公事包: data files load, rule-based fit (discovered clues only), tool status, select / remove
## / limit, 開始會談 enabling, the same layout for a different customer, nothing client-specific in
## the scripts, and the report analysis.

const BriefcaseData := preload("res://scripts/briefcase_data.gd")
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


func _option(id: String) -> Dictionary:
	return {
		"yuqing": {"id": "yuqing", "name": "林雨晴", "age": 29, "job": "自由接案插畫家", "difficulty": "入門", "family": "單身", "incomeInfo": "月收入 3–8 萬不等", "amount": "NT$ 600,000"},
		"boting": {"id": "boting", "name": "陳柏廷", "age": 36, "job": "半導體工程師", "difficulty": "進階"},
		"zhiming": {"id": "zhiming", "name": "黃志明", "age": 58, "job": "計程車司機", "difficulty": "挑戰"},
	}.get(id, {})


func _server_tools(ids: Array) -> Array:
	return ids.map(func(id): return {"id": id, "name": id, "effect": ""})


func _texts(n: Node) -> String:
	var out := ""
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			out += (l as Label).text + "\n"
	return out


func _run() -> void:
	# 1. Data files
	BriefcaseData.reload()
	var defs: Array = BriefcaseData.tool_defs()
	check(defs.size() == 6, "six tools in data/tools.json (%d)" % defs.size())
	for t: Dictionary in defs:
		for f: String in ["id", "name", "category", "icon", "effect", "matched_tags", "usage_limit", "unlock_condition"]:
			check(t.has(f), "%s has %s" % [t.get("id", "?"), f])
	for t: Dictionary in defs:
		var img := str(t.get("image", ""))
		check(img == "" or ResourceLoader.exists(img), "%s image loads (%s)" % [t.get("id", "?"), img])
	var all: Dictionary = BriefcaseData.customers()
	for id: String in ["yuqing", "boting", "wanting", "ziyuan", "zhiming"]:
		check(all.has(id) and not (all[id].get("clues", []) as Array).is_empty(), "customer data for %s" % id)

	# 2. current_customer: server fields + data; dossier clues known, interview clues locked
	var yu: Dictionary = BriefcaseData.customer(_option("yuqing"))
	check(yu.customer_name == "林雨晴" and yu.customer_job == "自由接案插畫家", "name / job from the server option")
	check((yu.unlocked_clues as Array).size() == 2 and (yu.locked_clues as Array).size() == 2, "2 found, 2 locked")
	var top: Array = BriefcaseData.top_clues(yu)
	check(top.size() == 3 and not bool(top[2].unlocked), "three clues by priority, the third still locked")
	var yu_found: Dictionary = BriefcaseData.customer(_option("yuqing"), ["wrist"])
	check((yu_found.unlocked_clues as Array).size() == 3, "a discovered interview clue unlocks")

	# 3. Rules: tags meet discovered clue tags; compliance links to the compliance-risk row
	var by_id := {}
	for t: Dictionary in defs:
		by_id[t.id] = t
	check(BriefcaseData.matches(by_id.cashflow, yu) == ["income"], "收支 → 收入不穩 (%s)" % str(BriefcaseData.matches(by_id.cashflow, yu)))
	check(BriefcaseData.matches(by_id.needs_form, yu) == ["goal"], "需求訪談 → 資金目標")
	check(BriefcaseData.matches(by_id.gap_sheet, yu).is_empty(), "保障缺口: its clue is still locked → no line")
	check(BriefcaseData.matches(by_id.gap_sheet, yu_found) == ["wrist"], "保障缺口 links once the clue is found")
	check(BriefcaseData.matches(by_id.compliance_check, yu) == ["compliance"], "合規 → compliance row")
	var bo: Dictionary = BriefcaseData.customer(_option("boting"))
	var pics := {}
	for c: Dictionary in bo.clues:
		pics[c.id] = str(c.get("image", ""))
	check(pics.mortgage.ends_with("clue_house.webp") and pics.family.ends_with("clue_family.webp"), "clue pictures picked by tag (%s)" % str(pics))
	check(pics.company == "", "no picture for a tag without one")
	check(BriefcaseData.matches(by_id.family_map, bo) == ["family"], "家庭責任圖 → 家庭責任 for a different client")
	check(BriefcaseData.matches(by_id.cashflow, bo) == ["mortgage"], "收支 → 房貸壓力")

	# 4. Status: not offered by the server → locked with a reason; served_at_least conditions
	var st: Array = BriefcaseData.tools({"served": 0}, _server_tools(["needs_form", "cashflow", "gap_sheet", "risk_survey", "compliance_check"]), ["cashflow"], ["needs_form"])
	var sm := {}
	for t: Dictionary in st:
		sm[t.id] = t
	check(sm.family_map.status == "locked" and str(sm.family_map.unlock_text) != "", "family_map locked when the server lacks it")
	check(sm.cashflow.status == "selected" and sm.needs_form.status == "used" and sm.gap_sheet.status == "available", "selected / used / available")
	check(BriefcaseData.status_label("locked") == "未解鎖" and BriefcaseData.status_label("selected") == "已選擇", "status labels")
	check(not BriefcaseData._condition_met({"type": "served_at_least", "value": 2}, {"served": 1}), "served_at_least: not yet")
	check(BriefcaseData._condition_met({"type": "served_at_least", "value": 2}, {"served": 2}), "served_at_least: met")
	var extra: Array = BriefcaseData.tools({}, _server_tools(["needs_form", "case_notes"]))
	check(extra.size() == 6, "case holds six tools at most")

	# 5. A client with no data entry still gets clues from the case file text
	var gen: Dictionary = BriefcaseData.customer({"id": "gen1", "name": "測試客戶", "family": "扶養兩個孩子", "incomeInfo": "旺季淡季落差大", "amount": "NT$ 500,000"})
	check((gen.clues as Array).size() == 3, "fallback clues from family / income / budget")
	check(BriefcaseData.matches(by_id.family_map, gen) == ["family"], "fallback tags from keywords")

	# 6. Report analysis (after the case every clue counts)
	var a: Dictionary = BriefcaseData.analyze(yu, ["needs_form", "cashflow", "compliance_check"])
	check((a.per_tool as Array).size() == 3, "analysis per packed tool")
	check((a.uncovered as Array) == ["收入綁定手腕"], "important clue without a tool (%s)" % str(a.uncovered))

	# 7. The view: same layout for another customer, locked clue never shown, select / remove / limit
	var net: Node = root.get_node("Net")
	net.set("state", {"phase": "playing", "caseOptions": [_option("yuqing"), _option("boting"), _option("zhiming")], "codex": [], "briefcaseSize": 3,
		"tools": _server_tools(["needs_form", "cashflow", "family_map", "gap_sheet", "risk_survey", "compliance_check"])})
	var stub := GameStub.new()
	stub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stub)
	var cs: Control = load("res://scripts/ui/case_setup.gd").new()
	stub.add_child(cs)
	await _wait(0.3)
	cs.client = _option("yuqing")
	cs._go_step(2)
	await _wait(0.4)
	cs._go_step(3)
	await _wait(0.5)
	var v: Control = cs._briefcase
	check(v != null and cs._tool_grid == v.briefcase_area and cs._confirm == v.start_button, "step 3 is the briefcase view")
	check(cs._step_items[0].text == "看線索" and cs._step_items[2].text == "開始會談", "steps read 看線索 → 選工具 → 開始會談")
	var txt := _texts(v)
	check(txt.contains("林雨晴") and txt.contains("未取得線索"), "customer name and a locked clue row")
	check(not txt.contains("收入綁定手腕") and not txt.contains("手腕疼痛"), "locked clue content never shown")
	v.focus_tool("cashflow")
	await _wait(0.1)
	var matched: Array = []
	for r in v._clue_rows:
		if r.matched:
			matched.append(r.clue_id)
	check(matched.is_empty(), "inspection does not reveal matching clues")
	check(_texts(v.attr_panel).contains("收支盤點器"), "attributes switch to the focused tool")
	check(v.start_button.disabled, "開始會談 disabled with an empty case")
	v._choose_tool("cashflow")
	check(v.focused_matches() == ["income"], "selection reveals discovered matching clue")
	check(v._a_matches.text.split("\n").size() == 2, "explanation has two lines")
	check(v._line_until > Time.get_ticks_msec(), "line appears after selection")
	await _wait(1.5)
	check(v._line_until < Time.get_ticks_msec(), "line expires automatically")
	v.toggle_requested.emit("needs_form")
	check(cs._tools.size() == 2 and v.start_button.disabled, "two packed, still disabled")
	check(v.status_label.text == "再選 1 項即可開始會談", "hint counts down (%s)" % v.status_label.text)
	v.toggle_requested.emit("compliance_check")
	check(cs._tools.size() == 3 and not v.start_button.disabled, "three packed → 開始會談 enabled")
	v.toggle_requested.emit("gap_sheet")
	check(cs._tools.size() == 3 and not cs._tools.has("gap_sheet"), "no fourth tool")
	v.focus_tool("gap_sheet")
	check(v._a_button.disabled and v._a_button.text == "公事包已滿", "full case: action disabled")
	# Tapping a packed tool in the bottom bar takes it out
	v._pack[0].pressed.emit()
	check(cs._tools.size() == 2 and not cs._tools.has("cashflow"), "bottom slot removes its tool (%s)" % str(cs._tools))
	# Tapping the focused tool again packs it
	v.focus_tool("gap_sheet")
	v._on_slot_pressed(v._slots[3])
	check(not cs._tools.has("gap_sheet"), "low priority tool waits for confirmation")
	check(v._a_button.text == "仍然攜帶" and v._replace_button.visible, "low priority offers both choices")
	v._replace_button.pressed.emit()
	check(not cs._tools.has("gap_sheet"), "replace cancels without packing")
	v._choose_tool("gap_sheet")
	v._a_button.pressed.emit()
	check(cs._tools.has("gap_sheet"), "low priority tool remains allowed")
	check(v.status_label.text.contains("✓"), "full case summarizes actual coverage")
	var rects := [v.clue_panel.get_rect(), v.briefcase_area.get_rect(), v.attr_panel.get_rect(), v._bar.get_rect()]
	# Another customer in the same scene: data changes, layout does not
	cs.client = _option("zhiming")
	cs.save_handoff()
	v.set_customer(cs.current_customer)
	await _wait(0.2)
	txt = _texts(v)
	check(txt.contains("黃志明") and not txt.contains("林雨晴"), "customer switch updates the panel")
	check(txt.contains("照顧年邁母親"), "new customer's clues shown")
	var after := [v.clue_panel.get_rect(), v.briefcase_area.get_rect(), v.attr_panel.get_rect(), v._bar.get_rect()]
	check(after == rects, "layout unchanged for another customer")
	var sent: Array = []
	cs.setup_sent.connect(func(p: Dictionary): sent.append(p))
	v.start_requested.emit()
	check(sent.size() == 1 and (sent[0].tools as Array).size() == 3, "開始會談 sends the packed tools")

	# 8. No client written into the screen scripts
	for path: String in ["res://scripts/ui/briefcase_view.gd", "res://scripts/ui/case_setup.gd", "res://scripts/briefcase_data.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for nm: String in ["林雨晴", "陳柏廷", "蘇婉婷", "周子安", "黃志明", "yuqing", "boting", "zhiming"]:
			check(not src.contains(nm), "%s does not name %s" % [path.get_file(), nm])

	print("briefcase_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
