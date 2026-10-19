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
