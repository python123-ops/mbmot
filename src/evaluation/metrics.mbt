///|
fn bbox_iou(left : @mbmot.BoundingBox, right : @mbmot.BoundingBox) -> Double {
  let intersection_left = if left.x1() > right.x1() {
    left.x1()
  } else {
    right.x1()
  }
  let intersection_top = if left.y1() > right.y1() {
    left.y1()
  } else {
    right.y1()
  }
  let intersection_right = if left.x2() < right.x2() {
    left.x2()
  } else {
    right.x2()
  }
  let intersection_bottom = if left.y2() < right.y2() {
    left.y2()
  } else {
    right.y2()
  }
  let width = intersection_right - intersection_left
  let height = intersection_bottom - intersection_top
  if width <= 0.0 || height <= 0.0 {
    return 0.0
  }
  let intersection = width * height
  let left_area = (left.x2() - left.x1()) * (left.y2() - left.y1())
  let right_area = (right.x2() - right.x1()) * (right.y2() - right.y1())
  intersection / (left_area + right_area - intersection)
}

///|
fn indices_by_frame(
  objects : Array[MotObject],
  frames : Int,
) -> Array[Array[Int]] {
  let grouped = Array::makei(frames + 1, _ => [])
  for index, object in objects {
    grouped[object.frame].push(index)
  }
  grouped
}

///|
fn id_index(ids : Array[Int], identity : Int) -> Int {
  match ids.search_by(id => id == identity) {
    Some(index) => index
    None => -1
  }
}

///|
fn unique_ids(objects : Array[MotObject]) -> Array[Int] {
  let ids : Array[Int] = []
  for object in objects {
    if !ids.contains(object.identity) {
      ids.push(object.identity)
    }
  }
  ids.sort()
  ids
}

///|
fn maximum_frame(
  ground_truth : Array[MotObject],
  tracker_results : Array[MotObject],
) -> Int {
  let mut maximum = 0
  for object in ground_truth {
    if object.frame > maximum {
      maximum = object.frame
    }
  }
  for object in tracker_results {
    if object.frame > maximum {
      maximum = object.frame
    }
  }
  maximum
}

///|
fn identity_counts(objects : Array[MotObject], ids : Array[Int]) -> Array[Int] {
  let counts = Array::make(ids.length(), 0)
  for object in objects {
    let index = id_index(ids, object.identity)
    counts[index] += 1
  }
  counts
}

///|
fn identity_metrics(
  ground_truth : Array[MotObject],
  tracker_results : Array[MotObject],
  threshold : Double,
  frames : Int,
) -> (Int, Int, Int) {
  let ground_truth_ids = unique_ids(ground_truth)
  let tracker_ids = unique_ids(tracker_results)
  let ground_truth_counts = identity_counts(ground_truth, ground_truth_ids)
  let tracker_counts = identity_counts(tracker_results, tracker_ids)
  let potential = Array::makei(ground_truth_ids.length(), _ => {
    Array::make(tracker_ids.length(), 0)
  })
  let ground_truth_by_frame = indices_by_frame(ground_truth, frames)
  let tracker_by_frame = indices_by_frame(tracker_results, frames)
  for frame in 1..<=frames {
    let ground_truth_indices = ground_truth_by_frame[frame]
    let tracker_indices = tracker_by_frame[frame]
    for ground_truth_index in ground_truth_indices {
      let truth = ground_truth[ground_truth_index]
      let truth_id_index = id_index(ground_truth_ids, truth.identity)
      for tracker_index in tracker_indices {
        let tracked = tracker_results[tracker_index]
        if bbox_iou(truth.bbox, tracked.bbox) >= threshold {
          let tracker_id_index = id_index(tracker_ids, tracked.identity)
          potential[truth_id_index][tracker_id_index] += 1
        }
      }
    }
  }
  let truth_count = ground_truth_ids.length()
  let tracker_count = tracker_ids.length()
  let size = truth_count + tracker_count
  if size == 0 {
    return (0, 0, 0)
  }
  let costs = Array::makei(size, row => {
    Array::makei(size, column => {
      if row < truth_count && column < tracker_count {
        (ground_truth_counts[row] +
        tracker_counts[column] -
        2 * potential[row][column]).to_double()
      } else if row < truth_count {
        ground_truth_counts[row].to_double()
      } else if column < tracker_count {
        tracker_counts[column].to_double()
      } else {
        0.0
      }
    })
  })
  let assignment = hungarian(costs)
  let assigned_tracker = Array::make(tracker_count, false)
  let mut id_true_positives = 0
  let mut id_false_positives = 0
  let mut id_false_negatives = 0
  for truth_index in 0..<truth_count {
    let tracker_index = assignment[truth_index]
    if tracker_index >= 0 && tracker_index < tracker_count {
      assigned_tracker[tracker_index] = true
      let matched = potential[truth_index][tracker_index]
      id_true_positives += matched
      id_false_negatives += ground_truth_counts[truth_index] - matched
      id_false_positives += tracker_counts[tracker_index] - matched
    } else {
      id_false_negatives += ground_truth_counts[truth_index]
    }
  }
  for tracker_index in 0..<tracker_count {
    if !assigned_tracker[tracker_index] {
      id_false_positives += tracker_counts[tracker_index]
    }
  }
  (id_true_positives, id_false_positives, id_false_negatives)
}

