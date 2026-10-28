///|
/// Window parameters use caller-defined integer time units.
pub(all) enum WindowSpec {
  Tumbling(size~ : Int32, offset~ : Int32)
  Sliding(size~ : Int32, slide~ : Int32, offset~ : Int32)
  Session(gap~ : Int32)
} derive(Eq)

///|
/// When a window is emitted early (marked `closing`) before the watermark
/// finalizes it. `Watermark` is the default and keeps the original behavior;
/// `Count(n)` additionally marks a window closing once it holds `n` events.
/// Trigger affects emission/phase only — finality still depends on the
/// watermark plus allowed lateness, so early-fired windows stay correctable.
pub(all) enum Trigger {
  Watermark
  Count(threshold~ : Int32)
} derive(Eq)

///|
pub(all) struct Config {
  window : WindowSpec
  lateness : Int32
  max_events : Int32
  max_operations : Int32
  trigger : Trigger
  value_field : String?
} derive(Eq)

///|
/// Event ID is global within one engine. Keys and IDs are opaque Unicode.
/// `fields` carries arbitrary structured attributes as sorted key/value
/// pairs; `value` is the numeric measure the built-in aggregates consume
/// (either supplied directly, or derived from `Config.value_field`).
pub(all) struct Event {
  id : String
  key : String
  at : Int32
  value : Int32
  fields : Array[(String, String)]?
} derive(Eq)

///|
pub(all) enum Mutation {
  Put(Event)
  Remove(String)
} derive(Eq)

///|
pub(all) enum Command {
  Transact(id~ : String, changes~ : Array[Mutation])
  Advance(id~ : String, to~ : Int32)
  Forget(id~ : String, to~ : Int32)
} derive(Eq)

///|
/// Finality is materialized so downstream consumers need no hidden clock.
pub(all) struct Window {
  key : String
  start : Int32
  end : Int32
  count : Int32
  sum : Int64
  min : Int32
  max : Int32
  members : Array[String]
  phase : String
} derive(Eq, ToJson)

///|
/// Apply all deltas in an outcome atomically. Deletes precede upserts.
pub(all) struct Delta {
  kind : String
  before : Window?
  after : Window?
} derive(Eq, ToJson)

///|
pub(all) struct Outcome {
  id : String
  status : String
  version : Int32
  watermark : Int32
  deltas : Array[Delta]
  message : String
} derive(Eq, ToJson)

///|
pub(all) suberror TideError {
  TideError(String)
} derive(Eq)

///|
fn[T] fail(message : String) -> T raise TideError {
  raise TideError(message)
}

///|
pub fn config(
  window : WindowSpec,
  lateness~ : Int32 = 0,
  max_events~ : Int32 = 5000,
  max_operations~ : Int32 = 10000,
  trigger~ : Trigger = Watermark,
  value_field~ : String? = None,
) -> Config raise TideError {
  let c = {
    window,
    lateness,
    max_events,
    max_operations,
    trigger,
    value_field,
  }
  validate_config(c)
  c
}

///|
fn validate_config(c : Config) -> Unit raise TideError {
  let extent = match c.window {
    Tumbling(size~, ..) | Sliding(size~, ..) => size
    Session(gap~) => gap
  }
  if extent.to_int64() + c.lateness.to_int64() > 1000000000 {
    fail(
      "window extent plus lateness must be <= 1000000000 so every window can finalize",
    )
  }
  if c.lateness < 0 || c.lateness > 1000000000 {
    fail("lateness must be in 0..1000000000")
  }
  if c.max_events < 1 || c.max_events > 5000 {
    fail("max_events must be in 1..5000")
  }
  if c.max_operations < 1 || c.max_operations > 10000 {
    fail("max_operations must be in 1..10000")
  }
  match c.trigger {
    Watermark => ()
    Count(threshold~) =>
      if threshold < 1 || threshold > 1000000000 {
        fail("trigger count threshold must be in 1..1000000000")
      }
  }
  match c.value_field {
    Some(name) => validate_name(name)
    None => ()
  }
  match c.window {
    Tumbling(size~, offset~) => validate_fixed(size, size, offset)
    Sliding(size~, slide~, offset~) => validate_fixed(size, slide, offset)
    Session(gap~) =>
      if gap < 1 || gap > 1000000000 {
        fail("session gap must be in 1..1000000000")
      }
  }
}

