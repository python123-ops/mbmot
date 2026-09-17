///|
/// Stateful line processor for the analytics NDJSON protocol.
pub struct AnalyticsReplaySession {
  mut analyzer : @analytics.SpatialAnalyzer?
  mut lines_read : Int
}

///|
pub fn AnalyticsReplaySession::new() -> AnalyticsReplaySession {
  { analyzer: None, lines_read: 0, }
}

///|
pub fn AnalyticsReplaySession::lines_read(self : AnalyticsReplaySession) -> Int {
  self.lines_read
}

///|
/// Consumes a setup line or frame line. Setup returns `None`; frames return JSON.
pub fn AnalyticsReplaySession::process_line(
  self : AnalyticsReplaySession,
  input : StringView,
) -> String? raise AnalyticsReplayLineError {
  let line = self.lines_read + 1
  self.lines_read = line
  if input.trim().is_empty() {
    return None
  }
  match self.analyzer {
    None => {
      let analyzer = parse_setup(input) catch {
        error => raise AnalyticsReplayLineError(line~, reason=error.message())
      }
      self.analyzer = Some(analyzer)
      None
    }
    Some(analyzer) => {
      let frame = parse_frame(input) catch {
        error => raise AnalyticsReplayLineError(line~, reason=error.message())
      }
      let result = analyzer.update(
        frame.frame,
        frame.tracks,
        frame.lost,
        frame.removed,
      ) catch {
        error => raise AnalyticsReplayLineError(line~, reason=error.message())
      }
      Some(encode_analytics_frame(result))
    }
  }
}
