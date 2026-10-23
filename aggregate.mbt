///|
/// A pluggable scalar aggregate (user-defined aggregate function, UDAF).
///
/// `step` folds one event value into the accumulator; `finish` turns the
/// accumulator and the event count into the emitted measure value. Because
/// `measure_window` recomputes a window from its full member list on every
/// call, measures stay correct under late arrivals and retractions without a
/// separate subtractive pass — the window members are the source of truth.
pub(all) struct Measure {
  name : String
  identity : Int64
  step : (Int64, Int64) -> Int64
  finish : (Int64, Int64) -> Int64
}

///|
/// A named, computed measure value.
pub(all) struct MeasureResult {
  name : String
  value : Int64
} derive(Eq, ToJson)

///|
/// A window summarized by caller-chosen measures instead of the fixed
/// count/sum/min/max profile. Uses the same assignment, session grouping and
/// phase rules as the stateful engine.
pub(all) struct MeasureWindow {
  key : String
  start : Int32
  end : Int32
  count : Int32
  measures : Array[MeasureResult]
  phase : String
} derive(Eq, ToJson)

///|
/// A custom measure: `identity` seeds the fold, `step` accumulates one event
/// value, `finish` derives the result from the accumulator and member count.
pub fn measure(
  name~ : String,
  identity~ : Int64,
  step~ : (Int64, Int64) -> Int64,
  finish~ : (Int64, Int64) -> Int64,
) -> Measure {
  { name, identity, step, finish, }
}

///|
pub fn count_measure() -> Measure {
  measure(name="count", identity=0, step=fn(acc, _) { acc + 1 }, finish=fn(
    acc,
    _,
  ) {
    acc
  })
}

///|
pub fn sum_measure() -> Measure {
  measure(name="sum", identity=0, step=fn(acc, v) { acc + v }, finish=fn(
    acc,
    _,
  ) {
    acc
  })
}

///|
pub fn min_measure() -> Measure {
  measure(
    name="min",
    identity=9223372036854775807L,
    step=fn(acc, v) { if v < acc { v } else { acc } },
    finish=fn(acc, n) { if n == 0 { 0 } else { acc } },
  )
}

///|
pub fn max_measure() -> Measure {
  measure(
    name="max",
    identity=-9223372036854775808L,
    step=fn(acc, v) { if v > acc { v } else { acc } },
    finish=fn(acc, n) { if n == 0 { 0 } else { acc } },
  )
}

///|
/// Arithmetic mean, truncated toward zero (integer arithmetic).
pub fn average_measure() -> Measure {
  measure(name="avg", identity=0, step=fn(acc, v) { acc + v }, finish=fn(
    acc,
    n,
  ) {
    if n == 0 {
      0
    } else {
      acc / n
    }
  })
}

///|
fn validate_measures(measures : Array[Measure]) -> Unit raise TideError {
  if measures.length() < 1 || measures.length() > 128 {
    fail("measure_window requires 1..128 measures")
  }
  let seen : Map[String, Bool] = Map([])
  for m in measures {
    validate_name(m.name)
    if seen.contains(m.name) {
      fail("duplicate measure name")
    }
    seen[m.name] = true
  }
}

///|
fn summarize_span(
  key : String,
  start : Int32,
  end : Int32,
  events : Array[Event],
  measures : Array[Measure],
  watermark : Int32,
  lateness : Int32,
  trigger : Trigger,
) -> MeasureWindow {
  let results = []
  for m in measures {
    let mut acc = m.identity
    for e in events {
      acc = (m.step)(acc, e.value.to_int64())
    }
    results.push(MeasureResult::{
      name: m.name,
      value: (m.finish)(acc, events.length().to_int64()),
    })
  }
  {
    key,
    start,
    end,
    count: events.length(),
    measures: results,
    phase: phase(end, events.length(), watermark, lateness, trigger),
  }
}

///|
fn fixed_spans(
  spec : WindowSpec,
  events : Array[Event],
) -> Array[(Int32, Int32, Array[Event])] raise TideError {
  let buckets : Map[Int32, Array[Event]] = Map([])
  let ends : Map[Int32, Int32] = Map([])
  for e in events {
    for pair in assign_fixed(spec, e.at) {
      let (start, end) = pair
      match buckets.get(start) {
        Some(bucket) => bucket.push(e)
        None => {
          buckets[start] = [e]
          ends[start] = end
        }
      }
    }
  }
  let spans = []
  for start, bucket in buckets {
    spans.push((start, ends[start], bucket))
  }
  spans.sort_by(fn(a, b) { a.0.compare(b.0) })
  spans
}

///|
fn session_spans(
  events : Array[Event],
  gap : Int32,
) -> Array[(Int32, Int32, Array[Event])] {
  let sorted = events.copy()
  sorted.sort_by(fn(a, b) {
    if a.at == b.at {
      a.id.compare(b.id)
    } else {
      a.at.compare(b.at)
    }
  })
  let spans = []
  let mut begin = 0
  for i in 1..<=sorted.length() {
    if i == sorted.length() || sorted[i].at - sorted[i - 1].at >= gap {
      let component = []
      for j in begin..<i {
        component.push(sorted[j])
      }
      spans.push((sorted[begin].at, sorted[i - 1].at + gap, component))
      begin = i
    }
  }
  spans
}

///|
fn measure_row_order(a : MeasureWindow, b : MeasureWindow) -> Int32 {
  if a.key != b.key {
    a.key.compare(b.key)
  } else if a.start != b.start {
    a.start.compare(b.start)
  } else {
    a.end.compare(b.end)
  }
}

///|
/// Compute caller-chosen measures for every window of the supplied events,
/// reusing the engine's window assignment, session grouping and phase rules.
/// Validate the same bounds as the stateful engine.
pub fn measure_window(
  c : Config,
  events : Array[Event],
  measures : Array[Measure],
  watermark~ : Int32 = 0,
) -> Array[MeasureWindow] raise TideError {
  validate_config(c)
  validate_measures(measures)
  if events.length() > c.max_events {
    fail("active event capacity exceeded")
  }
  if watermark < 0 || watermark > 2000000000 {
    fail("watermark out of range")
  }
  let ids : Map[String, Bool] = Map([])
  for e in events {
    validate_event(e)
    if ids.contains(e.id) {
      fail("duplicate event ID")
    }
    ids[e.id] = true
  }
  let grouped : Map[String, Array[Event]] = Map([])
  for e in events {
    match grouped.get(e.key) {
      Some(bucket) => bucket.push(e)
      None => grouped[e.key] = [e]
    }
  }
  let result = []
  for key, bucket in grouped {
    let spans = match c.window {
      Session(gap~) => session_spans(bucket, gap)
      _ => fixed_spans(c.window, bucket)
    }
    for span in spans {
      result.push(
        summarize_span(
          key,
          span.0,
          span.1,
          span.2,
          measures,
          watermark,
          c.lateness,
          c.trigger,
        ),
      )
    }
    if result.length() > 20000 {
      fail("window capacity exceeded")
    }
  }
  result.sort_by(measure_row_order)
  result
}
