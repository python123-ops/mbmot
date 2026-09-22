///|
priv struct SequenceInput {
  name : String
  detections : String
  ground_truth : String
} derive(FromJson)

///|
priv struct BatchInput {
  sequences : Array[SequenceInput]
} derive(FromJson)

///|
priv struct BaselineMetric {
  match_iou_threshold : Double
  mota : Double
  idf1 : Double
} derive(FromJson)

///|
priv struct BaselineSequence {
  name : String
  report : BaselineMetric
} derive(FromJson)

///|
priv struct BaselineReport {
  sequences : Array[BaselineSequence]
  overall : BaselineMetric
} derive(FromJson)

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
  if arguments.length() != 2 && arguments.length() != 8 {
    fail_command(
      "usage: mbmot-batch <manifest.json> [--baseline report.json --max-mota-drop N --max-idf1-drop N]",
    )
    return
  }
  // The optional comparison arguments are positional to keep unattended runs
  // fully explicit and reproducible.
  let has_baseline = arguments.length() == 8
  if has_baseline &&
    (
      arguments[2] != "--baseline" ||
      arguments[4] != "--max-mota-drop" ||
      arguments[6] != "--max-idf1-drop"
    ) {
    fail_command(
      "usage: mbmot-batch <manifest.json> [--baseline report.json --max-mota-drop N --max-idf1-drop N]",
    )
    return
  }
  let manifest_text = @fs.read_file(arguments[1]).text()
  let manifest_json = @json.parse(manifest_text) catch {
    _ => {
      fail_command("invalid manifest JSON")
      Json::null()
    }
  }
  let manifest : BatchInput = @json.from_json(manifest_json) catch {
    _ => {
      fail_command("manifest must contain a sequences array")
      { sequences: [], }
    }
  }
  if manifest.sequences.length() == 0 {
    fail_command("manifest must contain at least one sequence")
    return
  }
  let names : Array[String] = []
  for sequence in manifest.sequences {
    if sequence.name.length() == 0 ||
      names.contains(sequence.name) ||
      sequence.detections.length() == 0 ||
      sequence.ground_truth.length() == 0 {
      fail_command("sequence names must be unique and paths nonempty")
      return
    }
    names.push(sequence.name)
  }
  let reports : Array[@evaluation.EvaluationReport] = []
  let output = StringBuilder()
  output.write_string("{\"sequences\":[")
  for index, sequence in manifest.sequences {
    let detections_text = @fs.read_file(sequence.detections).text()
    let detections = @evaluation.parse_detections(detections_text) catch {
      error => {
        fail_command("\{sequence.name} detections: \{error.message()}")
        []
      }
    }
    let ground_truth_text = @fs.read_file(sequence.ground_truth).text()
    let ground_truth = @evaluation.parse_ground_truth(ground_truth_text) catch {
      error => {
        fail_command("\{sequence.name} ground truth: \{error.message()}")
        []
      }
    }
    let tracked = @evaluation.track_detections(
      detections,
      @mbmot.TrackerConfig::default(),
    ) catch {
      error => {
        fail_command("\{sequence.name} tracking: \{error.message()}")
        []
      }
    }
    let report = @evaluation.evaluate(
      ground_truth,
      tracked,
      @evaluation.EvaluationConfig::default(),
    )
    reports.push(report)
    if index > 0 {
      output.write_string(",")
    }
    output.write_string("{\"name\":")
    output.write_string(Json::string(sequence.name).stringify())
    output.write_string(",\"report\":")
    output.write_string(@evaluation.encode_report_json(report))
    output.write_string("}")
  }
  let overall = @evaluation.combine_reports(reports) catch {
    error => {
      fail_command(error.message())
      reports[0]
    }
  }
  output.write_string("],\"overall\":")
  output.write_string(@evaluation.encode_report_json(overall))
  let mut regressed = false
  if has_baseline {
    let mota_limit = @string.parse_double(arguments[5]) catch {
      _ => {
        fail_command("max MOTA drop must be a nonnegative finite number")
        0.0
      }
    }
    let idf1_limit = @string.parse_double(arguments[7]) catch {
      _ => {
        fail_command("max IDF1 drop must be a nonnegative finite number")
        0.0
      }
    }
    if mota_limit.is_nan() ||
      mota_limit.is_inf() ||
      mota_limit < 0.0 ||
      idf1_limit.is_nan() ||
      idf1_limit.is_inf() ||
      idf1_limit < 0.0 {
      fail_command("regression limits must be nonnegative and finite")
      return
    }
    let baseline_json = @json.parse(@fs.read_file(arguments[3]).text()) catch {
      _ => {
        fail_command("invalid baseline report JSON")
        Json::null()
      }
    }
    let baseline : BaselineReport = @json.from_json(baseline_json) catch {
      _ => {
        fail_command("baseline report must contain overall MOTA and IDF1")
        {
          sequences: [],
          overall: { match_iou_threshold: 0.0, mota: 0.0, idf1: 0.0, },
        }
      }
    }
    if baseline.sequences.length() != manifest.sequences.length() ||
      baseline.overall.match_iou_threshold != overall.match_iou_threshold() {
      fail_command("baseline sequences or IoU threshold differ from this run")
      return
    }
    for index, sequence in manifest.sequences {
      if baseline.sequences[index].name != sequence.name ||
        baseline.sequences[index].report.match_iou_threshold !=
        reports[index].match_iou_threshold() {
        fail_command("baseline sequences or IoU threshold differ from this run")
        return
      }
    }
    let mota_delta = overall.mota() - baseline.overall.mota
    let idf1_delta = overall.idf1() - baseline.overall.idf1
    regressed = mota_delta < -mota_limit || idf1_delta < -idf1_limit
    output.write_string(",\"comparison\":{\"mota_delta\":")
    output.write_string(mota_delta.to_string())
    output.write_string(",\"idf1_delta\":")
    output.write_string(idf1_delta.to_string())
    output.write_string(",\"max_mota_drop\":")
    output.write_string(mota_limit.to_string())
    output.write_string(",\"max_idf1_drop\":")
    output.write_string(idf1_limit.to_string())
    output.write_string(",\"sequences\":[")
    for index, sequence in manifest.sequences {
      if index > 0 {
        output.write_string(",")
      }
      let sequence_mota_delta = reports[index].mota() -
        baseline.sequences[index].report.mota
      let sequence_idf1_delta = reports[index].idf1() -
        baseline.sequences[index].report.idf1
      if sequence_mota_delta < -mota_limit || sequence_idf1_delta < -idf1_limit {
        regressed = true
      }
      output.write_string("{\"name\":")
      output.write_string(Json::string(sequence.name).stringify())
      output.write_string(",\"mota_delta\":")
      output.write_string(sequence_mota_delta.to_string())
      output.write_string(",\"idf1_delta\":")
      output.write_string(sequence_idf1_delta.to_string())
      output.write_string("}")
    }
    output.write_string("]")
    output.write_string(",\"regressed\":")
    output.write_string(if regressed { "true" } else { "false" })
    output.write_string("}")
  }
  output.write_string("}")
  @stdio.stdout..write(output.to_string()).write("\n")
  if regressed {
    fail_command("regression limit exceeded")
  }
}
