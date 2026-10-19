///|
/// Window parameters use caller-defined integer time units.
pub(all) enum WindowSpec {
  Tumbling(size~ : Int32, offset~ : Int32)
  Sliding(size~ : Int32, slide~ : Int32, offset~ : Int32)
  Session(gap~ : Int32)
} derive(Eq)

///|
pub(all) struct Config {
  window : WindowSpec
  lateness : Int32
  max_events : Int32
  max_operations : Int32
} derive(Eq)

///|
/// Event ID is global within one engine. Keys and IDs are opaque Unicode.
pub(all) struct Event {
  id : String
  key : String
  at : Int32
  value : Int32
} derive(Eq, ToJson)

///|
pub(all) enum Mutation {
  Put(Event)
  Remove(String)
} derive(Eq)

///|
pub(all) enum Command {
  Transact(id~ : String, changes~ : Array[Mutation])
  Advance(id~ : String, to~ : Int32)
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
) -> Config raise TideError {
  let c = { window, lateness, max_events, max_operations, }
  validate_config(c)
  c
}

///|
fn validate_config(c : Config) -> Unit raise TideError {
  if c.lateness < 0 || c.lateness > 1000000000 {
    fail("lateness must be in 0..1000000000")
  }
  if c.max_events < 1 || c.max_events > 5000 {
    fail("max_events must be in 1..5000")
  }
  if c.max_operations < 1 || c.max_operations > 10000 {
    fail("max_operations must be in 1..10000")
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
}

///|
fn validate_name(s : String) -> Unit raise TideError {
  if s.length() < 1 || s.length() > 128 {
    fail("IDs and keys must contain 1..128 UTF-16 units")
  }
}
