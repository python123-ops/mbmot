///|
extern "C" fn exit_process(code : Int) = "exit"

///|
async fn main {
  let session = @replay_codec.ReplaySession::new(
    @mbmot.TrackerConfig::default(),
  )
  while @stdio.stdin.read_until("\n") is Some(line) {
    let output = session.process_line(line) catch {
      error => {
        @stdio.stderr..write(error.message()).write("\n")
        exit_process(1)
        ""
      }
    }
    @stdio.stdout..write(output).write("\n")
  }
}
