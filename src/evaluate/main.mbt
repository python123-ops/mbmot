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
    fail_command(
      "usage: mbmot-evaluate <ground-truth.txt> <tracker-results.txt>",
    )
    return
  }
  let ground_truth_text = @fs.read_file(arguments[1]).text()
  let tracker_text = @fs.read_file(arguments[2]).text()
  let ground_truth = @evaluation.parse_ground_truth(ground_truth_text) catch {
    error => {
      fail_command("ground truth: \{error.message()}")
      []
    }
  }
  let tracker_results = @evaluation.parse_tracker_results(tracker_text) catch {
    error => {
      fail_command("tracker results: \{error.message()}")
      []
    }
  }
  let report = @evaluation.evaluate(
    ground_truth,
    tracker_results,
    @evaluation.EvaluationConfig::default(),
  )
  @stdio.stdout..write(@evaluation.encode_report_json(report)).write("\n")
}
