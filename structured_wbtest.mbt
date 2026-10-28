///|
test "a configured structured field drives the built-in aggregates" {
  let c = config(
    Tumbling(size=10, offset=0),
    lateness=0,
    value_field=Some("watts"),
  )
  let rows = aggregate(c, [
    {
      id: "a",
      key: "meter",
      at: 1,
      value: 0,
      fields: Some([("model", "PM-210"), ("watts", "145")]),
    },
    { id: "b", key: "meter", at: 3, value: 0, fields: Some([("watts", "77")]), },
  ])
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].count, 2)
  assert_eq(rows[0].sum, 222L)
  assert_eq(rows[0].min, 77)
  assert_eq(rows[0].max, 145)
}

///|
test "measure_window honors the configured structured field" {
  let c = config(Tumbling(size=10, offset=0), value_field=Some("watts"))
  let total = measure(name="total", identity=0, step=fn(acc, v) { acc + v }, finish=fn(
    acc,
    _,
  ) {
    acc
  })
  let windows = measure_window(
    c,
    [
      {
        id: "a",
        key: "meter",
        at: 2,
        value: 0,
        fields: Some([("watts", "30")]),
      },
    ],
    [total],
  )
  assert_eq(windows.length(), 1)
  assert_eq(windows[0].measures[0].value, 30L)
}

///|
test "structured JSON events omit value and carry fields through the report" {
  let request = "{\"schema_version\":1,\"config\":{\"window\":{\"kind\":\"tumbling\",\"size\":10,\"offset\":0},\"lateness\":0,\"value_field\":\"watts\"},\"commands\":[{\"id\":\"d1\",\"kind\":\"transaction\",\"changes\":[{\"op\":\"put\",\"event\":{\"id\":\"e1\",\"key\":\"meter\",\"at\":1,\"value\":999,\"fields\":{\"model\":\"PM-210\",\"watts\":145}}}]},{\"id\":\"w\",\"kind\":\"watermark\",\"to\":10}]}"
  let f = obj(strict_json(replay_json(request)))
  let rows = arr(req(f, "rows"), 8)
  assert_eq(str(req(obj(rows[0]), "sum")), "145")
  let events = arr(req(f, "events"), 8)
  let fields = arr(req(obj(events[0]), "fields"), 8)
  assert_eq(arr(fields[0], 2)[0], "model")
  assert_eq(arr(fields[0], 2)[1], "PM-210")
  assert_eq(arr(fields[1], 2)[0], "watts")
  assert_eq(arr(fields[1], 2)[1], "145")
}

///|
test "events missing the configured measure field are rejected" {
  let request = "{\"schema_version\":1,\"config\":{\"window\":{\"kind\":\"tumbling\",\"size\":10,\"offset\":0},\"lateness\":0,\"value_field\":\"watts\"},\"commands\":[{\"id\":\"d1\",\"kind\":\"transaction\",\"changes\":[{\"op\":\"put\",\"event\":{\"id\":\"e1\",\"key\":\"meter\",\"at\":1,\"fields\":{\"model\":\"PM-210\"}}}]}]}"
  let f = obj(strict_json(replay_json(request)))
  let steps = arr(req(f, "steps"), 8)
  assert_eq(str(req(obj(steps[0]), "status")), "rejected")
  assert_true(str(req(obj(steps[0]), "message")).contains("measure field"))
}

///|
test "structured fields round-trip through checkpoints" {
  let c = config(
    Tumbling(size=10, offset=0),
    lateness=0,
    value_field=Some("watts"),
  )
  let e = Engine::new(c)
  ignore(
    e.apply(
      Transact(id="d", changes=[
        Put({
          id: "e1",
          key: "meter",
          at: 1,
          value: 0,
          fields: Some([("watts", "145"), ("model", "PM-210")]),
        }),
      ]),
    ),
  )
  let restored = restore(e.checkpoint())
  assert_eq(restored.events().length(), 1)
  assert_eq(restored.events()[0].field("model"), Some("PM-210"))
  assert_eq(restored.events()[0].measure(Some("watts")), 145L)
}

///|
test "fields ride along unchanged when the measure stays numeric" {
  let c = config(Tumbling(size=10, offset=0))
  let rows = aggregate(c, [
    { id: "a", key: "k", at: 1, value: 5, fields: Some([("model", "PM-210")]), },
  ])
  assert_eq(rows[0].sum, 5L)
  let e = Engine::new(c)
  ignore(
    e.apply(
      Transact(id="d", changes=[
        Put({
          id: "a",
          key: "k",
          at: 1,
          value: 5,
          fields: Some([("model", "PM-210")]),
        }),
      ]),
    ),
  )
  assert_eq(e.events()[0].field("model"), Some("PM-210"))
}

///|
test "session windows honor the configured structured field" {
  let c = config(Session(gap=10), lateness=0, value_field=Some("kwh"))
  let rows = aggregate(c, [
    { id: "a", key: "home", at: 0, value: 0, fields: Some([("kwh", "3")]), },
    { id: "b", key: "home", at: 6, value: 0, fields: Some([("kwh", "4")]), },
    { id: "c", key: "home", at: 30, value: 0, fields: Some([("kwh", "5")]), },
  ])
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].sum, 7L)
  assert_eq(rows[1].sum, 5L)
}

///|
test "streaming accepts structured events with value_field" {
  let stream = "{\"config\":{\"window\":{\"kind\":\"tumbling\",\"size\":10,\"offset\":0},\"lateness\":0,\"value_field\":\"watts\"}}\n{\"id\":\"d1\",\"kind\":\"transaction\",\"changes\":[{\"op\":\"put\",\"event\":{\"id\":\"e1\",\"key\":\"meter\",\"at\":1,\"fields\":{\"watts\":50}}}]}\n{\"id\":\"w\",\"kind\":\"watermark\",\"to\":10}\n"
  let lines = stream_json(stream)
    .split("\n")
    .collect()
    .filter(fn(l) { l.contains("\"summary\"") })
  let summary = obj(strict_json(lines[0].to_owned()))
  let rows = arr(req(obj(req(summary, "summary")), "rows"), 8)
  assert_eq(str(req(obj(rows[0]), "sum")), "50")
}
