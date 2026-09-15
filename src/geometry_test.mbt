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

///|
test "bounding box converts detector coordinate formats" {
  let top_left = @mbmot.BoundingBox::from_xywh(10.0, 20.0, 8.0, 4.0)
  assert_eq(top_left.to_xywh(), (10.0, 20.0, 8.0, 4.0))
  assert_eq(top_left.to_cxcywh(), (14.0, 22.0, 8.0, 4.0))
  let centered = @mbmot.BoundingBox::from_cxcywh(14.0, 22.0, 8.0, 4.0)
  assert_eq(centered.x1(), 10.0)
  assert_eq(centered.y1(), 20.0)
  assert_eq(centered.x2(), 18.0)
  assert_eq(centered.y2(), 24.0)
}

///|
test "coordinate adapters preserve bounding box validation" {
  try @mbmot.BoundingBox::from_xywh(0.0, 0.0, 0.0, 1.0) catch {
    @mbmot.InvalidBoundingBox(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("zero width must be rejected")
  }
  try @mbmot.BoundingBox::from_cxcywh(0.0, 0.0, -1.0, 1.0) catch {
    @mbmot.InvalidBoundingBox(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("negative width must be rejected")
  }
  try
    @mbmot.BoundingBox::from_cxcywh(@double.not_a_number, 0.0, 1.0, 1.0)
  catch {
    @mbmot.InvalidBoundingBox(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("non-finite center must be rejected")
  }
}
