///|
fn cross(origin : Point, first : Point, second : Point) -> Double {
  (first.x - origin.x) * (second.y - origin.y) -
  (first.y - origin.y) * (second.x - origin.x)
}

///|
fn sign(value : Double) -> Int {
  if value > 0.0 {
    1
  } else if value < 0.0 {
    -1
  } else {
    0
  }
}

///|
fn point_on_segment(point : Point, start : Point, end : Point) -> Bool {
  if cross(start, end, point) != 0.0 {
    return false
  }
  let min_x = if start.x < end.x { start.x } else { end.x }
  let max_x = if start.x > end.x { start.x } else { end.x }
  let min_y = if start.y < end.y { start.y } else { end.y }
  let max_y = if start.y > end.y { start.y } else { end.y }
  point.x >= min_x && point.x <= max_x && point.y >= min_y && point.y <= max_y
}

///|
fn segments_intersect(a : Point, b : Point, c : Point, d : Point) -> Bool {
  let ab_c = sign(cross(a, b, c))
  let ab_d = sign(cross(a, b, d))
  let cd_a = sign(cross(c, d, a))
  let cd_b = sign(cross(c, d, b))
  if ab_c * ab_d < 0 && cd_a * cd_b < 0 {
    return true
  }
  (ab_c == 0 && point_on_segment(c, a, b)) ||
  (ab_d == 0 && point_on_segment(d, a, b)) ||
  (cd_a == 0 && point_on_segment(a, c, d)) ||
  (cd_b == 0 && point_on_segment(b, c, d))
}

///|
fn edges_adjacent(first : Int, second : Int, count : Int) -> Bool {
  first == second ||
  (first + 1) % count == second ||
  (second + 1) % count == first
}

///|
fn validate_polygon(
  id : Int,
  vertices : Array[Point],
) -> Unit raise AnalyticsError {
  if id < 0 {
    raise InvalidRegion("id must be non-negative")
  }
  let count = vertices.length()
  if count < 3 {
    raise InvalidRegion("at least three vertices are required")
  }
  let mut area_twice = 0.0
  for index = 0; index < count; index = index + 1 {
    let next = (index + 1) % count
    if vertices[index] == vertices[next] {
      raise InvalidRegion("adjacent vertices must differ")
    }
    area_twice += vertices[index].x * vertices[next].y -
      vertices[next].x * vertices[index].y
  }
  if area_twice == 0.0 {
    raise InvalidRegion("polygon area must be non-zero")
  }
  for first = 0; first < count; first = first + 1 {
    for second = first + 1; second < count; second = second + 1 {
      if edges_adjacent(first, second, count) {
        continue
      }
      let first_end = (first + 1) % count
      let second_end = (second + 1) % count
      if segments_intersect(
          vertices[first],
          vertices[first_end],
          vertices[second],
          vertices[second_end],
        ) {
        raise InvalidRegion("polygon edges must not self-intersect")
      }
    }
  }
}

///|
/// Returns -1 for outside, 0 for boundary and 1 for inside.
fn PolygonRegion::classify(self : PolygonRegion, point : Point) -> Int {
  let count = self.vertices.length()
  let mut inside = false
  for index = 0; index < count; index = index + 1 {
    let next = (index + 1) % count
    let first = self.vertices[index]
    let second = self.vertices[next]
    if point_on_segment(point, first, second) {
      return 0
    }
    let spans_y = (first.y > point.y) != (second.y > point.y)
    if spans_y {
      let intersection_x = (second.x - first.x) *
        (point.y - first.y) /
        (second.y - first.y) +
        first.x
      if point.x < intersection_x {
        inside = !inside
      }
    }
  }
  if inside {
    1
  } else {
    -1
  }
}

///|
/// Returns -1 for the right side, 0 on the line and 1 for the left side.
fn DirectedLine::classify(self : DirectedLine, point : Point) -> Int {
  sign(cross(self.start, self.end, point))
}

///|
fn TrackSample::anchor_point(self : TrackSample, anchor : Anchor) -> Point {
  let x = (self.bbox.x1() + self.bbox.x2()) / 2.0
  let y = match anchor {
    Center => (self.bbox.y1() + self.bbox.y2()) / 2.0
    BottomCenter => self.bbox.y2()
  }
  { x, y, }
}
