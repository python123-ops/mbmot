///|
test "detector rows preserve frame order and validated values" {
  let input =
    #|1,-1,0,0,10,20,0.9,-1,-1,-1
    #|1,-1,30,4,8,9,0.4,-1,-1,-1
    #|2,-1,1,0,10,20,0.8,-1,-1,-1
  let parsed = @evaluation.parse_detections(input)
  assert_eq(parsed.length(), 3)
  assert_eq(parsed[0].frame(), 1)
  assert_eq(parsed[1].confidence(), 0.4)
  let (left, top, width, height) = parsed[2].bbox().to_xywh()
  assert_eq(left, 1.0)
  assert_eq(top, 0.0)
  assert_eq(width, 10.0)
  assert_eq(height, 20.0)
}

///|
test "seven-column detector rows are accepted" {
  let parsed = @evaluation.parse_detections(
    "1,-1,4,5,6,7,0.75\n2,-1,5,5,6,7,0.8",
  )
  assert_eq(parsed.length(), 2)
  assert_eq(parsed[0].frame(), 1)
  assert_eq(parsed[1].confidence(), 0.8)
}

///|
test "detector parser orders frames without changing within-frame order" {
  let input =
    #|2,-1,0,0,10,10,0.9,-1,-1,-1
    #|1,-1,4,0,10,10,0.8,-1,-1,-1
    #|1,-1,8,0,10,10,0.7,-1,-1,-1
  let parsed = @evaluation.parse_detections(input)
  assert_eq(parsed[0].frame(), 1)
  assert_eq(parsed[0].bbox().x1(), 4.0)
  assert_eq(parsed[1].bbox().x1(), 8.0)
  assert_eq(parsed[2].frame(), 2)
}

///|
test "detector parser rejects invalid boxes and confidence" {
  let invalid_box = "1,-1,0,0,0,10,0.9,-1,-1,-1"
  try @evaluation.parse_detections(invalid_box) catch {
    error =>
      inspect(
        error.message(),
        content="line 1: bounding box must have finite coordinates and positive size",
      )
  } noraise {
    _ => fail("zero-width boxes must be rejected")
  }
  let invalid_score = "1,-1,0,0,10,10,1.1,-1,-1,-1"
  try @evaluation.parse_detections(invalid_score) catch {
    error =>
      inspect(
        error.message(),
        content="line 1: MOT detection confidence must be in [0, 1]",
      )
  } noraise {
    _ => fail("out-of-range confidence must be rejected")
  }
}

///|
test "tracking detector rows produces deterministic MOT identities" {
  let input =
    #|1,-1,0,0,10,10,0.9,-1,-1,-1
    #|2,-1,1,0,10,10,0.9,-1,-1,-1
    #|2,-1,30,0,10,10,0.8,-1,-1,-1
    #|3,-1,2,0,10,10,0.9,-1,-1,-1
    #|3,-1,29,0,10,10,0.8,-1,-1,-1
  let detections = @evaluation.parse_detections(input)
  let tracked = @evaluation.track_detections(
    detections,
    @mbmot.TrackerConfig::default(),
  )
  inspect(
    @evaluation.encode_tracker_results(tracked),
    content=(
      #|1,1,0,0,10,10,0.9,-1,-1,-1
      #|2,1,1,0,10,10,0.9,-1,-1,-1
      #|2,2,30,0,10,10,0.8,-1,-1,-1
      #|3,1,2,0,10,10,0.9,-1,-1,-1
      #|3,2,29,0,10,10,0.8,-1,-1,-1
    ),
  )
}
