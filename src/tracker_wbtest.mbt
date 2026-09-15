///|
test "invalid internal detection does not consume a frame or identity" {
  let tracker = Tracker::new(TrackerConfig::default())
  let bbox = BoundingBox::new(0.0, 0.0, 10.0, 10.0)
  let invalid : Detection = { bbox, score: @double.not_a_number, class_id: 0, }
  try tracker.update(1, [invalid]) catch {
    _ => ()
  } noraise {
    _ => fail("expected invalid detection to be rejected")
  }
  let valid = Detection::new(bbox, 0.9, 0)
  let result = tracker.update(1, [valid])
  assert_eq(result.tracks()[0].track_id(), 1)
}
