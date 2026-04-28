#!/usr/bin/env python3
"""
Add `map_url` Grafana custom variable to all geomap dashboards.

This script:
1. Adds a `map_url` custom variable to dashboards' templating.list
   with options for OpenStreetMap / 高德地图 / Carto 浅色
2. Replaces hardcoded basemap.config.url with ${map_url}
3. Converts `osm-standard` preset configs (internal/) to explicit `xyz` config

Run from repo root:
  python3 scripts/add-map-source-switcher.py
"""
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TARGET_FILES = [
    "grafana/dashboards/zh-cn/CurrentChargeView.json",
    "grafana/dashboards/zh-cn/CurrentDriveView.json",
    "grafana/dashboards/zh-cn/CurrentState.json",
    "grafana/dashboards/zh-cn/TrackingDrives.json",
    "grafana/dashboards/zh-cn/charging-stats.json",
    "grafana/dashboards/zh-cn/trip.json",
    "grafana/dashboards/zh-cn/visited.json",
    "grafana/dashboards/internal/charge-details.json",
    "grafana/dashboards/internal/drive-details.json",
]

OSM_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
AMAP_URL = "https://wprd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}"
AMAP_SAT_URL = "https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}"
GOOGLE_URL = "https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}"
GOOGLE_SAT_URL = "https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}"
CARTO_URL = "https://cartodb-basemaps-c.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png"

DESCRIPTION = (
    "🌏 地图源切换（中文版独有）— 6 种瓦片一键切换。"
    "中国大陆推荐：高德地图（路网详细、加载快）或 高德卫星。"
    "海外/翻墙：谷歌地图（路网）或 谷歌卫星。"
    "默认 OpenStreetMap（全球通用）。"
    "选「高德」或「谷歌路网」时自动做 GCJ-02 坐标纠偏，车辆轨迹精准贴合道路。"
)


def make_map_url_variable():
    return {
        "current": {"selected": False, "text": "OpenStreetMap", "value": OSM_URL},
        "description": DESCRIPTION,
        "hide": 0,
        "includeAll": False,
        "label": "地图源",
        "multi": False,
        "name": "map_url",
        "options": [
            {"selected": True, "text": "OpenStreetMap", "value": OSM_URL},
            {"selected": False, "text": "高德地图", "value": AMAP_URL},
            {"selected": False, "text": "高德卫星", "value": AMAP_SAT_URL},
            {"selected": False, "text": "谷歌地图", "value": GOOGLE_URL},
            {"selected": False, "text": "谷歌卫星", "value": GOOGLE_SAT_URL},
            {"selected": False, "text": "Carto 浅色", "value": CARTO_URL},
        ],
        "query": (
            f"OpenStreetMap : {OSM_URL},"
            f"高德地图 : {AMAP_URL},"
            f"高德卫星 : {AMAP_SAT_URL},"
            f"谷歌地图 : {GOOGLE_URL},"
            f"谷歌卫星 : {GOOGLE_SAT_URL},"
            f"Carto 浅色 : {CARTO_URL}"
        ),
        "queryValue": "",
        "skipUrlSync": False,
        "type": "custom",
    }


def detect_format(text: str):
    """Return indent for json.dumps that matches the source file's style."""
    return 2 if text.lstrip().startswith("{\n") else None


def update_dashboard(path: Path) -> tuple[bool, str]:
    text = path.read_text()
    indent = detect_format(text)
    d = json.loads(text)

    templating = d.setdefault("templating", {}).setdefault("list", [])
    if any(v.get("name") == "map_url" for v in templating):
        return False, "already has map_url variable, skipped"

    templating.append(make_map_url_variable())

    geomap_count = 0
    for p in d.get("panels", []):
        if p.get("type") != "geomap":
            continue
        geomap_count += 1
        basemap = p.setdefault("options", {}).setdefault("basemap", {})
        basemap.clear()
        basemap.update({
            "config": {
                "attribution": "${map_url:text} contributors",
                "url": "${map_url}",
                "minZoom": 3,
                "maxZoom": 18,
            },
            "name": "Layer 0",
            "type": "xyz",
        })

    if geomap_count == 0:
        return False, "no geomap panel found"

    if indent is None:
        out = json.dumps(d, ensure_ascii=False, separators=(",", ":"))
    else:
        out = json.dumps(d, ensure_ascii=False, indent=indent)
        if text.endswith("\n"):
            out += "\n"
    path.write_text(out)
    return True, f"updated {geomap_count} geomap panel(s)"


def main():
    failed = 0
    for rel in TARGET_FILES:
        path = REPO_ROOT / rel
        if not path.exists():
            print(f"  ✗ {rel}: file not found")
            failed += 1
            continue
        try:
            ok, msg = update_dashboard(path)
            mark = "✓" if ok else "·"
            print(f"  {mark} {rel}: {msg}")
        except Exception as e:
            print(f"  ✗ {rel}: {e}")
            failed += 1

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
