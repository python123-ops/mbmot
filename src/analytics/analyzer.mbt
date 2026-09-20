///|
priv struct LineState {
  mut has_stable : Bool
  mut stable_side : Int
  mut candidate_side : Int
  mut candidate_count : Int
}

///|
priv struct RegionState {
  mut stable_inside : Bool?
  mut candidate_inside : Bool?
  mut candidate_count : Int
  mut candidate_start : Int
  mut entry_frame : Int?
}

///|
priv struct TrackState {
  track_id : Int
  class_id : Int
  lines : Array[LineState]
  regions : Array[RegionState]
}

///|
priv struct LineTotals {
  mut left_to_right : Int
  mut right_to_left : Int
}

///|
priv struct RegionTotals {
  mut entries : Int
  mut exits : Int
  unique_ids : Array[Int]
}

///|
/// Stateful conversion from visible track samples to spatial events and counts.
struct SpatialAnalyzer {
  config : AnalyticsConfig
  lines : Array[DirectedLine]
  regions : Array[PolygonRegion]
  mut tracks : Array[TrackState]
  mut removed_ids : Array[Int]
  mut line_totals : Array[LineTotals]
  mut region_totals : Array[RegionTotals]
  mut last_frame : Int?
}

///|
fn ensure_unique_rule_ids(
  kind : String,
  ids : Array[Int],
) -> Unit raise AnalyticsError {
  let sorted = ids.copy()
  sorted.sort()
  for index = 1; index < sorted.length(); index = index + 1 {
    if sorted[index] == sorted[index - 1] {
      raise DuplicateRuleId(kind~, id=sorted[index])
    }
  }
}

///|
/// Creates an analyzer and fixes a deterministic rule order by rule identifier.
pub fn SpatialAnalyzer::new(
  config : AnalyticsConfig,
  lines : Array[DirectedLine],
  regions : Array[PolygonRegion],
) -> SpatialAnalyzer raise AnalyticsError {
  ensure_unique_rule_ids("line", lines.map(line => line.id))
  ensure_unique_rule_ids("region", regions.map(region => region.id))
  let sorted_lines = lines.copy()
  sorted_lines.sort_by((left, right) => left.id.compare(right.id))
  let sorted_regions = regions.copy()
  sorted_regions.sort_by((left, right) => left.id.compare(right.id))
  {
    config,
    lines: sorted_lines,
    regions: sorted_regions,
    tracks: [],
    removed_ids: [],
    line_totals: sorted_lines.map(_ => { left_to_right: 0, right_to_left: 0, }),
    region_totals: sorted_regions.map(_ => {
      entries: 0,
      exits: 0,
      unique_ids: [],
    }),
    last_frame: None,
  }
}

///|
fn LineState::copy_state(self : LineState) -> LineState {
  {
    has_stable: self.has_stable,
    stable_side: self.stable_side,
    candidate_side: self.candidate_side,
    candidate_count: self.candidate_count,
  }
}

///|
fn RegionState::copy_state(self : RegionState) -> RegionState {
  {
    stable_inside: self.stable_inside,
    candidate_inside: self.candidate_inside,
    candidate_count: self.candidate_count,
    candidate_start: self.candidate_start,
    entry_frame: self.entry_frame,
  }
}

///|
fn TrackState::copy_state(self : TrackState) -> TrackState {
  {
    track_id: self.track_id,
    class_id: self.class_id,
    lines: self.lines.map(state => state.copy_state()),
    regions: self.regions.map(state => state.copy_state()),
  }
}

///|
fn new_track_state(
  sample : TrackSample,
  line_count : Int,
  region_count : Int,
) -> TrackState {
  {
    track_id: sample.track_id,
    class_id: sample.class_id,
    lines: Array::makei(line_count, _ => {
      has_stable: false,
      stable_side: 0,
      candidate_side: 0,
      candidate_count: 0,
    }),
    regions: Array::makei(region_count, _ => {
      stable_inside: None,
      candidate_inside: None,
      candidate_count: 0,
      candidate_start: 0,
      entry_frame: None,
    }),
  }
}

///|
fn find_track(states : Array[TrackState], track_id : Int) -> Int? {
  for index, state in states {
    if state.track_id == track_id {
      return Some(index)
    }
  }
  None
}

