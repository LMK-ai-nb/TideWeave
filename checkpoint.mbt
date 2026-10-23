///|
fn Engine::checkpoint_value(self : Engine) -> Json {
  {
    "format": "tideweave-checkpoint",
    "schema_version": 1,
    "config": self.cfg.to_json(),
    "commands": @json.to_json(self.journal),
    "version": self.revision,
    "watermark": self.clock,
    "frozen": self.frozen_count(),
  }
}

///|
/// A portable validated replay checkpoint, not a signed proof of history.
pub fn Engine::checkpoint(self : Engine) -> String {
  self.checkpoint_value().stringify()
}

///|
fn restore_value(value : Json) -> Engine raise TideError {
  let f = obj(value)
  fields_only(f, [
    "format", "schema_version", "config", "commands", "version", "watermark", "frozen",
  ])
  if str(req(f, "format")) != "tideweave-checkpoint" ||
    integer(req(f, "schema_version")) != 1 {
    fail("unsupported checkpoint format or schema")
  }
  let c = read_config(req(f, "config"))
  let commands = read_commands(req(f, "commands"))
  let engine = Engine::new(c)
  for cmd in commands {
    if engine.apply(cmd).status != "accepted" {
      fail("checkpoint journal contains an uncommittable command")
    }
  }
  if engine.version() != integer(req(f, "version")) ||
    engine.watermark() != integer(req(f, "watermark")) {
    fail("checkpoint version or watermark disagrees with replayed journal")
  }
  if f.get("frozen") is Some(v) {
    if integer(v) != engine.frozen_count() {
      fail("checkpoint frozen count disagrees with replayed journal")
    }
  }
  engine
}

///|
pub fn restore(source : String) -> Engine raise TideError {
  restore_value(strict_json(source))
}

///|
/// Resume input has a checkpoint object and an array of new commands.
pub fn resume_json(source : String) -> String raise TideError {
  let f = obj(strict_json(source))
  fields_only(f, ["schema_version", "checkpoint", "commands"])
  if integer(req(f, "schema_version")) != 1 {
    fail("unsupported schema_version")
  }
  let engine = restore_value(req(f, "checkpoint"))
  let commands = read_commands(req(f, "commands"))
  engine.run(commands).to_json().stringify()
}
