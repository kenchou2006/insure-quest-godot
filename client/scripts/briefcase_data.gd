extends RefCounted
## Advisor briefcase data and rules. Customers (data/customers.json) and tools (data/tools.json) are
## plain data; the server's case option supplies name / age / job / difficulty. Nothing about a
## particular client lives in a scene or script.
## Fit is decided by rules — a tool "matches" a clue when its matched_tags meet the clue's tags —
## and only clues the player has already found count. No scores, no randomness, no right/wrong.

const CUSTOMERS_PATH := "res://data/customers.json"
const TOOLS_PATH := "res://data/tools.json"
## Tags for clients without a data entry, guessed from the case file text
const KEYWORD_TAGS := {
	"扶養": ["family_duty", "dependents"], "孩子": ["family_duty", "dependents"], "照顧": ["family_duty"],
	"房貸": ["mortgage"], "預算": ["budget_limited"], "下緣": ["budget_limited"],
	"不等": ["income_volatile"], "落差": ["income_volatile"], "旺季": ["income_volatile"], "無法工作": ["single_point"],
}

static var _customers: Dictionary = {}
static var _tools: Array = []


static func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("BriefcaseData: missing " + path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_warning("BriefcaseData: invalid JSON in " + path)
	return parsed


static func customers() -> Dictionary:
	if _customers.is_empty():
		var d: Variant = _load_json(CUSTOMERS_PATH)
		_customers = d if d is Dictionary else {}
	return _customers


static func tool_defs() -> Array:
	if _tools.is_empty():
		var d: Variant = _load_json(TOOLS_PATH)
		_tools = (d as Dictionary).get("tools", []) if d is Dictionary else []
	return _tools


## Clears cached data (tests, or after editing the data files)
static func reload() -> void:
	_customers = {}
	_tools = []


## current_customer: the data entry merged with the server's case option.
## found_clue_ids: interview clues the player has already discovered.
static func customer(case_option: Dictionary, found_clue_ids: Array = []) -> Dictionary:
	var id := str(case_option.get("id", ""))
	var base: Dictionary = customers().get(id, {})
	var clues: Array = []
	if base.has("clues"):
		for c: Dictionary in base.clues:
			clues.append(c.duplicate(true))
	else:
		clues = _fallback_clues(case_option)
	clues.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("priority", 99)) < int(b.get("priority", 99)))
	var unlocked: Array = []
	var locked: Array = []
	var images: Dictionary = customers().get("_clue_images", {})
	for c: Dictionary in clues:
		c.unlocked = str(c.get("reveal", "dossier")) == "dossier" or found_clue_ids.has(str(c.get("id", "")))
		# Picture: the clue's own, else the first of its tags that has one
		if str(c.get("image", "")) == "":
			for t in c.get("tags", []):
				if images.has(t):
					c.image = str(images[t])
					break
		(unlocked if c.unlocked else locked).append(c)
	return {
		"customer_id": id,
		"customer_name": str(case_option.get("name", "")),
		"customer_portrait": id,
		"customer_job": str(case_option.get("job", "")),
		"customer_age": int(case_option.get("age", 0)),
		"customer_age_group": str(base.get("age_group", "")),
		"family_structure": str(base.get("family_structure", case_option.get("family", ""))),
		"primary_needs": base.get("primary_needs", [str(case_option.get("goal", ""))]),
		"financial_constraints": base.get("financial_constraints", [str(case_option.get("incomeInfo", ""))]),
		"budget_range": str(base.get("budget_range", case_option.get("amount", ""))),
		"compliance_risk": str(base.get("compliance_risk", "")),
		"difficulty_level": str(case_option.get("difficulty", "")),
		"clues": clues,
		"unlocked_clues": unlocked,
		"locked_clues": locked,
	}


static func _fallback_clues(case_option: Dictionary) -> Array:
	var out: Array = []
	var fields := [["family", "家庭狀況", "users"], ["incomeInfo", "收入狀況", "chart"], ["amount", "預算", "wallet"]]
	for i in range(fields.size()):
		var text := str(case_option.get(fields[i][0], "")).strip_edges()
		if text == "":
			continue
		var tags: Array = []
		for kw: String in KEYWORD_TAGS:
			if text.contains(kw):
				for t in KEYWORD_TAGS[kw]:
					if not tags.has(t):
						tags.append(t)
		out.append({"id": fields[i][0], "title": fields[i][1], "detail": text, "icon": fields[i][2], "tags": tags, "priority": i + 1, "reveal": "dossier"})
	return out


