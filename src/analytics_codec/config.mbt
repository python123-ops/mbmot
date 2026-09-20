///|
fn input_point(
  coordinates : Array[Double],
) -> @analytics.Point raise AnalyticsReplayError {
  if coordinates.length() != 2 {
    raise InvalidSetup("point must contain exactly two numbers")
  }
  @analytics.Point::new(coordinates[0], coordinates[1]) catch {
    error => raise InvalidSetup(error.message())
  }
}

///|
fn input_anchor(value : String) -> @analytics.Anchor raise AnalyticsReplayError {
  match value {
    "center" => @analytics.Center
    "bottom_center" => @analytics.BottomCenter
    _ => raise InvalidSetup("anchor must be center or bottom_center")
  }
}

///|
fn parse_setup(
  line : StringView,
) -> @analytics.SpatialAnalyzer raise AnalyticsReplayError {
  let json = parse_json(line)
  let input : InputSetup = @json.from_json(json) catch {
    error => raise InvalidSetup(error.to_string())
  }
  let anchor = input_anchor(input.config.anchor)
  let config = @analytics.AnalyticsConfig::new(
    anchor~,
    stable_frames=input.config.stable_frames,
  ) catch {
    error => raise InvalidSetup(error.message())
  }
  let lines : Array[@analytics.DirectedLine] = []
  for index, item in input.lines {
    let start = input_point(item.start)
    let end = input_point(item.end)
    let line_rule : @analytics.DirectedLine = try {
      match item.class_ids {
        None => @analytics.DirectedLine::new(item.id, start, end)
        Some(class_ids) =>
          @analytics.DirectedLine::for_classes(item.id, start, end, class_ids)
      }
    } catch {
      error => raise InvalidRule(kind="line", index~, reason=error.message())
    }
    lines.push(line_rule)
  }
  let regions : Array[@analytics.PolygonRegion] = []
  for index, item in input.regions {
    let vertices : Array[@analytics.Point] = []
    for coordinates in item.vertices {
      vertices.push(input_point(coordinates))
    }
    let region : @analytics.PolygonRegion = try {
      match item.class_ids {
        None => @analytics.PolygonRegion::new(item.id, vertices)
        Some(class_ids) =>
          @analytics.PolygonRegion::for_classes(item.id, vertices, class_ids)
      }
    } catch {
      error => raise InvalidRule(kind="region", index~, reason=error.message())
    }
    regions.push(region)
  }
  @analytics.SpatialAnalyzer::new(config, lines, regions) catch {
    error => raise InvalidSetup(error.message())
  }
}
