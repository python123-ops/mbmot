///|
fn detection(
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  score : Double,
  class_id : Int,
) -> @mbmot.Detection raise {
  @mbmot.Detection::new(
    @mbmot.BoundingBox::new(x1, y1, x2, y2),
    score,
    class_id,
  )
}

///|
fn configured_tracker(
  max_lost_frames : Int,
  min_hits : Int,
) -> @mbmot.Tracker raise {
  @mbmot.Tracker::new(
    @mbmot.TrackerConfig::new(
      high_score_threshold=0.25,
      low_score_threshold=0.10,
      new_track_threshold=0.25,
      first_match_max_cost=0.80,
      second_match_max_cost=0.50,
      max_lost_frames~,
      min_hits~,
      fuse_score=true,
    ),
  )
}

///|
test "default configuration exposes the documented cutoffs" {
  let config = @mbmot.TrackerConfig::default()
  assert_eq(config.high_score_threshold(), 0.25)
  assert_eq(config.low_score_threshold(), 0.10)
  assert_eq(config.new_track_threshold(), 0.25)
  assert_eq(config.first_match_max_cost(), 0.80)
  assert_eq(config.second_match_max_cost(), 0.50)
  assert_eq(config.max_lost_frames(), 30)
  assert_eq(config.min_hits(), 1)
  assert_true(config.fuse_score())
}

///|
test "configuration rejects reversed score cutoffs" {
  try
    @mbmot.TrackerConfig::new(
      high_score_threshold=0.2,
      low_score_threshold=0.3,
      new_track_threshold=0.2,
      first_match_max_cost=0.8,
      second_match_max_cost=0.5,
      max_lost_frames=30,
      min_hits=1,
      fuse_score=true,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected low score cutoff above high cutoff to be rejected")
  }
}

///|
test "nearby high-confidence detections keep one identity" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  let first = tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)])
  let second = tracker.update(2, [detection(0.5, 0.0, 10.5, 10.0, 0.90, 0)])
  assert_eq(first.tracks().length(), 1)
  assert_eq(first.tracks()[0].track_id(), 1)
  assert_eq(second.tracks().length(), 1)
  assert_eq(second.tracks()[0].track_id(), 1)
  assert_eq(second.tracks()[0].hits(), 2)
  assert_eq(second.removed().length(), 0)
}

///|
test "class boundaries prevent identity reuse" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  let result = tracker.update(2, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 1)])
  assert_eq(result.tracks()[0].track_id(), 2)
  assert_eq(result.tracks()[0].class_id(), 1)
  assert_eq(result.lost(), [1])
  assert_eq(result.removed().length(), 0)
}

///|
test "an empty frame loses and a high score recovers one identity" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  let empty = tracker.update(2, [])
  assert_eq(empty.tracks().length(), 0)
  assert_eq(empty.lost(), [1])
  assert_eq(empty.removed().length(), 0)
  let recovered = tracker.update(3, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)])
  assert_eq(recovered.tracks()[0].track_id(), 1)
  assert_eq(recovered.tracks()[0].first_frame(), 1)
  assert_eq(recovered.tracks()[0].last_frame(), 3)
  assert_eq(recovered.tracks()[0].hits(), 2)
}

///|
test "a skipped frame advances motion and recovers within the lost window" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(4, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  let result = tracker.update(6, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)])
  assert_eq(result.lost().length(), 0)
  assert_eq(result.removed().length(), 0)
  assert_eq(result.tracks()[0].track_id(), 1)
}

///|
test "a low score detection sustains an active identity" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)]))
  let result = tracker.update(2, [detection(0.2, 0.0, 10.2, 10.0, 0.15, 0)])
  assert_eq(result.tracks().length(), 1)
  assert_eq(result.tracks()[0].track_id(), 1)
  assert_eq(result.tracks()[0].score(), 0.15)
  assert_eq(result.tracks()[0].hits(), 2)
  assert_eq(result.lost().length(), 0)
}

///|
test "low score detections neither create nor consume an identity" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  let low_only = tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.15, 0)])
  assert_eq(low_only.tracks().length(), 0)
  let created = tracker.update(2, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)])
  assert_eq(created.tracks()[0].track_id(), 1)
}

///|
test "a low score detection cannot reactivate a lost identity" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)]))
  assert_eq(tracker.update(2, []).lost(), [1])
  let low = tracker.update(3, [detection(0.0, 0.0, 10.0, 10.0, 0.15, 0)])
  assert_eq(low.tracks().length(), 0)
  assert_eq(low.lost().length(), 0)
  let recovered = tracker.update(4, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)])
  assert_eq(recovered.tracks()[0].track_id(), 1)
  assert_eq(recovered.tracks()[0].hits(), 2)
}

///|
test "motion prediction recovers fast movement after one blank frame" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  ignore(tracker.update(2, [detection(4.0, 0.0, 14.0, 10.0, 0.95, 0)]))
  assert_eq(tracker.update(3, []).lost(), [1])
  let recovered = tracker.update(4, [detection(11.0, 0.0, 21.0, 10.0, 0.95, 0)])
  assert_eq(recovered.tracks().length(), 1)
  assert_eq(recovered.tracks()[0].track_id(), 1)
  assert_eq(recovered.tracks()[0].hits(), 3)
}

