///|
extern "C" fn exit_process(code : Int) = "exit"

///|
async fn fail(message : String) -> Unit {
  @stdio.stderr..write(message).write("\n")
  exit_process(1)
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.length() < 2 || (arguments.length() - 2) % 2 != 0 {
    fail(
      "usage: mbmot-observe <rules.json> [--input yolo|xyxy] [--classes '[0,2]']",
    )
    return
  }
  let mut input_format = "yolo"
  let mut classes : Array[Int] = []
  let mut input_seen = false
  let mut classes_seen = false
  let mut index = 2
  while index < arguments.length() {
    if arguments[index] == "--input" && !input_seen {
      input_format = arguments[index + 1]
      input_seen = true
      if input_format != "yolo" && input_format != "xyxy" {
        fail("--input must be yolo or xyxy")
        return
      }
    } else if arguments[index] == "--classes" && !classes_seen {
      classes_seen = true
      let json = @json.parse(arguments[index + 1]) catch {
        _ => {
          fail("--classes must be a JSON array of class ids")
          Json::array([])
        }
      }
      classes = @json.from_json(json) catch {
        _ => {
          fail("--classes must be a JSON array of class ids")
          []
        }
      }
    } else {
      fail(
        "usage: mbmot-observe <rules.json> [--input yolo|xyxy] [--classes '[0,2]']",
      )
      return
    }
    index += 2
  }
  if input_format == "xyxy" && classes_seen {
    fail("--classes applies only to yolo input")
    return
  }
  let detector = @detection_adapter.YoloSession::new(class_ids=classes) catch {
    error => {
      fail(error.message())
      @detection_adapter.YoloSession::new()
    }
  }
  let tracking = @replay_codec.ReplaySession::new(
    @mbmot.TrackerConfig::default(),
  )
  let analytics = @analytics_codec.AnalyticsReplaySession::new()
  let rules = @fs.read_file(arguments[1]).text()
  if rules.trim().is_empty() {
    fail("rules file must contain one analytics setup object")
    return
  }
  let setup = analytics.process_line(rules) catch {
    error => {
      let @analytics_codec.AnalyticsReplayLineError(reason~, ..) = error
      fail("rules: \{reason}")
      None
    }
  }
  if setup is Some(_) {
    fail("rules file must contain one analytics setup object")
    return
  }
  let mut input_line = 0
  while @stdio.stdin.read_until("\n") is Some(line) {
    input_line += 1
    let converted = if input_format == "yolo" {
      detector.process_line(line) catch {
        error => {
          fail("input line \{input_line}: \{error.message()}")
          ""
        }
      }
    } else {
      line.to_string()
    }
    let tracked = tracking.process_line(converted) catch {
      error => {
        let @replay_codec.ReplayLineError(reason~, ..) = error
        fail("input line \{input_line} (tracking): \{reason}")
        ""
      }
    }
    let spatial = analytics.process_line(tracked) catch {
      error => {
        let @analytics_codec.AnalyticsReplayLineError(reason~, ..) = error
        fail("input line \{input_line} (analytics): \{reason}")
        None
      }
    }
    match spatial {
      Some(result) =>
        @stdio.stdout
        ..write("{\"tracking\":")
        ..write(tracked)
        ..write(",\"analytics\":")
        ..write(result)
        .write("}\n")
      None => {
        fail("input line \{input_line}: analytics produced no frame")
        return
      }
    }
  }
}
