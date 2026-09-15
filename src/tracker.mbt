///|
priv enum Lifecycle {
  Active
  Lost
}

///|
priv struct TrackedState {
  track : Track
  motion : MotionState
  lifecycle : Lifecycle
}

///|
/// Stateful online association for one ordered frame stream.
struct Tracker {
  config : TrackerConfig
  mut states : Array[TrackedState]
  mut next_id : Int
  mut last_frame : Int?
}

///|
/// Creates an empty tracker with a validated configuration.
pub fn Tracker::new(config : TrackerConfig) -> Tracker {
  { config, states: [], next_id: 1, last_frame: None, }
}

///|
fn TrackedState::active(self : TrackedState) -> Bool {
  self.lifecycle is Active
}

///|
fn TrackedState::confirmed(self : TrackedState, config : TrackerConfig) -> Bool {
  self.track.hits >= config.min_hits
}

///|
fn TrackedState::predict(self : TrackedState) -> TrackedState {
  {
    track: self.track,
    motion: self.motion.predict(self.lifecycle is Lost),
    lifecycle: self.lifecycle,
  }
}

///|
fn TrackedState::mark_lost(self : TrackedState) -> TrackedState {
  { track: self.track, motion: self.motion, lifecycle: Lost, }
}

///|
fn TrackedState::observe(
  self : TrackedState,
  detection : Detection,
  frame_id : Int,
) -> TrackedState {
  {
    track: {
      track_id: self.track.track_id,
      bbox: detection.bbox,
      class_id: self.track.class_id,
      score: detection.score,
      first_frame: self.track.first_frame,
      last_frame: frame_id,
      hits: self.track.hits + 1,
    },
    motion: self.motion.correct(detection.bbox),
    lifecycle: Active,
  }
}

///|
fn TrackedState::expired(
  self : TrackedState,
  frame_id : Int64,
  config : TrackerConfig,
) -> Bool {
  frame_id - self.track.last_frame.to_int64() >
  config.max_lost_frames.to_int64()
}

