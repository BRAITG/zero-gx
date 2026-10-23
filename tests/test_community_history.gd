extends "res://tests/test_case.gd"
## Account-owned play history and feedback outbox (scripts/community_history.gd), saved to disk.
## Every test saves to FILE under DIR: `_open` empties the folder first, `_wipe` empties it again.
## The module is reached through `load`, so this file compiles without it and each test reports the
## missing module instead of quietly running nothing.

const SCRIPT := "res://scripts/community_history.gd"
const DIR := "user://test_community_history"
const FILE := DIR + "/history.json"
const FORMAT := "zero-gx-community-history"
const ALICE := "player_alice"
const BOB := "player_bob"
const LEVEL := "level_community"
const START := 1000  # ms
const END := 2000  # ms
const LOCKED := "the test folder could not be made unwritable (running as root?), so a failed save cannot be simulated"

var sha_a := "a".repeat(64)
var sha_b := "b".repeat(64)


func test_missing_file_loads_as_an_empty_history() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "a first run with no file must load without error")
	check(h.batch(ALICE).is_empty() and h.pending_votes(ALICE).is_empty(), "a first run has nothing pending")
	check(h.begin(ALICE, LEVEL, sha_a, START) != "", "a first run must be able to record an attempt")
	_wipe()


func test_start_and_finish_survive_reload_with_the_same_id_and_revision() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	check(id.length() == 32 and id == id.to_lower() and id.is_valid_hex_number(), "an attempt id is 32 lowercase hex characters: '%s'" % id)
	check(h.finish(ALICE, id, "failed", END) == OK, "the finish must save")
	var again = _reload(h)
	check(_same_snapshots(again.batch(ALICE), [_snapshot(id, START, 2, "failed", END)]), "after reload the record keeps its id, at revision 2: %s" % [again.batch(ALICE)])
	check(again.owner_for_attempt(id) == ALICE, "the starter still owns the attempt after reload")
	_wipe()


func test_file_declares_its_format_and_version() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	h.begin(ALICE, LEVEL, sha_a, START)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	check(saved is Dictionary and saved.get("format") == FORMAT and saved.get("version") == 1, "the file must declare %s version 1: %s" % [FORMAT, saved])
	_wipe()


func test_snapshots_keep_native_json_types_after_reload() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	var started := _first(_reload(h).batch(ALICE))
	check(started.get("started_ms") == START and started.get("revision") == 1, "time and revision reload with their values: %s" % [started])
	check(typeof(started.get("outcome")) == TYPE_NIL and typeof(started.get("ended_ms")) == TYPE_NIL, "a start has a null outcome and end, not an empty string or zero")
	check(h.finish(ALICE, id, "cleared", END) == OK, "finish")
	var cleared := _first(_reload(h).batch(ALICE))
	check(cleared.get("started_ms") == START and cleared.get("ended_ms") == END and cleared.get("revision") == 2, "times and revision reload with their values: %s" % [cleared])
	check(typeof(cleared.get("id")) == TYPE_STRING and typeof(cleared.get("sha256")) == TYPE_STRING and cleared.get("outcome") == "cleared", "ids, hashes and outcomes reload as strings")
	_wipe()


func test_malformed_start_is_refused_and_stores_nothing() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	check(h.begin("", LEVEL, sha_a, START) == "", "an attempt without an account must not be recorded")
	check(h.begin(ALICE, LEVEL, "short", START) == "", "a version hash must be 64 characters")
	check(h.begin(ALICE, LEVEL, "g".repeat(64), START) == "", "a version hash must be hexadecimal")
	check(h.begin(ALICE, LEVEL, sha_a, -1) == "", "a negative start time must be refused")
	check(h.batch(ALICE).is_empty() and not FileAccess.file_exists(FILE), "refused starts reach neither the outbox nor the disk")
	_wipe()


