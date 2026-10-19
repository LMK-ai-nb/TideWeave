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
fn phase(end : Int32, watermark : Int32, lateness : Int32) -> String {
  if watermark.to_int64() >= end.to_int64() + lateness.to_int64() {
    "final"
  } else if watermark >= end {
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
) -> Window {
  let mut sum : Int64 = 0
  let mut low = events[0].value
  let mut high = events[0].value
  let members = []
  for e in events {
    sum = sum + e.value.to_int64()
    low = if e.value < low { e.value } else { low }
    high = if e.value > high { e.value } else { high }
    members.push(e.id)
  }
  members.sort()
  {
    key,
    start,
    end,
    count: events.length(),
    sum,
    min: low,
    max: high,
    members,
    phase: phase(end, watermark, lateness),
  }
}

///|
fn row_order(a : Window, b : Window) -> Int32 {
  if a.key != b.key {
    a.key.compare(b.key)
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
      row_from_events(key, start, ends[start], bucket, watermark, c.lateness),
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
/// Session implementation arrives in the next independent milestone.
fn session_rows(
  _c : Config,
  _key : String,
  _events : Array[Event],
  _watermark : Int32,
  _gap : Int32,
) -> Array[Window] raise TideError {
  fail("session aggregation is not implemented yet")
}