///|
fn association_cost(
  state : TrackedState,
  detection : Detection,
  fuse_score : Bool,
) -> Double {
  if state.track.class_id != detection.class_id {
    return 1.0e300
  }
  guard state.motion.bbox() is Some(predicted_bbox) else { return 1.0e300 }
  let overlap = predicted_bbox.iou(detection.bbox)
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
fn advance_silent_frame(
  states : Array[TrackedState],
  frame_id : Int64,
  config : TrackerConfig,
) -> Array[TrackedState] {
  let retained : Array[TrackedState] = []
  for state in states {
    let predicted = state.predict()
    let transitioned = if predicted.active() {
      if predicted.confirmed(config) {
        Some(predicted.mark_lost())
      } else {
        None
      }
    } else {
      Some(predicted)
    }
    match transitioned {
      Some(candidate) if !candidate.expired(frame_id, config) =>
        retained.push(candidate)
      _ => ()
    }
  }
  retained
}

///|
fn advance_skipped_frames(
  states : Array[TrackedState],
  previous_frame : Int,
  frame_id : Int,
  config : TrackerConfig,
) -> Array[TrackedState] {
  let previous = previous_frame.to_int64()
  let current = frame_id.to_int64()
  let silent_count = current - previous - 1L
  if silent_count <= 0L {
    return states
  }
  if silent_count > config.max_lost_frames.to_int64() {
    return []
  }
  let mut advanced = states
  let mut skipped = previous + 1L
  while skipped < current {
    advanced = advance_silent_frame(advanced, skipped, config)
    skipped += 1L
  }
  advanced
}

///|
fn new_state(
  track_id : Int,
  detection : Detection,
  frame_id : Int,
) -> TrackedState {
  {
    track: {
      track_id,
      bbox: detection.bbox,
      class_id: detection.class_id,
      score: detection.score,
      first_frame: frame_id,
      last_frame: frame_id,
      hits: 1,
    },
    motion: MotionState::init(detection.bbox),
    lifecycle: Active,
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
  let working = match self.last_frame {
    Some(previous) =>
      advance_skipped_frames(self.states, previous, frame_id, self.config)
    None => self.states
  }
  let predicted = working.map(state => state.predict())
  predicted.sort_by((left, right) => {
    left.track.track_id.compare(right.track.track_id)
  })
  let high : Array[Detection] = []
  let low : Array[Detection] = []
  for detection in detections {
    if detection.score >= self.config.high_score_threshold {
      high.push(detection)
    } else if detection.score >= self.config.low_score_threshold {
      low.push(detection)
    }
  }
  let first_costs = predicted.map(state => {
    high.map(detection => {
      association_cost(state, detection, self.config.fuse_score)
    })
  })
  let first_matches = optimal_matches(
    first_costs,
    self.config.first_match_max_cost,
  )
  let state_matched = Array::make(predicted.length(), false)
  let high_matched = Array::make(high.length(), false)
  let active_states : Array[TrackedState] = []
  for pair in first_matches {
    let updated = predicted[pair.track_index].observe(
      high[pair.detection_index],
      frame_id,
    )
    state_matched[pair.track_index] = true
    high_matched[pair.detection_index] = true
    active_states.push(updated)
  }
  let low_pool : Array[TrackedState] = []
  let pending_lost : Array[TrackedState] = []
  let removed : Array[Int] = []
  for index, state in predicted {
    if !state_matched[index] {
      if state.active() {
        if state.confirmed(self.config) {
          low_pool.push(state)
        } else {
          removed.push(state.track.track_id)
        }
      } else {
        pending_lost.push(state)
      }
    }
  }
  let second_costs = low_pool.map(state => {
    low.map(detection => association_cost(state, detection, false))
  })
  let second_matches = optimal_matches(
    second_costs,
    self.config.second_match_max_cost,
  )
  let low_state_matched = Array::make(low_pool.length(), false)
  for pair in second_matches {
    let updated = low_pool[pair.track_index].observe(
      low[pair.detection_index],
      frame_id,
    )
    low_state_matched[pair.track_index] = true
    active_states.push(updated)
  }
  let newly_lost : Array[TrackedState] = []
  for index, state in low_pool {
    if !low_state_matched[index] {
      let lost_state = state.mark_lost()
      pending_lost.push(lost_state)
      newly_lost.push(lost_state)
    }
  }
  let mut next_id = self.next_id
  for index, detection in high {
    if !high_matched[index] &&
      detection.score >= self.config.new_track_threshold {
      active_states.push(new_state(next_id, detection, frame_id))
      next_id += 1
    }
  }
  let retained_lost : Array[TrackedState] = []
  let lost : Array[Int] = []
  for state in pending_lost {
    if state.expired(frame_id.to_int64(), self.config) {
      removed.push(state.track.track_id)
    } else {
      retained_lost.push(state)
    }
  }
  for state in newly_lost {
    if !state.expired(frame_id.to_int64(), self.config) {
      lost.push(state.track.track_id)
    }
  }
  let next_states = active_states.copy()
  next_states.push_iter(retained_lost.iter())
  next_states.sort_by((left, right) => {
    left.track.track_id.compare(right.track.track_id)
  })
  let visible : Array[Track] = []
  for state in active_states {
    if state.confirmed(self.config) {
      visible.push(state.track)
    }
  }
  visible.sort_by((left, right) => left.track_id.compare(right.track_id))
  lost.sort()
  removed.sort()
  self.states = next_states
  self.next_id = next_id
  self.last_frame = Some(frame_id)
  { tracks: visible, lost, removed, }
}

///|
/// Clears every identity and restarts numbering from 1.
pub fn Tracker::reset(self : Tracker) -> Unit {
  self.states = []
  self.next_id = 1
  self.last_frame = None
}

///|
/// Summarizes retained identity state without exposing motion internals.
pub fn Tracker::status(self : Tracker) -> TrackerStatus {
  let mut active_count = 0
  let mut tentative_count = 0
  let mut lost_count = 0
  for state in self.states {
    if state.active() {
      if state.confirmed(self.config) {
        active_count += 1
      } else {
        tentative_count += 1
      }
    } else {
      lost_count += 1
    }
  }
  { last_frame: self.last_frame, active_count, tentative_count, lost_count, }
}
