///|
fn write_json_number(
  builder : StringBuilder,
  name : String,
  value : Double,
) -> Unit {
  builder.write_string("\"")
  builder.write_string(name)
  builder.write_string("\":")
  builder.write_string(value.to_string())
}

///|
fn write_json_int(builder : StringBuilder, name : String, value : Int) -> Unit {
  builder.write_string("\"")
  builder.write_string(name)
  builder.write_string("\":")
  builder.write_string(value.to_string())
}

///|
/// Encodes a report as a single deterministic JSON object.
pub fn encode_report_json(report : EvaluationReport) -> String {
  let output = StringBuilder()
  output.write_string("{")
  write_json_number(output, "match_iou_threshold", report.match_iou_threshold)
  output.write_string(",")
  write_json_int(output, "frames", report.frames)
  output.write_string(",")
  write_json_int(
    output,
    "ground_truth_detections",
    report.ground_truth_detections,
  )
  output.write_string(",")
  write_json_int(output, "tracker_detections", report.tracker_detections)
  output.write_string(",")
  write_json_int(output, "true_positives", report.true_positives)
  output.write_string(",")
  write_json_int(output, "false_positives", report.false_positives)
  output.write_string(",")
  write_json_int(output, "false_negatives", report.false_negatives)
  output.write_string(",")
  write_json_int(output, "identity_switches", report.identity_switches)
  output.write_string(",")
  write_json_number(output, "mota", report.mota())
  output.write_string(",")
  write_json_number(output, "motp", report.motp())
  output.write_string(",")
  write_json_int(output, "id_true_positives", report.id_true_positives)
  output.write_string(",")
  write_json_int(output, "id_false_positives", report.id_false_positives)
  output.write_string(",")
  write_json_int(output, "id_false_negatives", report.id_false_negatives)
  output.write_string(",")
  write_json_number(output, "id_precision", report.id_precision())
  output.write_string(",")
  write_json_number(output, "id_recall", report.id_recall())
  output.write_string(",")
  write_json_number(output, "idf1", report.idf1())
  output.write_string("}")
  output.to_string()
}