///|
fn contains_id(ids : Array[Int], id : Int) -> Bool {
  ids.any(value => value == id)
}

///|
fn validate_id_list(ids : Array[Int]) -> Unit raise AnalyticsError {
  let seen : Array[Int] = []
  for id in ids {
    if id <= 0 {
      raise InvalidTrackId(id)
    }
    if contains_id(seen, id) {
      raise ConflictingTrackId(id)
    }
    seen.push(id)
  }
}

///|
fn validate_frame_inputs(
  states : Array[TrackState],
  removed_ids : Array[Int],
  samples : Array[TrackSample],
  lost : Array[Int],
  removed : Array[Int],
) -> Unit raise AnalyticsError {
  validate_id_list(lost)
  validate_id_list(removed)
  let visible_ids : Array[Int] = []
  for sample in samples {
    if sample.track_id <= 0 {
      raise InvalidTrackId(sample.track_id)
    }
    if sample.class_id < 0 {
      raise InvalidClassId(sample.class_id)
    }
    if contains_id(visible_ids, sample.track_id) {
      raise DuplicateTrackId(sample.track_id)
    }
    if contains_id(removed_ids, sample.track_id) {
      raise ReusedRemovedId(sample.track_id)
    }
    match find_track(states, sample.track_id) {
      Some(index) if states[index].class_id != sample.class_id =>
        raise ChangedClassId(
          track_id=sample.track_id,
          previous=states[index].class_id,
          received=sample.class_id,
        )
      _ => ()
    }
    visible_ids.push(sample.track_id)
  }
  for id in lost {
    if contains_id(visible_ids, id) || contains_id(removed, id) {
      raise ConflictingTrackId(id)
    }
    if contains_id(removed_ids, id) {
      raise ReusedRemovedId(id)
    }
    if find_track(states, id) is None {
      raise UnknownLifecycleId(id)
    }
  }
  for id in removed {
    if contains_id(visible_ids, id) || contains_id(lost, id) {
      raise ConflictingTrackId(id)
    }
    if contains_id(removed_ids, id) {
      raise ReusedRemovedId(id)
    }
    if find_track(states, id) is None {
      raise UnknownLifecycleId(id)
    }
  }
}

///|
fn LineState::interrupt(self : LineState) -> Unit {
  self.has_stable = false
  self.stable_side = 0
  self.candidate_side = 0
  self.candidate_count = 0
}

///|
fn RegionState::interrupt(self : RegionState) -> Unit {
  self.candidate_inside = None
  self.candidate_count = 0
  self.candidate_start = 0
}

///|
fn advance_line(
  state : LineState,
  side : Int,
  stable_frames : Int,
  line_id : Int,
  track_id : Int,
  totals : LineTotals,
  events : Array[AnalyticsEvent],
) -> Unit {
  if side == 0 {
    return
  }
  if !state.has_stable {
    if state.candidate_side == side {
      state.candidate_count += 1
    } else {
      state.candidate_side = side
      state.candidate_count = 1
    }
    if state.candidate_count >= stable_frames {
      state.has_stable = true
      state.stable_side = side
      state.candidate_side = 0
      state.candidate_count = 0
    }
    return
  }
  if state.stable_side == side {
    state.candidate_side = 0
    state.candidate_count = 0
    return
  }
  if state.candidate_side == side {
    state.candidate_count += 1
  } else {
    state.candidate_side = side
    state.candidate_count = 1
  }
  if state.candidate_count < stable_frames {
    return
  }
  let direction = if state.stable_side > 0 { LeftToRight } else { RightToLeft }
  match direction {
    LeftToRight => totals.left_to_right += 1
    RightToLeft => totals.right_to_left += 1
  }
  events.push(LineCrossed(line_id~, track_id~, direction~))
  state.stable_side = side
  state.candidate_side = 0
  state.candidate_count = 0
}

///|
fn remember_unique(totals : RegionTotals, track_id : Int) -> Unit {
  if !contains_id(totals.unique_ids, track_id) {
    totals.unique_ids.push(track_id)
  }
}

