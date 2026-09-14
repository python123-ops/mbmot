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