///|
/// Evaluates one sequence using deterministic CLEAR and identity assignments.
pub fn evaluate(
  ground_truth : Array[MotObject],
  tracker_results : Array[MotObject],
  config : EvaluationConfig,
) -> EvaluationReport {
  let frames = maximum_frame(ground_truth, tracker_results)
  let last_frame_pairs : Array[(Int, Int)] = []
  let last_identity_by_truth : Array[(Int, Int)] = []
  let ground_truth_by_frame = indices_by_frame(ground_truth, frames)
  let tracker_by_frame = indices_by_frame(tracker_results, frames)
  let mut true_positives = 0
  let mut false_positives = 0
  let mut false_negatives = 0
  let mut identity_switches = 0
  let mut matched_iou_sum = 0.0
  for frame in 1..<=frames {
    let ground_truth_indices = ground_truth_by_frame[frame]
    let tracker_indices = tracker_by_frame[frame]
    let used_truth = Array::make(ground_truth_indices.length(), false)
    let used_tracker = Array::make(tracker_indices.length(), false)
    let frame_matches : Array[(Int, Int)] = []
    for previous_pair in last_frame_pairs {
      let (previous_truth_id, previous_tracker_id) = previous_pair
      let truth_position = ground_truth_indices.search_by(index => {
        ground_truth[index].identity == previous_truth_id
      })
      let tracker_position = tracker_indices.search_by(index => {
        tracker_results[index].identity == previous_tracker_id
      })
      match (truth_position, tracker_position) {
        (Some(truth_position), Some(tracker_position)) => {
          let similarity = bbox_iou(
            ground_truth[ground_truth_indices[truth_position]].bbox,
            tracker_results[tracker_indices[tracker_position]].bbox,
          )
          if similarity >= config.match_iou_threshold {
            used_truth[truth_position] = true
            used_tracker[tracker_position] = true
            frame_matches.push((truth_position, tracker_position))
          }
        }
        _ => ()
      }
    }
    let remaining_truth : Array[Int] = []
    let remaining_tracker : Array[Int] = []
    for position in 0..<ground_truth_indices.length() {
      if !used_truth[position] {
        remaining_truth.push(position)
      }
    }
    for position in 0..<tracker_indices.length() {
      if !used_tracker[position] {
        remaining_tracker.push(position)
      }
    }
    let similarities = Array::makei(remaining_truth.length(), row => {
      Array::makei(remaining_tracker.length(), column => {
        bbox_iou(
          ground_truth[ground_truth_indices[remaining_truth[row]]].bbox,
          tracker_results[tracker_indices[remaining_tracker[column]]].bbox,
        )
      })
    })
    for
      assignment in maximum_iou_assignment(
        similarities,
        config.match_iou_threshold,
      ) {
      let (truth_row, tracker_column) = assignment
      frame_matches.push(
        (remaining_truth[truth_row], remaining_tracker[tracker_column]),
      )
    }
    last_frame_pairs.clear()
    for frame_match in frame_matches {
      let (truth_position, tracker_position) = frame_match
      let truth = ground_truth[ground_truth_indices[truth_position]]
      let tracked = tracker_results[tracker_indices[tracker_position]]
      true_positives += 1
      matched_iou_sum += bbox_iou(truth.bbox, tracked.bbox)
      match last_identity_by_truth.search_by(pair => pair.0 == truth.identity) {
        Some(index) => {
          if last_identity_by_truth[index].1 != tracked.identity {
            identity_switches += 1
          }
          last_identity_by_truth[index] = (truth.identity, tracked.identity)
        }
        None => last_identity_by_truth.push((truth.identity, tracked.identity))
      }
      last_frame_pairs.push((truth.identity, tracked.identity))
    }
    false_negatives += ground_truth_indices.length() - frame_matches.length()
    false_positives += tracker_indices.length() - frame_matches.length()
  }
  let (id_true_positives, id_false_positives, id_false_negatives) = identity_metrics(
    ground_truth,
    tracker_results,
    config.match_iou_threshold,
    frames,
  )
  {
    match_iou_threshold: config.match_iou_threshold,
    frames,
    ground_truth_detections: ground_truth.length(),
    tracker_detections: tracker_results.length(),
    true_positives,
    false_positives,
    false_negatives,
    identity_switches,
    matched_iou_sum,
    id_true_positives,
    id_false_positives,
    id_false_negatives,
  }
}
