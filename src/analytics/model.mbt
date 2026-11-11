///|
/// Errors raised when spatial rules or one analytics frame violate their contract.
#derive(Debug, Eq)
pub(all) suberror AnalyticsError {
  InvalidPoint
  InvalidBoundingBox
  InvalidLine(String)
  InvalidRegion(String)
  InvalidConfig(String)
  InvalidClassFilter(String)
  DuplicateRuleId(kind~ : String, id~ : Int32)
  NonIncreasingFrame(previous~ : Int32, received~ : Int32)
  InvalidTrackId(Int32)
  InvalidClassId(Int32)
  DuplicateTrackId(Int32)
  ConflictingTrackId(Int32)
  ChangedClassId(track_id~ : Int32, previous~ : Int32, received~ : Int32)
  UnknownLifecycleId(Int32)
  ReusedRemovedId(Int32)
}

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
    InvalidClassFilter(reason) => "invalid class filter: " + reason
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
#derive(Debug, Eq)
struct Point {
  x : Double
  y : Double
}

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
#derive(Debug, Eq)
struct DirectedLine {
  id : Int32
  start : Point
  end : Point
  class_ids : Array[Int32]?
}

///|
fn normalize_class_ids(
  class_ids : Array[Int32],
) -> Array[Int32] raise AnalyticsError {
  if class_ids.is_empty() {
    raise InvalidClassFilter("class_ids must not be empty")
  }
  let normalized = class_ids.copy()
  normalized.sort()
  for index, class_id in normalized {
    if class_id < 0 {
      raise InvalidClassFilter("class_id must be non-negative: \{class_id}")
    }
    if index > 0 && class_id == normalized[index - 1] {
      raise InvalidClassFilter("duplicate class_id: \{class_id}")
    }
  }
  normalized
}

///|
/// Creates a non-degenerate directed line with a non-negative rule identifier.
pub fn DirectedLine::new(
  id : Int32,
  start : Point,
  end : Point,
) -> DirectedLine raise AnalyticsError {
  if id < 0 {
    raise InvalidLine("id must be non-negative")
  }
  if start == end {
    raise InvalidLine("start and end must differ")
  }
  { id, start, end, class_ids: None, }
}

///|
/// Creates a directed line that observes only the listed classes.
pub fn DirectedLine::for_classes(
  id : Int32,
  start : Point,
  end : Point,
  class_ids : Array[Int32],
) -> DirectedLine raise AnalyticsError {
  let line = DirectedLine::new(id, start, end)
  { ..line, class_ids: Some(normalize_class_ids(class_ids)), }
}