///|
test "lost identities expire once and removed ids are not reused" {
  let tracker = configured_tracker(2, 1)
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)]))
  assert_eq(tracker.update(2, []).lost(), [1])
  let retained = tracker.update(3, [])
  assert_eq(retained.lost().length(), 0)
  assert_eq(retained.removed().length(), 0)
  let expired = tracker.update(4, [])
  assert_eq(expired.lost().length(), 0)
  assert_eq(expired.removed(), [1])
  let quiet = tracker.update(5, [])
  assert_eq(quiet.removed().length(), 0)
  let replacement = tracker.update(6, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)])
  assert_eq(replacement.tracks()[0].track_id(), 2)
}

///|
test "zero lost window removes without also reporting lost" {
  let tracker = configured_tracker(0, 1)
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)]))
  let result = tracker.update(2, [])
  assert_eq(result.lost().length(), 0)
  assert_eq(result.removed(), [1])
}

///|
test "frame gaps and explicit empty frames reach the same state" {
  let explicit = configured_tracker(2, 1)
  let jumped = configured_tracker(2, 1)
  let first = detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)
  ignore(explicit.update(1, [first]))
  ignore(jumped.update(1, [first]))
  ignore(explicit.update(2, []))
  ignore(explicit.update(3, []))
  let current = detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)
  let explicit_result = explicit.update(4, [current])
  let jumped_result = jumped.update(4, [current])
  assert_eq(explicit_result, jumped_result)
  assert_eq(jumped_result.tracks()[0].track_id(), 1)
}

///|
test "a gap beyond the lost window silently expires intermediate state" {
  let tracker = configured_tracker(1, 1)
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)]))
  let result = tracker.update(4, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)])
  assert_eq(result.tracks()[0].track_id(), 2)
  assert_eq(result.lost().length(), 0)
  assert_eq(result.removed().length(), 0)
}

///|
test "tentative identities require consecutive high score hits" {
  let confirmed = configured_tracker(30, 2)
  let first = confirmed.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)])
  assert_eq(first.tracks().length(), 0)
  let second = confirmed.update(2, [detection(0.2, 0.0, 10.2, 10.0, 0.90, 0)])
  assert_eq(second.tracks()[0].track_id(), 1)
  assert_eq(second.tracks()[0].hits(), 2)
  let rejected = configured_tracker(30, 2)
  ignore(rejected.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)]))
  let low = rejected.update(2, [detection(0.0, 0.0, 10.0, 10.0, 0.15, 0)])
  assert_eq(low.tracks().length(), 0)
  assert_eq(low.lost().length(), 0)
  assert_eq(low.removed(), [1])
  let replacement = rejected.update(3, [
    detection(0.0, 0.0, 10.0, 10.0, 0.90, 0),
  ])
  assert_eq(replacement.tracks().length(), 0)
  let visible = rejected.update(4, [detection(0.0, 0.0, 10.0, 10.0, 0.90, 0)])
  assert_eq(visible.tracks()[0].track_id(), 2)
}

///|
test "motion keeps ids when same-class targets cross and input order reverses" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(
    tracker.update(1, [
      detection(0.0, 0.0, 10.0, 10.0, 0.95, 0),
      detection(20.0, 4.0, 30.0, 14.0, 0.95, 0),
    ]),
  )
  ignore(
    tracker.update(2, [
      detection(4.0, 0.0, 14.0, 10.0, 0.95, 0),
      detection(16.0, 4.0, 26.0, 14.0, 0.95, 0),
    ]),
  )
  ignore(
    tracker.update(3, [
      detection(8.0, 0.0, 18.0, 10.0, 0.95, 0),
      detection(12.0, 4.0, 22.0, 14.0, 0.95, 0),
    ]),
  )
  let crossed = tracker.update(4, [
    detection(8.0, 4.0, 18.0, 14.0, 0.95, 0),
    detection(12.0, 0.0, 22.0, 10.0, 0.95, 0),
  ])
  assert_eq(crossed.tracks().length(), 2)
  assert_eq(crossed.tracks()[0].track_id(), 1)
  assert_eq(crossed.tracks()[0].bbox().x1(), 12.0)
  assert_eq(crossed.tracks()[0].bbox().y1(), 0.0)
  assert_eq(crossed.tracks()[1].track_id(), 2)
  assert_eq(crossed.tracks()[1].bbox().x1(), 8.0)
  assert_eq(crossed.tracks()[1].bbox().y1(), 4.0)
}

///|
test "a rejected frame leaves identity state untouched" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  try tracker.update(1, []) catch {
    _ => ()
  } noraise {
    _ => fail("expected a repeated frame id to be rejected")
  }
  let result = tracker.update(2, [detection(0.2, 0.0, 10.2, 10.0, 0.95, 0)])
  assert_eq(result.tracks()[0].track_id(), 1)
  assert_eq(result.tracks()[0].hits(), 2)
}

///|
test "reset restarts frame acceptance and identity numbering" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(10, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  tracker.reset()
  let result = tracker.update(1, [detection(20.0, 0.0, 30.0, 10.0, 0.95, 0)])
  assert_eq(result.tracks()[0].track_id(), 1)
}
