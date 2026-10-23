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

	# macOS / iOS (Safari / Chrome Apple voices)
	var macos := [
		{"id": "Eddy (Chinese (Taiwan))", "name": "Eddy (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Reed (Chinese (Taiwan))", "name": "Reed (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Rocko (Chinese (Taiwan))", "name": "Rocko (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Grandpa (Chinese (Taiwan))", "name": "Grandpa (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Flo (Chinese (Taiwan))", "name": "Flo (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Sandy (Chinese (Taiwan))", "name": "Sandy (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Shelley (Chinese (Taiwan))", "name": "Shelley (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Grandma (Chinese (Taiwan))", "name": "Grandma (Chinese (Taiwan))", "language": "zh-TW"},
		{"id": "Meijia", "name": "Meijia", "language": "zh-TW"},
		{"id": "Tingting", "name": "Tingting", "language": "zh-CN"},
		{"id": "Sinji", "name": "Sinji", "language": "yue-HK"},
		{"id": "Eddy (Chinese (China mainland))", "name": "Eddy (Chinese (China mainland))", "language": "zh-CN"},
		{"id": "Reed (Chinese (China mainland))", "name": "Reed (Chinese (China mainland))", "language": "zh-CN"},
		{"id": "Rocko (Chinese (China mainland))", "name": "Rocko (Chinese (China mainland))", "language": "zh-CN"},
		{"id": "Grandpa (Chinese (China mainland))", "name": "Grandpa (Chinese (China mainland))", "language": "zh-CN"},
		{"id": "Flo (Chinese (China mainland))", "name": "Flo (Chinese (China mainland))", "language": "zh-CN"},
		{"id": "Sandy (Chinese (China mainland))", "name": "Sandy (Chinese (China mainland))", "language": "zh-CN"},
		{"id": "Shelley (Chinese (China mainland))", "name": "Shelley (Chinese (China mainland))", "language": "zh-CN"},
		{"id": "Grandma (Chinese (China mainland))", "name": "Grandma (Chinese (China mainland))", "language": "zh-CN"},
	]
	check(SecretaryVoice.pick("kevin", macos) in ["Eddy (Chinese (Taiwan))", "Reed (Chinese (Taiwan))", "Rocko (Chinese (Taiwan))", "Grandpa (Chinese (Taiwan))"], "Kevin picks a zh-TW male voice on macOS")
	check(SecretaryVoice.pick("aly", macos) == "Meijia", "Aly picks Meijia on macOS")
	check(SecretaryVoice.pick("aly", macos) != SecretaryVoice.pick("kevin", macos), "Aly and Kevin never share a voice on macOS")
	check(SecretaryVoice.pick("kevin", macos) != "Sinji" and SecretaryVoice.pick("aly", macos) != "Sinji", "Sinji is never chosen")

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
