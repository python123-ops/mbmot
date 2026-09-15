///|
/// Errors raised when an MBMOT value or frame violates its input contract.
pub(all) suberror TrackerError {
  InvalidBoundingBox(String)
  InvalidScore(Double)
  InvalidClassId(Int)
  InvalidConfig(String)
  NonIncreasingFrame(previous~ : Int, received~ : Int)
  InvalidDetection(index~ : Int)
} derive(Debug)

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
