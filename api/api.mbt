///|
fn bad_input(message : String) -> String {
  let value : Json = {
    "schema_version": 1,
    "error": { "code": "INVALID_INPUT", "message": message },
  }
  value.stringify()
}

///|
pub fn replay(source : String) -> String {
  @tide.replay_json(source) catch {
    @tide.TideError(message) => bad_input(message)
  }
}

///|
pub fn resume_replay(source : String) -> String {
  @tide.resume_json(source) catch {
    @tide.TideError(message) => bad_input(message)
  }
}

///|
/// Drive one engine session from newline-delimited JSON. See `stream_json`.
pub fn stream_ndjson(source : String) -> String {
  @tide.stream_json(source) catch {
    @tide.TideError(message) => bad_input(message)
  }
}
