///|
extern "C" fn exit_process(code : Int) = "exit"

///|
async fn main {
  let arguments = @env.args()
  let mut classes : Array[Int] = []
  if arguments.length() == 3 && arguments[1] == "--classes" {
    let json = @json.parse(arguments[2]) catch {
      _ => {
        @stdio.stderr.write("--classes must be a JSON array of class ids\n")
        exit_process(1)
        Json::array([])
      }
    }
    classes = @json.from_json(json) catch {
      _ => {
        @stdio.stderr.write("--classes must be a JSON array of class ids\n")
        exit_process(1)
        []
      }
    }
  } else if arguments.length() != 1 {
    @stdio.stderr.write("usage: mbmot-yolo-import [--classes '[0,2]']\n")
    exit_process(1)
  }
  let session = @detection_adapter.YoloSession::new(class_ids=classes) catch {
    error => {
      @stdio.stderr..write(error.message()).write("\n")
      exit_process(1)
      @detection_adapter.YoloSession::new()
    }
  }
  while @stdio.stdin.read_until("\n") is Some(line) {
    let output = session.process_line(line) catch {
      error => {
        @stdio.stderr
        ..write("line \{session.lines_read()}: \{error.message()}")
        .write("\n")
        exit_process(1)
        ""
      }
    }
    @stdio.stdout..write(output).write("\n")
  }
}