func test_finish_refuses_bad_outcomes_times_and_unknown_attempts() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	check(h.finish(ALICE, id, "bogus", END) != OK, "only failed, abandoned and cleared are outcomes")
	check(h.finish(ALICE, id, "cleared", START - 1) != OK, "an end before the start must be refused")
	check(h.finish(ALICE, "f".repeat(32), "cleared", END) != OK, "a finish without its start must be refused")
	check(_same_snapshots(h.batch(ALICE), [_snapshot(id, START, 1, null, null)]), "refused finishes change nothing: %s" % [h.batch(ALICE)])
	check(h.finish(ALICE, id, "cleared", START) == OK, "an end equal to the start is a valid instant")
	check(_same_snapshots(h.batch(ALICE), [_snapshot(id, START, 2, "cleared", START)]), "the valid finish is pending as revision 2")
	_wipe()


func test_duplicate_finish_changes_nothing_and_conflicts_keep_the_first_outcome() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	check(h.finish(ALICE, id, "failed", END) == OK, "first finish")
	var first := _snapshot(id, START, 2, "failed", END)
	h.finish(ALICE, id, "failed", END)  # a retried finish is the same fact
	check(_same_snapshots(h.batch(ALICE), [first]), "an identical finish must not bump the revision: %s" % [h.batch(ALICE)])
	for conflict in [["cleared", END], ["failed", END + 100], ["abandoned", END]]:
		check(h.finish(ALICE, id, conflict[0], conflict[1]) != OK, "%s at %d conflicts with the first finish" % conflict)
		check(_same_snapshots(h.batch(ALICE), [first]), "%s at %d must not overwrite the first finish" % conflict)
	check(_same_snapshots(_reload(h).batch(ALICE), [first]), "after reload the first finish is still the one saved")
	_wipe()


func test_finish_from_another_account_is_refused_and_ownership_stays() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	check(h.finish(BOB, id, "cleared", END) != OK, "another account must not finish this attempt")
	check(h.owner_for_attempt(id) == ALICE and h.owner_for_attempt("f".repeat(32)) == "", "the starter stays the owner; an unknown attempt has none")
	check(h.batch(BOB).is_empty(), "the other account gets no record from it")
	check(_same_snapshots(h.batch(ALICE), [_snapshot(id, START, 1, null, null)]), "the starter's record is untouched")
	check(h.finish(ALICE, id, "cleared", END) == OK, "the starter can still finish it")
	check(_reload(h).owner_for_attempt(id) == ALICE, "ownership survives reload")
	_wipe()


func test_batch_captures_revision_one_and_acknowledging_it_keeps_revision_two() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	var sent = h.batch(ALICE)  # the upload in flight holds revision 1
	check(h.finish(ALICE, id, "cleared", END) == OK, "finish")
	check(_same_snapshots(sent, [_snapshot(id, START, 1, null, null)]), "a captured batch must not change when the attempt finishes: %s" % [sent])
	check(h.acknowledge(ALICE, _reply([{"id": id, "revision": 1}])) == OK, "acknowledge revision 1")
	check(_same_snapshots(h.batch(ALICE), [_snapshot(id, START, 2, "cleared", END)]), "a stale acknowledgment leaves revision 2 pending: %s" % [h.batch(ALICE)])
	_wipe()


func test_lost_response_resend_sends_the_same_id() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	var sent = h.batch(ALICE)  # the acknowledgment never arrives
	check(_same_snapshots(_reload(h).batch(ALICE), sent) and _same_snapshots(sent, [_snapshot(id, START, 1, null, null)]), "a resend after a restart carries the same id and revision")
	h.finish(ALICE, id, "cleared", END)
	check(_same_snapshots(_reload(h).batch(ALICE), [_snapshot(id, START, 2, "cleared", END)]), "the finish keeps the same id")
	_wipe()


func test_acknowledging_the_clear_empties_the_outbox_but_keeps_the_history() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	h.finish(ALICE, id, "cleared", END)
	check(h.acknowledge(ALICE, _reply([{"id": id, "revision": 2}])) == OK, "acknowledge revision 2")
	check(h.batch(ALICE).is_empty(), "an acknowledged revision leaves the outbox")
	check(h.owner_for_attempt(id) == ALICE, "the attempt stays in history")
	check(h.begin(ALICE, LEVEL, sha_a, START + 1000) == "", "a cleared version records no new attempt")
	check(h.begin(ALICE, LEVEL, sha_b, START + 1000) != "", "a clear of one version does not stop another version")
	var again = _reload(h)
	check(not _ids(again.batch(ALICE)).has(id) and again.owner_for_attempt(id) == ALICE, "after reload the clear stays out of the outbox but in history")
	check(again.begin(ALICE, LEVEL, sha_a, START + 1000) == "", "after reload a cleared version still records no new attempt")
	_wipe()


