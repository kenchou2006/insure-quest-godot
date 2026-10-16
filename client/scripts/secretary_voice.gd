extends RefCounted
## Training secretary → speech voice. Every spoken line (guide, tips, settlement, AI replies) goes
## through here so Aly always speaks with a Traditional Chinese female voice and Kevin with a male one.
## TTS voices carry no gender field, so gender comes from known voice names. A missing voice never
## falls back to the other gender: the caller shows subtitles only.

const PROFILES := {
	"aly": {"id": "aly", "name": "Aly", "voice_enabled": true, "voice_gender": "female", "language": "zh-TW", "sample": "你好，我是 Aly，你的培訓秘書。我會陪你走完每一個關卡。"},
	"kevin": {"id": "kevin", "name": "Kevin", "voice_enabled": true, "voice_gender": "male", "language": "zh-TW", "sample": "你好，我是 Kevin。需要提醒的時候，我會在旁邊幫你。"},
	"none": {"id": "none", "name": "自行挑戰", "voice_enabled": false, "voice_gender": "", "language": "zh-TW", "sample": ""},
}

## Name fragments of common zh voices (Windows, Edge online, macOS, Google, Android)
const FEMALE_HINTS := ["female", "女", "hanhan", "yating", "hsiaochen", "hsiaoyu", "xiaoxiao", "xiaoyi", "xiaochen", "xiaohan", "xiaomo", "xiaorui", "xiaoshuang", "huihui", "yaoyao", "meijia", "mei-jia", "tingting", "ting-ting", "lili", "google"]
static var _reported := {}

const MALE_HINTS := ["male", "男", "zhiwei", "yunjhe", "yunxi", "yunyang", "yunjian", "yunxia", "yunye", "yunze", "yunfeng", "yunhao", "kangkang", "limu", "li-mu", "liang"]


## secretary_id from the stored guide choice
static func id_from_choice(enabled: bool, role: String) -> String:
	if not enabled:
		return "none"
	return "kevin" if role == "male" else "aly"


static func profile(secretary_id: String) -> Dictionary:
	return PROFILES.get(secretary_id, PROFILES["none"])


## "female", "male" or "" (unknown) from the voice name
static func gender_of(voice: Dictionary) -> String:
	var n := str(voice.get("name", "")).to_lower()
	for hint: String in FEMALE_HINTS:
		if n.contains(hint):
			return "female"
	for hint: String in MALE_HINTS:
		if n.contains(hint):
			return "male"
	return ""


## Language rank: zh-TW first, then other Mandarin (zh-CN / zh-SG / zh); Cantonese (zh-HK / yue) is excluded
static func _language_rank(voice: Dictionary) -> int:
	var lang := str(voice.get("language", "")).to_lower().replace("_", "-")
	if lang.begins_with("zh-tw") or lang.begins_with("zh-hant-tw") or lang.begins_with("cmn-hant"):
		return 2
	if lang.begins_with("zh-hk") or lang.begins_with("zh-mo") or lang.begins_with("yue"):
		return -1
	if lang.begins_with("zh") or lang.begins_with("cmn"):
		return 1
	return -1


## Voice id for this secretary, or "" when none fits (then: subtitles only, never the other gender).
## Pass `voices` in tests; otherwise the system list is read each time (web voices load late).
static func pick(secretary_id: String, voices: Variant = null) -> String:
	var p := profile(secretary_id)
	if not bool(p.voice_enabled):
		return ""
	var list: Array = voices if voices is Array else _system_voices()
	var want := str(p.voice_gender)
	var best := ""
	var best_rank := -1
	# Aly may use a zh voice of unknown gender as a last resort; Kevin only a voice known to be male
	for pass_unknown: bool in ([false, true] if want == "female" else [false]):
		for v in list:
			if not v is Dictionary:
				continue
			var g := gender_of(v)
			if not (g == want or (pass_unknown and g == "")):
				continue
			var rank := _language_rank(v)
			if rank > best_rank:
				best_rank = rank
				best = str(v.get("id", ""))
		if best != "":
			return best
	# Logged once per secretary per session
	if not _reported.has(secretary_id):
		_reported[secretary_id] = true
		if secretary_id == "kevin":
			push_error("SecretaryVoice: no Mandarin male voice for Kevin; showing subtitles only.")
		elif secretary_id == "aly":
			push_warning("SecretaryVoice: no Mandarin female voice for Aly; showing subtitles only.")
	return ""


static func _system_voices() -> Array:
	if DisplayServer.get_name() == "headless":
		return []
	return DisplayServer.tts_get_voices()


## Speaks a line in this secretary's voice at the Voice volume (music dips meanwhile).
## Returns false when it stays silent (no voice / solo / voice muted).
static func speak(secretary_id: String, text: String) -> bool:
	var voice := pick(secretary_id)
	if voice == "" or text.strip_edges() == "":
		return false
	var mm := _music()
	if mm != null:
		return mm.speak(text, voice)
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, voice, 71, 1.0, 1.0)
	return true


static func stop() -> void:
	var mm := _music()
	if mm != null:
		mm.stop_speech()
	elif DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()


## MusicManager autoload, looked up at run time so tests can preload this script before autoloads exist
static func _music() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("MusicManager") if tree != null else null
