///|
/// Stateful online association for one ordered frame stream.
struct Tracker {
  config : TrackerConfig
  mut active : Array[Track]
  mut next_id : Int
  mut last_frame : Int?
}

///|
/// Creates an empty tracker with a validated configuration.
pub fn Tracker::new(config : TrackerConfig) -> Tracker {
  { config, active: [], next_id: 1, last_frame: None, }
}

///|
fn association_cost(
  track : Track,
  detection : Detection,
  fuse_score : Bool,
) -> Double {
  if track.class_id != detection.class_id {
    return 1.0e300
  }
  let overlap = track.bbox.iou(detection.bbox)
  if fuse_score {
    1.0 - overlap * detection.score
  } else {
    1.0 - overlap
  }
}

///|
fn validate_detections(
  detections : Array[Detection],
) -> Unit raise TrackerError {
  for index, detection in detections {
    if !detection.valid() {
      raise InvalidDetection(index~)
    }
  }
}

///|
/// Associates one strictly newer frame and returns its visible identities.
///
/// The entire frame is validated before tracker state changes.
pub fn Tracker::update(
  self : Tracker,
  frame_id : Int,
  detections : Array[Detection],
) -> FrameTracks raise TrackerError {
  match self.last_frame {
    Some(previous) if frame_id <= previous =>
      raise NonIncreasingFrame(previous~, received=frame_id)
    _ => ()
  }
  validate_detections(detections)
  let candidates : Array[Detection] = []
  for detection in detections {
    if detection.score >= self.config.high_score_threshold {
      candidates.push(detection)
    }
  }
  let prior_active = match self.last_frame {
    Some(previous) if frame_id == previous + 1 => self.active
    _ => []
  }
  let costs = prior_active.map(track => {
    candidates.map(detection => {
      association_cost(track, detection, self.config.fuse_score)
    })
  })
  let matches = optimal_matches(costs, self.config.first_match_max_cost)
  let track_matched = Array::make(prior_active.length(), false)
  let detection_matched = Array::make(candidates.length(), false)
  let next_active : Array[Track] = []
  let visible : Array[Track] = []
  for pair in matches {
    let old = prior_active[pair.track_index]
    let detection = candidates[pair.detection_index]
    let updated : Track = {
      track_id: old.track_id,
      bbox: detection.bbox,
      class_id: old.class_id,
      score: detection.score,
      first_frame: old.first_frame,
      last_frame: frame_id,
      hits: old.hits + 1,
    }
    track_matched[pair.track_index] = true
    detection_matched[pair.detection_index] = true
    next_active.push(updated)
    if updated.hits >= self.config.min_hits {
      visible.push(updated)
    }
  }
  let removed : Array[Int] = []
  for index, track in self.active {
    let retained = frame_id == track.last_frame + 1 &&
      index < track_matched.length() &&
      track_matched[index]
    if !retained {
      removed.push(track.track_id)
    }
  }
  for index, detection in candidates {
    if !detection_matched[index] &&
      detection.score >= self.config.new_track_threshold {
      let created : Track = {
        track_id: self.next_id,
        bbox: detection.bbox,
        class_id: detection.class_id,
        score: detection.score,
        first_frame: frame_id,
        last_frame: frame_id,
        hits: 1,
      }
      self.next_id += 1
      next_active.push(created)
      if created.hits >= self.config.min_hits {
        visible.push(created)
      }
    }
  }
  next_active.sort_by((left, right) => left.track_id.compare(right.track_id))
  visible.sort_by((left, right) => left.track_id.compare(right.track_id))
  removed.sort()
  self.active = next_active
  self.last_frame = Some(frame_id)
  { tracks: visible, lost: [], removed, }
}

///|
/// Clears every identity and restarts numbering from 1.
pub fn Tracker::reset(self : Tracker) -> Unit {
  self.active = []
  self.next_id = 1
  self.last_frame = None
}
