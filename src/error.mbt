///|
/// Errors raised when an MBMOT value or frame violates its input contract.
#derive(Debug)
pub(all) suberror TrackerError {
  InvalidBoundingBox(String)
  InvalidScore(Double)
  InvalidClassId(Int32)
  InvalidConfig(String)
  NonIncreasingFrame(previous~ : Int32, received~ : Int32)
  InvalidDetection(index~ : Int32)
}

///|
pub extend TrackerError with Debug::{to_repr}

///|
/// Returns a stable human-readable description of an input error.
pub fn TrackerError::message(self : TrackerError) -> String {
  match self {
    InvalidBoundingBox(reason) => "invalid bounding box: " + reason
    InvalidScore(score) => "invalid score: " + score.to_string()
    InvalidClassId(class_id) => "invalid class_id: " + class_id.to_string()
    InvalidConfig(reason) => "invalid tracker config: " + reason
    NonIncreasingFrame(previous~, received~) =>
      "frame must increase: previous " +
      previous.to_string() +
      ", received " +
      received.to_string()
    InvalidDetection(index~) =>
      "invalid detection at index " + index.to_string()
  }
}
