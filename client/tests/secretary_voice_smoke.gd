extends SceneTree
## Run: godot --headless --path client --script res://tests/secretary_voice_smoke.gd
## Secretary → voice mapping: Aly female, Kevin male, solo silent, no cross-gender fallback.

const SecretaryVoice := preload("res://scripts/secretary_voice.gd")
var failures := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Windows (Chrome / Edge local voices) as installed on this machine
	var windows := [
		{"id": "en-zira", "name": "Microsoft Zira - English (United States)", "language": "en-US"},
		{"id": "hanhan", "name": "Microsoft Hanhan - Chinese (Traditional, Taiwan)", "language": "zh-TW"},
		{"id": "yating", "name": "Microsoft Yating - Chinese (Traditional, Taiwan)", "language": "zh-TW"},
		{"id": "zhiwei", "name": "Microsoft Zhiwei - Chinese (Traditional, Taiwan)", "language": "zh-TW"},
		{"id": "danny", "name": "Microsoft Danny - Chinese (Traditional, Hong Kong SAR)", "language": "zh-HK"},
		{"id": "tracy", "name": "Microsoft Tracy - Chinese (Traditional, Hong Kong SAR)", "language": "zh-HK"},
	]
	check(SecretaryVoice.pick("aly", windows) in ["hanhan", "yating"], "Aly uses a zh-TW female voice")
	check(SecretaryVoice.pick("kevin", windows) == "zhiwei", "Kevin uses the zh-TW male voice")
	check(SecretaryVoice.pick("none", windows) == "", "solo challenge has no voice")
	check(SecretaryVoice.pick("aly", windows) != SecretaryVoice.pick("kevin", windows), "Aly and Kevin never share a voice")

	# Edge online natural voices
	var edge := [
		{"id": "hsiaochen", "name": "Microsoft HsiaoChen Online (Natural) - Chinese (Taiwan)", "language": "zh-TW"},
		{"id": "yunjhe", "name": "Microsoft YunJhe Online (Natural) - Chinese (Taiwan)", "language": "zh-TW"},
		{"id": "yunxi", "name": "Microsoft Yunxi Online (Natural) - Chinese (Mainland)", "language": "zh-CN"},
	]
	check(SecretaryVoice.pick("kevin", edge) == "yunjhe", "Kevin prefers zh-TW male over zh-CN male")
	check(SecretaryVoice.pick("aly", edge) == "hsiaochen", "Aly picks the Edge zh-TW female voice")

	# Only female Chinese voices (e.g. Google / macOS default): Kevin must stay silent, not fall back to a woman
	var female_only := [
		{"id": "google-tw", "name": "Google 國語（臺灣）", "language": "zh-TW"},
		{"id": "meijia", "name": "Mei-Jia", "language": "zh-TW"},
	]
	check(SecretaryVoice.pick("kevin", female_only) == "", "Kevin without a male voice → subtitles only")
	check(SecretaryVoice.pick("aly", female_only) != "", "Aly still speaks")

	# Cantonese male only: not used for Mandarin lines
	var cantonese := [{"id": "danny", "name": "Microsoft Danny", "language": "zh-HK"}]
	check(SecretaryVoice.pick("kevin", cantonese) == "", "Cantonese voice is not used for Kevin")

	# Stored choice → secretary_id (including switching mid-game)
	check(SecretaryVoice.id_from_choice(true, "female") == "aly", "female choice → aly")
	check(SecretaryVoice.id_from_choice(true, "male") == "kevin", "male choice → kevin")
	check(SecretaryVoice.id_from_choice(false, "male") == "none", "solo → none")

	# "female" contains "male": the female hint must win
	check(SecretaryVoice.gender_of({"name": "Some Female Voice"}) == "female", "female not misread as male")

	print("secretary_voice_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
