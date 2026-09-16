///|
/// Errors raised when spatial rules or one analytics frame violate their contract.
pub(all) suberror AnalyticsError {
  InvalidPoint
  InvalidBoundingBox
  InvalidLine(String)
  InvalidRegion(String)
  InvalidConfig(String)
  DuplicateRuleId(kind~ : String, id~ : Int)
  NonIncreasingFrame(previous~ : Int, received~ : Int)
  InvalidTrackId(Int)
  InvalidClassId(Int)
  DuplicateTrackId(Int)
  ConflictingTrackId(Int)
  ChangedClassId(track_id~ : Int, previous~ : Int, received~ : Int)
  UnknownLifecycleId(Int)
  ReusedRemovedId(Int)
} derive(Debug, Eq)

///|
/// Returns a stable description suitable for command-line error reporting.
pub fn AnalyticsError::message(self : AnalyticsError) -> String {
  match self {
    InvalidPoint => "point coordinates must be finite"
    InvalidBoundingBox =>
      "track sample bounding box must be finite and non-degenerate"
    InvalidLine(reason) => "invalid directed line: " + reason
    InvalidRegion(reason) => "invalid polygon region: " + reason
    InvalidConfig(reason) => "invalid analytics config: " + reason
    DuplicateRuleId(kind~, id~) => "duplicate \{kind} id: \{id}"
    NonIncreasingFrame(previous~, received~) =>
      "frame must increase: previous \{previous}, received \{received}"
    InvalidTrackId(id) => "track_id must be positive: \{id}"
    InvalidClassId(id) => "class_id must be non-negative: \{id}"
    DuplicateTrackId(id) => "duplicate visible track_id: \{id}"
    ConflictingTrackId(id) =>
      "track_id appears in more than one frame collection: \{id}"
    ChangedClassId(track_id~, previous~, received~) =>
      "track \{track_id} changed class_id from \{previous} to \{received}"
    UnknownLifecycleId(id) =>
      "lifecycle event references unknown track_id: \{id}"
    ReusedRemovedId(id) => "removed track_id cannot be reused: \{id}"
  }
}

///|
/// A finite two-dimensional coordinate.
struct Point {
  x : Double
  y : Double
} derive(Debug, Eq)

///|
/// Creates a point after rejecting NaN and infinite coordinates.
pub fn Point::new(x : Double, y : Double) -> Point raise AnalyticsError {
  if x.is_nan() || x.is_inf() || y.is_nan() || y.is_inf() {
    raise InvalidPoint
  }
  { x, y, }
}

///|
pub fn Point::x(self : Point) -> Double {
  self.x
}

///|
pub fn Point::y(self : Point) -> Double {
  self.y
}

///|
/// A counting line whose direction runs from `start` to `end`.
struct DirectedLine {
  id : Int
  start : Point
  end : Point
} derive(Debug, Eq)

///|
/// Creates a non-degenerate directed line with a non-negative rule identifier.
pub fn DirectedLine::new(
  id : Int,
  start : Point,
  end : Point,
) -> DirectedLine raise AnalyticsError {
  if id < 0 {
    raise InvalidLine("id must be non-negative")
  }
  if start == end {
    raise InvalidLine("start and end must differ")
  }
  { id, start, end, }
}

///|
pub fn DirectedLine::id(self : DirectedLine) -> Int {
  self.id
}

///|
pub fn DirectedLine::start(self : DirectedLine) -> Point {
  self.start
}

///|
pub fn DirectedLine::end(self : DirectedLine) -> Point {
  self.end
}

///|
/// A simple polygon used as an occupancy region.
struct PolygonRegion {
  id : Int
  vertices : Array[Point]
} derive(Debug, Eq)

///|
/// Creates a clockwise or counter-clockwise simple polygon.
pub fn PolygonRegion::new(
  id : Int,
  vertices : Array[Point],
) -> PolygonRegion raise AnalyticsError {
  validate_polygon(id, vertices)
  { id, vertices: vertices.copy(), }
}

///|
pub fn PolygonRegion::id(self : PolygonRegion) -> Int {
  self.id
}

///|
pub fn PolygonRegion::vertices(self : PolygonRegion) -> Array[Point] {
  self.vertices.copy()
}

///|
/// Selects the representative point extracted from each tracked box.
pub(all) enum Anchor {
  Center
  BottomCenter
} derive(Debug, Eq)

///|
/// Boundary-stability settings shared by all line and region rules.
struct AnalyticsConfig {
  anchor : Anchor
  stable_frames : Int
} derive(Debug, Eq)

///|
pub fn AnalyticsConfig::new(
  anchor~ : Anchor,
  stable_frames~ : Int,
) -> AnalyticsConfig raise AnalyticsError {
  if stable_frames < 1 {
    raise InvalidConfig("stable_frames must be at least 1")
  }
  { anchor, stable_frames, }
}

///|
/// Uses the bottom-center of each box and requires two stable observations.
pub fn AnalyticsConfig::default() -> AnalyticsConfig {
  { anchor: BottomCenter, stable_frames: 2, }
}

///|
pub fn AnalyticsConfig::anchor(self : AnalyticsConfig) -> Anchor {
  self.anchor
}

///|
pub fn AnalyticsConfig::stable_frames(self : AnalyticsConfig) -> Int {
  self.stable_frames
}

