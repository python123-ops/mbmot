///|
test "bounding boxes reject invalid coordinates" {
  try @mbmot.BoundingBox::new(0.0, 0.0, 0.0, 1.0) catch {
    _ => ()
  } noraise {
    _ => fail("expected a zero-width box to be rejected")
  }
  try @mbmot.BoundingBox::new(@double.not_a_number, 0.0, 1.0, 1.0) catch {
    _ => ()
  } noraise {
    _ => fail("expected NaN to be rejected")
  }
  try @mbmot.BoundingBox::new(0.0, 0.0, @double.infinity, 1.0) catch {
    _ => ()
  } noraise {
    _ => fail("expected infinity to be rejected")
  }
}

///|
test "detections reject invalid scores and class identifiers" {
  let bbox = @mbmot.BoundingBox::new(0.0, 0.0, 10.0, 10.0)
  try @mbmot.Detection::new(bbox, 1.01, 0) catch {
    _ => ()
  } noraise {
    _ => fail("expected score above one to be rejected")
  }
  try @mbmot.Detection::new(bbox, 0.5, -1) catch {
    _ => ()
  } noraise {
    _ => fail("expected a negative class id to be rejected")
  }
}