///|
pub fn DirectedLine::id(self : DirectedLine) -> Int32 {
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
/// Returns `None` when the rule accepts every class.
pub fn DirectedLine::class_ids(self : DirectedLine) -> Array[Int32]? {
  self.class_ids.map(ids => ids.copy())
}

///|
fn DirectedLine::accepts_class(self : DirectedLine, class_id : Int32) -> Bool {
  match self.class_ids {
    None => true
    Some(ids) => ids.contains(class_id)
  }
}

///|
/// A simple polygon used as an occupancy region.
#derive(Debug, Eq)
struct PolygonRegion {
  id : Int32
  vertices : Array[Point]
  class_ids : Array[Int32]?
}

///|
/// Creates a clockwise or counter-clockwise simple polygon.
pub fn PolygonRegion::new(
  id : Int32,
  vertices : Array[Point],
) -> PolygonRegion raise AnalyticsError {
  validate_polygon(id, vertices)
  { id, vertices: vertices.copy(), class_ids: None, }
}

///|
/// Creates a polygon region that observes only the listed classes.
pub fn PolygonRegion::for_classes(
  id : Int32,
  vertices : Array[Point],
  class_ids : Array[Int32],
) -> PolygonRegion raise AnalyticsError {
  let region = PolygonRegion::new(id, vertices)
  { ..region, class_ids: Some(normalize_class_ids(class_ids)), }
}

///|
pub fn PolygonRegion::id(self : PolygonRegion) -> Int32 {
  self.id
}

///|
pub fn PolygonRegion::vertices(self : PolygonRegion) -> Array[Point] {
  self.vertices.copy()
}

///|
/// Returns `None` when the rule accepts every class.
pub fn PolygonRegion::class_ids(self : PolygonRegion) -> Array[Int32]? {
  self.class_ids.map(ids => ids.copy())
}

///|
fn PolygonRegion::accepts_class(self : PolygonRegion, class_id : Int32) -> Bool {
  match self.class_ids {
    None => true
    Some(ids) => ids.contains(class_id)
  }
}

///|
/// Selects the representative point extracted from each tracked box.
#derive(Debug, Eq)
pub(all) enum Anchor {
  Center
  BottomCenter
}

///|
/// Boundary-stability settings shared by all line and region rules.
#derive(Debug, Eq)
struct AnalyticsConfig {
  anchor : Anchor
  stable_frames : Int32
}

///|
pub fn AnalyticsConfig::new(
  anchor~ : Anchor,
  stable_frames~ : Int32,
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
pub fn AnalyticsConfig::stable_frames(self : AnalyticsConfig) -> Int32 {
  self.stable_frames
}

///|
/// The minimum tracker-independent input required by spatial analytics.
#derive(Debug, Eq)
struct TrackSample {
  track_id : Int32
  bbox : @mbmot.BoundingBox
  class_id : Int32
}

///|
pub fn TrackSample::new(
  track_id : Int32,
  bbox : @mbmot.BoundingBox,
  class_id : Int32,
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
pub fn TrackSample::track_id(self : TrackSample) -> Int32 {
  self.track_id
}

///|
pub fn TrackSample::bbox(self : TrackSample) -> @mbmot.BoundingBox {
  self.bbox
}

///|
pub fn TrackSample::class_id(self : TrackSample) -> Int32 {
  self.class_id
}

///|
/// Direction of a confirmed transition across a directed line.
#derive(Debug, Eq)
pub(all) enum CrossingDirection {
  LeftToRight
  RightToLeft
}

///|
/// A spatial state transition confirmed in the current frame.
#derive(Debug, Eq)
pub(all) enum AnalyticsEvent {
  LineCrossed(
    line_id~ : Int32,
    track_id~ : Int32,
    direction~ : CrossingDirection
  )
  RegionEntered(region_id~ : Int32, track_id~ : Int32, initial~ : Bool)
  RegionExited(region_id~ : Int32, track_id~ : Int32, dwell_frames~ : Int32)
}

///|
/// Cumulative crossings for one directed line.
#derive(Debug, Eq)
struct LineCount {
  line_id : Int32
  left_to_right : Int32
  right_to_left : Int32
  unique_left_to_right : Int32
  unique_right_to_left : Int32
}

///|
pub fn LineCount::line_id(self : LineCount) -> Int32 {
  self.line_id
}

///|
pub fn LineCount::left_to_right(self : LineCount) -> Int32 {
  self.left_to_right
}

///|
pub fn LineCount::right_to_left(self : LineCount) -> Int32 {
  self.right_to_left
}

///|
pub fn LineCount::unique_left_to_right(self : LineCount) -> Int32 {
  self.unique_left_to_right
}

///|
pub fn LineCount::unique_right_to_left(self : LineCount) -> Int32 {
  self.unique_right_to_left
}

///|
/// Cumulative crossings for one class on one directed line.
#derive(Debug, Eq)
struct LineClassCount {
  line_id : Int32
  class_id : Int32
  left_to_right : Int32
  right_to_left : Int32
  unique_left_to_right : Int32
  unique_right_to_left : Int32
}

///|
pub fn LineClassCount::line_id(self : LineClassCount) -> Int32 {
  self.line_id
}

///|
pub fn LineClassCount::class_id(self : LineClassCount) -> Int32 {
  self.class_id
}

///|
pub fn LineClassCount::left_to_right(self : LineClassCount) -> Int32 {
  self.left_to_right
}

///|
pub fn LineClassCount::right_to_left(self : LineClassCount) -> Int32 {
  self.right_to_left
}

///|
pub fn LineClassCount::unique_left_to_right(self : LineClassCount) -> Int32 {
  self.unique_left_to_right
}

///|
pub fn LineClassCount::unique_right_to_left(self : LineClassCount) -> Int32 {
  self.unique_right_to_left
}

///|
/// Cumulative entries, exits and unique identities for one region.
#derive(Debug, Eq)
struct RegionCount {
  region_id : Int32
  entries : Int32
  exits : Int32
  unique_tracks : Int32
  current_occupancy : Int32
  peak_occupancy : Int32
  completed_dwell_frames : Int32
}

///|
pub fn RegionCount::region_id(self : RegionCount) -> Int32 {
  self.region_id
}

///|
pub fn RegionCount::entries(self : RegionCount) -> Int32 {
  self.entries
}

///|
pub fn RegionCount::exits(self : RegionCount) -> Int32 {
  self.exits
}

///|
pub fn RegionCount::unique_tracks(self : RegionCount) -> Int32 {
  self.unique_tracks
}

///|
pub fn RegionCount::current_occupancy(self : RegionCount) -> Int32 {
  self.current_occupancy
}

///|
pub fn RegionCount::peak_occupancy(self : RegionCount) -> Int32 {
  self.peak_occupancy
}

///|
pub fn RegionCount::completed_dwell_frames(self : RegionCount) -> Int32 {
  self.completed_dwell_frames
}

///|
/// Cumulative entries, exits and current occupancy for one class in one region.
#derive(Debug, Eq)
struct RegionClassCount {
  region_id : Int32
  class_id : Int32
  entries : Int32
  exits : Int32
  unique_tracks : Int32
  current_occupancy : Int32
  peak_occupancy : Int32
  completed_dwell_frames : Int32
}

///|
pub fn RegionClassCount::region_id(self : RegionClassCount) -> Int32 {
  self.region_id
}

///|
pub fn RegionClassCount::class_id(self : RegionClassCount) -> Int32 {
  self.class_id
}

///|
pub fn RegionClassCount::entries(self : RegionClassCount) -> Int32 {
  self.entries
}

///|
pub fn RegionClassCount::exits(self : RegionClassCount) -> Int32 {
  self.exits
}

///|
pub fn RegionClassCount::unique_tracks(self : RegionClassCount) -> Int32 {
  self.unique_tracks
}

///|
pub fn RegionClassCount::current_occupancy(self : RegionClassCount) -> Int32 {
  self.current_occupancy
}

///|
pub fn RegionClassCount::peak_occupancy(self : RegionClassCount) -> Int32 {
  self.peak_occupancy
}

///|
pub fn RegionClassCount::completed_dwell_frames(
  self : RegionClassCount,
) -> Int32 {
  self.completed_dwell_frames
}

///|
/// A confirmed exit from one region followed by entry into another.
#derive(Debug, Eq)
struct RegionTransitionCount {
  from_region_id : Int32
  to_region_id : Int32
  class_id : Int32
  count : Int32
}

///|
pub fn RegionTransitionCount::from_region_id(
  self : RegionTransitionCount,
) -> Int32 {
  self.from_region_id
}

///|
pub fn RegionTransitionCount::to_region_id(
  self : RegionTransitionCount,
) -> Int32 {
  self.to_region_id
}

///|
pub fn RegionTransitionCount::class_id(self : RegionTransitionCount) -> Int32 {
  self.class_id
}

///|
pub fn RegionTransitionCount::count(self : RegionTransitionCount) -> Int32 {
  self.count
}

///|
/// One visible identity currently confirmed inside a region.
#derive(Debug, Eq)
struct RegionOccupant {
  region_id : Int32
  track_id : Int32
  class_id : Int32
  dwell_frames : Int32
}

///|
pub fn RegionOccupant::region_id(self : RegionOccupant) -> Int32 {
  self.region_id
}

///|
pub fn RegionOccupant::track_id(self : RegionOccupant) -> Int32 {
  self.track_id
}

///|
pub fn RegionOccupant::class_id(self : RegionOccupant) -> Int32 {
  self.class_id
}

///|
pub fn RegionOccupant::dwell_frames(self : RegionOccupant) -> Int32 {
  self.dwell_frames
}

///|
/// Events and deterministic cumulative snapshots returned for one frame.
#derive(Debug, Eq)
struct AnalyticsFrame {
  frame_id : Int32
  events : Array[AnalyticsEvent]
  line_counts : Array[LineCount]
  line_class_counts : Array[LineClassCount]
  region_counts : Array[RegionCount]
  region_class_counts : Array[RegionClassCount]
  transition_counts : Array[RegionTransitionCount]
  occupants : Array[RegionOccupant]
}

///|
pub fn AnalyticsFrame::frame_id(self : AnalyticsFrame) -> Int32 {
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
pub fn AnalyticsFrame::line_class_counts(
  self : AnalyticsFrame,
) -> Array[LineClassCount] {
  self.line_class_counts.copy()
}

///|
pub fn AnalyticsFrame::region_counts(
  self : AnalyticsFrame,
) -> Array[RegionCount] {
  self.region_counts.copy()
}

///|
pub fn AnalyticsFrame::region_class_counts(
  self : AnalyticsFrame,
) -> Array[RegionClassCount] {
  self.region_class_counts.copy()
}

///|
pub fn AnalyticsFrame::transition_counts(
  self : AnalyticsFrame,
) -> Array[RegionTransitionCount] {
  self.transition_counts.copy()
}

///|
pub fn AnalyticsFrame::occupants(
  self : AnalyticsFrame,
) -> Array[RegionOccupant] {
  self.occupants.copy()
}
