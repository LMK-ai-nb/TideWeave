"""Real Chromium checks for shared-core behavior, XSS-safe rendering and exports."""
import json, pathlib, sys
from playwright.sync_api import sync_playwright

base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:4174"
root = pathlib.Path(__file__).resolve().parent.parent
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1440, "height": 1120}, device_scale_factor=1)
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(base, wait_until="networkidle")
    assert page.locator("#event-count").inner_text() == "2"
    assert page.locator("#window-count").inner_text() == "2"
    page.locator("#next").click()  # watermark
    assert page.locator("#watermark").inner_text() == "12"
    page.locator("#next").click()  # bridge
    assert page.locator("#window-count").inner_text() == "1"
    assert page.locator("#delta-count").inner_text() == "3 条变更"
    assert "合并" in page.locator("#narrative").inner_text()
    page.locator("#next").click()  # retract
    assert page.locator("#window-count").inner_text() == "2"
    page.locator("#finish").click()
    assert page.locator("#version").inner_text() == "05"
    assert page.locator(".phase.final").count() == 2
    assert "拒绝" in page.locator("#narrative").inner_text()
    page.locator("details").evaluate("e => e.open = true")
    with page.expect_download() as d:
        page.locator("#export").click()
    value = json.loads(pathlib.Path(d.value.path()).read_text(encoding="utf-8"))
    assert value["format"] == "tideweave-checkpoint" and value["version"] == 5
    assert len(value["commands"]) == 5  # rejected command excluded
    page.locator('[data-example="order-amendment.json"]').click()
    page.wait_for_function("document.querySelector('#input').value.includes('order-1')")
    page.locator("#finish").click()
    assert page.locator("#rows").inner_text().find("18900") >= 0
    source = {"schema_version": 1, "config": {"window": {"kind": "session", "gap": 5}},
        "commands": [{"kind": "transaction", "id": "<script>alert(1)</script>", "changes": [
            {"op": "put", "event": {"id": "<img src=x onerror=alert(1)>", "key": "中文🔧", "at": 1, "value": 2}}]}]}
    page.locator("#input").fill(json.dumps(source))
    page.locator("#apply").click(); page.locator("#next").click()
    assert page.locator("#commands b").inner_text() == "<script>alert(1)</script>"
    assert "<img src=x onerror=alert(1)>" in page.locator("#rows").inner_text()
    assert page.locator("#rows img").count() == 0
    page.locator("#input").fill('{"schema_version":1,"schema_version":1}')
    page.locator("#apply").click()
    assert page.locator("#error").is_visible()
    assert page.locator("#event-count").inner_text() == "—"
    assert page.locator("#export").is_disabled()
    page.reload(wait_until="networkidle")
    page.locator("#next").click(); page.locator("#next").click()
    image_dir=root/'artifacts';image_dir.mkdir(exist_ok=True)
    page.screenshot(path=str(image_dir/'desktop.png'),full_page=True)
    page.set_viewport_size({"width":390,"height":844})
    page.reload(wait_until="networkidle")
    assert page.evaluate("document.documentElement.scrollWidth") == 390
    page.locator("#next").click(); page.locator("#next").click()
    page.screenshot(path=str(image_dir/'mobile.png'),full_page=True)
    assert not errors, errors
    browser.close()
    print("Browser checks passed: merge/split/finality, export, scenarios, strict input, XSS, mobile.")
