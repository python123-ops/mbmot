///|
extern "C" fn exit_process(code : Int) = "exit"

///|
async fn main {
  let session = @analytics_codec.AnalyticsReplaySession::new()
  while @stdio.stdin.read_until("\n") is Some(line) {
    let output = session.process_line(line) catch {
      error => {
        @stdio.stderr..write(error.message()).write("\n")
        exit_process(1)
        None
      }
    }
    match output {
      Some(value) => @stdio.stdout..write(value).write("\n")
      None => ()
    }
  }
}