func test_starting_again_after_a_known_clear_yields_no_record() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	h.finish(ALICE, id, "cleared", END)
	var again = _reload(h)
	check(again.begin(ALICE, LEVEL, sha_a, START + 1000) == "", "a clear saved before a restart still stops new starts")
	check(_same_snapshots(again.batch(ALICE), [_snapshot(id, START, 2, "cleared", END)]), "no record was added: %s" % [again.batch(ALICE)])
	_wipe()


func test_server_reported_clear_stops_new_starts_for_that_version() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	check(h.acknowledge(ALICE, _reply([], [], [sha_a])) == OK, "a reply may report a clear")
	check(h.begin(ALICE, LEVEL, sha_a, START) == "", "a version the server reports cleared records no attempt")
	check(h.begin(ALICE, LEVEL, sha_b, START) != "", "other versions still record")
	check(_reload(h).begin(ALICE, LEVEL, sha_a, START) == "", "the reported clear survives a restart")
	_wipe()


func test_unfinished_start_survives_restart_and_is_not_a_clear() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	var again = _reload(h)
	check(_same_snapshots(again.batch(ALICE), [_snapshot(id, START, 1, null, null)]), "an unfinished start is pending as revision 1: %s" % [again.batch(ALICE)])
	var second: String = again.begin(ALICE, LEVEL, sha_a, START + 1000)
	check(second != "" and second != id, "an unfinished start is not a clear, so the next attempt records")
	var last = _reload(again)
	check(last.batch(ALICE).size() == 2 and _ids(last.batch(ALICE)).has(id) and _ids(last.batch(ALICE)).has(second), "both starts are pending after another restart")
	_wipe()


func test_acknowledgement_from_a_json_reply_matches_integer_revisions() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	h.finish(ALICE, id, "cleared", END)
	var body: String = '{"acknowledged": [{"id": "%s", "revision": 2}], "discarded": [], "cleared": ["%s"]}' % [id, sha_a]
	check(h.acknowledge(ALICE, JSON.parse_string(body)) == OK, "a server reply parsed from JSON must be accepted")
	check(h.batch(ALICE).is_empty(), "revision 2 from JSON must clear the record it names")
	_wipe()


func test_discarded_records_leave_the_outbox_and_keep_the_history() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	h.finish(ALICE, id, "cleared", END)
	h.acknowledge(ALICE, _reply([], [{"id": id, "revision": 1, "reason": "conflict"}]))
	check(_same_snapshots(h.batch(ALICE), [_snapshot(id, START, 2, "cleared", END)]), "discarding a stale revision keeps the newer one pending")
	h.acknowledge(ALICE, _reply([], [{"id": id, "revision": 2, "reason": "hidden_version"}]))
	check(h.batch(ALICE).is_empty(), "a discarded record leaves the outbox so it cannot block the rest")
	var again = _reload(h)
	check(again.batch(ALICE).is_empty() and again.owner_for_attempt(id) == ALICE, "after reload it stays out of the outbox and in history")
	_wipe()


func test_acknowledgement_from_another_account_is_ignored() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	h.acknowledge(BOB, _reply([{"id": id, "revision": 1}], [], [sha_a]))
	check(_same_snapshots(h.batch(ALICE), [_snapshot(id, START, 1, null, null)]), "another account's acknowledgment must not clear this record")
	check(h.begin(ALICE, LEVEL, sha_a, START + 1000) != "", "another account's reported clear must not stop this account")
	_wipe()


