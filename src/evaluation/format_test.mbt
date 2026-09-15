///|
test "ground truth parser skips zero-marked rows and accepts nine columns" {
  let rows = @evaluation.parse_ground_truth(
    (
      #|2,2,20,0,10,10,1,1,0.8
      #|1,1,0,0,10,10,1,1,1
      #|3,3,30,0,10,10,0,1,0.5
    ),
  )
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].frame(), 1)
  assert_eq(rows[0].identity(), 1)
  assert_eq(rows[1].frame(), 2)
  assert_eq(rows[1].bbox().x1(), 20.0)
}

///|
test "tracker parser and encoder use deterministic ten-column rows" {
  let rows = @evaluation.parse_tracker_results(
    (
      #|2,8,10,20,30,40,0.75,-1,-1,-1
      #|1,7,0,0,10,10,0.9,-1,-1,-1
    ),
  )
  assert_eq(rows[0].identity(), 7)
  assert_eq(rows[1].bbox().to_xywh(), (10.0, 20.0, 30.0, 40.0))
  assert_eq(
    @evaluation.encode_tracker_results(rows),
    (
      #|1,7,0,0,10,10,0.9,-1,-1,-1
      #|2,8,10,20,30,40,0.75,-1,-1,-1
    ),
  )
}

///|
test "parser reports the physical line containing a duplicate identity" {
  try
    @evaluation.parse_tracker_results(
      (
        #|1,4,0,0,10,10,0.9,-1,-1,-1
        #|
        #|1,4,1,0,10,10,0.8,-1,-1,-1
      ),
    )
  catch {
    error => assert_eq(error.message(), "line 3: duplicate frame and identity")
  } noraise {
    _ => fail("duplicate frame and identity must be rejected")
  }
}

///|
test "parser rejects non-finite and non-positive boxes" {
  try
    @evaluation.parse_tracker_results(
      (
        #|1,1,0,0,0,10,0.9,-1,-1,-1
      ),
    )
  catch {
    error =>
      assert_eq(
        error.message(),
        "line 1: bounding box must have finite coordinates and positive size",
      )
  } noraise {
    _ => fail("zero-width tracker box must be rejected")
  }
}

///|
test "visible tracker output converts directly to MOT rows" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  let frame = tracker.update(4, [
    @mbmot.Detection::new(
      @mbmot.BoundingBox::from_xywh(3.0, 5.0, 10.0, 20.0),
      0.8,
      0,
    ),
  ])
  let rows = @evaluation.objects_from_tracks(frame.tracks())
  assert_eq(
    @evaluation.encode_tracker_results(rows),
    "4,1,3,5,10,20,0.8,-1,-1,-1",
  )
}
