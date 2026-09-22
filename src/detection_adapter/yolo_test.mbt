///|
test "normalized and pixel center boxes produce the same replay frame" {
  let normalized = "{\"frame\":1,\"width\":100,\"height\":50,\"coordinates\":\"normalized\",\"detections\":[{\"cxcywh\":[0.5,0.5,0.4,0.4],\"score\":0.9,\"class_id\":2}]}"
  let pixels = "{\"frame\":1,\"width\":100,\"height\":50,\"coordinates\":\"pixels\",\"detections\":[{\"cxcywh\":[50,25,40,20],\"score\":0.9,\"class_id\":2}]}"
  let first = @detection_adapter.parse_yolo_frame(normalized)
  let second = @detection_adapter.parse_yolo_frame(pixels)
  assert_eq(
    @detection_adapter.encode_replay_frame(first),
    @detection_adapter.encode_replay_frame(second),
  )
  assert_eq(first.detections()[0].bbox().x1(), 30.0)
  assert_eq(first.detections()[0].bbox().y2(), 35.0)
}

///|
test "class filtering keeps valid selected detections in source order" {
  let input = "{\"frame\":1,\"width\":100,\"height\":50,\"coordinates\":\"pixels\",\"detections\":[{\"cxcywh\":[10,10,4,4],\"score\":0.8,\"class_id\":3},{\"cxcywh\":[20,20,4,4],\"score\":0.7,\"class_id\":1},{\"cxcywh\":[30,30,4,4],\"score\":0.6,\"class_id\":3}]}"
  let frame = @detection_adapter.parse_yolo_frame(input, class_ids=[3])
  assert_eq(frame.detections().length(), 2)
  assert_eq(frame.detections()[0].class_id(), 3)
  assert_eq(frame.detections()[0].bbox().x1(), 8.0)
  assert_eq(frame.detections()[1].bbox().x1(), 28.0)
}

///|
test "invalid input is rejected without advancing the frame" {
  let session = @detection_adapter.YoloSession::new()
  let frame_one = "{\"frame\":1,\"width\":100,\"height\":100,\"coordinates\":\"normalized\",\"detections\":[]}"
  let bad_frame = "{\"frame\":2,\"width\":100,\"height\":100,\"coordinates\":\"normalized\",\"detections\":[{\"cxcywh\":[0.9,0.5,0.4,0.2],\"score\":0.9,\"class_id\":0}]}"
  let good_frame = "{\"frame\":2,\"width\":100,\"height\":100,\"coordinates\":\"normalized\",\"detections\":[]}"
  ignore(session.process_line(frame_one))
  try session.process_line(bad_frame) catch {
    @detection_adapter.InvalidDetection(index=0, ..) => ()
    _ => fail("expected an invalid detection")
  } noraise {
    _ => fail("expected failure")
  }
  assert_eq(session.process_line(good_frame), "{\"frame\":2,\"detections\":[]}")
  try session.process_line(frame_one) catch {
    @detection_adapter.NonIncreasingFrame(previous=2, received=1) => ()
    _ => fail("expected a frame order error")
  } noraise {
    _ => fail("expected failure")
  }
  assert_eq(session.lines_read(), 4)
}

///|
test "filter cannot hide an invalid detection" {
  let input = "{\"frame\":1,\"width\":100,\"height\":100,\"coordinates\":\"pixels\",\"detections\":[{\"cxcywh\":[10,10,0,4],\"score\":0.8,\"class_id\":1}]}"
  try @detection_adapter.parse_yolo_frame(input, class_ids=[2]) catch {
    @detection_adapter.InvalidDetection(index=0, ..) => ()
    _ => fail("expected an invalid detection")
  } noraise {
    _ => fail("expected failure")
  }
  try @detection_adapter.YoloSession::new(class_ids=[1, 1]) catch {
    @detection_adapter.InvalidClassFilter(_) => ()
    _ => fail("expected invalid class filter")
  } noraise {
    _ => fail("expected failure")
  }
}
