///|
/// Mathematical floor division. MoonBit division truncates toward zero.
fn floor_div(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  if a < 0 && a % b != 0 {
    q - 1
  } else {
    q
  }
}

///|
/// Return start/end pairs in ascending order, including negative starts.
pub fn assign_fixed(
  spec : WindowSpec,
  at : Int32,
) -> Array[(Int32, Int32)] raise TideError {
  if at < 0 || at > 1000000000 {
    fail("invalid event time")
  }
  let (size, slide, offset) = match spec {
    Tumbling(size~, offset~) => (size, size, offset)
    Sliding(size~, slide~, offset~) => (size, slide, offset)
    Session(..) => fail("assign_fixed requires a fixed window")
  }
  validate_fixed(size, slide, offset)
  let t = at.to_int64()
  let width = size.to_int64()
  let step = slide.to_int64()
  let shift = offset.to_int64()
  let last = floor_div(t - shift, step)
  let first = floor_div(t - shift - width, step) + 1
  let result = []
  for index = first; index <= last; index = index + 1 {
    let start = index * step + shift
    let end = start + width
    // Validated bounds imply -1e9 <= start and end <= 2e9.
    result.push((start.to_int(), end.to_int()))
  }
  result
}

///|
fn closing(trigger : Trigger, count : Int32) -> Bool {
  match trigger {
    Watermark => false
    Count(threshold~) => count >= threshold
  }
}

///|
fn phase(
  end : Int32,
  count : Int32,
  watermark : Int32,
  lateness : Int32,
  trigger : Trigger,
) -> String {
  if watermark.to_int64() >= end.to_int64() + lateness.to_int64() {
    "final"
  } else if watermark >= end || closing(trigger, count) {
    "closing"
  } else {
    "open"
  }
}

///|
fn row_from_events(
  key : String,
  start : Int32,
  end : Int32,
  events : Array[Event],
  watermark : Int32,
  lateness : Int32,
  trigger : Trigger,
  value_field : String?,
) -> Window raise TideError {
  let mut sum : Int64 = 0
  let mut low : Int64 = 0
  let mut high : Int64 = 0
  let members = []
  for i, e in events {
    let v = e.measure(value_field)
    if i == 0 {
      low = v
      high = v
    }
    sum = sum + v
    low = if v < low { v } else { low }
    high = if v > high { v } else { high }
    members.push(e.id)
  }
  members.sort_by(fn(a, b) { a.lexical_compare(b) })
  {
    key,
    start,
    end,
    count: events.length(),
    sum,
    min: low.to_int(),
    max: high.to_int(),
    members,
    phase: phase(end, events.length(), watermark, lateness, trigger),
  }
}

///|
fn row_order(a : Window, b : Window) -> Int32 {
  if a.key != b.key {
    a.key.lexical_compare(b.key)
  } else if a.start != b.start {
    a.start.compare(b.start)
  } else {
    a.end.compare(b.end)
  }
}

///|
/// Aggregate one already isolated key, without encoding tuple keys as text.
fn fixed_rows(
  c : Config,
  key : String,
  events : Array[Event],
  watermark : Int32,
) -> Array[Window] raise TideError {
  let buckets : Map[Int32, Array[Event]] = Map([])
  let ends : Map[Int32, Int32] = Map([])
  for e in events {
    for pair in assign_fixed(c.window, e.at) {
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
  let rows = []
  for start, bucket in buckets {
    rows.push(
      row_from_events(
        key,
        start,
        ends[start],
        bucket,
        watermark,
        c.lateness,
        c.trigger,
        c.value_field,
      ),
    )
  }
  rows.sort_by(row_order)
  rows
}

///|
/// Batch aggregation API. Validates the same bounds used by the state machine.
pub fn aggregate(
  c : Config,
  events : Array[Event],
  watermark~ : Int32 = 0,
) -> Array[Window] raise TideError {
  validate_config(c)
  if events.length() > c.max_events {
    fail("active event capacity exceeded")
  }
  if watermark < 0 || watermark > 2000000000 {
    fail("watermark out of range")
  }
  let grouped : Map[String, Array[Event]] = Map([])
  let ids : Map[String, Bool] = Map([])
  for e in events {
    validate_event(e)
    if ids.contains(e.id) {
      fail("duplicate event ID")
    }
    ids[e.id] = true
    match grouped.get(e.key) {
      Some(bucket) => bucket.push(e)
      None => grouped[e.key] = [e]
    }
  }
  let result = []
  for key, bucket in grouped {
    let rows = match c.window {
      Session(gap~) => session_rows(c, key, bucket, watermark, gap)
      _ => fixed_rows(c, key, bucket, watermark)
    }
    for row in rows {
      result.push(row)
    }
    if result.length() > 20000 {
      fail("window capacity exceeded")
    }
  }
  result.sort_by(row_order)
  result
}

///|
/// Rebuild connected components after corrections, including deletion splits.
fn session_rows(
  c : Config,
  key : String,
  events : Array[Event],
  watermark : Int32,
  gap : Int32,
) -> Array[Window] raise TideError {
  let sorted = events.copy()
  sorted.sort_by(fn(a, b) {
    if a.at == b.at {
      a.id.lexical_compare(b.id)
    } else {
      a.at.compare(b.at)
    }
  })
  let rows = []
  let mut begin = 0
  for i in 1..<=sorted.length() {
    if i == sorted.length() || sorted[i].at - sorted[i - 1].at >= gap {
      let component = []
      for j in begin..<i {
        component.push(sorted[j])
      }
      rows.push(
        row_from_events(
          key,
          sorted[begin].at,
          sorted[i - 1].at + gap,
          component,
          watermark,
          c.lateness,
          c.trigger,
          c.value_field,
        ),
      )
      begin = i
    }
  }
  rows
}
