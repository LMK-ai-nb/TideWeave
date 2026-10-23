///|
test "watermark tracker trails the largest observed time by allowed lateness" {
  let t = WatermarkTracker::new(allowed_lateness=10)
  assert_eq(t.observe(50), 40)
  assert_eq(t.observe(30), 40)
  assert_eq(t.observe(45), 40)
  assert_eq(t.value(), 40)
  assert_eq(t.max_time(), 50)
}

///|
test "watermark tracker clamps at zero and validates input" {
  let t = WatermarkTracker::new(allowed_lateness=10)
  assert_eq(t.observe(5), 0)
  assert_true(
    try {
      ignore(t.observe(-1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(WatermarkTracker::new(allowed_lateness=-1))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "generated watermark drives finality and the lateness boundary" {
  let c = config(Tumbling(size=10, offset=0), lateness=5)
  let tracker = WatermarkTracker::new(allowed_lateness=5)
  ignore(tracker.observe(20))
  let w = tracker.value()
  assert_eq(w, 15)
  let e = Engine::new(c)
  ignore(e.apply(Transact(id="seed", changes=[Put(sample("a", 9))])))
  ignore(e.apply(Advance(id="w", to=w)))
  assert_eq(e.rows()[0].phase, "final")
  assert_true(e.within_lateness(10))
  assert_false(e.within_lateness(9))
}

///|
test "within_lateness tracks the correction horizon of the watermark" {
  let e = Engine::new(config(Session(gap=10), lateness=20))
  ignore(e.apply(Advance(id="w", to=30)))
  assert_true(e.within_lateness(10))
  assert_false(e.within_lateness(9))
  assert_eq(e.lateness(), 20)
}

///|
test "within_lateness is a heuristic while correctable is exact" {
  let e = Engine::new(config(Tumbling(size=10, offset=1), lateness=0))
  ignore(e.apply(Transact(id="seed", changes=[Put(sample("a", 1))])))
  ignore(e.apply(Advance(id="w", to=10)))
  // Window [1,11) is still open, so the fact is correctable...
  assert_true(e.correctable("a"))
  // ...even though its timestamp lies behind the watermark.
  assert_false(e.within_lateness(1))
}
