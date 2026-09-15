///|
test "NDJSON line decodes a frame and ordered detections" {
  let parsed = parse_frame_line(
    (
      #|{"frame":7,"detections":[{"xyxy":[1,2,11,22],"score":0.91,"class_id":3},{"xyxy":[20,5,25,15],"score":0.4,"class_id":1}]}
    ),
  )
  assert_eq(parsed.frame(), 7)
  let detections = parsed.detections()
  assert_eq(detections.length(), 2)
  assert_eq(detections[0].bbox().to_xywh(), (1.0, 2.0, 10.0, 20.0))
  assert_eq(detections[0].score(), 0.91)
  assert_eq(detections[0].class_id(), 3)
  assert_eq(detections[1].class_id(), 1)
}

///|
test "NDJSON parser reports syntax and field context" {
  try
    parse_frame_line(
      (
        #|{"frame":1,
      ),
    )
  catch {
    InvalidJson(reason) => assert_true(reason.length() > 0)
    _ => fail("expected JSON syntax error")
  } noraise {
    _ => fail("malformed JSON must be rejected")
  }
  try
    parse_frame_line(
      (
        #|{"frame":1,"detections":[{"score":0.9,"class_id":0}]}
      ),
    )
  catch {
    InvalidFrame(reason) => assert_true(reason.contains("xyxy"))
    _ => fail("expected missing-field error")
  } noraise {
    _ => fail("missing xyxy must be rejected")
  }
}

///|
test "NDJSON parser identifies the invalid detection index" {
  try
    parse_frame_line(
      (
        #|{"frame":2,"detections":[{"xyxy":[0,0,10,10],"score":0.9,"class_id":0},{"xyxy":[0,0,0,10],"score":0.8,"class_id":0}]}
      ),
    )
  catch {
    InvalidDetection(index~, reason~) => {
      assert_eq(index, 1)
      assert_true(reason.contains("x2 > x1"))
    }
    _ => fail("expected detection validation error")
  } noraise {
    _ => fail("degenerate box must be rejected")
  }
}
