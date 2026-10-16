extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var journal = load("res://scripts/training_journal.gd").new()
	journal.storage_dir = "user://journal_test_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var state := {"phase": "playing", "round": 1, "turnStage": "roll", "trainingAttemptId": null, "players": [{"id": "p1", "name": "測試顧問", "decisions": [{"title": "第一個決策"}]}]}
	assert(journal.checkpoint(state, "p1", "local-unique", "guest"))
	assert(journal.active_id == "local-unique:p1")
	assert(journal.checkpoint(state, "p1", "local-unique", "guest"))
	assert(journal.list_records("guest")[0].data.decisions.size() == 1, "Repeated state must not duplicate decisions")
	state.players[0].decisions.append({"title": "第二個決策"})
	state.session = {"playerId": "p1", "step": "discover", "client": {"id": "c", "name": "客戶"}, "asked": [{"question": "保障需求？", "answer": "家庭保障"}]}
	assert(journal.checkpoint(state, "p1", "local-unique", "guest"))
	assert(journal.close_attempt())
	var reload = load("res://scripts/training_journal.gd").new()
	reload.storage_dir = journal.storage_dir
	reload.load_records()
	var records: Array = reload.list_records("guest")
	assert(records.size() == 1 and records[0].status == "abandoned")
	assert(records[0].data.decisions.size() == 2)
	assert(records[0].data.currentSession.asked[0].answer == "家庭保障")
	assert(reload.list_records("other-account").is_empty())
	state.trainingAttemptId = "cloud-id"
	assert(reload.checkpoint(state, "p1", "room", "owner"))
	assert(reload.active_id == "cloud-id:p1")
	state.phase = "ended"
	state.final = [{"playerId": "p1", "score": 92, "grade": "A"}]
	assert(reload.checkpoint(state, "p1", "room", "owner"))
	assert(reload.close_attempt())
	assert(reload.list_records("owner")[0].status == "completed")
	assert(reload.list_records("owner")[0].score == 92)
	assert(reload.delete_owner("owner"))
	assert(reload.list_records("owner").is_empty())
	assert(reload.list_records("guest").size() == 1)
	# Force an unwritable path via an existing file, then restore and retry.
	var blocker: String = journal.storage_dir.path_join("blocker")
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("blocked")
	file.close()
	reload.storage_dir = blocker + "/child"
	assert(not reload.retry())
	assert(not reload.last_error.is_empty())
	reload.storage_dir = journal.storage_dir
	assert(reload.retry() and reload.last_error.is_empty())
	# Exercise the actual network state handler and acknowledgement ordering.
	var net := root.get_node("Net")
	var original_journal = net._journal
	net._journal = reload
	net.player_id = "p1"
	net._game_id = "integration"
	net.user_profile = {"user": {"id": "owner"}}
	state.phase = "playing"
	state.final = null
	state.trainingAttemptId = "integration:p1"
	net._handle(JSON.stringify({"t": "training_saved", "attempt_id": "integration:p1", "status": "saved"}))
	net._handle(JSON.stringify({"t": "state", "state": state}))
	assert(net.training_save_status.local == "saved" and net.training_save_status.cloud == "saved")
	assert(net.local_training_attempts().size() == 1)
	net.leave(false)
	assert(net.local_training_attempts()[0].status == "abandoned")
	assert(reload.delete_owner("owner"))
	net.user_profile = {}
	net._journal = original_journal
	assert(reload.delete_owner("guest"))
	DirAccess.remove_absolute(blocker)
	DirAccess.remove_absolute(journal.storage_dir)
	var records_ui = load("res://scripts/ui/records.gd").new()
	root.add_child(records_ui)
	await process_frame
	assert(records_ui._tab_ids == ["attempts"], "Guests need training history without login")
	records_ui.queue_free()
	print("Training journal: checkpoints, dedup, reload, ownership, completion, failure/retry and guest UI passed")
	quit()
