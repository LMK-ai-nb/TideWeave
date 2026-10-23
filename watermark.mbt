///|
/// A bounded-out-of-orderness watermark generator, the counterpart of Flink's
/// `BoundedOutOfOrdernessWatermarks`: the watermark trails the largest observed
/// event timestamp by exactly `allowed_lateness`. Feed every observed event
/// timestamp into `observe`, then advance the engine with the returned value.
pub struct WatermarkTracker {
  mut max_time : Int32
  allowed_lateness : Int32
}

///|
pub fn WatermarkTracker::new(
  allowed_lateness~ : Int32 = 0,
) -> WatermarkTracker raise TideError {
  if allowed_lateness < 0 || allowed_lateness > 1000000000 {
    fail("allowed lateness must be in 0..1000000000")
  }
  { max_time: 0, allowed_lateness, }
}

///|
/// Record an observed event timestamp and return the current watermark.
pub fn WatermarkTracker::observe(
  self : WatermarkTracker,
  at : Int32,
) -> Int32 raise TideError {
  if at < 0 || at > 1000000000 {
    fail("event time must be in 0..1000000000")
  }
  if at > self.max_time {
    self.max_time = at
  }
  self.value()
}

///|
/// The current watermark: `max(0, max_time - allowed_lateness)`.
pub fn WatermarkTracker::value(self : WatermarkTracker) -> Int32 {
  let w = self.max_time - self.allowed_lateness
  if w < 0 {
    0
  } else {
    w
  }
}

///|
pub fn WatermarkTracker::max_time(self : WatermarkTracker) -> Int32 {
  self.max_time
}
