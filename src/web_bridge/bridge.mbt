///|
priv struct BrowserSession {
  setup : String
  tracker : @replay_codec.ReplaySession
  analytics : @analytics_codec.AnalyticsReplaySession
}

///|
let sessions : Map[Int, BrowserSession] = Map([])

///|
let next_session_id : Ref[Int] = Ref(1)

///|
priv suberror BridgeFailure {
  BridgeFailure(String)
} derive(Debug)

///|
fn BridgeFailure::message(self : BridgeFailure) -> String {
  let BridgeFailure(message) = self
  message
}

///|
fn error_result(code : String, message : String) -> String {
  let escaped_code = Json::string(code).stringify()
  let escaped_message = Json::string(message).stringify()
  "{\"ok\":false,\"code\":\{escaped_code},\"message\":\{escaped_message}}"
}

///|
fn success_result(result : String) -> String {
  "{\"ok\":true,\"result\":\{result}}"
}

///|
fn create_session(
  config_json : StringView,
) -> BrowserSession raise BridgeFailure {
  let analytics = @analytics_codec.AnalyticsReplaySession::new()
  let setup = analytics.process_line(config_json) catch {
    error => raise BridgeFailure(error.message())
  }
  if setup is Some(_) {
    raise BridgeFailure("analytics setup must not produce a frame result")
  }
  {
    setup: config_json.to_owned(),
    tracker: @replay_codec.ReplaySession::new(@mbmot.TrackerConfig::default()),
    analytics,
  }
}

///|
fn BrowserSession::process(
  self : BrowserSession,
  frame_json : StringView,
) -> String raise BridgeFailure {
  let tracking = self.tracker.process_line(frame_json) catch {
    error => raise BridgeFailure(error.message())
  }
  let analytics = self.analytics.process_line(tracking) catch {
    error => raise BridgeFailure(error.message())
  }
  match analytics {
    Some(spatial) => "{\"tracking\":\{tracking},\"analytics\":\{spatial}}"
    None => raise BridgeFailure("analytics frame did not produce output")
  }
}

///|
pub fn mbmot_create(config_json : String) -> String {
  let session = create_session(config_json) catch {
    error => return error_result("invalid_config", error.message())
  }
  let id = next_session_id.val
  next_session_id.val = id + 1
  sessions[id] = session
  success_result("{\"session_id\":\{id}}")
}

///|
pub fn mbmot_update(session_id : Int, frame_json : String) -> String {
  match sessions.get(session_id) {
    None => error_result("unknown_session", "session does not exist")
    Some(session) => {
      let output = session.process(frame_json) catch {
        error => return error_result("invalid_frame", error.message())
      }
      success_result(output)
    }
  }
}

///|
pub fn mbmot_reset(session_id : Int) -> String {
  match sessions.get(session_id) {
    None => error_result("unknown_session", "session does not exist")
    Some(session) => {
      let replacement = create_session(session.setup) catch {
        error => return error_result("invalid_config", error.message())
      }
      sessions[session_id] = replacement
      success_result("{\"reset\":true}")
    }
  }
}

///|
pub fn mbmot_close(session_id : Int) -> String {
  if sessions.contains(session_id) {
    sessions.remove(session_id)
    success_result("{\"closed\":true}")
  } else {
    error_result("unknown_session", "session does not exist")
  }
}

///|
/// Converts one center-box detector frame to the existing replay protocol.
/// This function is stateless; frame ordering belongs to the replay session.
pub fn mbmot_convert_yolo_frame(frame_json : String) -> String {
  let frame = @detection_adapter.parse_yolo_frame(frame_json) catch {
    error => return error_result("invalid_detection", error.message())
  }
  success_result(@detection_adapter.encode_replay_frame(frame))
}
