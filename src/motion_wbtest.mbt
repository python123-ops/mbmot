///|
test "xyah conversion round trips a detector box" {
  let bbox = BoundingBox::new(2.0, 3.0, 14.0, 11.0)
  let measurement = bbox_measurement(bbox)
  assert_eq(measurement[0], 8.0)
  assert_eq(measurement[1], 7.0)
  assert_eq(measurement[2], 1.5)
  assert_eq(measurement[3], 8.0)
  guard measurement_bbox(measurement) is Some(round_trip) else {
    fail("expected a valid round trip box")
  }
  assert_eq(round_trip, bbox)
}

///|
test "Kalman correction learns motion and keeps covariance usable" {
  let first = BoundingBox::new(0.0, 0.0, 10.0, 10.0)
  let shifted = BoundingBox::new(4.0, 0.0, 14.0, 10.0)
  let initial = MotionState::init(first)
  assert_true(initial.finite())
  assert_true(initial.positive_diagonal())
  let predicted = initial.predict(false)
  let corrected = predicted.correct(shifted)
  let next = corrected.predict(false)
  assert_true(corrected.finite())
  assert_true(corrected.positive_diagonal())
  assert_true(next.mean[0] > corrected.mean[0])
  assert_true(next.finite())
  assert_true(next.positive_diagonal())
}

///|
test "an unusable correction reinitializes from the observation" {
  let bbox = BoundingBox::new(5.0, 6.0, 15.0, 16.0)
  let broken : MotionState = {
    mean: FixedArray::make(8, 0.0),
    covariance: FixedArray::make(64, 0.0),
  }
  let recovered = broken.correct(bbox)
  assert_true(recovered.finite())
  assert_true(recovered.positive_diagonal())
  guard recovered.bbox() is Some(recovered_bbox) else {
    fail("expected reinitialized motion state to expose a box")
  }
  assert_eq(recovered_bbox, bbox)
}
