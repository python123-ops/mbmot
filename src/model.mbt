///|
/// One detector observation supplied to a tracker update.
pub struct Detection {
  bbox : BoundingBox
  score : Double
  class_id : Int
} derive(Debug, Eq)

///|
fn Detection::valid(self : Detection) -> Bool {
  self.bbox.valid() &&
  is_finite(self.score) &&
  self.score >= 0.0 &&
  self.score <= 1.0 &&
  self.class_id >= 0
}

///|
/// Creates a detection after validating its score and class identifier.
pub fn Detection::new(
  bbox : BoundingBox,
  score : Double,
  class_id : Int,
) -> Detection raise TrackerError {
  if !bbox.valid() {
    raise InvalidBoundingBox("detection contains an invalid box")
  }
  if !is_finite(score) || score < 0.0 || score > 1.0 {
    raise InvalidScore(score)
  }
  if class_id < 0 {
    raise InvalidClassId(class_id)
  }
  { bbox, score, class_id, }
}

///|
/// Returns the detection box.
pub fn Detection::bbox(self : Detection) -> BoundingBox {
  self.bbox
}

///|
/// Returns the detector confidence in the closed interval `[0, 1]`.
pub fn Detection::score(self : Detection) -> Double {
  self.score
}

///|
/// Returns the non-negative detector class identifier.
pub fn Detection::class_id(self : Detection) -> Int {
  self.class_id
}

///|
/// Settings that determine detection selection and identity association.
pub struct TrackerConfig {
  high_score_threshold : Double
  low_score_threshold : Double
  new_track_threshold : Double
  first_match_max_cost : Double
  second_match_max_cost : Double
  max_lost_frames : Int
  min_hits : Int
  fuse_score : Bool
} derive(Debug, Eq)

///|
fn valid_unit_interval(value : Double) -> Bool {
  is_finite(value) && value >= 0.0 && value <= 1.0
}

///|
/// Creates a complete tracker configuration.
pub fn TrackerConfig::new(
  high_score_threshold~ : Double,
  low_score_threshold~ : Double,
  new_track_threshold~ : Double,
  first_match_max_cost~ : Double,
  second_match_max_cost~ : Double,
  max_lost_frames~ : Int,
  min_hits~ : Int,
  fuse_score~ : Bool,
) -> TrackerConfig raise TrackerError {
  if !valid_unit_interval(high_score_threshold) ||
    !valid_unit_interval(low_score_threshold) ||
    !valid_unit_interval(new_track_threshold) {
    raise InvalidConfig("score thresholds must be finite values in [0, 1]")
  }
  if low_score_threshold > high_score_threshold {
    raise InvalidConfig(
      "low_score_threshold must not exceed high_score_threshold",
    )
  }
  if !valid_unit_interval(first_match_max_cost) ||
    !valid_unit_interval(second_match_max_cost) {
    raise InvalidConfig("matching costs must be finite values in [0, 1]")
  }
  if max_lost_frames < 0 {
    raise InvalidConfig("max_lost_frames must be non-negative")
  }
  if min_hits < 1 {
    raise InvalidConfig("min_hits must be at least 1")
  }
  {
    high_score_threshold,
    low_score_threshold,
    new_track_threshold,
    first_match_max_cost,
    second_match_max_cost,
    max_lost_frames,
    min_hits,
    fuse_score,
  }
}

///|
/// Returns MBMOT's default association settings.
pub fn TrackerConfig::default() -> TrackerConfig {
  {
    high_score_threshold: 0.25,
    low_score_threshold: 0.10,
    new_track_threshold: 0.25,
    first_match_max_cost: 0.80,
    second_match_max_cost: 0.50,
    max_lost_frames: 30,
    min_hits: 1,
    fuse_score: true,
  }
}

///|
/// Returns the high-confidence cutoff used by the first association stage.
pub fn TrackerConfig::high_score_threshold(self : TrackerConfig) -> Double {
  self.high_score_threshold
}

///|
/// Returns the low-confidence cutoff reserved for the second association stage.
pub fn TrackerConfig::low_score_threshold(self : TrackerConfig) -> Double {
  self.low_score_threshold
}

///|
/// Returns the minimum score allowed to create a new track.
pub fn TrackerConfig::new_track_threshold(self : TrackerConfig) -> Double {
  self.new_track_threshold
}

///|
/// Returns the maximum accepted first-stage assignment cost.
pub fn TrackerConfig::first_match_max_cost(self : TrackerConfig) -> Double {
  self.first_match_max_cost
}

///|
/// Returns the maximum second-stage cost reserved for low-score recovery.
pub fn TrackerConfig::second_match_max_cost(self : TrackerConfig) -> Double {
  self.second_match_max_cost
}

///|
/// Returns the configured number of frames retained after a track is lost.
pub fn TrackerConfig::max_lost_frames(self : TrackerConfig) -> Int {
  self.max_lost_frames
}

///|
/// Returns the number of hits required before a track becomes visible.
pub fn TrackerConfig::min_hits(self : TrackerConfig) -> Int {
  self.min_hits
}

///|
/// Reports whether detector scores are fused into first-stage costs.
pub fn TrackerConfig::fuse_score(self : TrackerConfig) -> Bool {
  self.fuse_score
}

///|
/// A visible tracked object for one processed frame.
pub struct Track {
  track_id : Int
  bbox : BoundingBox
  class_id : Int
  score : Double
  first_frame : Int
  last_frame : Int
  hits : Int
} derive(Debug, Eq)

///|
/// Returns the stable identity assigned by this tracker instance.
pub fn Track::track_id(self : Track) -> Int {
  self.track_id
}

///|
/// Returns the box observed in the current frame.
pub fn Track::bbox(self : Track) -> BoundingBox {
  self.bbox
}

///|
/// Returns the class identifier fixed when the track was created.
pub fn Track::class_id(self : Track) -> Int {
  self.class_id
}

///|
/// Returns the most recent detector confidence.
pub fn Track::score(self : Track) -> Double {
  self.score
}

///|
/// Returns the frame in which the identity was created.
pub fn Track::first_frame(self : Track) -> Int {
  self.first_frame
}

///|
/// Returns the most recent frame associated with the identity.
pub fn Track::last_frame(self : Track) -> Int {
  self.last_frame
}

///|
/// Returns the number of detector observations assigned to the identity.
pub fn Track::hits(self : Track) -> Int {
  self.hits
}

///|
/// The visible tracks and lifecycle events produced by one update.
struct FrameTracks {
  tracks : Array[Track]
  lost : Array[Int]
  removed : Array[Int]
} derive(Debug, Eq)

///|
/// Returns visible tracks sorted by `track_id`.
pub fn FrameTracks::tracks(self : FrameTracks) -> Array[Track] {
  self.tracks.copy()
}

///|
/// Returns identities that entered the recoverable lost state in this frame.
pub fn FrameTracks::lost(self : FrameTracks) -> Array[Int] {
  self.lost.copy()
}

///|
/// Returns identities permanently removed in this frame.
pub fn FrameTracks::removed(self : FrameTracks) -> Array[Int] {
  self.removed.copy()
}