///|
/// The minimum tracker-independent input required by spatial analytics.
struct TrackSample {
  track_id : Int
  bbox : @mbmot.BoundingBox
  class_id : Int
} derive(Debug, Eq)

///|
pub fn TrackSample::new(
  track_id : Int,
  bbox : @mbmot.BoundingBox,
  class_id : Int,
) -> TrackSample raise AnalyticsError {
  if track_id <= 0 {
    raise InvalidTrackId(track_id)
  }
  if class_id < 0 {
    raise InvalidClassId(class_id)
  }
  if bbox.x1().is_nan() ||
    bbox.x1().is_inf() ||
    bbox.y1().is_nan() ||
    bbox.y1().is_inf() ||
    bbox.x2().is_nan() ||
    bbox.x2().is_inf() ||
    bbox.y2().is_nan() ||
    bbox.y2().is_inf() ||
    bbox.x2() <= bbox.x1() ||
    bbox.y2() <= bbox.y1() {
    raise InvalidBoundingBox
  }
  { track_id, bbox, class_id, }
}

///|
/// Converts one visible MBMOT track without exposing tracker internals.
pub fn TrackSample::from_track(track : @mbmot.Track) -> TrackSample {
  {
    track_id: track.track_id(),
    bbox: track.bbox(),
    class_id: track.class_id(),
  }
}

///|
pub fn TrackSample::track_id(self : TrackSample) -> Int {
  self.track_id
}

///|
pub fn TrackSample::bbox(self : TrackSample) -> @mbmot.BoundingBox {
  self.bbox
}

///|
pub fn TrackSample::class_id(self : TrackSample) -> Int {
  self.class_id
}

///|
/// Direction of a confirmed transition across a directed line.
pub(all) enum CrossingDirection {
  LeftToRight
  RightToLeft
} derive(Debug, Eq)

///|
/// A spatial state transition confirmed in the current frame.
pub(all) enum AnalyticsEvent {
  LineCrossed(line_id~ : Int, track_id~ : Int, direction~ : CrossingDirection)
  RegionEntered(region_id~ : Int, track_id~ : Int, initial~ : Bool)
  RegionExited(region_id~ : Int, track_id~ : Int, dwell_frames~ : Int)
} derive(Debug, Eq)

///|
/// Cumulative crossings for one directed line.
struct LineCount {
  line_id : Int
  left_to_right : Int
  right_to_left : Int
} derive(Debug, Eq)

///|
pub fn LineCount::line_id(self : LineCount) -> Int {
  self.line_id
}

///|
pub fn LineCount::left_to_right(self : LineCount) -> Int {
  self.left_to_right
}

///|
pub fn LineCount::right_to_left(self : LineCount) -> Int {
  self.right_to_left
}

///|
/// Cumulative entries, exits and unique identities for one region.
struct RegionCount {
  region_id : Int
  entries : Int
  exits : Int
  unique_tracks : Int
  current_occupancy : Int
} derive(Debug, Eq)

///|
pub fn RegionCount::region_id(self : RegionCount) -> Int {
  self.region_id
}

///|
pub fn RegionCount::entries(self : RegionCount) -> Int {
  self.entries
}

///|
pub fn RegionCount::exits(self : RegionCount) -> Int {
  self.exits
}

///|
pub fn RegionCount::unique_tracks(self : RegionCount) -> Int {
  self.unique_tracks
}

///|
pub fn RegionCount::current_occupancy(self : RegionCount) -> Int {
  self.current_occupancy
}

///|
/// One visible identity currently confirmed inside a region.
struct RegionOccupant {
  region_id : Int
  track_id : Int
  class_id : Int
  dwell_frames : Int
} derive(Debug, Eq)

///|
pub fn RegionOccupant::region_id(self : RegionOccupant) -> Int {
  self.region_id
}

///|
pub fn RegionOccupant::track_id(self : RegionOccupant) -> Int {
  self.track_id
}

///|
pub fn RegionOccupant::class_id(self : RegionOccupant) -> Int {
  self.class_id
}

///|
pub fn RegionOccupant::dwell_frames(self : RegionOccupant) -> Int {
  self.dwell_frames
}

///|
/// Events and deterministic cumulative snapshots returned for one frame.
struct AnalyticsFrame {
  frame_id : Int
  events : Array[AnalyticsEvent]
  line_counts : Array[LineCount]
  region_counts : Array[RegionCount]
  occupants : Array[RegionOccupant]
} derive(Debug, Eq)

///|
pub fn AnalyticsFrame::frame_id(self : AnalyticsFrame) -> Int {
  self.frame_id
}

///|
pub fn AnalyticsFrame::events(self : AnalyticsFrame) -> Array[AnalyticsEvent] {
  self.events.copy()
}

///|
pub fn AnalyticsFrame::line_counts(self : AnalyticsFrame) -> Array[LineCount] {
  self.line_counts.copy()
}

///|
pub fn AnalyticsFrame::region_counts(
  self : AnalyticsFrame,
) -> Array[RegionCount] {
  self.region_counts.copy()
}

///|
pub fn AnalyticsFrame::occupants(
  self : AnalyticsFrame,
) -> Array[RegionOccupant] {
  self.occupants.copy()
}
