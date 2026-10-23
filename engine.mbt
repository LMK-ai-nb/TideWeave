///|
/// Opaque mutable engine. Public queries and outcomes return detached arrays.
pub struct Engine {
  cfg : Config
  mut records : Map[String, Event]
  mut frozen : Map[String, Event]
  mut materialized : Array[Window]
  mut clock : Int32
  mut revision : Int32
  committed : Map[String, Command]
  journal : Array[Command]
  mut journal_units : Int32
}

///|
pub fn Engine::new(cfg : Config) -> Engine raise TideError {
  validate_config(cfg)
  {
    cfg,
    records: Map([]),
    frozen: Map([]),
    materialized: [],
    clock: 0,
    revision: 0,
    committed: Map([]),
    journal: [],
    journal_units: 0,
  }
}

///|
fn copy_row(w : Window) -> Window {
  { ..w, members: w.members.copy(), }
}

///|
fn copy_command(command : Command) -> Command {
  match command {
    Transact(id~, changes~) => Transact(id~, changes=changes.copy())
    Advance(..) | Forget(..) => command
  }
}

///|
/// Detached, sorted materialized view. Mutating its arrays cannot alter state.
pub fn Engine::rows(self : Engine) -> Array[Window] {
  self.materialized.map(copy_row)
}

///|
/// Active (still correctable) events, sorted by ID. Sealed finalized facts are
/// excluded: they are frozen and can no longer be inserted, replaced or removed.
pub fn Engine::events(self : Engine) -> Array[Event] {
  let result = []
  for _, e in self.records {
    result.push(e)
  }
  result.sort_by(fn(a, b) { a.id.compare(b.id) })
  result
}

///|
/// Number of frozen (finalized) facts still retained for replay.
pub fn Engine::frozen_count(self : Engine) -> Int32 {
  self.frozen.length()
}

///|
pub fn Engine::watermark(self : Engine) -> Int32 {
  self.clock
}

///|
pub fn Engine::lateness(self : Engine) -> Int32 {
  self.cfg.lateness
}

///|
/// True when an event timestamp is not more than `allowed_lateness` behind the
/// current watermark: `at + allowed_lateness >= watermark`. This is the
/// Flink-style "late event" heuristic hosts use to decide whether to forward a
/// correction. It is not a correctness guarantee: window finality is the
/// authoritative gate, and a timestamp behind the watermark can still land in
/// a window whose end lies in the future (and thus remain correctable). For an
/// exact answer about a specific fact, use `correctable`.
pub fn Engine::within_lateness(self : Engine, at : Int32) -> Bool {
  at.to_int64() + self.cfg.lateness.to_int64() >= self.clock.to_int64()
}

///|
/// True when the event is still active and none of its current windows is
/// final. This mirrors the freeze predicate used by `Forget`. A correction
/// that moves the event to another key or timestamp can still be rejected by
/// finality in the destination windows.
pub fn Engine::correctable(self : Engine, id : String) -> Bool {
  if !self.records.contains(id) {
    return false
  }
  let mut found = false
  for w in self.materialized {
    if w.members.contains(id) {
      found = true
      if w.phase == "final" {
        return false
      }
    }
  }
  found
}

///|
pub fn Engine::version(self : Engine) -> Int32 {
  self.revision
}

///|
fn command_id(c : Command) -> String {
  match c {
    Transact(id~, ..) | Advance(id~, ..) | Forget(id~, ..) => id
  }
}

///|
fn validate_command(c : Command) -> Unit raise TideError {
  validate_name(command_id(c))
  match c {
    Advance(to~, ..) | Forget(to~, ..) =>
      if to < 0 || to > 2000000000 {
        fail("watermark must be in 0..2000000000")
      }
    Transact(changes~, ..) => {
      if changes.length() < 1 || changes.length() > 128 {
        fail("transaction requires 1..128 changes")
      }
      let seen : Map[String, Bool] = Map([])
      for m in changes {
        let id = match m {
          Put(e) => {
            validate_event(e)
            e.id
          }
          Remove(id) => {
            validate_name(id)
            id
          }
        }
        if seen.contains(id) {
          fail("one transaction cannot repeat an event ID")
        }
        seen[id] = true
      }
    }
  }
}

///|
fn indexed(rows : Array[Window]) -> Map[(String, Int32, Int32), Window] {
  let result : Map[(String, Int32, Int32), Window] = Map([])
  for w in rows {
    result[(w.key, w.start, w.end)] = w
  }
  result
}

///|
/// Stable delete/upsert order. Before images support guarded downstream replay.
fn difference(before : Array[Window], after : Array[Window]) -> Array[Delta] {
  let old = indexed(before)
  let fresh = indexed(after)
  let result = []
  for w in before {
    if !fresh.contains((w.key, w.start, w.end)) {
      result.push(Delta::{
        kind: "delete",
        before: Some(copy_row(w)),
        after: None,
      })
    }
  }
  for w in after {
    let previous = old.get((w.key, w.start, w.end))
    if previous != Some(w) {
      result.push(Delta::{
        kind: "upsert",
        before: previous.map(copy_row),
        after: Some(copy_row(w)),
      })
    }
  }
  result
}

