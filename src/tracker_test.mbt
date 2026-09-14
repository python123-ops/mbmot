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
  assert_eq(result.removed(), [1])
}

///|
test "an empty frame closes current baseline identities" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(1, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  let empty = tracker.update(2, [])
  assert_eq(empty.tracks().length(), 0)
  assert_eq(empty.lost().length(), 0)
  assert_eq(empty.removed(), [1])
  let restarted = tracker.update(3, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)])
  assert_eq(restarted.tracks()[0].track_id(), 2)
}

///|
test "a skipped frame cannot silently bridge the last box" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  ignore(tracker.update(4, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)]))
  let result = tracker.update(6, [detection(0.0, 0.0, 10.0, 10.0, 0.95, 0)])
  assert_eq(result.removed(), [1])
  assert_eq(result.tracks()[0].track_id(), 2)
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
