///|
#derive(FromJson)
priv struct InputAnalyticsConfig {
  anchor : String
  stable_frames : Int32
}

///|
#derive(FromJson)
priv struct InputLine {
  id : Int32
  start : Array[Double]
  end : Array[Double]
  class_ids : Array[Int32]?
}

///|
#derive(FromJson)
priv struct InputRegion {
  id : Int32
  vertices : Array[Array[Double]]
  class_ids : Array[Int32]?
}

///|
#derive(FromJson)
priv struct InputSetup {
  config : InputAnalyticsConfig
  lines : Array[InputLine]
  regions : Array[InputRegion]
}

///|
#derive(FromJson)
priv struct InputTrack {
  track_id : Int32
  xyxy : Array[Double]
  class_id : Int32
}

///|
#derive(FromJson)
priv struct InputFrame {
  frame : Int32
  tracks : Array[InputTrack]
  lost : Array[Int32]
  removed : Array[Int32]
}

///|
#derive(Debug, Eq)
pub(all) suberror AnalyticsReplayError {
  InvalidJson(String)
  InvalidSetup(String)
  InvalidFrame(String)
  InvalidRule(kind~ : String, index~ : Int32, reason~ : String)
  InvalidTrack(index~ : Int32, reason~ : String)
}

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
#derive(Debug, Eq)
pub(all) suberror AnalyticsReplayLineError {
  AnalyticsReplayLineError(line~ : Int32, reason~ : String)
}

///|
pub fn AnalyticsReplayLineError::line(self : AnalyticsReplayLineError) -> Int32 {
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
