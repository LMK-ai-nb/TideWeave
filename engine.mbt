///|
/// Opaque mutable engine. Public queries and outcomes return detached arrays.
pub struct Engine {
  cfg : Config
  mut records : Map[String, Event]
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
    Advance(..) => command
  }
}

///|
/// Detached, sorted materialized view. Mutating its arrays cannot alter state.
pub fn Engine::rows(self : Engine) -> Array[Window] {
  self.materialized.map(copy_row)
}

///|
pub fn Engine::events(self : Engine) -> Array[Event] {
  let result = []
  for _, e in self.records {
    result.push(e)
  }
  result.sort_by(fn(a, b) { a.id.compare(b.id) })
  result
}

///|
pub fn Engine::watermark(self : Engine) -> Int32 {
  self.clock
}

///|
pub fn Engine::version(self : Engine) -> Int32 {
  self.revision
}

///|
fn command_id(c : Command) -> String {
  match c {
    Transact(id~, ..) | Advance(id~, ..) => id
  }
}

///|
fn validate_command(c : Command) -> Unit raise TideError {
  validate_name(command_id(c))
  match c {
    Advance(to~, ..) =>
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
) -> (Map[String, Event], Array[Window], Int32) raise TideError {
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
        phase: phase(w.end, to, self.cfg.lateness),
      })
      (self.records, rows, to)
    }
    Transact(changes~, ..) => {
      let proposed : Map[String, Event] = Map([])
      for id, e in self.records {
        proposed[id] = e
      }
      let affected : Map[String, Bool] = Map([])
      for m in changes {
        match m {
          Put(e) => {
            if self.records.get(e.id) is Some(old) {
              affected[old.key] = true
            }
            proposed[e.id] = e
            affected[e.key] = true
          }
          Remove(id) => {
            let old = match self.records.get(id) {
              Some(e) => e
              None => fail("cannot remove an unknown event")
            }
            proposed.remove(id)
            affected[old.key] = true
          }
        }
      }
      if proposed.length() > self.cfg.max_events {
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
            fail("correction would change a finalized window")
          }
          // Equal sums do not permit rewriting the underlying finalized facts.
          for event_id in w.members {
            if proposed.get(event_id) != self.records.get(event_id) {
              fail("correction would change a finalized event")
            }
          }
        }
      }
      for w in next {
        if w.phase == "final" && old.get((w.key, w.start, w.end)) != Some(w) {
          fail("correction would create an already finalized window")
        }
      }
      (proposed, next, self.clock)
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
  let (records, rows, watermark) = self.candidate(command) catch {
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
