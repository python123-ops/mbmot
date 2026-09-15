///|
test "replay session emits stable track and lifecycle fields" {
  let session = ReplaySession::new(@mbmot.TrackerConfig::default())
  let first = session.process_line(
    (
      #|{"frame":1,"detections":[{"xyxy":[0,0,10,10],"score":0.91,"class_id":0}]}
    ),
  )
  assert_eq(
    first,
    (
      #|{"frame":1,"tracks":[{"track_id":1,"xyxy":[0,0,10,10],"score":0.91,"class_id":0,"first_frame":1,"last_frame":1,"hits":1}],"lost":[],"removed":[]}
    ),
  )
  let empty = session.process_line(
    (
      #|{"frame":2,"detections":[]}
    ),
  )
  assert_eq(
    empty,
    (
      #|{"frame":2,"tracks":[],"lost":[1],"removed":[]}
    ),
  )
}

///|
test "replay errors carry physical line numbers and preserve tracker state" {
  let session = ReplaySession::new(@mbmot.TrackerConfig::default())
  ignore(
    session.process_line(
      (
        #|{"frame":1,"detections":[{"xyxy":[0,0,10,10],"score":0.9,"class_id":0}]}
      ),
    ),
  )
  try
    session.process_line(
      (
        #|{"frame":oops}
      ),
    )
  catch {
    error => {
      assert_eq(error.line(), 2)
      assert_true(error.message().has_prefix("line 2: invalid JSON:"))
    }
  } noraise {
    _ => fail("invalid JSON must stop this line")
  }
  let resumed = session.process_line(
    (
      #|{"frame":2,"detections":[{"xyxy":[0,0,10,10],"score":0.9,"class_id":0}]}
    ),
  )
  assert_true(
    resumed.contains(
      (
        #|"track_id":1
      ),
    ),
  )
  assert_true(
    resumed.contains(
      (
        #|"hits":2
      ),
    ),
  )
  assert_eq(session.lines_read(), 3)
}

///|
test "replay reports decreasing frame at its input line" {
  let session = ReplaySession::new(@mbmot.TrackerConfig::default())
  ignore(
    session.process_line(
      (
        #|{"frame":3,"detections":[]}
      ),
    ),
  )
  try
    session.process_line(
      (
        #|{"frame":2,"detections":[]}
      ),
    )
  catch {
    error =>
      assert_eq(
        error.message(),
        "line 2: frame must increase: previous 3, received 2",
      )
  } noraise {
    _ => fail("decreasing frame must be rejected")
  }
}