## The three most important clues for the left panel (locked ones stay hidden as 未取得線索)
static func top_clues(cust: Dictionary, count := 3) -> Array:
	return (cust.get("clues", []) as Array).slice(0, count)


## Tools with status: locked (unlock condition not met / not offered by this server), available,
## selected, used. progress: {"served": int}; server_tools: the server's tool list (only those can
## be packed). A server tool missing from the data file still shows, with the server's own text.
static func tools(progress: Dictionary, server_tools: Array, selected: Array = [], used: Array = [], slots := 6) -> Array:
	var server_ids: Array = server_tools.map(func(t): return str((t as Dictionary).get("id", "")) if t is Dictionary else "")
	var defs: Array = tool_defs().duplicate(true)
	var known: Array = defs.map(func(d): return str(d.get("id", "")))
	for st in server_tools:
		if st is Dictionary and not known.has(str(st.get("id", ""))) and defs.size() < slots:
			defs.append({"id": str(st.get("id", "")), "name": str(st.get("name", "")), "category": "工具", "icon": "briefcase",
				"image": "", "effect": str(st.get("effect", "")), "chips": [], "matched_tags": [], "usage_limit": "", "unlock_condition": {"type": "none"}})
	var out: Array = []
	for t: Dictionary in defs.slice(0, slots):
		var id := str(t.get("id", ""))
		var cond: Dictionary = t.get("unlock_condition", {"type": "none"})
		var offered := server_ids.is_empty() or server_ids.has(id)
		var open := _condition_met(cond, progress) and offered
		t.unlock_text = _condition_text(cond) if offered else "這場培訓尚未提供此工具"
		if not open:
			t.status = "locked"
		elif used.has(id):
			t.status = "used"
		elif selected.has(id):
			t.status = "selected"
		else:
			t.status = "available"
		out.append(t)
	return out


static func _condition_met(cond: Dictionary, progress: Dictionary) -> bool:
	match str(cond.get("type", "none")):
		"served_at_least":
			return int(progress.get("served", 0)) >= int(cond.get("value", 0))
		_:
			return true


static func _condition_text(cond: Dictionary) -> String:
	match str(cond.get("type", "none")):
		"served_at_least":
			return str(cond.get("text", "完成 %d 位客戶會談後解鎖" % int(cond.get("value", 0))))
		_:
			return ""


static func status_label(status: String) -> String:
	return {"locked": "未解鎖", "available": "可選", "selected": "已選擇", "used": "已使用"}.get(status, status)


## Clue ids (and "compliance" for the compliance-risk row) this tool connects to.
## Only discovered clues count unless include_locked (the report, after the case).
static func matches(tool: Dictionary, cust: Dictionary, include_locked := false) -> Array:
	var tags: Array = tool.get("matched_tags", [])
	var out: Array = []
	for c: Dictionary in cust.get("clues", []):
		if not include_locked and not bool(c.get("unlocked", false)):
			continue
		for t in c.get("tags", []):
			if tags.has(t):
				out.append(str(c.get("id", "")))
				break
	if tags.has("compliance") and str(cust.get("compliance_risk", "")) != "":
		out.append("compliance")
	return out


## Report analysis after the case: which clues each packed tool spoke to, and which important
## clues no packed tool covered. Descriptive only (no right / wrong).
static func analyze(cust: Dictionary, tool_ids: Array) -> Dictionary:
	var per_tool: Array = []
	var covered := {}
	var titles := {"compliance": "合規提醒"}
	for c: Dictionary in cust.get("clues", []):
		titles[str(c.get("id", ""))] = str(c.get("title", ""))
	for d: Dictionary in tool_defs():
		if not tool_ids.has(str(d.get("id", ""))):
			continue
		var m := matches(d, cust, true)
		for id in m:
			covered[id] = true
		per_tool.append({"name": str(d.get("name", "")), "matched": m.map(func(id): return titles.get(id, id))})
	var uncovered: Array = []
	for c: Dictionary in top_clues(cust, 3):
		if not covered.has(str(c.get("id", ""))):
			uncovered.append(str(c.get("title", "")))
	return {"per_tool": per_tool, "uncovered": uncovered}
