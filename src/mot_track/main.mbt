///|
extern "C" fn exit_process(code : Int) = "exit"

///|
async fn fail_command(message : String) -> Unit {
  @stdio.stderr..write(message).write("\n")
  exit_process(1)
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.length() != 3 {
    fail_command("usage: mbmot-track <detections.txt> <tracker-results.txt>")
    return
  }
  let input = @fs.read_file(arguments[1]).text()
  let detections = @evaluation.parse_detections(input) catch {
    error => {
      fail_command("detections: \{error.message()}")
      []
    }
  }
  let tracked = @evaluation.track_detections(
    detections,
    @mbmot.TrackerConfig::default(),
  ) catch {
    error => {
      fail_command("tracking: \{error.message()}")
      []
    }
  }
  let encoded = @evaluation.encode_tracker_results(tracked)
  let output = if encoded.length() == 0 { encoded } else { encoded + "\n" }
  @fs.write_file(arguments[2], output)
}
