# TideWeave typed API

此例随 `moon test` 编译并运行。

```mbt check
///|
test "documented typed session correction and recovery" {
  let c = @tideweave.config(@tideweave.Session(gap=10), lateness=20)
  let engine = @tideweave.Engine::new(c)
  let view = @tideweave.View::new()
  let outcome = engine.apply(
    @tideweave.Transact(id="seed", changes=[
      @tideweave.Put({ id: "a", key: "device", at: 0, value: 20, fields: None, }),
      @tideweave.Put({
        id: "c",
        key: "device",
        at: 16,
        value: 35,
        fields: None,
      }),
    ]),
  )
  view.apply(outcome)
  let merged = engine.apply(
    @tideweave.Transact(id="late", changes=[
      @tideweave.Put({ id: "b", key: "device", at: 8, value: 12, fields: None, }),
    ]),
  )
  view.apply(merged)
  assert_eq(view.rows().length(), 1)
  let restored = @tideweave.restore(engine.checkpoint())
  assert_true(restored.rows() == engine.rows())
}
```

结构化事件：事件携带任意 `fields` 键值属性；配置 `value_field` 后，任意整数字段就是窗口度量，事件不再需要固定 `value`。

```mbt check
///|
test "documented structured events with a configurable measure" {
  let c = @tideweave.config(
    @tideweave.Tumbling(size=60, offset=0),
    value_field=Some("watts"),
  )
  let engine = @tideweave.Engine::new(c)
  let outcome = engine.apply(
    @tideweave.Transact(id="meter", changes=[
      @tideweave.Put({
        id: "e1",
        key: "meter-7",
        at: 10,
        value: 0,
        fields: Some([
          ("model", "PM-210"),
          ("firmware", "2.3.1"),
          ("watts", "145"),
        ]),
      }),
      @tideweave.Put({
        id: "e2",
        key: "meter-7",
        at: 40,
        value: 0,
        fields: Some([("model", "PM-210"), ("watts", "98")]),
      }),
    ]),
  )
  assert_eq(outcome.status, "accepted")
  assert_eq(outcome.deltas.length(), 1)
  let row = outcome.deltas[0].after.unwrap()
  assert_eq(row.sum, 243L)
  assert_eq(row.max, 145)
  // 结构化字段原样保留，可从事件读回
  assert_eq(engine.events()[0].field("model"), Some("PM-210"))
}
```
