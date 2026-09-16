///|
fn point(x : Double, y : Double) -> @analytics.Point raise {
  @analytics.Point::new(x, y)
}

///|
fn sample(x : Double) -> @analytics.TrackSample raise {
  @analytics.TrackSample::new(
    1,
    @mbmot.BoundingBox::new(x - 1.0, 2.0, x + 1.0, 5.0),
    0,
  )
}

///|
fn event_text(event : @analytics.AnalyticsEvent) -> String {
  match event {
    @analytics.LineCrossed(line_id~, track_id~, direction~) => {
      let direction_text = match direction {
        @analytics.LeftToRight => "left_to_right"
        @analytics.RightToLeft => "right_to_left"
      }
      "crossed(line=\{line_id},track=\{track_id},direction=\{direction_text})"
    }
    @analytics.RegionEntered(region_id~, track_id~, initial~) =>
      "entered(region=\{region_id},track=\{track_id},initial=\{initial})"
    @analytics.RegionExited(region_id~, track_id~, dwell_frames~) =>
      "exited(region=\{region_id},track=\{track_id},dwell=\{dwell_frames})"
  }
}

///|
fn events_text(events : Array[@analytics.AnalyticsEvent]) -> String {
  let output = StringBuilder()
  output.write_string("[")
  for index, event in events {
    if index > 0 {
      output.write_string(",")
    }
    output.write_string(event_text(event))
  }
  output.write_string("]")
  output.to_string()
}

///|
fn occupant_text(occupants : Array[@analytics.RegionOccupant]) -> String {
  let output = StringBuilder()
  output.write_string("[")
  for index, occupant in occupants {
    if index > 0 {
      output.write_string(",")
    }
    output.write_string(
      "track=\{occupant.track_id()}:dwell=\{occupant.dwell_frames()}",
    )
  }
  output.write_string("]")
  output.to_string()
}

///|
fn show(frame : @analytics.AnalyticsFrame) -> Unit {
  let line = frame.line_counts()[0]
  let region = frame.region_counts()[0]
  println(
    "frame=\{frame.frame_id()} events=\{events_text(frame.events())} line=\{line.left_to_right()}/\{line.right_to_left()} region=\{region.entries()}/\{region.exits()}/\{region.unique_tracks()} occupancy=\{region.current_occupancy()} occupants=\{occupant_text(frame.occupants())}",
  )
}

///|
fn main raise {
  let line = @analytics.DirectedLine::new(4, point(5.0, 0.0), point(5.0, 10.0))
  let region = @analytics.PolygonRegion::new(7, [
    point(0.0, 0.0),
    point(10.0, 0.0),
    point(10.0, 10.0),
    point(0.0, 10.0),
  ])
  let analyzer = @analytics.SpatialAnalyzer::new(
    @analytics.AnalyticsConfig::new(
      anchor=@analytics.BottomCenter,
      stable_frames=1,
    ),
    [line],
    [region],
  )
  show(analyzer.update(1, [sample(-2.0)], [], []))
  show(analyzer.update(2, [sample(2.0)], [], []))
  show(analyzer.update(3, [sample(7.0)], [], []))
  show(analyzer.update(4, [], [1], []))
  show(analyzer.update(5, [sample(8.0)], [], []))
  show(analyzer.update(6, [sample(12.0)], [], []))
}
