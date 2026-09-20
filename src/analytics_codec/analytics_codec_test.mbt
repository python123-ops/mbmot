///|
fn setup_line(
  anchor? : String = "bottom_center",
  stable_frames? : Int = 1,
) -> String {
  "{\"config\":{\"anchor\":\"\{anchor}\",\"stable_frames\":\{stable_frames}},\"lines\":[{\"id\":4,\"start\":[5,0],\"end\":[5,10]}],\"regions\":[{\"id\":7,\"vertices\":[[0,0],[10,0],[10,10],[0,10]]}]}"
}

///|
fn frame_line(
  frame : Int,
  x : Double,
  track_id? : Int = 1,
  class_id? : Int = 0,
) -> String {
  "{\"frame\":\{frame},\"tracks\":[{\"track_id\":\{track_id},\"xyxy\":[\{x - 1.0},2,\{x + 1.0},5],\"class_id\":\{class_id}}],\"lost\":[],\"removed\":[]}"
}

///|
test "setup line creates rules without emitting a frame" {
  let session = AnalyticsReplaySession::new()
  assert_eq(session.process_line("   "), None)
  assert_eq(session.process_line(setup_line()), None)
  assert_eq(session.lines_read(), 2)
  let output = session.process_line(frame_line(1, -2.0))
  assert_true(output is Some(text) && text.contains("\"line_id\":4"))
  assert_true(output is Some(text) && text.contains("\"region_id\":7"))
}

///|
test "setup class filters separate line and region traffic" {
  let session = AnalyticsReplaySession::new()
  ignore(
    session.process_line(
      "{\"config\":{\"anchor\":\"bottom_center\",\"stable_frames\":1},\"lines\":[{\"id\":4,\"start\":[5,0],\"end\":[5,10],\"class_ids\":[1]}],\"regions\":[{\"id\":7,\"vertices\":[[0,0],[10,0],[10,10],[0,10]],\"class_ids\":[0]}]}",
    ),
  )
  ignore(
    session.process_line(
      "{\"frame\":1,\"tracks\":[{\"track_id\":1,\"xyxy\":[1,2,3,5],\"class_id\":1},{\"track_id\":2,\"xyxy\":[-3,2,-1,5],\"class_id\":0}],\"lost\":[],\"removed\":[]}",
    ),
  )
  let output = session.process_line(
    "{\"frame\":2,\"tracks\":[{\"track_id\":1,\"xyxy\":[6,2,8,5],\"class_id\":1},{\"track_id\":2,\"xyxy\":[1,2,3,5],\"class_id\":0}],\"lost\":[],\"removed\":[]}",
  )
  assert_true(
    output is Some(text) &&
    text.contains("\"type\":\"line_crossed\",\"line_id\":4,\"track_id\":1") &&
    text.contains("\"type\":\"region_entered\",\"region_id\":7,\"track_id\":2") &&
    !text.contains("\"line_id\":4,\"track_id\":2") &&
    !text.contains("\"region_id\":7,\"track_id\":1"),
  )
}

///|
test "invalid class filters retain rule index in setup errors" {
  let session = AnalyticsReplaySession::new()
  try
    session.process_line(
      "{\"config\":{\"anchor\":\"center\",\"stable_frames\":1},\"lines\":[{\"id\":4,\"start\":[0,0],\"end\":[1,0],\"class_ids\":[]}],\"regions\":[]}",
    )
  catch {
    error =>
      assert_eq(
        error.message(),
        "line 1: invalid line 0: invalid class filter: class_ids must not be empty",
      )
  } noraise {
    _ => fail("an empty class filter must be rejected")
  }
}

///|
test "frame output exposes deterministic region entry and occupancy" {
  let session = AnalyticsReplaySession::new()
  ignore(session.process_line(setup_line()))
  ignore(session.process_line(frame_line(1, -2.0)))
  let output = session.process_line(frame_line(2, 2.0))
  assert_eq(
    output,
    Some(
      "{\"frame\":2,\"events\":[{\"type\":\"region_entered\",\"region_id\":7,\"track_id\":1,\"initial\":false}],\"line_counts\":[{\"line_id\":4,\"left_to_right\":0,\"right_to_left\":0}],\"region_counts\":[{\"region_id\":7,\"entries\":1,\"exits\":0,\"unique_tracks\":1,\"current_occupancy\":1}],\"occupants\":[{\"region_id\":7,\"track_id\":1,\"class_id\":0,\"dwell_frames\":1}]}",
    ),
  )
}

///|
test "line crossings and region exits retain direction and dwell" {
  let session = AnalyticsReplaySession::new()
  ignore(session.process_line(setup_line()))
  ignore(session.process_line(frame_line(1, -2.0)))
  ignore(session.process_line(frame_line(2, 2.0)))
  let crossed = session.process_line(frame_line(3, 7.0))
  assert_true(
    crossed is Some(text) &&
    text.contains(
      "\"type\":\"line_crossed\",\"line_id\":4,\"track_id\":1,\"direction\":\"left_to_right\"",
    ),
  )
  let exited = session.process_line(frame_line(6, 12.0))
  assert_true(
    exited is Some(text) &&
    text.contains(
      "\"type\":\"region_exited\",\"region_id\":7,\"track_id\":1,\"dwell_frames\":4",
    ),
  )
}

///|
test "lost frames remove occupancy without duplicating an entry after recovery" {
  let session = AnalyticsReplaySession::new()
  ignore(session.process_line(setup_line()))
  ignore(session.process_line(frame_line(1, 2.0)))
  let lost = session.process_line(
    "{\"frame\":2,\"tracks\":[],\"lost\":[1],\"removed\":[]}",
  )
  assert_true(lost is Some(text) && text.contains("\"current_occupancy\":0"))
  let recovered = session.process_line(frame_line(3, 3.0))
  assert_true(recovered is Some(text) && text.contains("\"events\":[]"))
  assert_true(
    recovered is Some(text) && text.contains("\"current_occupancy\":1"),
  )
}

