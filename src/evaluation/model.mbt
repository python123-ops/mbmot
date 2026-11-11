///|
/// An error raised while parsing or evaluating MOT records.
pub(all) suberror MotError {
  InvalidConfig(String)
  InvalidMotLine(line~ : Int32, message~ : String)
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
#derive(Debug, Eq)
pub struct MotObject {
  frame : Int32
  identity : Int32
  bbox : @mbmot.BoundingBox
  confidence : Double
}

///|
/// Creates a validated MOT observation.
pub fn MotObject::new(
  frame : Int32,
  identity : Int32,
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
pub fn MotObject::frame(self : MotObject) -> Int32 {
  self.frame
}

///|
pub fn MotObject::identity(self : MotObject) -> Int32 {
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
#derive(Debug, Eq)
pub struct EvaluationConfig {
  match_iou_threshold : Double
}

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
#derive(Debug, Eq)
pub struct EvaluationReport {
  match_iou_threshold : Double
  frames : Int32
  ground_truth_detections : Int32
  tracker_detections : Int32
  true_positives : Int32
  false_positives : Int32
  false_negatives : Int32
  identity_switches : Int32
  matched_iou_sum : Double
  id_true_positives : Int32
  id_false_positives : Int32
  id_false_negatives : Int32
}

///|
pub fn EvaluationReport::match_iou_threshold(self : EvaluationReport) -> Double {
  self.match_iou_threshold
}

///|
pub fn EvaluationReport::frames(self : EvaluationReport) -> Int32 {
  self.frames
}

///|
pub fn EvaluationReport::ground_truth_detections(
  self : EvaluationReport,
) -> Int32 {
  self.ground_truth_detections
}

///|
pub fn EvaluationReport::tracker_detections(self : EvaluationReport) -> Int32 {
  self.tracker_detections
}

///|
pub fn EvaluationReport::true_positives(self : EvaluationReport) -> Int32 {
  self.true_positives
}

///|
pub fn EvaluationReport::false_positives(self : EvaluationReport) -> Int32 {
  self.false_positives
}

///|
pub fn EvaluationReport::false_negatives(self : EvaluationReport) -> Int32 {
  self.false_negatives
}

///|
pub fn EvaluationReport::identity_switches(self : EvaluationReport) -> Int32 {
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
pub fn EvaluationReport::id_true_positives(self : EvaluationReport) -> Int32 {
  self.id_true_positives
}

///|
pub fn EvaluationReport::id_false_positives(self : EvaluationReport) -> Int32 {
  self.id_false_positives
}

///|
pub fn EvaluationReport::id_false_negatives(self : EvaluationReport) -> Int32 {
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