func test_batch_holds_at_most_32_and_the_rest_follow() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var ids := {}
	for i in 33:
		ids[h.begin(ALICE, LEVEL, sha_a, START + i)] = true
	check(ids.size() == 33 and not ids.has(""), "each start gets its own id")
	var first = h.batch(ALICE)
	var sent := _ids(first)
	var distinct := {}
	for id in sent:
		distinct[id] = true
	check(first.size() == 32 and distinct.size() == 32 and ids.has_all(sent), "a batch holds 32 distinct started attempts, not %d" % first.size())
	check(h.acknowledge(ALICE, _reply(first.map(func(s): return {"id": s.get("id"), "revision": 1}))) == OK, "acknowledge the batch")
	var rest = h.batch(ALICE)
	check(rest.size() == 1 and not sent.has(rest[0].get("id")), "the 33rd attempt follows once the first 32 are acknowledged")
	_wipe()


func test_vote_keeps_only_the_latest_desired_value_and_a_rising_revision() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	check(h.queue_like(ALICE, LEVEL, true) == OK, "queue a like")
	var key: String = _find(h.pending_votes(ALICE), "like", "").get("key", "")
	check(key != "", "a queued like needs a key")
	h.queue_like(ALICE, LEVEL, false)
	var again = _reload(h)
	var like = _find(again.pending_votes(ALICE), "like", "")
	check(again.pending_votes(ALICE).size() == 1 and like.get("key") == key and like.get("revision") == 2 and like.get("value") == false, "only the latest desired value is pending, under the same key: %s" % [like])
	again.ack_vote(ALICE, key, 1)  # a stale acknowledgment of the first like
	again = _reload(again)
	like = _find(again.pending_votes(ALICE), "like", "")
	check(like.get("revision") == 2 and like.get("value") == false, "a stale acknowledgment must not remove the newer desired value")
	again.ack_vote(ALICE, key, 2)
	check(again.pending_votes(ALICE).is_empty(), "acknowledging the current revision clears the queue")
	again.queue_like(ALICE, LEVEL, true)
	like = _find(again.pending_votes(ALICE), "like", "")
	check(like.get("key") == key and like.get("revision") == 3 and like.get("value") == true, "after an acknowledgment the next change keeps the key and continues the revision: %s" % [like])
	_wipe()


func test_difficulty_votes_are_one_per_version_and_invalid_values_are_refused() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	check(h.queue_difficulty(ALICE, LEVEL, sha_a, "hard") == OK, "queue a difficulty for version a")
	check(h.queue_difficulty(ALICE, LEVEL, sha_b, "easy") == OK, "queue a difficulty for version b")
	check(h.queue_difficulty(ALICE, LEVEL, sha_a, "expert") == OK, "change version a's vote")
	check(h.queue_difficulty(ALICE, LEVEL, sha_a, "legendary") != OK, "an unknown difficulty must be refused")
	var votes = h.pending_votes(ALICE)
	var a = _find(votes, "difficulty", sha_a)
	var b = _find(votes, "difficulty", sha_b)
	check(votes.size() == 2, "one editable vote per version, so 2 queued votes, not %d" % votes.size())
	check(a.get("value") == "expert" and a.get("revision") == 2, "version a keeps only its latest vote: %s" % [a])
	check(b.get("value") == "easy" and b.get("revision") == 1, "version b's vote is independent of version a: %s" % [b])
	check(_reload(h).pending_votes(ALICE).size() == 2, "both votes survive a restart")
	_wipe()


func test_emptied_difficulty_vote_is_sent_as_a_removal() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	h.queue_difficulty(ALICE, LEVEL, sha_a, "hard")
	var key: String = _find(h.pending_votes(ALICE), "difficulty", sha_a).get("key", "")
	h.ack_vote(ALICE, key, 1)
	check(h.pending_votes(ALICE).is_empty(), "an acknowledged vote leaves the queue")
	check(h.queue_difficulty(ALICE, LEVEL, sha_a, "") == OK, "an empty value removes the vote")
	var removal := _find(_reload(h).pending_votes(ALICE), "difficulty", sha_a)
	check(removal.get("key") == key and removal.get("value") == "" and removal.get("revision") == 2, "the removal is queued under the same key, as revision 2: %s" % [removal])
	_wipe()