///|
fn confirm_initial_region(
  state : RegionState,
  inside : Bool,
  region_id : Int,
  track_id : Int,
  totals : RegionTotals,
  events : Array[AnalyticsEvent],
) -> Unit {
  state.stable_inside = Some(inside)
  if inside {
    state.entry_frame = Some(state.candidate_start)
    totals.entries += 1
    remember_unique(totals, track_id)
    events.push(RegionEntered(region_id~, track_id~, initial=true))
  }
  state.candidate_inside = None
  state.candidate_count = 0
}

///|
fn advance_region(
  state : RegionState,
  classification : Int,
  frame_id : Int,
  stable_frames : Int,
  region_id : Int,
  track_id : Int,
  totals : RegionTotals,
  events : Array[AnalyticsEvent],
) -> Unit {
  if classification == 0 {
    return
  }
  let inside = classification > 0
  match state.stable_inside {
    None => {
      if state.candidate_inside == Some(inside) {
        state.candidate_count += 1
      } else {
        state.candidate_inside = Some(inside)
        state.candidate_count = 1
        state.candidate_start = frame_id
      }
      if state.candidate_count >= stable_frames {
        confirm_initial_region(
          state, inside, region_id, track_id, totals, events,
        )
      }
    }
    Some(stable) => {
      if stable == inside {
        state.candidate_inside = None
        state.candidate_count = 0
        return
      }
      if state.candidate_inside == Some(inside) {
        state.candidate_count += 1
      } else {
        state.candidate_inside = Some(inside)
        state.candidate_count = 1
        state.candidate_start = frame_id
      }
      if state.candidate_count < stable_frames {
        return
      }
      state.stable_inside = Some(inside)
      if inside {
        state.entry_frame = Some(state.candidate_start)
        totals.entries += 1
        remember_unique(totals, track_id)
        events.push(RegionEntered(region_id~, track_id~, initial=false))
      } else {
        let dwell_frames = match state.entry_frame {
          Some(entered) => state.candidate_start - entered
          None => 0
        }
        state.entry_frame = None
        totals.exits += 1
        events.push(RegionExited(region_id~, track_id~, dwell_frames~))
      }
      state.candidate_inside = None
      state.candidate_count = 0
    }
  }
}

///|
fn event_key(event : AnalyticsEvent) -> (Int, Int, Int) {
  match event {
    LineCrossed(line_id~, track_id~, ..) => (0, line_id, track_id)
    RegionEntered(region_id~, track_id~, ..) => (1, region_id, track_id)
    RegionExited(region_id~, track_id~, ..) => (2, region_id, track_id)
  }
}

///|
fn compare_event(left : AnalyticsEvent, right : AnalyticsEvent) -> Int {
  let (left_kind, left_rule, left_track) = event_key(left)
  let (right_kind, right_rule, right_track) = event_key(right)
  if left_kind != right_kind {
    left_kind.compare(right_kind)
  } else if left_rule != right_rule {
    left_rule.compare(right_rule)
  } else {
    left_track.compare(right_track)
  }
}

///|
fn make_frame(
  frame_id : Int,
  lines : Array[DirectedLine],
  regions : Array[PolygonRegion],
  states : Array[TrackState],
  visible_ids : Array[Int],
  line_totals : Array[LineTotals],
  region_totals : Array[RegionTotals],
  events : Array[AnalyticsEvent],
) -> AnalyticsFrame {
  events.sort_by(compare_event)
  let line_counts = Array::makei(lines.length(), index => {
    line_id: lines[index].id,
    left_to_right: line_totals[index].left_to_right,
    right_to_left: line_totals[index].right_to_left,
  })
  let occupants : Array[RegionOccupant] = []
  let region_counts : Array[RegionCount] = []
  for region_index, region in regions {
    let mut occupancy = 0
    for state in states {
      if !contains_id(visible_ids, state.track_id) {
        continue
      }
      let region_state = state.regions[region_index]
      if region_state.stable_inside == Some(true) {
        let dwell_frames = match region_state.entry_frame {
          Some(entered) => frame_id - entered + 1
          None => 0
        }
        occupants.push({
          region_id: region.id,
          track_id: state.track_id,
          class_id: state.class_id,
          dwell_frames,
        })
        occupancy += 1
      }
    }
    region_counts.push({
      region_id: region.id,
      entries: region_totals[region_index].entries,
      exits: region_totals[region_index].exits,
      unique_tracks: region_totals[region_index].unique_ids.length(),
      current_occupancy: occupancy,
    })
  }
  occupants.sort_by((left, right) => {
    if left.region_id != right.region_id {
      left.region_id.compare(right.region_id)
    } else {
      left.track_id.compare(right.track_id)
    }
  })
  { frame_id, events, line_counts, region_counts, occupants, }
}

