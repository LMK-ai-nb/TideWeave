///|
/// Reject duplicate decoded keys before any domain decoding.
fn strict_json(source : String) -> Json raise TideError {
  if source.length() > 8388608 {
    fail("JSON exceeds 8 Mi UTF-16 units")
  }
  @json.parse(
    source,
    max_nesting_depth=24,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    _ => fail("invalid JSON, duplicate key, or nesting exceeds 24")
  }
}

///|
fn obj(value : Json) -> Map[String, Json] raise TideError {
  match value {
    Object(fields) => fields
    _ => fail("expected object")
  }
}

///|
fn fields_only(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Unit raise TideError {
  for key, _ in fields {
    if !allowed.contains(key) {
      fail("unknown or inapplicable field")
    }
  }
}

///|
fn req(fields : Map[String, Json], name : String) -> Json raise TideError {
  match fields.get(name) {
    Some(v) => v
    None => fail("missing required field: " + name)
  }
}

///|
fn str(value : Json) -> String raise TideError {
  match value {
    String(s) => s
    _ => fail("expected string")
  }
}

///|
fn arr(value : Json, limit : Int32) -> Array[Json] raise TideError {
  match value {
    Array(a) => {
      if a.length() > limit {
        fail("array capacity exceeded")
      }
      a
    }
    _ => fail("expected array")
  }
}

///|
/// Canonical decimal integer tokens only; no rounded fractions or underflow.
fn integer(value : Json) -> Int32 raise TideError {
  match value {
    Number(n, repr=Some(token)) => {
      if token.length() > 11 || token.length() == 0 {
        fail("integer token out of range")
      }
      for i in 0..<token.length() {
        let ch = token[i]
        if !(ch >= 48 && ch <= 57) && !(i == 0 && ch == 45) {
          fail("expected plain decimal integer without fraction or exponent")
        }
      }
      if n < -2000000000.0 || n > 2000000000.0 {
        fail("integer outside supported range")
      }
      n.to_int()
    }
    _ => fail("expected decimal integer token")
  }
}

///|
fn int_or(
  fields : Map[String, Json],
  name : String,
  fallback : Int32,
) -> Int32 raise TideError {
  match fields.get(name) {
    Some(v) => integer(v)
    None => fallback
  }
}

///|
fn read_trigger(value : Json) -> Trigger raise TideError {
  let f = obj(value)
  match str(req(f, "kind")) {
    "watermark" => {
      fields_only(f, ["kind"])
      Watermark
    }
    "count" => {
      fields_only(f, ["kind", "threshold"])
      Count(threshold=integer(req(f, "threshold")))
    }
    _ => fail("unknown trigger kind")
  }
}

///|
fn read_config(value : Json) -> Config raise TideError {
  let f = obj(value)
  fields_only(f, [
    "window", "lateness", "max_events", "max_operations", "trigger",
  ])
  let w = obj(req(f, "window"))
  let kind = str(req(w, "kind"))
  let window = match kind {
    "session" => {
      fields_only(w, ["kind", "gap"])
      Session(gap=integer(req(w, "gap")))
    }
    "tumbling" => {
      fields_only(w, ["kind", "size", "offset"])
      Tumbling(size=integer(req(w, "size")), offset=int_or(w, "offset", 0))
    }
    "sliding" => {
      fields_only(w, ["kind", "size", "slide", "offset"])
      Sliding(
        size=integer(req(w, "size")),
        slide=integer(req(w, "slide")),
        offset=int_or(w, "offset", 0),
      )
    }
    _ => fail("unknown window kind")
  }
  let trigger = match f.get("trigger") {
    Some(v) => read_trigger(v)
    None => Watermark
  }
  config(
    window,
    lateness=int_or(f, "lateness", 0),
    max_events=int_or(f, "max_events", 5000),
    max_operations=int_or(f, "max_operations", 10000),
    trigger~,
  )
}

///|
fn read_event(value : Json) -> Event raise TideError {
  let f = obj(value)
  fields_only(f, ["id", "key", "at", "value"])
  let e = Event::{
    id: str(req(f, "id")),
    key: str(req(f, "key")),
    at: integer(req(f, "at")),
    value: integer(req(f, "value")),
  }
  validate_event(e)
  e
}

///|
fn read_command(value : Json) -> Command raise TideError {
  let f = obj(value)
  let kind = str(req(f, "kind"))
  let id = str(req(f, "id"))
  let command = match kind {
    "watermark" => {
      fields_only(f, ["kind", "id", "to"])
      Advance(id~, to=integer(req(f, "to")))
    }
    "forget" => {
      fields_only(f, ["kind", "id", "to"])
      Forget(id~, to=integer(req(f, "to")))
    }
    "transaction" => {
      fields_only(f, ["kind", "id", "changes"])
      let changes = []
      for value in arr(req(f, "changes"), 128) {
        let m = obj(value)
        match str(req(m, "op")) {
          "put" => {
            fields_only(m, ["op", "event"])
            changes.push(Put(read_event(req(m, "event"))))
          }
          "remove" => {
            fields_only(m, ["op", "event_id"])
            changes.push(Remove(str(req(m, "event_id"))))
          }
          _ => fail("unknown mutation op")
        }
      }
      Transact(id~, changes~)
    }
    _ => fail("unknown command kind")
  }
  validate_command(command)
  command
}

///|
fn read_commands(value : Json) -> Array[Command] raise TideError {
  arr(value, 10000).map(read_command)
}

///|
pub fn decode_config(source : String) -> Config raise TideError {
  read_config(strict_json(source))
}

///|
pub fn decode_commands(source : String) -> Array[Command] raise TideError {
  read_commands(strict_json(source))
}

///|
pub impl ToJson for WindowSpec with fn to_json(self) {
  match self {
    Session(gap~) => { "kind": "session", "gap": gap }
    Tumbling(size~, offset~) =>
      { "kind": "tumbling", "size": size, "offset": offset }
    Sliding(size~, slide~, offset~) =>
      { "kind": "sliding", "size": size, "slide": slide, "offset": offset }
  }
}

///|
pub impl ToJson for Trigger with fn to_json(self) {
  match self {
    Watermark => { "kind": "watermark" }
    Count(threshold~) => { "kind": "count", "threshold": threshold }
  }
}

///|
pub impl ToJson for Config with fn to_json(self) {
  {
    "window": self.window.to_json(),
    "lateness": self.lateness,
    "max_events": self.max_events,
    "max_operations": self.max_operations,
    "trigger": self.trigger.to_json(),
  }
}

///|
pub impl ToJson for Mutation with fn to_json(self) {
  match self {
    Put(e) => { "op": "put", "event": e.to_json() }
    Remove(id) => { "op": "remove", "event_id": id }
  }
}

///|
pub impl ToJson for Command with fn to_json(self) {
  match self {
    Advance(id~, to~) => { "kind": "watermark", "id": id, "to": to }
    Forget(id~, to~) => { "kind": "forget", "id": id, "to": to }
    Transact(id~, changes~) =>
      { "kind": "transaction", "id": id, "changes": @json.to_json(changes) }
  }
}

///|
pub(all) struct Replay {
  schema_version : Int32
  config : Config
  steps : Array[Outcome]
  rows : Array[Window]
  events : Array[Event]
  watermark : Int32
  version : Int32
  checkpoint : Json
} derive(ToJson)

///|
pub fn replay(c : Config, commands : Array[Command]) -> Replay raise TideError {
  if commands.length() > 10000 {
    fail("at most 10000 commands per replay")
  }
  let engine = Engine::new(c)
  engine.run(commands)
}

///|
/// Resume on an existing engine; commands are processed in supplied order.
pub fn Engine::run(
  engine : Engine,
  commands : Array[Command],
) -> Replay raise TideError {
  if commands.length() > 10000 {
    fail("at most 10000 commands per replay")
  }
  let steps = commands.map(command => engine.apply(command))
  {
    schema_version: 1,
    config: engine.cfg,
    steps,
    rows: engine.rows(),
    events: engine.events(),
    watermark: engine.watermark(),
    version: engine.version(),
    checkpoint: engine.checkpoint_value(),
  }
}

///|
/// Validate all input before running; domain rejections are report steps.
pub fn replay_json(source : String) -> String raise TideError {
  let f = obj(strict_json(source))
  fields_only(f, ["schema_version", "config", "commands"])
  if integer(req(f, "schema_version")) != 1 {
    fail("unsupported schema_version")
  }
  let c = read_config(req(f, "config"))
  let commands = read_commands(req(f, "commands"))
  replay(c, commands).to_json().stringify()
}