func test_queued_votes_carry_what_the_sender_needs() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	h.queue_like(ALICE, LEVEL, true)
	h.queue_difficulty(ALICE, LEVEL, sha_a, "normal")
	var votes = _reload(h).pending_votes(ALICE)
	var like = _find(votes, "like", "")
	var difficulty = _find(votes, "difficulty", sha_a)
	check(like.get("level") == LEVEL and typeof(like.get("value")) == TYPE_BOOL and like.get("value") == true and like.get("revision") == 1, "a like names its level, value and revision: %s" % [like])
	check(difficulty.get("level") == LEVEL and difficulty.get("value") == "normal" and difficulty.get("revision") == 1, "a difficulty names its level, version, value and revision: %s" % [difficulty])
	check(typeof(like.get("key")) == TYPE_STRING and like.get("key") != "" and like.get("key") != difficulty.get("key"), "each vote has its own non-empty string key")
	_wipe()


func test_erasing_one_account_leaves_the_other_intact() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var ids := _seed_two_accounts(h)
	check(ids["b"] != "", "another account's clear must not stop this account from starting")
	check(_same_snapshots(h.batch(BOB), [_snapshot(ids["b"], START + 1000, 1, null, null)]), "before erasure, account B sees only its own start: %s" % [h.batch(BOB)])
	check(h.pending_votes(BOB).size() == 1 and h.progress(BOB, LEVEL, sha_a).get("cleared") == false, "before erasure, account B sees none of A's votes or feedback")
	check(h.erase_owner(ALICE) == OK, "erasing an account must save")
	var again = _reload(h)
	check(again.batch(ALICE).is_empty() and again.pending_votes(ALICE).is_empty() and again.progress(ALICE, LEVEL, sha_a).is_empty(), "the erased account keeps no queued data or cached feedback")
	check(again.owner_for_attempt(ids["a"]) == "", "an erased attempt has no owner")
	check(_same_snapshots(again.batch(BOB), [_snapshot(ids["b"], START + 1000, 1, null, null)]), "the other account's start is intact")
	check(_find(again.pending_votes(BOB), "like", "").get("value") == false, "the other account's vote is intact")
	check(again.progress(BOB, LEVEL, sha_a).get("attempts") == 4 and again.owner_for_attempt(ids["b"]) == BOB, "the other account's feedback and ownership are intact")
	_wipe()


func test_late_ack_and_finish_for_an_erased_account_recreate_nothing() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var ids := _seed_two_accounts(h)
	var like_key: String = _find(h.pending_votes(ALICE), "like", "").get("key", "")
	var in_flight: String = h.begin(ALICE, LEVEL, sha_b, START + 2000)
	check(in_flight != "", "control: the account has a start in flight")
	check(h.erase_owner(ALICE) == OK, "erasing an account must save")
	h.acknowledge(ALICE, _reply([{"id": in_flight, "revision": 1}], [], [sha_b]))
	h.ack_vote(ALICE, like_key, 1)
	h.finish(ALICE, in_flight, "cleared", START + 3000)  # the attempt's end arrives after erasure
	var again = _reload(h)
	check(again.batch(ALICE).is_empty() and again.pending_votes(ALICE).is_empty(), "late acknowledgments and finishes must not recreate the erased outbox")
	check(again.owner_for_attempt(in_flight) == "" and again.owner_for_attempt(ids["a"]) == "", "erased attempts have no owner")
	check(again.progress(ALICE, LEVEL, sha_a).is_empty(), "late acknowledgments must not recreate cached feedback")
	check(again.begin(ALICE, LEVEL, sha_b, START + 4000) != "", "a late server clear must not leave the erased account with a clear")
	_wipe()


func test_late_clear_replaces_the_cached_summary_instead_of_adding_to_it() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	check(h.confirm_progress(ALICE, LEVEL, sha_a, _you(3, false)) == OK, "the first feedback reply must save")
	check(h.confirm_progress(ALICE, LEVEL, sha_a, _you(1, true, "hard")) == OK, "the recomputed reply after an older offline clear must save")
	var again = _reload(h)
	var progress = again.progress(ALICE, LEVEL, sha_a)
	check(progress.get("attempts") == 1, "the summary is replaced, not added to: %s" % [progress])
	check(progress.get("cleared") == true and progress.get("difficulty") == "hard" and typeof(progress.get("difficulty")) == TYPE_STRING, "the replacement's clear and vote reload with native types: %s" % [progress])
	check(again.progress(ALICE, LEVEL, sha_b).is_empty(), "another version has no cached summary")
	check(again.progress(BOB, LEVEL, sha_a).is_empty(), "another account has no cached summary")
	_wipe()


