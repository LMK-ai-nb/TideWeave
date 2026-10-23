///|
/// Process newline-delimited JSON (NDJSON) in one incremental pass.
///
/// The first non-blank line is a session header:
/// `{"schema_version":1,"config":{...}}`. Every later non-blank line is one
/// command object, exactly as it would appear in a replay `commands` array.
/// The result is one outcome line per command followed by a final
/// `{"summary":{...}}` line, so the engine can be driven by any line-oriented
/// producer without writing MoonBit or re-parsing a whole batch.
pub fn stream_json(source : String) -> String raise TideError {
  if source.length() > 8388608 {
    fail("JSON exceeds 8 Mi UTF-16 units")
  }
  let lines : Array[String] = []
  for line in source.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.length() > 0 {
      lines.push(trimmed)
    }
  }
  if lines.length() < 1 {
    fail("stream requires a config header line")
  }
  let head = obj(strict_json(lines[0]))
  fields_only(head, ["schema_version", "config"])
  if head.get("schema_version") is Some(v) {
    if integer(v) != 1 {
      fail("unsupported schema_version")
    }
  }
  let c = read_config(req(head, "config"))
  if lines.length() - 1 > 10000 {
    fail("at most 10000 commands per stream")
  }
  let engine = Engine::new(c)
  let out : Array[String] = []
  for i in 1..<lines.length() {
    let cmd = read_command(strict_json(lines[i]))
    out.push(engine.apply(cmd).to_json().stringify())
  }
  let summary : Json = {
    "summary": {
      "schema_version": 1,
      "rows": @json.to_json(engine.rows()),
      "events": @json.to_json(engine.events()),
      "frozen": engine.frozen_count(),
      "watermark": engine.watermark(),
      "version": engine.version(),
      "checkpoint": engine.checkpoint_value(),
    },
  }
  out.push(summary.stringify())
  out.join("\n")
}
