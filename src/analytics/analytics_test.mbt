///|
fn point(x : Double, y : Double) -> @analytics.Point raise {
  @analytics.Point::new(x, y)
}

///|
fn horizontal_line(id : Int) -> @analytics.DirectedLine raise {
  @analytics.DirectedLine::new(id, point(0.0, 0.0), point(10.0, 0.0))
}

///|
fn square(id : Int) -> @analytics.PolygonRegion raise {
  @analytics.PolygonRegion::new(id, [
    point(0.0, 0.0),
    point(10.0, 0.0),
    point(10.0, 10.0),
    point(0.0, 10.0),
  ])
}

///|
fn sample_at(id : Int, x : Double, y : Double) -> @analytics.TrackSample raise {
  sample_at_class(id, x, y, 0)
}

///|
fn sample_at_class(
  id : Int,
  x : Double,
  y : Double,
  class_id : Int,
) -> @analytics.TrackSample raise {
  @analytics.TrackSample::new(
    id,
    @mbmot.BoundingBox::new(x - 1.0, y - 2.0, x + 1.0, y),
    class_id,
  )
}

///|
fn analyzer(
  stable_frames : Int,
  lines : Array[@analytics.DirectedLine],
  regions : Array[@analytics.PolygonRegion],
) -> @analytics.SpatialAnalyzer raise {
  @analytics.SpatialAnalyzer::new(
    @analytics.AnalyticsConfig::new(
      anchor=@analytics.BottomCenter,
      stable_frames~,
    ),
    lines,
    regions,
  )
}

