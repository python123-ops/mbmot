///|
fn write_event(
  builder : StringBuilder,
  event : @analytics.AnalyticsEvent,
) -> Unit {
  match event {
    @analytics.LineCrossed(line_id~, track_id~, direction~) => {
      let direction_text = match direction {
        @analytics.LeftToRight => "left_to_right"
        @analytics.RightToLeft => "right_to_left"
      }
      builder.write_string(
        "{\"type\":\"line_crossed\",\"line_id\":\{line_id},\"track_id\":\{track_id},\"direction\":\"\{direction_text}\"}",
      )
    }
    @analytics.RegionEntered(region_id~, track_id~, initial~) =>
      builder.write_string(
        "{\"type\":\"region_entered\",\"region_id\":\{region_id},\"track_id\":\{track_id},\"initial\":\{initial}}",
      )
    @analytics.RegionExited(region_id~, track_id~, dwell_frames~) =>
      builder.write_string(
        "{\"type\":\"region_exited\",\"region_id\":\{region_id},\"track_id\":\{track_id},\"dwell_frames\":\{dwell_frames}}",
      )
  }
}

///|
fn write_line_count(
  builder : StringBuilder,
  count : @analytics.LineCount,
) -> Unit {
  builder.write_string(
    "{\"line_id\":\{count.line_id()},\"left_to_right\":\{count.left_to_right()},\"right_to_left\":\{count.right_to_left()},\"unique_left_to_right\":\{count.unique_left_to_right()},\"unique_right_to_left\":\{count.unique_right_to_left()}}",
  )
}

///|
fn write_line_class_count(
  builder : StringBuilder,
  count : @analytics.LineClassCount,
) -> Unit {
  builder.write_string(
    "{\"line_id\":\{count.line_id()},\"class_id\":\{count.class_id()},\"left_to_right\":\{count.left_to_right()},\"right_to_left\":\{count.right_to_left()},\"unique_left_to_right\":\{count.unique_left_to_right()},\"unique_right_to_left\":\{count.unique_right_to_left()}}",
  )
}

///|
fn write_region_count(
  builder : StringBuilder,
  count : @analytics.RegionCount,
) -> Unit {
  builder.write_string(
    "{\"region_id\":\{count.region_id()},\"entries\":\{count.entries()},\"exits\":\{count.exits()},\"unique_tracks\":\{count.unique_tracks()},\"current_occupancy\":\{count.current_occupancy()},\"peak_occupancy\":\{count.peak_occupancy()},\"completed_dwell_frames\":\{count.completed_dwell_frames()}}",
  )
}

///|
fn write_region_class_count(
  builder : StringBuilder,
  count : @analytics.RegionClassCount,
) -> Unit {
  builder.write_string(
    "{\"region_id\":\{count.region_id()},\"class_id\":\{count.class_id()},\"entries\":\{count.entries()},\"exits\":\{count.exits()},\"unique_tracks\":\{count.unique_tracks()},\"current_occupancy\":\{count.current_occupancy()},\"peak_occupancy\":\{count.peak_occupancy()},\"completed_dwell_frames\":\{count.completed_dwell_frames()}}",
  )
}

///|
fn write_transition_count(
  builder : StringBuilder,
  count : @analytics.RegionTransitionCount,
) -> Unit {
  builder.write_string(
    "{\"from_region_id\":\{count.from_region_id()},\"to_region_id\":\{count.to_region_id()},\"class_id\":\{count.class_id()},\"count\":\{count.count()}}",
  )
}

///|
fn write_occupant(
  builder : StringBuilder,
  occupant : @analytics.RegionOccupant,
) -> Unit {
  builder.write_string(
    "{\"region_id\":\{occupant.region_id()},\"track_id\":\{occupant.track_id()},\"class_id\":\{occupant.class_id()},\"dwell_frames\":\{occupant.dwell_frames()}}",
  )
}

///|
fn encode_analytics_frame(frame : @analytics.AnalyticsFrame) -> String {
  let builder = StringBuilder()
  builder.write_string("{\"frame\":\{frame.frame_id()},\"events\":[")
  for index, event in frame.events() {
    if index > 0 {
      builder.write_char(',')
    }
    write_event(builder, event)
  }
  builder.write_string("],\"line_counts\":[")
  for index, count in frame.line_counts() {
    if index > 0 {
      builder.write_char(',')
    }
    write_line_count(builder, count)
  }
  builder.write_string("],\"line_class_counts\":[")
  for index, count in frame.line_class_counts() {
    if index > 0 {
      builder.write_char(',')
    }
    write_line_class_count(builder, count)
  }
  builder.write_string("],\"region_counts\":[")
  for index, count in frame.region_counts() {
    if index > 0 {
      builder.write_char(',')
    }
    write_region_count(builder, count)
  }
  builder.write_string("],\"region_class_counts\":[")
  for index, count in frame.region_class_counts() {
    if index > 0 {
      builder.write_char(',')
    }
    write_region_class_count(builder, count)
  }
  builder.write_string("],\"transition_counts\":[")
  for index, count in frame.transition_counts() {
    if index > 0 {
      builder.write_char(',')
    }
    write_transition_count(builder, count)
  }
  builder.write_string("],\"occupants\":[")
  for index, occupant in frame.occupants() {
    if index > 0 {
      builder.write_char(',')
    }
    write_occupant(builder, occupant)
  }
  builder.write_string("]}")
  builder.to_string()
}