func test_corrupt_file_is_left_untouched_and_counting_stops() -> void:
	var source = _open()
	if source == null:
		return
	check(source.load_file() == OK, "a first run must load before it records anything")
	var id: String = source.begin(ALICE, LEVEL, sha_a, START)
	check(id != "", "a saved start must give an attempt id to damage")
	var real: PackedByteArray = FileAccess.get_file_as_bytes(FILE)
	check(not real.is_empty(), "the history must be saved before it is damaged")
	check(_same_snapshots(_reload(source).batch(ALICE), [_snapshot(id, START, 1, null, null)]), "the undamaged revision-1 record must load")
	var saved = JSON.parse_string(real.get_string_from_utf8())
	if typeof(saved) != TYPE_DICTIONARY:
		check(false, "the saved history must parse as a JSON object")
		return
	var cases := {
		"not_json": "{not json".to_utf8_buffer(),
		"array_root": "[1, 2]".to_utf8_buffer(),
		"other_format": '{"format": "other-game", "version": 1}'.to_utf8_buffer(),
		"future_version": '{"format": "zero-gx-community-history", "version": 2}'.to_utf8_buffer(),
		"truncated": real.slice(0, real.size() / 2),
	}
	for missing in ["outcome", "ended_ms"]:  # a revision-1 record must keep both terminal fields, even as null
		var damaged: Dictionary = saved.duplicate(true)
		damaged["owners"][ALICE]["attempts"][id].erase(missing)
		cases["revision_1_without_%s" % missing] = JSON.stringify(damaged).to_utf8_buffer()
	for name in cases:
		var h = _open()
		if h == null:
			return
		var before: PackedByteArray = cases[name]
		_write(FILE, before)
		check(h.load_file() != OK, "%s must not load" % name)
		check(h.begin(ALICE, LEVEL, sha_a, START) == "", "%s must not record attempts" % name)
		check(h.queue_like(ALICE, LEVEL, true) != OK, "%s must not queue votes" % name)
		check(FileAccess.get_file_as_bytes(FILE) == before, "%s must keep its bytes" % name)
	_wipe()


func test_failed_first_save_records_nothing() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	if not _lock(FILE):
		return
	check(h.begin(ALICE, LEVEL, sha_a, START) == "", "an attempt that cannot be saved must not get an id")
	check(not FileAccess.file_exists(FILE), "a failed save must leave no file")
	_unlock(FILE)
	check(h.batch(ALICE).is_empty(), "a failed save must not leave a pending record in memory")
	check(h.begin(ALICE, LEVEL, sha_a, START) != "", "once the folder is writable again, the next attempt records")
	_wipe()


func test_failed_save_keeps_the_existing_bytes_and_state() -> void:
	var h = _open()
	if h == null:
		return
	check(h.load_file() == OK, "load")
	var id: String = h.begin(ALICE, LEVEL, sha_a, START)
	var saved: PackedByteArray = FileAccess.get_file_as_bytes(FILE)
	var last := [_snapshot(id, START, 1, null, null)]
	if not _lock(FILE):
		return
	check(h.begin(ALICE, LEVEL, sha_a, END) == "", "a start that cannot be saved must not get an id")
	check(h.finish(ALICE, id, "cleared", END) != OK, "a finish that cannot be saved must fail")
	check(h.queue_like(ALICE, LEVEL, true) != OK, "a vote that cannot be saved must fail")
	check(_same_snapshots(h.batch(ALICE), last), "memory keeps the last saved state: %s" % [h.batch(ALICE)])
	check(FileAccess.get_file_as_bytes(FILE) == saved, "the file keeps its bytes")
	_unlock(FILE)
	var again = _reload(h)
	check(_same_snapshots(again.batch(ALICE), last), "a reload sees the last saved state")
	check(again.finish(ALICE, id, "cleared", END) == OK, "once the folder is writable again, the finish saves")
	_wipe()


