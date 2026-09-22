///|
/// Combines independent sequence reports by adding their observations and
/// matching counts. Derived scores are then calculated from the combined
/// counts, never by averaging sequence percentages.
pub fn combine_reports(
  reports : Array[EvaluationReport],
) -> EvaluationReport raise MotError {
  if reports.length() == 0 {
    raise InvalidConfig("at least one sequence report is required")
  }
  let threshold = reports[0].match_iou_threshold
  let mut frames = 0
  let mut ground_truth_detections = 0
  let mut tracker_detections = 0
  let mut true_positives = 0
  let mut false_positives = 0
  let mut false_negatives = 0
  let mut identity_switches = 0
  let mut matched_iou_sum = 0.0
  let mut id_true_positives = 0
  let mut id_false_positives = 0
  let mut id_false_negatives = 0
  for report in reports {
    if report.match_iou_threshold != threshold {
      raise InvalidConfig("sequence reports use different IoU thresholds")
    }
    frames += report.frames
    ground_truth_detections += report.ground_truth_detections
    tracker_detections += report.tracker_detections
    true_positives += report.true_positives
    false_positives += report.false_positives
    false_negatives += report.false_negatives
    identity_switches += report.identity_switches
    matched_iou_sum += report.matched_iou_sum
    id_true_positives += report.id_true_positives
    id_false_positives += report.id_false_positives
    id_false_negatives += report.id_false_negatives
  }
  {
    match_iou_threshold: threshold,
    frames,
    ground_truth_detections,
    tracker_detections,
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