///|
/// Advances one frame atomically. Coordinates and rules must share one scale.
pub fn SpatialAnalyzer::update(
  self : SpatialAnalyzer,
  frame_id : Int,
  samples : Array[TrackSample],
  lost : Array[Int],
  removed : Array[Int],
) -> AnalyticsFrame raise AnalyticsError {
  match self.last_frame {
    Some(previous) if frame_id <= previous =>
      raise NonIncreasingFrame(previous~, received=frame_id)
    _ => ()
  }
  validate_frame_inputs(self.tracks, self.removed_ids, samples, lost, removed)
  let working_tracks = self.tracks.map(state => state.copy_state())
  let working_removed = self.removed_ids.copy()
  let working_lines = self.line_totals.map(total => {
    left_to_right: total.left_to_right,
    right_to_left: total.right_to_left,
  })
  let working_regions = self.region_totals.map(total => {
    entries: total.entries,
    exits: total.exits,
    unique_ids: total.unique_ids.copy(),
  })
  for id in lost {
    guard find_track(working_tracks, id) is Some(index) else { continue }
    for line_state in working_tracks[index].lines {
      line_state.interrupt()
    }
    for region_state in working_tracks[index].regions {
      region_state.interrupt()
    }
  }
  for id in removed {
    working_removed.push(id)
  }
  let retained = working_tracks.filter(state => {
    !contains_id(removed, state.track_id)
  })
  let ordered_samples = samples.copy()
  ordered_samples.sort_by((left, right) => left.track_id.compare(right.track_id))
  let events : Array[AnalyticsEvent] = []
  for sample in ordered_samples {
    let state_index = match find_track(retained, sample.track_id) {
      Some(index) => index
      None => {
        retained.push(
          new_track_state(sample, self.lines.length(), self.regions.length()),
        )
        retained.length() - 1
      }
    }
    let state = retained[state_index]
    let point = sample.anchor_point(self.config.anchor)
    for line_index, line in self.lines {
      if !line.accepts_class(state.class_id) {
        continue
      }
      advance_line(
        state.lines[line_index],
        line.classify(point),
        self.config.stable_frames,
        line.id,
        state.track_id,
        working_lines[line_index],
        events,
      )
    }
    for region_index, region in self.regions {
      if !region.accepts_class(state.class_id) {
        continue
      }
      advance_region(
        state.regions[region_index],
        region.classify(point),
        frame_id,
        self.config.stable_frames,
        region.id,
        state.track_id,
        working_regions[region_index],
        events,
      )
    }
  }
  retained.sort_by((left, right) => left.track_id.compare(right.track_id))
  working_removed.sort()
  let visible_ids = ordered_samples.map(sample => sample.track_id)
  let frame = make_frame(
    frame_id,
    self.lines,
    self.regions,
    retained,
    visible_ids,
    working_lines,
    working_regions,
    events,
  )
  self.tracks = retained
  self.removed_ids = working_removed
  self.line_totals = working_lines
  self.region_totals = working_regions
  self.last_frame = Some(frame_id)
  frame
}

///|
/// Accepts the visible and lifecycle output of an MBMOT tracker directly.
pub fn SpatialAnalyzer::update_mbmot(
  self : SpatialAnalyzer,
  frame_id : Int,
  frame_tracks : @mbmot.FrameTracks,
) -> AnalyticsFrame raise AnalyticsError {
  self.update(
    frame_id,
    frame_tracks.tracks().map(TrackSample::from_track),
    frame_tracks.lost(),
    frame_tracks.removed(),
  )
}

///|
/// Clears identities, counters, dwell state and the frame clock.
pub fn SpatialAnalyzer::reset(self : SpatialAnalyzer) -> Unit {
  self.tracks = []
  self.removed_ids = []
  self.line_totals = self.lines.map(_ => { left_to_right: 0, right_to_left: 0, })
  self.region_totals = self.regions.map(_ => {
    entries: 0,
    exits: 0,
    unique_ids: [],
  })
  self.last_frame = None
}
