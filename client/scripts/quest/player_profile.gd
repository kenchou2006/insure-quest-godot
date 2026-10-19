@tool
extends Node
## PlayerProfile (autoload): the advisor the player created on 新人顧問報到 — name, portrait, token
## colour, level and XP — plus the solo sparring line-up. Saved in user://player_profile.cfg.
## The server only knows the advisor's name (sent on join); the portrait and colour are shown by
## this client. AI sparring advisors keep the server's bot names in the state; every screen shows
## them through display_name() as the chosen 模擬顧問 (沈知妍 / 顧承宇 / 程雅寧), in the order added.

signal changed

const PATH := "user://player_profile.cfg"
## Older builds kept advisor XP here (mission pages); read once when no profile exists yet
const LEGACY_XP_PATH := "user://quest_profile.cfg"
const XP_PER_LEVEL := 200
const NAME_MIN := 2
const NAME_MAX := 10

## Six player looks — none of them is Aly, Kevin, a sparring advisor or a client
const AVATARS := [
	{"id": "player_01", "label": "形象 01", "gender": "female", "path": "res://assets/advisors/player_01.webp"},
	{"id": "player_02", "label": "形象 02", "gender": "female", "path": "res://assets/advisors/player_02.webp"},
	{"id": "player_03", "label": "形象 03", "gender": "female", "path": "res://assets/advisors/player_03.webp"},
	{"id": "player_04", "label": "形象 04", "gender": "male", "path": "res://assets/advisors/player_04.webp"},
	{"id": "player_05", "label": "形象 05", "gender": "male", "path": "res://assets/advisors/player_05.webp"},
	{"id": "player_06", "label": "形象 06", "gender": "male", "path": "res://assets/advisors/player_06.webp"},
]
const TOKEN_COLORS := {
	"green": {"label": "綠", "color": Color("#00A86B")},
	"blue": {"label": "藍", "color": Color("#3D7FC1")},
	"gold": {"label": "金", "color": Color("#C6A15B")},
	"red": {"label": "紅", "color": Color("#C8553D")},
}
const TOKEN_ORDER := ["green", "blue", "gold", "red"]
## Solo sparring advisors; level is the server bot level each one plays at
const SIM_ADVISORS := [
	{"id": "shen", "name": "沈知妍", "type": "同理洞察型", "icon": "handshake", "level": "pro", "note": "資深顧問：示範先同理、再釐清的做法", "color": Color("#C9928C"), "path": "res://assets/advisors/sim_shen.webp"},
	{"id": "gu", "name": "顧承宇", "type": "數據配置型", "icon": "bars", "level": "novice", "note": "新人顧問：重視數字，常忽略客戶感受", "color": Color("#8FB3C4"), "path": "res://assets/advisors/sim_gu.webp"},
	{"id": "cheng", "name": "程雅寧", "type": "合規策略型", "icon": "shield", "level": "pro", "note": "資深顧問：守住合規，說明清楚再建議", "color": Color("#A7C080"), "path": "res://assets/advisors/sim_cheng.webp"},
]
const DEFAULT_SPARRING := ["shen", "gu"]
const LEVEL_TITLES := ["新人顧問", "初階顧問", "專業顧問", "資深顧問", "首席顧問"]

var player_profile_created := false
var player_name := ""
var player_avatar_id := "player_01"
var player_portrait_path := "res://assets/advisors/player_01.webp"
var player_token_color := "green"
var advisor_xp := 0
var advisor_level := 1
var selected_simulated_advisors: Array = DEFAULT_SPARRING.duplicate()
var simulated_advisor_count := 2
## Unconfirmed choices kept while the player goes back and forth (never saved)
var draft: Dictionary = {}
var sparring_draft: Array = []
var _textures: Dictionary = {}


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_profile_created = bool(cfg.get_value("player", "player_profile_created", false))
		player_name = str(cfg.get_value("player", "player_name", ""))
		player_avatar_id = str(cfg.get_value("player", "player_avatar_id", "player_01"))
		player_portrait_path = str(cfg.get_value("player", "player_portrait_path", avatar(player_avatar_id).path))
		player_token_color = str(cfg.get_value("player", "player_token_color", "green"))
		advisor_xp = int(cfg.get_value("player", "advisor_xp", 0))
		selected_simulated_advisors = _valid_sparring(cfg.get_value("sparring", "selected_simulated_advisors", DEFAULT_SPARRING))
	else:
		var legacy := ConfigFile.new()
		if legacy.load(LEGACY_XP_PATH) == OK:
			advisor_xp = int(legacy.get_value("advisor", "xp", 0))
	if not TOKEN_COLORS.has(player_token_color):
		player_token_color = "green"
	if avatar(player_avatar_id).is_empty():
		player_avatar_id = "player_01"
	player_portrait_path = str(avatar(player_avatar_id).path)
	simulated_advisor_count = selected_simulated_advisors.size()
	advisor_level = level_for(advisor_xp)


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "player_profile_created", player_profile_created)
	cfg.set_value("player", "player_name", player_name)
	cfg.set_value("player", "player_avatar_id", player_avatar_id)
	cfg.set_value("player", "player_portrait_path", player_portrait_path)
	cfg.set_value("player", "player_token_color", player_token_color)
	cfg.set_value("player", "advisor_level", advisor_level)
	cfg.set_value("player", "advisor_xp", advisor_xp)
	cfg.set_value("sparring", "selected_simulated_advisors", selected_simulated_advisors)
	cfg.set_value("sparring", "simulated_advisor_count", simulated_advisor_count)
	cfg.save(PATH)
	changed.emit()


