///|
pub(all) suberror ReplayLineError {
  ReplayLineError(line~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
pub fn ReplayLineError::line(self : ReplayLineError) -> Int {
  let ReplayLineError(line~, ..) = self
  line
}

///|
pub fn ReplayLineError::message(self : ReplayLineError) -> String {
  let ReplayLineError(line~, reason~) = self
  "line " + line.to_string() + ": " + reason
}

///|
pub struct ReplaySession {
  tracker : @mbmot.Tracker
  mut lines_read : Int
}

///|
pub fn ReplaySession::new(config : @mbmot.TrackerConfig) -> ReplaySession {
  { tracker: @mbmot.Tracker::new(config), lines_read: 0, }
}

///|
pub fn ReplaySession::lines_read(self : ReplaySession) -> Int {
  self.lines_read
}

///|
pub fn ReplaySession::process_line(
  self : ReplaySession,
  input : StringView,
) -> String raise ReplayLineError {
  let line = self.lines_read + 1
  self.lines_read = line
  let frame = parse_frame_line(input) catch {
    error => raise ReplayLineError(line~, reason=error.message())
  }
  let result = self.tracker.update(frame.frame(), frame.detections()) catch {
    error => raise ReplayLineError(line~, reason=error.message())
  }
  encode_frame_result(frame.frame(), result)
}
