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