///|
test "geometry constructors reject non-finite points and degenerate lines" {
  try @analytics.Point::new(@double.not_a_number, 0.0) catch {
    @analytics.InvalidPoint => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("NaN must be rejected")
  }
  let start = point(1.0, 1.0)
  try @analytics.DirectedLine::new(0, start, start) catch {
    @analytics.InvalidLine(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("a zero-length line must be rejected")
  }
}

///|
test "configuration and duplicate rule ids fail before state is created" {
  try
    @analytics.AnalyticsConfig::new(
      anchor=@analytics.BottomCenter,
      stable_frames=0,
    )
  catch {
    @analytics.InvalidConfig(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("zero stable frames must be rejected")
  }
  let line = horizontal_line(4)
  try
    @analytics.SpatialAnalyzer::new(
      @analytics.AnalyticsConfig::default(),
      [line, line],
      [],
    )
  catch {
    @analytics.DuplicateRuleId(kind="line", id=4) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicate line ids must be rejected")
  }
}

///|
test "class filters normalize ids and reject ambiguous lists" {
  let line = @analytics.DirectedLine::for_classes(
    2,
    point(0.0, 0.0),
    point(10.0, 0.0),
    [3, 1],
  )
  assert_eq(line.class_ids(), Some([1, 3]))
  guard line.class_ids() is Some(returned_ids) else {
    fail("filtered line must expose its classes")
  }
  returned_ids.push(9)
  assert_eq(line.class_ids(), Some([1, 3]))
  assert_eq(horizontal_line(3).class_ids(), None)
  let region = @analytics.PolygonRegion::for_classes(4, square(5).vertices(), [
    2,
  ])
  assert_eq(region.class_ids(), Some([2]))
  try
    @analytics.DirectedLine::for_classes(6, point(0.0, 0.0), point(1.0, 0.0), [])
  catch {
    @analytics.InvalidClassFilter("class_ids must not be empty") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("an empty filter must be rejected")
  }
  try
    @analytics.PolygonRegion::for_classes(7, square(8).vertices(), [1, 1])
  catch {
    @analytics.InvalidClassFilter("duplicate class_id: 1") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicate classes must be rejected")
  }
  try
    @analytics.DirectedLine::for_classes(9, point(0.0, 0.0), point(1.0, 0.0), [
      -1,
    ])
  catch {
    @analytics.InvalidClassFilter("class_id must be non-negative: -1") => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("negative classes must be rejected")
  }
}

///|
test "each spatial rule observes only its selected classes" {
  let line = @analytics.DirectedLine::for_classes(
    10,
    point(0.0, 0.0),
    point(10.0, 0.0),
    [1],
  )
  let region = @analytics.PolygonRegion::for_classes(
    11,
    square(12).vertices(),
    [0],
  )
  let subject = analyzer(1, [line], [region])
  ignore(
    subject.update(
      1,
      [sample_at_class(1, 5.0, 2.0, 1), sample_at_class(2, -2.0, 2.0, 0)],
      [],
      [],
    ),
  )
  let frame = subject.update(
    2,
    [sample_at_class(1, 5.0, -2.0, 1), sample_at_class(2, 5.0, 5.0, 0)],
    [],
    [],
  )
  assert_eq(frame.events(), [
    @analytics.LineCrossed(
      line_id=10,
      track_id=1,
      direction=@analytics.LeftToRight,
    ),
    @analytics.RegionEntered(region_id=11, track_id=2, initial=false),
  ])
  assert_eq(frame.line_counts()[0].left_to_right(), 1)
  assert_eq(frame.line_class_counts().length(), 1)
  assert_eq(frame.line_class_counts()[0].line_id(), 10)
  assert_eq(frame.line_class_counts()[0].class_id(), 1)
  assert_eq(frame.line_class_counts()[0].left_to_right(), 1)
  assert_eq(frame.region_counts()[0].entries(), 1)
  assert_eq(frame.region_counts()[0].current_occupancy(), 1)
  assert_eq(frame.region_class_counts().length(), 1)
  assert_eq(frame.region_class_counts()[0].region_id(), 11)
  assert_eq(frame.region_class_counts()[0].class_id(), 0)
  assert_eq(frame.region_class_counts()[0].entries(), 1)
  assert_eq(frame.region_class_counts()[0].current_occupancy(), 1)
  assert_eq(frame.occupants()[0].class_id(), 0)
}

///|
test "unfiltered rules return deterministic per-class crossing totals" {
  let subject = analyzer(1, [horizontal_line(9), horizontal_line(4)], [])
  ignore(
    subject.update(
      1,
      [sample_at_class(5, 5.0, 2.0, 2), sample_at_class(3, 5.0, -2.0, 0)],
      [],
      [],
    ),
  )
  let frame = subject.update(
    2,
    [sample_at_class(5, 5.0, -2.0, 2), sample_at_class(3, 5.0, 2.0, 0)],
    [],
    [],
  )
  let counts = frame.line_class_counts()
  assert_eq(counts.length(), 4)
  assert_eq(counts[0].line_id(), 4)
  assert_eq(counts[0].class_id(), 0)
  assert_eq(counts[0].left_to_right(), 0)
  assert_eq(counts[0].right_to_left(), 1)
  assert_eq(counts[1].line_id(), 4)
  assert_eq(counts[1].class_id(), 2)
  assert_eq(counts[1].left_to_right(), 1)
  assert_eq(counts[1].right_to_left(), 0)
  assert_eq(counts[2].line_id(), 9)
  assert_eq(counts[2].class_id(), 0)
  assert_eq(counts[3].line_id(), 9)
  assert_eq(counts[3].class_id(), 2)
  assert_eq(frame.line_counts()[0].left_to_right(), 1)
  assert_eq(frame.line_counts()[0].right_to_left(), 1)
}

///|
test "region class counts preserve totals while lost tracks leave occupancy" {
  let subject = analyzer(1, [], [square(6)])
  let entered = subject.update(
    1,
    [sample_at_class(8, 5.0, 5.0, 2), sample_at_class(7, 5.0, 5.0, 0)],
    [],
    [],
  )
  assert_eq(entered.region_class_counts().length(), 2)
  let lost = subject.update(2, [sample_at_class(8, 12.0, 5.0, 2)], [7], [])
  let counts = lost.region_class_counts()
  assert_eq(counts[0].class_id(), 0)
  assert_eq(counts[0].entries(), 1)
  assert_eq(counts[0].exits(), 0)
  assert_eq(counts[0].unique_tracks(), 1)
  assert_eq(counts[0].current_occupancy(), 0)
  assert_eq(counts[1].class_id(), 2)
  assert_eq(counts[1].entries(), 1)
  assert_eq(counts[1].exits(), 1)
  assert_eq(counts[1].unique_tracks(), 1)
  assert_eq(counts[1].current_occupancy(), 0)
  assert_eq(lost.region_counts()[0].entries(), 2)
  assert_eq(lost.region_counts()[0].exits(), 1)
}

///|
test "polygon rejects too few points, zero area and self intersection" {
  try
    @analytics.PolygonRegion::new(0, [point(0.0, 0.0), point(1.0, 1.0)])
  catch {
    @analytics.InvalidRegion(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("two points must be rejected")
  }
  try
    @analytics.PolygonRegion::new(0, [
      point(0.0, 0.0),
      point(1.0, 0.0),
      point(2.0, 0.0),
    ])
  catch {
    @analytics.InvalidRegion(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("zero area must be rejected")
  }
  try
    @analytics.PolygonRegion::new(0, [
      point(0.0, 0.0),
      point(2.0, 2.0),
      point(0.0, 2.0),
      point(2.0, 0.0),
    ])
  catch {
    @analytics.InvalidRegion(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("crossing edges must be rejected")
  }
}

///|
test "clockwise and counter-clockwise polygons behave alike" {
  let clockwise = @analytics.PolygonRegion::new(1, [
    point(0.0, 0.0),
    point(0.0, 10.0),
    point(10.0, 10.0),
    point(10.0, 0.0),
  ])
  let subject = analyzer(1, [], [clockwise])
  let frame = subject.update(1, [sample_at(1, 5.0, 5.0)], [], [])
  assert_eq(frame.events(), [
    @analytics.RegionEntered(region_id=1, track_id=1, initial=true),
  ])
}

///|
test "anchor choice changes which side of a line the same box occupies" {
  let line = @analytics.DirectedLine::new(1, point(0.0, 7.0), point(10.0, 7.0))
  let bbox = @mbmot.BoundingBox::new(4.0, 0.0, 6.0, 10.0)
  let sample = @analytics.TrackSample::new(1, bbox, 0)
  let centered = @analytics.SpatialAnalyzer::new(
    @analytics.AnalyticsConfig::new(anchor=@analytics.Center, stable_frames=1),
    [line],
    [],
  )
  let bottom = @analytics.SpatialAnalyzer::new(
    @analytics.AnalyticsConfig::new(
      anchor=@analytics.BottomCenter,
      stable_frames=1,
    ),
    [line],
    [],
  )
  ignore(centered.update(1, [sample], [], []))
  ignore(bottom.update(1, [sample], [], []))
  let moved = @analytics.TrackSample::new(
    1,
    @mbmot.BoundingBox::new(4.0, 2.0, 6.0, 6.0),
    0,
  )
  assert_eq(centered.update(2, [moved], [], []).events().length(), 0)
  assert_eq(bottom.update(2, [moved], [], []).events(), [
    @analytics.LineCrossed(
      line_id=1,
      track_id=1,
      direction=@analytics.LeftToRight,
    ),
  ])
}

///|
test "line crossings count both directions" {
  let subject = analyzer(1, [horizontal_line(3)], [])
  ignore(subject.update(1, [sample_at(1, 5.0, 2.0)], [], []))
  let down = subject.update(2, [sample_at(1, 5.0, -2.0)], [], [])
  let up = subject.update(3, [sample_at(1, 5.0, 2.0)], [], [])
  assert_eq(down.events(), [
    @analytics.LineCrossed(
      line_id=3,
      track_id=1,
      direction=@analytics.LeftToRight,
    ),
  ])
  assert_eq(up.events(), [
    @analytics.LineCrossed(
      line_id=3,
      track_id=1,
      direction=@analytics.RightToLeft,
    ),
  ])
  assert_eq(up.line_counts()[0].left_to_right(), 1)
  assert_eq(up.line_counts()[0].right_to_left(), 1)
}

///|
test "line boundary does not advance debounce evidence" {
  let subject = analyzer(2, [horizontal_line(0)], [])
  ignore(subject.update(1, [sample_at(1, 5.0, 2.0)], [], []))
  ignore(subject.update(2, [sample_at(1, 5.0, 2.0)], [], []))
  ignore(subject.update(3, [sample_at(1, 5.0, -2.0)], [], []))
  let boundary = subject.update(4, [sample_at(1, 5.0, 0.0)], [], [])
  let confirmed = subject.update(5, [sample_at(1, 5.0, -2.0)], [], [])
  assert_eq(boundary.events().length(), 0)
  assert_eq(confirmed.events().length(), 1)
}

///|
test "initial inside state emits one entry and reports dwell" {
  let subject = analyzer(2, [], [square(5)])
  assert_eq(
    subject.update(10, [sample_at(7, 5.0, 5.0)], [], []).events().length(),
    0,
  )
  let frame = subject.update(12, [sample_at(7, 5.0, 5.0)], [], [])
  assert_eq(frame.events(), [
    @analytics.RegionEntered(region_id=5, track_id=7, initial=true),
  ])
  assert_eq(frame.occupants()[0].dwell_frames(), 3)
  assert_eq(frame.region_counts()[0].entries(), 1)
  assert_eq(frame.region_counts()[0].unique_tracks(), 1)
  assert_eq(frame.region_counts()[0].current_occupancy(), 1)
}

///|
test "region entry and exit use real frame ids for dwell" {
  let subject = analyzer(1, [], [square(0)])
  ignore(subject.update(2, [sample_at(1, -2.0, 5.0)], [], []))
  let entered = subject.update(5, [sample_at(1, 5.0, 5.0)], [], [])
  let exited = subject.update(11, [sample_at(1, 12.0, 5.0)], [], [])
  assert_eq(entered.events(), [
    @analytics.RegionEntered(region_id=0, track_id=1, initial=false),
  ])
  assert_eq(exited.events(), [
    @analytics.RegionExited(region_id=0, track_id=1, dwell_frames=6),
  ])
  assert_eq(exited.region_counts()[0].exits(), 1)
  assert_eq(exited.region_counts()[0].current_occupancy(), 0)
}

///|
test "polygon boundary pauses an in-progress exit" {
  let subject = analyzer(2, [], [square(0)])
  ignore(subject.update(1, [sample_at(1, 5.0, 5.0)], [], []))
  ignore(subject.update(2, [sample_at(1, 5.0, 5.0)], [], []))
  ignore(subject.update(3, [sample_at(1, 12.0, 5.0)], [], []))
  let boundary = subject.update(4, [sample_at(1, 10.0, 5.0)], [], [])
  let exited = subject.update(5, [sample_at(1, 12.0, 5.0)], [], [])
  assert_eq(boundary.events().length(), 0)
  assert_eq(boundary.region_counts()[0].current_occupancy(), 1)
  assert_eq(exited.events(), [
    @analytics.RegionExited(region_id=0, track_id=1, dwell_frames=2),
  ])
}

///|
test "lost recovery preserves region membership without an extra entry" {
  let subject = analyzer(1, [], [square(0)])
  ignore(subject.update(1, [sample_at(1, 5.0, 5.0)], [], []))
  let lost = subject.update(2, [], [1], [])
  let recovered = subject.update(4, [sample_at(1, 6.0, 5.0)], [], [])
  assert_eq(lost.occupants().length(), 0)
  assert_eq(lost.region_counts()[0].current_occupancy(), 0)
  assert_eq(recovered.events().length(), 0)
  assert_eq(recovered.region_counts()[0].entries(), 1)
  assert_eq(recovered.occupants()[0].dwell_frames(), 4)
}

///|
test "lost interrupts line evidence and recovery does not infer a crossing" {
  let subject = analyzer(1, [horizontal_line(0)], [])
  ignore(subject.update(1, [sample_at(1, 5.0, 2.0)], [], []))
  ignore(subject.update(2, [], [1], []))
  let recovered = subject.update(3, [sample_at(1, 5.0, -2.0)], [], [])
  assert_eq(recovered.events().length(), 0)
  assert_eq(recovered.line_counts()[0].left_to_right(), 0)
}

///|
test "removed ids clear occupancy and cannot be reused" {
  let subject = analyzer(1, [], [square(0)])
  ignore(subject.update(1, [sample_at(1, 5.0, 5.0)], [], []))
  let removed = subject.update(2, [], [], [1])
  assert_eq(removed.occupants().length(), 0)
  assert_eq(removed.region_counts()[0].entries(), 1)
  try subject.update(3, [sample_at(1, 5.0, 5.0)], [], []) catch {
    @analytics.ReusedRemovedId(1) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("a removed id must not be accepted again")
  }
}

///|
test "duplicate and conflicting ids reject the whole frame" {
  let subject = analyzer(1, [horizontal_line(0)], [])
  let first = sample_at(1, 5.0, 2.0)
  try subject.update(1, [first, first], [], []) catch {
    @analytics.DuplicateTrackId(1) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicates must fail")
  }
  let accepted = subject.update(1, [first], [], [])
  assert_eq(accepted.line_counts()[0].left_to_right(), 0)
  try subject.update(2, [sample_at(1, 5.0, -2.0)], [1], []) catch {
    @analytics.ConflictingTrackId(1) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("visible and lost must be disjoint")
  }
  let crossed = subject.update(2, [sample_at(1, 5.0, -2.0)], [], [])
  assert_eq(crossed.events().length(), 1)
}

///|
test "invalid frame and class changes are atomic" {
  let subject = analyzer(1, [horizontal_line(0)], [])
  ignore(subject.update(4, [sample_at(1, 5.0, 2.0)], [], []))
  try subject.update(4, [sample_at(1, 5.0, -2.0)], [], []) catch {
    @analytics.NonIncreasingFrame(..) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicate frame must fail")
  }
  let changed = @analytics.TrackSample::new(
    1,
    @mbmot.BoundingBox::new(4.0, -4.0, 6.0, -2.0),
    1,
  )
  try subject.update(5, [changed], [], []) catch {
    @analytics.ChangedClassId(..) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("class changes must fail")
  }
  assert_eq(
    subject.update(5, [sample_at(1, 5.0, -2.0)], [], []).events().length(),
    1,
  )
}

///|
test "event and snapshot ordering is independent of input order" {
  let subject = analyzer(1, [horizontal_line(9), horizontal_line(2)], [
    square(8),
    square(1),
  ])
  ignore(
    subject.update(1, [sample_at(5, 5.0, 2.0), sample_at(3, 5.0, 2.0)], [], []),
  )
  let frame = subject.update(
    2,
    [sample_at(5, 5.0, -2.0), sample_at(3, 5.0, -2.0)],
    [],
    [],
  )
  assert_eq(frame.line_counts()[0].line_id(), 2)
  assert_eq(frame.region_counts()[0].region_id(), 1)
  assert_eq(
    frame
    .events()
    .map(event => {
      match event {
        @analytics.LineCrossed(line_id~, track_id~, ..) =>
          (0, line_id, track_id)
        @analytics.RegionEntered(region_id~, track_id~, ..) =>
          (1, region_id, track_id)
        @analytics.RegionExited(region_id~, track_id~, ..) =>
          (2, region_id, track_id)
      }
    }),
    [
      (0, 2, 3),
      (0, 2, 5),
      (0, 9, 3),
      (0, 9, 5),
      (2, 1, 3),
      (2, 1, 5),
      (2, 8, 3),
      (2, 8, 5),
    ],
  )
}

///|
test "reset clears counters, tombstones and frame clock" {
  let subject = analyzer(1, [], [square(0)])
  ignore(subject.update(1, [sample_at(1, 5.0, 5.0)], [], []))
  ignore(subject.update(2, [], [], [1]))
  subject.reset()
  let fresh = subject.update(1, [sample_at(1, 5.0, 5.0)], [], [])
  assert_eq(fresh.region_counts()[0].entries(), 1)
  assert_eq(fresh.region_counts()[0].unique_tracks(), 1)
}

///|
test "MBMOT frame output feeds the analyzer without an adapter" {
  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  let subject = analyzer(1, [], [square(0)])
  let detection = @mbmot.Detection::new(
    @mbmot.BoundingBox::new(4.0, 2.0, 6.0, 5.0),
    0.9,
    0,
  )
  let tracks = tracker.update(1, [detection])
  let frame = subject.update_mbmot(1, tracks)
  assert_eq(frame.occupants()[0].track_id(), 1)
  assert_eq(frame.events().length(), 1)
}
