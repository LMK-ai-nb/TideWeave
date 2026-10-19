///|
/// A downstream materialized view that rejects gaps and stale before-images.
pub struct View {
  mut materialized : Array[Window]
  mut revision : Int32
  mut clock : Int32
  mut last_delivery : String
}

///|
pub fn View::new() -> View {
  { materialized: [], revision: 0, clock: 0, last_delivery: "", }
}

///|
pub fn View::rows(self : View) -> Array[Window] {
  self.materialized.map(copy_row)
}

///|
pub fn View::version(self : View) -> Int32 {
  self.revision
}

///|
/// Validates transport consistency; authenticity is the host's responsibility.
pub fn View::apply(self : View, outcome : Outcome) -> Unit raise TideError {
  if outcome.status != "accepted" {
    if !["duplicate", "conflict", "rejected"].contains(outcome.status) ||
      outcome.version != self.revision ||
      outcome.watermark != self.clock ||
      outcome.deltas.length() != 0 {
      fail("noncommitting outcome is inconsistent with local view")
    }
    return
  }
  let delivery = outcome.to_json().stringify()
  if outcome.version == self.revision && delivery == self.last_delivery {
    return
  }
  if outcome.version != self.revision + 1 {
    fail("view version gap or conflicting delivery")
  }
  if outcome.watermark < self.clock {
    fail("view watermark cannot move backwards")
  }
  let proposed = indexed(self.materialized)
  let touched : Map[(String, Int32, Int32), Bool] = Map([])
  for delta in outcome.deltas {
    let w = match (delta.kind, delta.before, delta.after) {
      ("delete", Some(before), None) => before
      ("upsert", _, Some(after)) => after
      _ => fail("invalid delta shape")
    }
    let key = (w.key, w.start, w.end)
    if touched.contains(key) {
      fail("duplicate row identity in one delivery")
    }
    touched[key] = true
    if delta.before is Some(before) {
      if (before.key, before.start, before.end) != key {
        fail("upsert changed identity")
      }
    }
    if proposed.get(key) != delta.before {
      fail("stale or missing before image")
    }
    match delta.after {
      Some(after) => proposed[key] = copy_row(after)
      None => proposed.remove(key)
    }
  }
  if proposed.length() > 20000 {
    fail("view capacity exceeded")
  }
  let rows = []
  for _, w in proposed {
    rows.push(w)
  }
  rows.sort_by(row_order)
  self.materialized = rows
  self.revision = outcome.version
  self.clock = outcome.watermark
  self.last_delivery = delivery
}