///|
fn Engine::candidate(
  self : Engine,
  c : Command,
) -> (Map[String, Event], Map[String, Event], Array[Window], Int32) raise TideError {
  validate_command(c)
  if self.journal_units + c.to_json().stringify().length() > 2097152 {
    fail("serialized successful journal exceeds 2 Mi UTF-16 units")
  }
  if self.journal.length() >= self.cfg.max_operations {
    fail("successful command capacity exceeded")
  }
  match c {
    Advance(to~, ..) => {
      if to < self.clock {
        fail("watermark cannot move backwards")
      }
      let rows = self.materialized.map(w => {
        ..w,
        phase: phase(w.end, w.count, to, self.cfg.lateness, self.cfg.trigger),
      })
      (self.records, self.frozen, rows, to)
    }
    Forget(to~, ..) => {
      if to < self.clock {
        fail("watermark cannot move backwards")
      }
      let rows = self.materialized.map(w => {
        ..w,
        phase: phase(w.end, w.count, to, self.cfg.lateness, self.cfg.trigger),
      })
      let next_frozen : Map[String, Event] = Map([])
      for id, e in self.frozen {
        next_frozen[id] = e
      }
      let next_records : Map[String, Event] = Map([])
      for id, e in self.records {
        let mut found = false
        let mut all_final = true
        for w in rows {
          if w.members.contains(id) {
            found = true
            if w.phase != "final" {
              all_final = false
              break
            }
          }
        }
        if found && all_final {
          next_frozen[id] = e
        } else {
          next_records[id] = e
        }
      }
      (next_records, next_frozen, rows, to)
    }
    Transact(changes~, ..) => {
      let current : Map[String, Event] = Map([])
      for id, e in self.records {
        current[id] = e
      }
      for id, e in self.frozen {
        current[id] = e
      }
      let proposed : Map[String, Event] = Map([])
      for id, e in current {
        proposed[id] = e
      }
      let affected : Map[String, Bool] = Map([])
      for m in changes {
        match m {
          Put(e) => {
            if self.frozen.contains(e.id) {
              fail("cannot replace a sealed (finalized) fact")
            }
            if self.records.get(e.id) is Some(old) {
              affected[old.key] = true
            }
            proposed[e.id] = e
            affected[e.key] = true
          }
          Remove(id) => {
            if self.frozen.contains(id) {
              fail("cannot remove a sealed (finalized) fact")
            }
            let old = match self.records.get(id) {
              Some(e) => e
              None => fail("cannot remove an unknown event")
            }
            proposed.remove(id)
            affected[old.key] = true
          }
        }
      }
      let mut active = 0
      for id, _ in proposed {
        if !self.frozen.contains(id) {
          active = active + 1
        }
      }
      if active > self.cfg.max_events {
        fail("active event capacity exceeded")
      }
      let groups : Map[String, Array[Event]] = Map([])
      for _, e in proposed {
        if affected.contains(e.key) {
          match groups.get(e.key) {
            Some(bucket) => bucket.push(e)
            None => groups[e.key] = [e]
          }
        }
      }
      let next = []
      for w in self.materialized {
        if !affected.contains(w.key) {
          next.push(w)
        }
      }
      for key, bucket in groups {
        let rebuilt = match self.cfg.window {
          Session(gap~) => session_rows(self.cfg, key, bucket, self.clock, gap)
          _ => fixed_rows(self.cfg, key, bucket, self.clock)
        }
        for w in rebuilt {
          next.push(w)
        }
        if next.length() > 20000 {
          fail("window capacity exceeded")
        }
      }
      next.sort_by(row_order)
      let old = indexed(self.materialized)
      let fresh = indexed(next)
      for w in self.materialized {
        if w.phase == "final" {
          if fresh.get((w.key, w.start, w.end)) != Some(w) {
            fail(
              "correction would change a finalized window (watermark >= end + allowed_lateness)",
            )
          }
          // Equal sums do not permit rewriting the underlying finalized facts.
          for event_id in w.members {
            if proposed.get(event_id) != current.get(event_id) {
              fail("correction would change a finalized event")
            }
          }
        }
      }
      for w in next {
        if w.phase == "final" && old.get((w.key, w.start, w.end)) != Some(w) {
          fail(
            "late event would create a window already finalized by watermark + allowed_lateness",
          )
        }
      }
      let next_records : Map[String, Event] = Map([])
      for id, e in proposed {
        if !self.frozen.contains(id) {
          next_records[id] = e
        }
      }
      (next_records, self.frozen, next, self.clock)
    }
  }
}

///|
/// All failures leave state, version, successful IDs and journal unchanged.
pub fn Engine::apply(self : Engine, command : Command) -> Outcome {
  let id = command_id(command)
  if self.committed.get(id) is Some(previous) {
    let same = previous == command
    return {
      id,
      status: if same {
        "duplicate"
      } else {
        "conflict"
      },
      version: self.revision,
      watermark: self.clock,
      deltas: [],
      message: if same {
        "already committed; no effects repeated"
      } else {
        "command ID already used with different content"
      },
    }
  }
  let (records, frozen, rows, watermark) = self.candidate(command) catch {
    TideError(message) =>
      return {
        id,
        status: "rejected",
        version: self.revision,
        watermark: self.clock,
        deltas: [],
        message,
      }
  }
  let deltas = difference(self.materialized, rows)
  self.records = records
  self.frozen = frozen
  self.materialized = rows
  self.clock = watermark
  self.revision = self.revision + 1
  let detached = copy_command(command)
  self.committed[id] = detached
  self.journal.push(detached)
  self.journal_units = self.journal_units +
    detached.to_json().stringify().length()
  {
    id,
    status: "accepted",
    version: self.revision,
    watermark,
    deltas,
    message: "committed atomically",
  }
}
