extends "res://tests/test_case.gd"

const DIR := "user://test_community_scores/"
const PATH := DIR + "scores.json"
const SHA := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const OTHER_SHA := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


func test_enqueue_survives_restart_with_immutable_bytes_and_owner_isolation() -> void:
	var scores := _boot()
	var bytes := "first run".to_utf8_buffer()
	check(scores.enqueue("alice", "stage_1", SHA, bytes) == OK, "enqueue is durable before success")
	bytes[0] = 0
	check(scores.enqueue("bob", "stage_1", SHA, "bob run".to_utf8_buffer()) == OK, "another owner can queue the same hash")
	var disk := _disk()
	check(disk.entry("alice", SHA).get("revision") == 1, "revision survives restart")
	check(disk.snapshot("alice", SHA, 1).get_string_from_utf8() == "first run", "source mutations cannot change the snapshot")
	check(disk.snapshot("bob", SHA, 1).get_string_from_utf8() == "bob run", "owners never overwrite each other's replay")
	check(_files().size() == 2, "two owners have two snapshot files")
	_done()


func test_replacement_and_old_acknowledgment_cannot_erase_a_newer_best() -> void:
	var scores := _boot()
	scores.enqueue("alice", "stage_1", SHA, "old".to_utf8_buffer())
	scores.enqueue("bob", "stage_1", SHA, "bob".to_utf8_buffer())
	check(scores.enqueue("alice", "stage_1", SHA, "higher best".to_utf8_buffer()) == OK, "a newer best replaces the entry")
	check(scores.entries("alice").size() == 1 and scores.entry("alice", SHA).revision == 2, "replacement is one entry with a new revision")
	check(scores.settle("alice", SHA, 1) == OK and _disk().entry("alice", SHA).revision == 2, "old acknowledgment does not erase replacement")
	check(scores.snapshot("alice", SHA, 2).get_string_from_utf8() == "higher best", "replacement snapshot stays")
	check(_files().size() == 2, "old snapshot cleaned, current owners kept")
	check(scores.settle("alice", SHA, 2) == OK, "matching acknowledgment settles")
	check(scores.entries("alice").is_empty() and _files().size() == 1, "success deletes only acknowledged snapshot")
	check(scores.snapshot("bob", SHA, 1).get_string_from_utf8() == "bob", "other owner unaffected")
	check(scores.enqueue("alice", "stage_1", SHA, "next best".to_utf8_buffer()) == OK and scores.entry("alice", SHA).revision == 3, "revisions never repeat after settlement")
	check(scores.settle("alice", SHA, 2) == OK and scores.entry("alice", SHA).revision == 3, "late ack after a subsequent enqueue remains harmless")
	_done()


func test_failed_metadata_writes_preserve_previous_queue_and_snapshots() -> void:
	var scores := _boot()
	scores.enqueue("alice", "stage_1", SHA, "old".to_utf8_buffer())
	var before := FileAccess.get_file_as_bytes(PATH)
	# An occupied temporary filename causes a deterministic real write failure, including on privileged test runners.
	DirAccess.make_dir_recursive_absolute(PATH + ".tmp")
	check(scores.enqueue("alice", "stage_1", SHA, "new".to_utf8_buffer()) != OK, "enqueue must report failed persistence")
	check(scores.entry("alice", SHA).revision == 1 and _disk().entry("alice", SHA).revision == 1, "failed enqueue changes neither memory nor disk")
	check(scores.snapshot("alice", SHA, 1).get_string_from_utf8() == "old" and _files().size() == 1, "failed replacement removes only its new snapshot")
	check(scores.settle("alice", SHA, 1) != OK, "acknowledgment save failure is visible")
	check(scores.erase_owner("alice") != OK, "purge save failure is visible")
	check(FileAccess.get_file_as_bytes(PATH) == before and scores.snapshot("alice", SHA, 1).get_string_from_utf8() == "old", "failed settlement/purge never destroy previous queue data")
	DirAccess.remove_absolute(PATH + ".tmp")
	check(scores.erase_owner("alice") == OK and scores.entries("alice").is_empty(), "erasure can be retried")
	_done()


