@tool
class_name Compliance
## 合規雷達規則引擎（客戶端版）
## 即時偵測業務員話術中的違規或瑕疵，與伺服器 server/src/game/compliance.ts 規則保持同步。

const RULE_BY_CODE := {
	"PROMISE_RETURN": "保險業招攬廣告自律規範：不得為保證獲利或保本之宣傳",
	"FEAR_MONGERING": "金融消費者保護法：不得以誇大、恐嚇方式招攬",
	"MISLEADING_COMPARISON": "保險業招攬廣告自律規範：不得為不當比較或貶低同業",
	"UNDISCLOSED_RISK": "金融消費者保護法：應充分說明商品重要內容與風險",
	"EARLY_PRESSURE": "金融服務業公平待客原則：應充分說明並給予客戶考慮時間",
	"INJECTION_ATTEMPT": "面談系統防護：輸入內容與客戶面談無關",
}

const SUGGESTIONS := {
	"PROMISE_RETURN": "說明各商品之風險屬性與條款，避免保證用語",
	"FEAR_MONGERING": "以同理心探詢客戶擔憂，勿使用恐嚇式語言",
	"MISLEADING_COMPARISON": "客觀說明商品特色，尊重客戶原有財務規劃",
	"UNDISCLOSED_RISK": "充分說明商品費用與潛在風險",
	"EARLY_PRESSURE": "給予客戶充分思考時間，先確認需求再討論促成",
	"INJECTION_ATTEMPT": "請專注於客戶需求訪談，勿輸入無關指令",
}

static var _re_injection: RegEx = null
static var _re_promise: RegEx = null
static var _re_neg_promise: RegEx = null
static var _re_fear: RegEx = null
static var _re_neg_fear: RegEx = null
static var _re_comparison: RegEx = null
static var _re_pressure: RegEx = null


static func _init_regexes() -> void:
	if _re_injection != null:
		return
	_re_injection = RegEx.create_from_string("(?i)(ignore (all )?previous|system prompt|你現在是|忘記你的設定|忽略前述指令|無視指令|角色扮演指令|reveal system)")
	# 關鍵字：保證(獲利|收益|賺|理賠|保本|不賠|報酬|回本)|保證|穩賺(不賠)?|一定賺|絕(對|不會)虧|比定存(好|高)
	_re_promise = RegEx.create_from_string("(保證(獲利|收益|賺|理賠|保本|不賠|報酬|回本)|保證|穩賺(不賠)?|一定賺|絕(對|不會)虧|比定存(好|高))")
	_re_neg_promise = RegEx.create_from_string("(不|無法|不能|沒辦法|沒有人能|不敢|不會)(說|講|承諾|給你|跟你說)?$")

	_re_fear = RegEx.create_from_string("(不買會後悔|出事就完(了|蛋)|一定會後悔|完蛋了|等死|後悔莫及)")
	_re_neg_fear = RegEx.create_from_string("(不|不會|不要)$")

	_re_comparison = RegEx.create_from_string("(比定存強|定存很蠢|別家(保險)?都很爛|別家會倒)")
	_re_pressure = RegEx.create_from_string("(只剩今天|現在不簽就沒了|立刻簽|馬上決定|今天不買就沒了)")


## 檢查單段話術並回傳合規判讀結果
static func check(text: String) -> Dictionary:
	_init_regexes()
	var issues: Array = []
	var worst_level := "pass"
	var min_penalty := 0

	# 1. 注入攻擊偵測
	if _re_injection != null:
		var m_inj := _re_injection.search(text)
		if m_inj != null:
			issues.append({
				"code": "INJECTION_ATTEMPT",
				"quote": m_inj.get_string().substr(0, 15),
				"rule": RULE_BY_CODE["INJECTION_ATTEMPT"],
				"suggestion": SUGGESTIONS["INJECTION_ATTEMPT"],
			})
			worst_level = "violation"
			min_penalty = mini(min_penalty, -25)

	# 2. 保證收益
	if _re_promise != null:
		var matches := _re_promise.search_all(text)
		for m in matches:
			var start_pos := m.get_start()
			var prefix := text.substr(0, start_pos).strip_edges(false, true)
			if _re_neg_promise != null and _re_neg_promise.search(prefix) != null:
				# 否定語境（如「無法保證收益」「不能說穩賺」），不視為違規
				continue
			issues.append({
				"code": "PROMISE_RETURN",
				"quote": m.get_string().substr(0, 15),
				"rule": RULE_BY_CODE["PROMISE_RETURN"],
				"suggestion": SUGGESTIONS["PROMISE_RETURN"],
			})
			worst_level = "violation"
			min_penalty = mini(min_penalty, -20)
			break

	# 3. 恐嚇推銷
	if _re_fear != null:
		var matches := _re_fear.search_all(text)
		for m in matches:
			var start_pos := m.get_start()
			var prefix := text.substr(0, start_pos).strip_edges(false, true)
			if _re_neg_fear != null and _re_neg_fear.search(prefix) != null:
				continue
			issues.append({
				"code": "FEAR_MONGERING",
				"quote": m.get_string().substr(0, 15),
				"rule": RULE_BY_CODE["FEAR_MONGERING"],
				"suggestion": SUGGESTIONS["FEAR_MONGERING"],
			})
			worst_level = "violation"
			min_penalty = mini(min_penalty, -20)
			break

	# 4. 不實比較
	if _re_comparison != null:
		var m_comp := _re_comparison.search(text)
		if m_comp != null:
			issues.append({
				"code": "MISLEADING_COMPARISON",
				"quote": m_comp.get_string().substr(0, 15),
				"rule": RULE_BY_CODE["MISLEADING_COMPARISON"],
				"suggestion": SUGGESTIONS["MISLEADING_COMPARISON"],
			})
			worst_level = "violation"
			min_penalty = mini(min_penalty, -15)

	# 5. 時間/逼單壓力 (warning)
	if _re_pressure != null:
		var m_press := _re_pressure.search(text)
		if m_press != null:
			issues.append({
				"code": "EARLY_PRESSURE",
				"quote": m_press.get_string().substr(0, 15),
				"rule": RULE_BY_CODE["EARLY_PRESSURE"],
				"suggestion": SUGGESTIONS["EARLY_PRESSURE"],
			})
			if worst_level != "violation":
				worst_level = "warning"
			min_penalty = mini(min_penalty, -8)

	return {
		"level": worst_level,
		"penalty": min_penalty,
		"issues": issues,
	}


static func level_tag(level: String) -> String:
	match level:
		"violation": return "× 違規"
		"warning": return "▲ 話術瑕疵"
		_: return "✓ 合規"


static func level_color(level: String) -> Color:
	match level:
		"violation": return UI.BAD
		"warning": return UI.OK
		_: return UI.GOOD