///|
fn validate_fixed(
  size : Int32,
  slide : Int32,
  offset : Int32,
) -> Unit raise TideError {
  if size < 1 || size > 1000000000 || slide < 1 || slide > size {
    fail("require 1 <= slide <= size <= 1000000000")
  }
  if offset < 0 || offset >= slide {
    fail("offset must be in 0..<slide")
  }
  if (size.to_int64() + slide.to_int64() - 1) / slide.to_int64() > 64 {
    fail("sliding window fanout must be <= 64")
  }
}

///|
pub fn validate_event(e : Event) -> Unit raise TideError {
  validate_name(e.id)
  validate_name(e.key)
  if e.at < 0 || e.at > 1000000000 {
    fail("event time must be in 0..1000000000")
  }
  if e.value < -1000000000 || e.value > 1000000000 {
    fail("event value must be in -1000000000..1000000000")
  }
  match e.fields {
    Some(fs) => {
      if fs.length() > 32 {
        fail("event fields capacity exceeded (max 32)")
      }
      for pair in fs {
        let (k, v) = pair
        validate_name(k)
        if v.length() > 1024 {
          fail("event field values must be at most 1024 UTF-16 units")
        }
      }
    }
    None => ()
  }
}

///|
/// Look up one structured field. Fields are stored sorted, so this is a
/// linear scan over at most 32 entries.
pub fn Event::field(self : Event, key : String) -> String? {
  let mut hit : String? = None
  match self.fields {
    Some(fs) =>
      for pair in fs {
        let (k, v) = pair
        if k == key {
          hit = Some(v)
        }
      }
    None => ()
  }
  hit
}

///|
/// The numeric measure this event contributes to built-in aggregates: its
/// `value`, or — when the engine is configured with `value_field` — the
/// structured field of that name parsed as a plain decimal integer.
pub fn Event::measure(
  self : Event,
  value_field : String?,
) -> Int64 raise TideError {
  match value_field {
    None => self.value.to_int64()
    Some(k) =>
      match self.field(k) {
        None => fail("event \"\{self.id}\" is missing measure field \"\{k}\"")
        Some(raw) => {
          let j = strict_json(raw) catch {
            _ => fail("measure field \"\{k}\" must be a plain decimal integer")
          }
          let parsed = integer(j) catch {
            _ => fail("measure field \"\{k}\" must be a plain decimal integer")
          }
          if parsed < -1000000000 || parsed > 1000000000 {
            fail("measure field \"\{k}\" must be in -1000000000..1000000000")
          }
          parsed.to_int64()
        }
      }
  }
}

///|
/// Deterministic serialization: `fields` is emitted as a sorted array of
/// `[key, value]` pairs and omitted entirely when the event carries none.
pub impl ToJson for Event with fn to_json(self) {
  match self.fields {
    Some(fs) => {
      let sorted = fs.copy()
      sorted.sort_by(fn(a, b) { a.0.lexical_compare(b.0) })
      let pairs = []
      for pair in sorted {
        let (k, v) = pair
        pairs.push([k, v])
      }
      {
        "id": self.id,
        "key": self.key,
        "at": self.at,
        "value": self.value,
        "fields": pairs,
      }
    }
    None =>
      { "id": self.id, "key": self.key, "at": self.at, "value": self.value }
  }
}

///|
fn validate_name(s : String) -> Unit raise TideError {
  if s.length() < 1 || s.length() > 128 {
    fail("IDs and keys must contain 1..128 UTF-16 units")
  }
}
