extends RefCounted
## Training secretary lines by game state. The text is the same for Aly and Kevin; the portrait and
## voice follow the secretary the player chose. Screens only name the state; the lines live here.

const STATES := {
	"training_entry": ["接下來，我會依照你的進度安排培訓任務。需要協助時，可以點擊秘書圖示。"],
	"first_assignment": ["這是你的第一位培訓客戶。先接受任務，再查看客戶留下的線索。"],
	"dossier_unlocking": ["正在開啟客戶檔案。"],
	"clue_review": ["先確認三項線索，別急著推薦商品。"],
	"tool_selection": ["根據線索，從公事包選擇三項工具。你的準備會影響後續會談。"],
	"meeting_ready": ["準備完成。會談時請留意客戶需求、預算與合規風險。"],
	"later_matching": ["這次會從目前可配對的客戶中安排一位，不同客戶需要不同準備。"],
	"locked_client_info": ["完成培訓任務並達成條件，就能解鎖新的客戶案例。"],
}


static func lines(state: String) -> Array:
	return (STATES.get(state, []) as Array).duplicate()


static func has_state(state: String) -> bool:
	return STATES.has(state)
