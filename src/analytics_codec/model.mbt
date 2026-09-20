///|
priv struct InputAnalyticsConfig {
  anchor : String
  stable_frames : Int
} derive(FromJson)

///|
priv struct InputLine {
  id : Int
  start : Array[Double]
  end : Array[Double]
  class_ids : Array[Int]?
} derive(FromJson)

///|
priv struct InputRegion {
  id : Int
  vertices : Array[Array[Double]]
  class_ids : Array[Int]?
} derive(FromJson)

///|
priv struct InputSetup {
  config : InputAnalyticsConfig
  lines : Array[InputLine]
  regions : Array[InputRegion]
} derive(FromJson)

///|
priv struct InputTrack {
  track_id : Int
  xyxy : Array[Double]
  class_id : Int
} derive(FromJson)

///|
priv struct InputFrame {
  frame : Int
  tracks : Array[InputTrack]
  lost : Array[Int]
  removed : Array[Int]
} derive(FromJson)

///|
pub(all) suberror AnalyticsReplayError {
  InvalidJson(String)
  InvalidSetup(String)
  InvalidFrame(String)
  InvalidRule(kind~ : String, index~ : Int, reason~ : String)
  InvalidTrack(index~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
pub fn AnalyticsReplayError::message(self : AnalyticsReplayError) -> String {
  match self {
    InvalidJson(reason) => "invalid JSON: " + reason
    InvalidSetup(reason) => "invalid setup: " + reason
    InvalidFrame(reason) => "invalid frame: " + reason
    InvalidRule(kind~, index~, reason~) =>
      "invalid " + kind + " " + index.to_string() + ": " + reason
    InvalidTrack(index~, reason~) =>
      "invalid track " + index.to_string() + ": " + reason
  }
}

///|
pub(all) suberror AnalyticsReplayLineError {
  AnalyticsReplayLineError(line~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
pub fn AnalyticsReplayLineError::line(self : AnalyticsReplayLineError) -> Int {
  let AnalyticsReplayLineError(line~, ..) = self
  line
}

///|
pub fn AnalyticsReplayLineError::message(
  self : AnalyticsReplayLineError,
) -> String {
  let AnalyticsReplayLineError(line~, reason~) = self
  "line " + line.to_string() + ": " + reason
}

///|
fn parse_json(line : StringView) -> Json raise AnalyticsReplayError {
  @json.parse(line) catch {
    error => raise InvalidJson(error.to_string())
  }
}