## A fresh history saved to FILE, or null (and a failure) when the module is missing or broken.
func _open():
	var module = load(SCRIPT)
	if module == null or not module.can_instantiate():
		check(false, "%s is missing or does not compile" % SCRIPT)
		return null
	_wipe()
	DirAccess.make_dir_recursive_absolute(DIR)
	var history = module.new()
	history.path = FILE
	return history


## A new instance on the same file, loaded from disk as the app does at start-up.
func _reload(before):
	var again = load(SCRIPT).new()
	again.path = before.path
	check(again.load_file() == OK, "the saved file must load again")
	return again


func _wipe() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	_chmod(DIR, 493)  # rwxr-xr-x: a locked folder must still be emptied
	for file in DirAccess.get_files_at(DIR):
		_chmod(DIR + "/" + file, 420)
		DirAccess.remove_absolute(DIR + "/" + file)
	DirAccess.remove_absolute(DIR)


func _chmod(path: String, mode: int) -> void:
	FileAccess.set_unix_permissions(ProjectSettings.globalize_path(path), mode)


## Makes the folder and the file unwritable so every save fails. Returns false (and a failure) when
## the platform ignores permissions, as root does, because then the save would succeed.
func _lock(path: String) -> bool:
	_chmod(path.get_base_dir(), 365)  # r-x: nothing can be created or renamed inside
	if FileAccess.file_exists(path):
		_chmod(path, 292)  # r--
	var probe := FileAccess.open(path.get_base_dir() + "/probe.tmp", FileAccess.WRITE)
	if probe != null:
		probe.close()
		DirAccess.remove_absolute(path.get_base_dir() + "/probe.tmp")
		check(false, LOCKED)
		return false
	return true


func _unlock(path: String) -> void:
	_chmod(path.get_base_dir(), 493)
	if FileAccess.file_exists(path):
		_chmod(path, 420)


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


## Account A cleared a version and queued a like; account B started the same version, queued the opposite like and holds its own cached feedback.
func _seed_two_accounts(h) -> Dictionary:
	var a: String = h.begin(ALICE, LEVEL, sha_a, START)
	h.finish(ALICE, a, "cleared", END)
	h.queue_like(ALICE, LEVEL, true)
	h.confirm_progress(ALICE, LEVEL, sha_a, _you(1, true))
	var b: String = h.begin(BOB, LEVEL, sha_a, START + 1000)
	h.queue_like(BOB, LEVEL, false)
	h.confirm_progress(BOB, LEVEL, sha_a, _you(4, false))
	return {"a": a, "b": b}


func _reply(acknowledged: Array = [], discarded: Array = [], cleared: Array = []) -> Dictionary:
	return {"acknowledged": acknowledged, "discarded": discarded, "cleared": cleared}


## The snapshot a batch must hold for one attempt (Task 1 wire format).
func _snapshot(id: String, started: int, revision: int, outcome: Variant, ended: Variant) -> Dictionary:
	return {"id": id, "sha256": sha_a, "started_ms": started, "revision": revision, "outcome": outcome, "ended_ms": ended}


## Snapshot lists match when each holds exactly the expected keys and each value is `==` (so a whole number
## reloaded from JSON as a float equals the int it was saved from).
func _same_snapshots(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in expected.size():
		if actual[i].size() != expected[i].size():
			return false
		for key in expected[i]:
			if not actual[i].has(key) or actual[i][key] != expected[i][key]:
				return false
	return true


## The `you` block of a feedback reply for one version (Task 2).
func _you(attempts: int, cleared: bool, difficulty: Variant = null) -> Dictionary:
	return {"liked": false, "like_eligible": true, "difficulty": difficulty, "difficulty_eligible": true, "attempts": attempts, "cleared": cleared}


func _first(snapshots: Array) -> Dictionary:
	return snapshots[0] if not snapshots.is_empty() else {}


func _ids(snapshots: Array) -> Array:
	return snapshots.map(func(snapshot): return snapshot.get("id"))


## The queued vote of `kind` ("like" or "difficulty") for `sha`; a stage-wide like has no sha.
func _find(votes: Array, kind: String, sha: String) -> Dictionary:
	for vote in votes:
		if vote.get("kind") == kind and vote.get("sha", "") == sha:
			return vote
	return {}
