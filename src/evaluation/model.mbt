///|
/// An error raised while parsing or evaluating MOT records.
pub(all) suberror MotError {
  InvalidConfig(String)
  InvalidMotLine(line~ : Int, message~ : String)
}

///|
pub fn MotError::message(self : MotError) -> String {
  match self {
    InvalidConfig(message) => message
    InvalidMotLine(line~, message~) => "line \{line}: \{message}"
  }
}

///|
/// One axis-aligned observation in a MOT sequence.
pub struct MotObject {
  frame : Int
  identity : Int
  bbox : @mbmot.BoundingBox
  confidence : Double
} derive(Debug, Eq)

///|
/// Creates a validated MOT observation.
pub fn MotObject::new(
  frame : Int,
  identity : Int,
  bbox : @mbmot.BoundingBox,
  confidence : Double,
) -> MotObject raise MotError {
  if frame <= 0 {
    raise InvalidConfig("MOT frame must be positive")
  }
  if identity <= 0 {
    raise InvalidConfig("MOT identity must be positive")
  }
  if confidence.is_nan() || confidence.is_inf() {
    raise InvalidConfig("MOT confidence must be finite")
  }
  { frame, identity, bbox, confidence, }
}

///|
pub fn MotObject::frame(self : MotObject) -> Int {
  self.frame
}

///|
pub fn MotObject::identity(self : MotObject) -> Int {
  self.identity
}

///|
pub fn MotObject::bbox(self : MotObject) -> @mbmot.BoundingBox {
  self.bbox
}

///|
pub fn MotObject::confidence(self : MotObject) -> Double {
  self.confidence
}

///|
/// Configuration shared by the CLEAR and identity metric calculations.
pub struct EvaluationConfig {
  match_iou_threshold : Double
} derive(Debug, Eq)

///|
pub fn EvaluationConfig::new(
  match_iou_threshold~ : Double,
) -> EvaluationConfig raise MotError {
  if match_iou_threshold.is_nan() ||
    match_iou_threshold.is_inf() ||
    match_iou_threshold <= 0.0 ||
    match_iou_threshold > 1.0 {
    raise InvalidConfig("match IoU threshold must be in (0, 1]")
  }
  { match_iou_threshold, }
}

///|
pub fn EvaluationConfig::default() -> EvaluationConfig {
  { match_iou_threshold: 0.5, }
}

///|
pub fn EvaluationConfig::match_iou_threshold(self : EvaluationConfig) -> Double {
  self.match_iou_threshold
}

///|
/// Aggregate CLEAR and identity measurements for one sequence.
pub struct EvaluationReport {
  match_iou_threshold : Double
  frames : Int
  ground_truth_detections : Int
  tracker_detections : Int
  true_positives : Int
  false_positives : Int
  false_negatives : Int
  identity_switches : Int
  matched_iou_sum : Double
  id_true_positives : Int
  id_false_positives : Int
  id_false_negatives : Int
} derive(Debug, Eq)

///|
pub fn EvaluationReport::match_iou_threshold(self : EvaluationReport) -> Double {
  self.match_iou_threshold
}

///|
pub fn EvaluationReport::frames(self : EvaluationReport) -> Int {
  self.frames
}

///|
pub fn EvaluationReport::ground_truth_detections(
  self : EvaluationReport,
) -> Int {
  self.ground_truth_detections
}

///|
pub fn EvaluationReport::tracker_detections(self : EvaluationReport) -> Int {
  self.tracker_detections
}

///|
pub fn EvaluationReport::true_positives(self : EvaluationReport) -> Int {
  self.true_positives
}

///|
pub fn EvaluationReport::false_positives(self : EvaluationReport) -> Int {
  self.false_positives
}

///|
pub fn EvaluationReport::false_negatives(self : EvaluationReport) -> Int {
  self.false_negatives
}

///|
pub fn EvaluationReport::identity_switches(self : EvaluationReport) -> Int {
  self.identity_switches
}

///|
pub fn EvaluationReport::mota(self : EvaluationReport) -> Double {
  let denominator = if self.ground_truth_detections > 0 {
    self.ground_truth_detections
  } else {
    1
  }
  (self.true_positives - self.false_positives - self.identity_switches).to_double() /
  denominator.to_double()
}

///|
/// Returns the average IoU of matched boxes.
pub fn EvaluationReport::motp(self : EvaluationReport) -> Double {
  if self.true_positives == 0 {
    0.0
  } else {
    self.matched_iou_sum / self.true_positives.to_double()
  }
}

///|
pub fn EvaluationReport::id_true_positives(self : EvaluationReport) -> Int {
  self.id_true_positives
}

///|
pub fn EvaluationReport::id_false_positives(self : EvaluationReport) -> Int {
  self.id_false_positives
}

///|
pub fn EvaluationReport::id_false_negatives(self : EvaluationReport) -> Int {
  self.id_false_negatives
}

///|
pub fn EvaluationReport::id_precision(self : EvaluationReport) -> Double {
  let denominator = self.id_true_positives + self.id_false_positives
  if denominator == 0 {
    0.0
  } else {
    self.id_true_positives.to_double() / denominator.to_double()
  }
}

///|
pub fn EvaluationReport::id_recall(self : EvaluationReport) -> Double {
  let denominator = self.id_true_positives + self.id_false_negatives
  if denominator == 0 {
    0.0
  } else {
    self.id_true_positives.to_double() / denominator.to_double()
  }
}

///|
pub fn EvaluationReport::idf1(self : EvaluationReport) -> Double {
  let denominator = 2 * self.id_true_positives +
    self.id_false_positives +
    self.id_false_negatives
  if denominator == 0 {
    0.0
  } else {
    (2 * self.id_true_positives).to_double() / denominator.to_double()
  }
}