///|
test "center and bottom-center anchors can classify the same box differently" {
  let bottom = AnalyticsReplaySession::new()
  ignore(bottom.process_line(setup_line(anchor="bottom_center")))
  let bottom_output = bottom.process_line(
    "{\"frame\":1,\"tracks\":[{\"track_id\":1,\"xyxy\":[1,-4,3,2],\"class_id\":0}],\"lost\":[],\"removed\":[]}",
  )
  assert_true(bottom_output is Some(text) && text.contains("\"entries\":1"))
  let center = AnalyticsReplaySession::new()
  ignore(center.process_line(setup_line(anchor="center")))
  let center_output = center.process_line(
    "{\"frame\":1,\"tracks\":[{\"track_id\":1,\"xyxy\":[1,-4,3,2],\"class_id\":0}],\"lost\":[],\"removed\":[]}",
  )
  assert_true(center_output is Some(text) && text.contains("\"entries\":0"))
}

///|
test "invalid setup reports its physical line and can be retried" {
  let session = AnalyticsReplaySession::new()
  try session.process_line(setup_line(anchor="corner")) catch {
    error =>
      assert_eq(
        error.message(),
        "line 1: invalid setup: anchor must be center or bottom_center",
      )
  } noraise {
    _ => fail("unknown anchor must be rejected")
  }
  assert_eq(session.process_line(setup_line()), None)
  assert_eq(session.lines_read(), 2)
}

///|
test "invalid rule geometry includes rule kind and index" {
  let session = AnalyticsReplaySession::new()
  try
    session.process_line(
      "{\"config\":{\"anchor\":\"center\",\"stable_frames\":1},\"lines\":[{\"id\":4,\"start\":[1,1],\"end\":[1,1]}],\"regions\":[]}",
    )
  catch {
    error =>
      assert_eq(
        error.message(),
        "line 1: invalid line 0: invalid directed line: start and end must differ",
      )
  } noraise {
    _ => fail("degenerate line must be rejected")
  }
}

///|
test "invalid track does not advance analyzer state" {
  let session = AnalyticsReplaySession::new()
  ignore(session.process_line(setup_line()))
  try
    session.process_line(
      "{\"frame\":1,\"tracks\":[{\"track_id\":1,\"xyxy\":[0,0,0,4],\"class_id\":0}],\"lost\":[],\"removed\":[]}",
    )
  catch {
    error => {
      assert_eq(error.line(), 2)
      assert_true(error.message().contains("invalid track 0"))
    }
  } noraise {
    _ => fail("degenerate track box must be rejected")
  }
  let accepted = session.process_line(frame_line(1, -2.0))
  assert_true(accepted is Some(text) && text.contains("\"frame\":1"))
}

///|
test "analytics validation errors keep their input line" {
  let session = AnalyticsReplaySession::new()
  ignore(session.process_line(setup_line()))
  ignore(session.process_line(frame_line(3, -2.0)))
  try session.process_line(frame_line(2, -1.0)) catch {
    error =>
      assert_eq(
        error.message(),
        "line 3: frame must increase: previous 3, received 2",
      )
  } noraise {
    _ => fail("decreasing frame must be rejected")
  }
}

///|
test "malformed JSON is rejected before setup state changes" {
  let session = AnalyticsReplaySession::new()
  try session.process_line("{\"config\":") catch {
    error => assert_true(error.message().has_prefix("line 1: invalid JSON:"))
  } noraise {
    _ => fail("malformed JSON must be rejected")
  }
  assert_eq(session.process_line(setup_line()), None)
}

///|
test "a frame cannot be consumed before the rule setup" {
  let session = AnalyticsReplaySession::new()
  try session.process_line(frame_line(1, 2.0)) catch {
    error => {
      assert_eq(error.line(), 1)
      assert_true(error.message().has_prefix("line 1: invalid setup:"))
    }
  } noraise {
    _ => fail("first non-empty line must be a setup object")
  }
}

///|
test "duplicate rule identifiers are rejected during setup" {
  let session = AnalyticsReplaySession::new()
  try
    session.process_line(
      "{\"config\":{\"anchor\":\"center\",\"stable_frames\":1},\"lines\":[{\"id\":4,\"start\":[0,0],\"end\":[1,0]},{\"id\":4,\"start\":[0,1],\"end\":[1,1]}],\"regions\":[]}",
    )
  catch {
    error =>
      assert_eq(error.message(), "line 1: invalid setup: duplicate line id: 4")
  } noraise {
    _ => fail("duplicate line ids must be rejected")
  }
}

///|
test "visible and lost identity conflicts do not partially update a frame" {
  let session = AnalyticsReplaySession::new()
  ignore(session.process_line(setup_line()))
  ignore(session.process_line(frame_line(1, 2.0)))
  try
    session.process_line(
      "{\"frame\":2,\"tracks\":[{\"track_id\":1,\"xyxy\":[2,2,4,5],\"class_id\":0}],\"lost\":[1],\"removed\":[]}",
    )
  catch {
    error =>
      assert_eq(
        error.message(),
        "line 3: track_id appears in more than one frame collection: 1",
      )
  } noraise {
    _ => fail("one identity cannot be visible and lost")
  }
  let accepted = session.process_line(frame_line(2, 3.0))
  assert_true(accepted is Some(text) && text.contains("\"frame\":2"))
}