func test_snapshot_write_failure_cannot_replace_old_metadata() -> void:
	var scores := _boot()
	scores.enqueue("alice", "stage_1", SHA, "old".to_utf8_buffer())
	var replay := _files()[0]
	var held := FileAccess.get_file_as_bytes(replay)
	DirAccess.remove_absolute(replay)
	DirAccess.remove_absolute(CommunityScores.replay_dir(PATH))
	var blocker := FileAccess.open(CommunityScores.replay_dir(PATH).trim_suffix("/"), FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	check(scores.enqueue("alice", "stage_1", SHA, "new".to_utf8_buffer()) != OK, "snapshot failure refuses enqueue")
	check(_disk().entry("alice", SHA).revision == 1, "snapshot failure cannot advance metadata")
	DirAccess.remove_absolute(CommunityScores.replay_dir(PATH).trim_suffix("/"))
	DirAccess.make_dir_recursive_absolute(CommunityScores.replay_dir(PATH))
	var restored := FileAccess.open(replay, FileAccess.WRITE)
	restored.store_buffer(held)
	restored.close()
	check(scores.snapshot("alice", SHA, 1).get_string_from_utf8() == "old", "old metadata still names the original bytes")
	_done()


func test_erasure_removes_only_this_owner_and_late_ack_cannot_recreate_it() -> void:
	var scores := _boot()
	scores.enqueue("alice", "stage_1", SHA, "a".to_utf8_buffer())
	scores.enqueue("alice", "stage_2", OTHER_SHA, "b".to_utf8_buffer())
	scores.enqueue("bob", "stage_1", SHA, "c".to_utf8_buffer())
	check(scores.erase_owner("alice") == OK, "erase owner")
	check(scores.settle("alice", SHA, 1) == OK, "late acknowledgment is a no-op")
	check(_disk().entries("alice").is_empty() and _files().size() == 1, "metadata and both snapshots of erased owner gone")
	check(_disk().snapshot("bob", SHA, 1).get_string_from_utf8() == "c", "other owner's bytes survive")
	_done()


func test_corrupt_metadata_is_never_overwritten_and_damaged_snapshot_is_never_sent() -> void:
	var scores := _boot()
	scores.enqueue("alice", "stage_1", SHA, "old".to_utf8_buffer())
	var snapshot := FileAccess.open(_files()[0], FileAccess.WRITE)
	snapshot.store_string("different bytes")
	snapshot.close()
	check(scores.snapshot("alice", SHA, 1).is_empty(), "snapshot checksum detects corruption")
	var corrupt := FileAccess.open(PATH, FileAccess.WRITE)
	corrupt.store_string("not score metadata")
	corrupt.close()
	var reloaded := CommunityScores.new()
	reloaded.path = PATH
	check(reloaded.load_file() == ERR_INVALID_DATA, "bad metadata refused")
	check(reloaded.enqueue("alice", "stage_1", SHA, "new".to_utf8_buffer()) != OK, "unloaded outbox cannot be overwritten")
	check(FileAccess.get_file_as_string(PATH) == "not score metadata", "original corrupt data preserved for recovery")
	_done()


func _boot() -> CommunityScores:
	_wipe(DIR)
	return _disk()


func _disk() -> CommunityScores:
	var scores := CommunityScores.new()
	scores.path = PATH
	check(scores.load_file() == OK, "load score metadata")
	return scores


func _files() -> PackedStringArray:
	var files := PackedStringArray()
	var folder := CommunityScores.replay_dir(PATH)
	for name in DirAccess.get_files_at(folder):
		files.append(folder + name)
	return files


func _done() -> void:
	_wipe(DIR)


func _wipe(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub in DirAccess.get_directories_at(folder):
		_wipe(folder.path_join(sub))
		DirAccess.remove_absolute(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