# --- Profile -------------------------------------------------------------------------------------

## "" when valid, else the message to show next to the field
static func name_error(n: String) -> String:
	var t := n.strip_edges()
	if t == "":
		return "請輸入顧問名稱"
	if t.length() < NAME_MIN or t.length() > NAME_MAX:
		return "顧問名稱需為 %d～%d 個字" % [NAME_MIN, NAME_MAX]
	return ""


## Saves the onboarding result and makes the name the one sent to the server
func create(name_text: String, avatar_id: String, token: String) -> bool:
	if name_error(name_text) != "" or avatar(avatar_id).is_empty() or not TOKEN_COLORS.has(token):
		return false
	player_name = name_text.strip_edges()
	player_avatar_id = avatar_id
	player_portrait_path = str(avatar(avatar_id).path)
	player_token_color = token
	player_profile_created = true
	draft = {}
	advisor_level = level_for(advisor_xp)
	Net.player_name = player_name
	Net.save_prefs()
	save_profile()
	return true


static func avatar(id: String) -> Dictionary:
	for a in AVATARS:
		if str(a.id) == id:
			return a
	return {}


func texture_for(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


func portrait() -> Texture2D:
	return texture_for(player_portrait_path) if player_profile_created else null


func token_color() -> Color:
	return TOKEN_COLORS.get(player_token_color, TOKEN_COLORS.green).color


static func level_for(xp: int) -> int:
	return 1 + maxi(0, xp) / XP_PER_LEVEL


static func level_title(level: int) -> String:
	return LEVEL_TITLES[clampi(level - 1, 0, LEVEL_TITLES.size() - 1)]


## "Lv.1 新人顧問" — the real level, never a placeholder
func level_text() -> String:
	return "Lv.%d %s" % [advisor_level, level_title(advisor_level)]


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	advisor_xp += amount
	advisor_level = level_for(advisor_xp)
	save_profile()


# --- Sparring --------------------------------------------------------------------------------------

static func sim(id: String) -> Dictionary:
	for s in SIM_ADVISORS:
		if str(s.id) == id:
			return s
	return {}


func _valid_sparring(ids: Variant) -> Array:
	var out: Array = []
	if ids is Array:
		for id in ids:
			if not sim(str(id)).is_empty() and not out.has(str(id)):
				out.append(str(id))
	if out.is_empty() or out.size() > 3:
		out = DEFAULT_SPARRING.duplicate()
	return out


func set_sparring(ids: Array) -> void:
	selected_simulated_advisors = _valid_sparring(ids)
	simulated_advisor_count = selected_simulated_advisors.size()
	sparring_draft = []
	save_profile()


## Bot levels for the server, one per chosen advisor, in order
func sparring_levels() -> Array:
	var out: Array = []
	for id in selected_simulated_advisors:
		out.append(str(sim(str(id)).get("level", "pro")))
	return out


# --- Names and colours on every screen ------------------------------------------------------------

## The chosen sparring advisor behind a server bot (by the order bots were added)
func bot_advisor(p: Dictionary) -> Dictionary:
	if not bool(p.get("isBot", false)):
		return {}
	var idx := 0
	for q in Net.state.get("players", []):
		var qd := q as Dictionary
		if str(qd.get("id", "")) == str(p.get("id", "")):
			break
		if bool(qd.get("isBot", false)):
			idx += 1
	var ids: Array = selected_simulated_advisors if Net.is_solo else ["shen", "gu", "cheng"]
	if idx < ids.size():
		return sim(str(ids[idx]))
	return SIM_ADVISORS[idx % SIM_ADVISORS.size()]


func is_me(p: Dictionary) -> bool:
	return str(p.get("id", "")) != "" and str(p.get("id", "")) == Net.player_id


func display_name(p: Dictionary) -> String:
	if is_me(p) and player_profile_created and player_name != "":
		return player_name
	var adv := bot_advisor(p)
	if not adv.is_empty():
		return str(adv.name)
	return str(p.get("name", ""))


func display_name_by_id(id: String) -> String:
	for p in Net.state.get("players", []):
		if str((p as Dictionary).get("id", "")) == id:
			return display_name(p)
	return ""


## Server text (logs, banners) with bot names replaced by the sparring advisors' names
func localize(text: String) -> String:
	var out := text
	for p in Net.state.get("players", []):
		var pd := p as Dictionary
		var server_name := str(pd.get("name", ""))
		if server_name == "":
			continue
		var shown := display_name(pd)
		if shown != server_name:
			out = out.replace(server_name, shown)
	return out


func player_color(p: Dictionary, index: int) -> Color:
	if is_me(p) and player_profile_created:
		return token_color()
	var adv := bot_advisor(p)
	if not adv.is_empty():
		return adv.color
	return UI.PLAYER_COLORS[index % UI.PLAYER_COLORS.size()]


func portrait_of(p: Dictionary) -> Texture2D:
	if is_me(p):
		return portrait()
	var adv := bot_advisor(p)
	if not adv.is_empty():
		return texture_for(str(adv.path))
	return null


func reset_for_tests() -> void:
	player_profile_created = false
	player_name = ""
	player_avatar_id = "player_01"
	player_portrait_path = str(avatar("player_01").path)
	player_token_color = "green"
	advisor_xp = 0
	advisor_level = 1
	selected_simulated_advisors = DEFAULT_SPARRING.duplicate()
	simulated_advisor_count = 2
	draft = {}
	sparring_draft = []
