extends SceneTree
## Run: godot --headless --path client --script res://tests/quest_flow_smoke.gd
## 單人培訓流程狀態機（QuestFlow）與四個畫面的新元件：
## 七個狀態與合法切換、動畫中擋下操作、防連點、頁面對應的狀態、下一站解鎖；
## 公事包道具抽屜（用途、次數、時機、效果，使用後真的寫進本局資料）、決策回顧、數值條、
## 骰盤（移動中…骰出 N、跳過動畫）、地圖路線貼合道路與解鎖金線。

var failures := 0
var flow: Node
var gs: Node
var net: Node


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


func _click(c: Control) -> void:
	var w: Vector2 = root.get_final_transform() * c.get_global_rect().get_center()
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	root.push_input(m)
	await process_frame
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


class GameStub extends Control:
	var _is_overlay_deferred := false


func _run() -> void:
	flow = root.get_node("QuestFlow")
	gs = root.get_node("GameState")
	net = root.get_node("Net")

	# 1. 狀態機：起點、動畫中擋下操作、防連點
	flow.call("reset")
	check(str(flow.get("state")) == "MAP_IDLE", "starts on MAP_IDLE")
	check(bool(flow.call("can_roll")), "can roll on MAP_IDLE")
	check(bool(flow.call("go", "DICE_ROLLING", "test")), "MAP_IDLE → DICE_ROLLING")
	check(bool(flow.call("busy")) and not bool(flow.call("can_roll")), "no input while the dice roll")
	check(not bool(flow.call("claim")), "claim refused during an animation")
	check(bool(flow.call("go", "PLAYER_MOVING", "test")), "DICE_ROLLING → PLAYER_MOVING")
	check(bool(flow.call("go", "MISSION_BRIEFING", "test")), "PLAYER_MOVING → MISSION_BRIEFING")
	check(not bool(flow.call("busy")), "briefing takes input")
	check(bool(flow.call("go", "CLIENT_INTERVIEW", "test")), "→ CLIENT_INTERVIEW")
	check(bool(flow.call("go", "MISSION_RESULT", "test")), "→ MISSION_RESULT")
	check(bool(flow.call("go", "NEXT_STAGE_UNLOCKED", "test")), "→ NEXT_STAGE_UNLOCKED")
	check(bool(flow.call("busy")), "no input during the unlock animation")
	check(bool(flow.call("go", "MAP_IDLE", "test")), "→ MAP_IDLE")
	check(not bool(flow.call("go", "MAP_IDLE", "test")), "same state is not a switch")
	check(not bool(flow.call("go", "NOT_A_STATE", "test")), "unknown state refused")
	# 防連點：第一次成功，0.3 秒內的第二次被擋下，之後又可以
	check(bool(flow.call("claim", 0.3)), "first click claimed")
	check(not bool(flow.call("claim", 0.3)), "rapid second click refused")
	await _wait(0.4)
	check(bool(flow.call("claim", 0.05)), "click accepted again after the guard")
	await _wait(0.1)
	# 非預期切換：照後端狀態切過去（不卡住），但留下紀錄
	check(bool(flow.call("go", "NEXT_STAGE_UNLOCKED", "unexpected")), "unexpected switch still applied")
	flow.call("reset")
	check(str(flow.get("state")) == "MAP_IDLE", "reset back to MAP_IDLE")
	var hist: Array = flow.get("history")
	check(hist.size() >= 8, "switches are logged (%d)" % hist.size())

	# 2. 任務層：頁面對應的狀態
	var game := GameStub.new()
	game.size = Vector2(1280, 720)
	root.add_child(game)
	var layer: Control = load("res://scripts/quest/quest_layer.gd").new()
	layer.set("game", game)
	game.add_child(layer)
	await _frames(2)
	for spec in [["arrival", "MISSION_BRIEFING"], ["dialogue", "CLIENT_INTERVIEW"], ["clues", "CLIENT_INTERVIEW"], ["proposal", "CLIENT_INTERVIEW"], ["objection", "CLIENT_INTERVIEW"], ["compliance", "CLIENT_INTERVIEW"], ["result", "MISSION_RESULT"], ["event", "MISSION_BRIEFING"]]:
		layer.call("_sync_flow", spec[0])
		check(str(flow.get("state")) == spec[1], "page %s → %s (got %s)" % [spec[0], spec[1], flow.get("state")])
	flow.set("unlock_pending", true)
	layer.call("_sync_flow", "")
	check(str(flow.get("state")) == "NEXT_STAGE_UNLOCKED" and not bool(flow.get("unlock_pending")), "back on the map after 前往下一站 → NEXT_STAGE_UNLOCKED")
	flow.call("go", "MAP_IDLE", "test")
	flow.call("go", "DICE_ROLLING", "test")
	game._is_overlay_deferred = true
	layer.call("_sync_flow", "")
	check(str(flow.get("state")) == "DICE_ROLLING", "no page while the pawn is still moving: state kept")
	game._is_overlay_deferred = false
	layer.call("_sync_flow", "")
	check(str(flow.get("state")) == "MAP_IDLE", "no page after arrival → MAP_IDLE")
	game.queue_free()
	await _frames(2)

	# 3. 公事包：用途、次數、時機、效果；使用後寫進本局資料
	net.set("player_id", "p1")
	net.set("static_data", {"cards": [{"id": "medical", "title": "醫療費用分擔"}, {"id": "income", "title": "工作能力防線"}]})
	net.set("state", {"phase": "playing", "players": [{"id": "p1", "name": "林小安", "briefcase": ["gap_sheet", "family_map", "compliance_check"]}],
		"session": {"playerId": "p1", "step": "discover", "freeLeft": 1, "talkLeft": 3, "toolHints": {"coreCards": ["medical", "income"]}, "client": {"id": "yuqing", "name": "林雨晴"}}})
	gs.set("record", {"decisions": [], "tools": {}})
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	var drawer: Control = load("res://scripts/quest/widgets/briefcase_drawer.gd").new()
	holder.add_child(drawer)
	await _wait(0.5)
	for id in ["gap_sheet", "family_map", "compliance_check"]:
		var card: Node = drawer.find_child("Tool_" + id, true, false)
		check(card != null, "tool card " + id)
		if card:
			var t := _all_text(card)
			check(t.contains("可使用次數") and t.contains("適用時機") and t.contains("實際效果"), "%s shows uses / timing / effect" % id)
	check(_all_text(drawer.find_child("Tool_compliance_check", true, false)).contains("已生效"), "passive tool marked 已生效")
	var use_gap: Button = drawer.find_child("UseTool_gap_sheet", true, false)
	check(use_gap != null and not use_gap.disabled, "使用：查看核心保障建議 enabled")
	await _click(use_gap)
	await _frames(3)
	var rec: Dictionary = gs.get("record")
	check((rec.get("tools", {}) as Dictionary).has("gap_sheet"), "use recorded in the game's tool data")
	check(int((rec.get("tool_uses", {}) as Dictionary).get("gap_sheet", 0)) == 1, "use counted")
	check((rec.get("decisions", []) as Array).size() == 1 and str((rec.decisions[0] as Dictionary).get("stage", "")) == "公事包", "use written to the decision record")
	check(_all_text(drawer).contains("醫療費用分擔") and _all_text(drawer).contains("工作能力防線"), "core cards from the server shown after use")
	var asked := [false]
	drawer.connect("free_question_requested", func(): asked[0] = true)
	await _click(drawer.find_child("UseTool_family_map", true, false))
	await _wait(0.4)
	check(asked[0], "家庭責任圖 opens the extra free question")
	check(not is_instance_valid(drawer) or drawer.is_queued_for_deletion(), "drawer closes after 家庭責任圖")
	await _frames(2)
	check(holder.find_child("BriefcaseDrawer", true, false) == null, "no drawer left catching the mouse")
	# 關閉按鈕
	drawer = load("res://scripts/quest/widgets/briefcase_drawer.gd").new()
	holder.add_child(drawer)
	await _wait(0.4)
	await _click(drawer.find_child("CloseDrawer", true, false))
	await _wait(0.4)
	check(holder.find_child("BriefcaseDrawer", true, false) == null, "關閉 removes the drawer")

	# 4. 決策回顧
	var review: Control = load("res://scripts/quest/widgets/decision_review.gd").new()
	holder.add_child(review)
	await _frames(3)
	var list: Node = review.find_child("DecisionList", true, false)
	check(list != null and list.get_child_count() == 2, "decision review lists the game's choices (both tool uses)")
	await _click(review.find_child("ReviewDone", true, false))
	await _frames(2)
	check(holder.find_child("DecisionReview", true, false) == null, "decision review closes")

	# 5. 數值條：補間、+／−、反向數值變紅
	var meter: Control = load("res://scripts/quest/widgets/stat_meter.gd").new("trust", "信任", "heart", Color("#00A86B"), false)
	holder.add_child(meter)
	meter.call("set_value", 50, false)
	meter.call("set_value", 62, true)
	await _wait(0.6)
	check((meter.find_child("Delta", true, false) as Label).text == "+12", "meter shows +12")
	check(int((meter.find_child("Bar", true, false) as ProgressBar).value) == 62, "meter bar reaches 62")
	var risk: Control = load("res://scripts/quest/widgets/stat_meter.gd").new("risk", "合規風險", "shield", Color("#C8D2CE"), true)
	holder.add_child(risk)
	risk.call("set_value", -1, false)
	check((risk.find_child("Value", true, false) as Label).text == "—", "unknown value shows —")

	# 6. 骰盤：擲骰中… → 移動中…骰出 N，前進 N 站；跳過動畫
	var dice: Control = load("res://scripts/quest/pages/dice_roll_overlay.gd").new()
	holder.add_child(dice)
	await _frames(2)
	var land: float = dice.call("play", "林小安", 4, true)
	check((dice.find_child("DiceTitle", true, false) as Label).text == "擲骰中…", "rolling title")
	await _wait(land + 0.1)
	check((dice.find_child("DiceTitle", true, false) as Label).text == "移動中…", "moving title")
	check((dice.find_child("DiceCaption", true, false) as Label).text == "骰出 4，前進 4 站", "caption 骰出 4，前進 4 站")
	var skipped := [false]
	dice.connect("skip_requested", func(): skipped[0] = true)
	await _click(dice.find_child("SkipAnimation", true, false))
	check(skipped[0], "跳過動畫 asks to skip the walk")
	flow.call("go", "DICE_ROLLING", "test")
	flow.call("go", "PLAYER_MOVING", "test")
	flow.call("go", "MISSION_BRIEFING", "test")
	await _wait(0.5)
	check(not dice.visible, "dice tray fades once the pawn has arrived")
	flow.call("reset")

	# 7. 地圖：路線貼著道路、解鎖金線
	var board: Control = load("res://scripts/ui/board_aerial.gd").new()
	board.size = Vector2(880, 700)
	holder.add_child(board)
	await _frames(2)
	var tiles: Array = []
	for i in range(24):
		tiles.append({"type": "client" if i % 3 == 1 else "life", "name": "站點%d" % i})
	board.call("set_data", tiles, [{"id": "p1", "pos": 3}], "p1", {})
	await _frames(3)
	check(bool(board.call("_use_road")), "desktop board: stations on the traced road")
	var dots: Array = board.get("_dots")
	var inside := dots.size() == 24
	for d in dots:
		if not Rect2(Vector2.ZERO, board.size).has_point(d):
			inside = false
	check(inside, "all 24 stations inside the board")
	var dur: float = board.call("play_unlock", 3, 7, 0.5)
	check(dur > 0.4 and bool(board.call("unlock_playing")), "unlock line plays")
	await _wait(0.7)
	check(not bool(board.call("unlock_playing")), "unlock line finishes")
	board.size = Vector2(420, 700)
	await _frames(2)
	check(not bool(board.call("_use_road")), "narrow board falls back to the loop (road would be cut off)")

	# 8. 標頭「第 N / M 站」跟著回合走；全部結束（後端回合 = 總數 + 1）時停在最後一站、圓點全部完成
	var mp: HBoxContainer = load("res://scripts/quest/widgets/mission_progress.gd").new()
	holder.add_child(mp)
	net.set("state", {"round": 3, "settings": {"rounds": 5}})
	mp.call("refresh")
	check(_all_text(mp).contains("第 3 /5 站"), "header follows the round (3/5)")
	net.set("state", {"round": 6, "phase": "ended", "settings": {"rounds": 5}})
	mp.call("refresh")
	check(_all_text(mp).contains("第 5 /5 站"), "after the last round the header stays on 5/5, not 6/5")
	var all_done := true
	for d in (mp.get("_dots") as Node).get_children():
		if int(d.get("state")) != 2:
			all_done = false
	check(all_done, "every station dot is done once the game has ended")
	var game_src: String = FileAccess.get_file_as_string("res://scripts/ui/game.gd")
	check(game_src.contains("_map_header.call(\"refresh\")"), "the map header is refreshed on every state")

	holder.queue_free()
	net.set("state", {})
	gs.set("record", {})
	await _frames(2)
	print("quest_flow_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
