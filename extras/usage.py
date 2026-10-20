#!/usr/bin/env python3
"""Where your Claude Code usage went, from the local session logs.

Reads the JSONL transcripts Claude Code writes under ~/.claude/projects (or
$CLAUDE_CONFIG_DIR/projects) and reports usage by day, model, project and
session. Nothing leaves the machine.

  python3 usage.py                     # last 7 days, including today
  python3 usage.py --days 30           # last 30 days
  python3 usage.py --all --sessions    # all history, plus the top sessions
  python3 usage.py --daily-target 50   # flag days above $50
  python3 usage.py --json              # machine-readable summary

Dollar amounts are Claude API list prices from prices.json. On a Pro or Max
subscription you do not pay these amounts; read them as a relative weight of
how much compute each day, model or session used. Requests whose model is not
in prices.json are counted and reported separately, never as $0.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import glob
import json
import os
import re
import sys
from typing import Any, Dict, Iterable, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN_FIELDS = ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")


def default_root() -> str:
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(base, "projects")


def default_prices() -> str:
    return os.environ.get("CLAUDE_USAGE_PRICES") or os.path.join(HERE, "prices.json")


def model_family(model_id: str) -> str:
    """Map a model id to its prices.json key.

    claude-haiku-4-5-20251001   -> claude-haiku-4-5
    claude-opus-5-5[1m]         -> claude-opus-5-5
    us.anthropic.claude-opus-5  -> claude-opus-5
    claude-haiku-4-5@20251001   -> claude-haiku-4-5
    An unknown version stays unknown: claude-opus-5-6 never becomes claude-opus-5.
    """
    m = model_id.strip().lower()
    m = re.sub(r"\[[^\]]*\]$", "", m)
    m = m.rsplit("/", 1)[-1]
    m = re.sub(r"^(?:[a-z]{2,4}\.)?anthropic\.", "", m)
    m = re.sub(r"-v\d+(?::\d+)?$", "", m)
    m = re.sub(r"@\d{8}$", "", m)
    m = re.sub(r"-\d{8}$", "", m)
    return m


def load_prices(path: str) -> Dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        sys.exit(f"usage.py: price file not found: {path} (pass --prices or set CLAUDE_USAGE_PRICES)")
    except ValueError as exc:
        sys.exit(f"usage.py: {path} is not valid JSON: {exc}")
    if not isinstance(data.get("models"), dict):
        sys.exit(f"usage.py: {path} has no 'models' object")
    return data


def request_cost(row: Dict[str, Any], prices: Dict[str, Any]) -> Optional[float]:
    """USD cost of one request, or None when no price is known for it."""
    entry = prices["models"].get(model_family(row["model"]))
    if not entry:
        return None
    rates = dict(entry)
    prompt_tokens = row["inp"] + row["cw5"] + row["cw1"] + row["cr"]
    long_ctx = entry.get("long_context")
    if long_ctx and prompt_tokens > long_ctx.get("threshold_tokens", float("inf")):
        rates.update({k: v for k, v in long_ctx.items() if k != "threshold_tokens"})
    if row["speed"] == "fast":
        fast = entry.get("fast")
        if not fast:
            return None
        ratio = fast["input"] / rates["input"]
        for key in ("cache_write_5m", "cache_write_1h", "cache_read"):
            rates[key] = rates[key] * ratio
        rates["input"], rates["output"] = fast["input"], fast["output"]
    cost = (
        row["inp"] * rates["input"]
        + row["cw5"] * rates["cache_write_5m"]
        + row["cw1"] * rates["cache_write_1h"]
        + row["cr"] * rates["cache_read"]
        + row["out"] * rates["output"]
    ) / 1e6
    geo = (prices.get("modifiers") or {}).get("inference_geo") or {}
    return cost * geo.get(row["geo"], 1.0)


def iter_rows(root: str, since: Optional[dt.date], tz: dt.tzinfo) -> Iterable[Dict[str, Any]]:
    seen = set()
    for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        try:
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                msg = d.get("message") or {}
                usage = msg.get("usage") or {}
                if msg.get("role") != "assistant" or not isinstance(usage, dict):
                    continue
                tokens = {k: int(usage.get(k) or 0) for k in TOKEN_FIELDS}
                if not any(tokens.values()):
                    continue  # error placeholders and synthetic messages carry no usage
                key = d.get("requestId") or msg.get("id")
                stamp = d.get("timestamp")
                if not key or key in seen or not stamp:
                    continue
                try:
                    when = dt.datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(tz)
                except ValueError:
                    continue
                if since and when.date() < since:
                    continue
                seen.add(key)
                cache = usage.get("cache_creation") or {}
                cw1 = int(cache.get("ephemeral_1h_input_tokens") or 0)
                cw5 = tokens["cache_creation_input_tokens"] - cw1
                yield {
                    "when": when,
                    "day": when.strftime("%Y-%m-%d"),
                    "model": msg.get("model") or "unknown",
                    "session": d.get("sessionId") or "unknown",
                    "project": d.get("cwd") or os.path.basename(os.path.dirname(path)),
                    "sidechain": bool(d.get("isSidechain")),
                    "speed": usage.get("speed") or "standard",
                    "geo": usage.get("inference_geo") or "global",
                    "inp": tokens["input_tokens"],
                    "out": tokens["output_tokens"],
                    "cw5": max(cw5, 0),
                    "cw1": cw1,
                    "cr": tokens["cache_read_input_tokens"],
                }


def resolve_tz(name: str) -> dt.tzinfo:
    if name == "local":
        tz = dt.datetime.now().astimezone().tzinfo
        return tz if tz is not None else dt.timezone.utc
    if name.upper() == "UTC":
        return dt.timezone.utc
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(name)
    except Exception:  # unknown zone, or zoneinfo/tzdata unavailable
        sys.exit(f"usage.py: unknown time zone: {name}")


def env_float(name: str) -> Optional[float]:
    raw = os.environ.get(name)
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        sys.exit(f"usage.py: {name} must be a number, got {raw!r}")


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Claude Code usage from local session logs")
    period = ap.add_mutually_exclusive_group()
    period.add_argument("--days", type=int, help="last N days including today (default: 7)")
    period.add_argument("--since", help="from this date, YYYY-MM-DD")
    period.add_argument("--all", action="store_true", help="all history")
    ap.add_argument("--sessions", action="store_true", help="also rank sessions")
    ap.add_argument("--daily-target", type=float, default=env_float("CLAUDE_USAGE_DAILY_TARGET"),
                    help="flag days above this USD amount (env: CLAUDE_USAGE_DAILY_TARGET)")
    ap.add_argument("--tz", default=os.environ.get("CLAUDE_USAGE_TZ", "local"),
                    help="time zone for day boundaries: local (default), UTC or an IANA name")
    ap.add_argument("--prices", default=default_prices(), help="price file (default: prices.json next to this script)")
    ap.add_argument("--root", default=default_root(), help="Claude Code projects directory")
    ap.add_argument("--json", action="store_true", help="print a JSON summary instead of the report")
    args = ap.parse_args(argv)
    if args.days is not None and args.days < 1:
        ap.error("--days must be 1 or more (use --all for the full history)")
    if args.daily_target is not None and args.daily_target <= 0:
        ap.error("--daily-target must be greater than 0")
    return args


def period_start(args: argparse.Namespace, today: dt.date) -> Tuple[Optional[dt.date], str]:
    if args.all:
        return None, "all history"
    if args.since:
        try:
            start = dt.date.fromisoformat(args.since)
        except ValueError:
            sys.exit("usage.py: --since must be YYYY-MM-DD")
        return start, f"since {start.isoformat()}"
    days = args.days or 7
    return today - dt.timedelta(days=days - 1), f"last {days} day{'s' if days != 1 else ''}"


def bar(value: float, peak: float, width: int = 22) -> str:
    if peak <= 0 or value <= 0:
        return ""
    return "#" * max(1, int(round(value / peak * width)))


def summarize(rows: List[Dict[str, Any]], prices: Dict[str, Any]) -> Dict[str, Any]:
    priced, unpriced = [], collections.Counter()
    for r in rows:
        r["cost"] = request_cost(r, prices)
        if r["cost"] is None:
            known = model_family(r["model"]) in prices["models"]
            unpriced[f'{r["model"]} (fast mode)' if known else r["model"]] += 1
        else:
            priced.append(r)
    total = sum(r["cost"] for r in priced)
    by_model: Dict[str, Dict[str, float]] = collections.defaultdict(lambda: {"requests": 0, "usd": 0.0})
    for r in priced:
        by_model[r["model"]]["requests"] += 1
        by_model[r["model"]]["usd"] += r["cost"]
    return {
        "requests": len(rows),
        "priced_requests": len(priced),
        "unpriced_requests": sum(unpriced.values()),
        "unpriced_models": dict(unpriced),
        "total_usd": round(total, 6),
        "by_model": {k: {"requests": v["requests"], "usd": round(v["usd"], 6)} for k, v in by_model.items()},
        "priced": priced,
    }


def print_report(summary: Dict[str, Any], label: str, args: argparse.Namespace, prices: Dict[str, Any]) -> None:
    priced: List[Dict[str, Any]] = summary["priced"]
    total = summary["total_usd"]
    days = sorted({r["day"] for r in priced})
    print(f"\n  CLAUDE CODE USAGE - {label}")
    print(f"  {'-' * 62}")
    print(f"  {summary['requests']:,} requests | US$ {total:,.2f} at API list prices", end="")
    print(f" | US$ {total / len(priced):.4f}/request" if priced else "")
    if days:
        pace = total / len(days)
        target = f"   (target <= US$ {args.daily_target:,.2f}/day)" if args.daily_target else ""
        print(f"  pace: US$ {pace:,.2f}/active day{target}")

    if priced:
        per_day = collections.Counter()
        for r in priced:
            per_day[r["day"]] += r["cost"]
        peak = max(per_day.values())
        print("\n  BY DAY")
        for d in days:
            v = per_day[d]
            flag = "  <-- above target" if args.daily_target and v > args.daily_target else ""
            print(f"    {d}  US$ {v:>9,.2f}  {bar(v, peak):<22}{flag}")

        for title, key in (("BY MODEL", "model"), ("BY PROJECT", "project")):
            agg: Dict[str, List[float]] = collections.defaultdict(lambda: [0, 0.0])
            for r in priced:
                agg[r[key]][0] += 1
                agg[r[key]][1] += r["cost"]
            print(f"\n  {title}")
            for k, (n, v) in sorted(agg.items(), key=lambda x: -x[1][1])[:8]:
                name = k.replace("claude-", "") if key == "model" else (os.path.basename(k.rstrip("/")) or k)
                share = v / total * 100 if total else 0.0
                print(f"    {name[:34]:<34} US$ {v:>9,.2f}  {share:>5.1f}%  ({int(n):,} req)")

        print("\n  MAIN THREAD vs SUBAGENTS")
        for name, group in (("main thread", [r for r in priced if not r["sidechain"]]),
                            ("subagents", [r for r in priced if r["sidechain"]])):
            if not group:
                continue
            c = sum(r["cost"] for r in group)
            ctx = sum(r["cr"] for r in group) / len(group)
            share = c / total * 100 if total else 0.0
            print(f"    {name:<18} US$ {c:>9,.2f}  {share:>5.1f}%  US$ {c / len(group):.4f}/req  avg cached ctx {ctx / 1000:,.0f}k")

        if args.sessions:
            sess: Dict[str, List[Any]] = collections.defaultdict(lambda: [0, 0.0, None, None, ""])
            for r in priced:
                b = sess[r["session"]]
                b[0] += 1
                b[1] += r["cost"]
                b[2] = r["when"] if b[2] is None else min(b[2], r["when"])
                b[3] = r["when"] if b[3] is None else max(b[3], r["when"])
                b[4] = r["project"]
            print("\n  TOP SESSIONS")
            for _, (n, v, t0, t1, proj) in sorted(sess.items(), key=lambda x: -x[1][1])[:12]:
                hours = (t1 - t0).total_seconds() / 3600
                print(f"    US$ {v:>9,.2f} | {n:>5} req | {hours:>5.1f}h | "
                      f"{t0.strftime('%Y-%m-%d %H:%M')} | {os.path.basename(proj.rstrip('/'))[:30]}")

    if summary["unpriced_requests"]:
        models = ", ".join(f"{m} ({n})" for m, n in sorted(summary["unpriced_models"].items(), key=lambda x: -x[1]))
        print(f"\n  WARNING: {summary['unpriced_requests']:,} requests without a known price: {models}.")
        print("  They are left out of the dollar totals above. Add the model to prices.json to include them.")
    print(f"\n  Prices: {prices.get('source', 'prices.json')} (retrieved {prices.get('retrieved', 'unknown')})\n")


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    tz = resolve_tz(args.tz)
    prices = load_prices(args.prices)
    today = dt.datetime.now(tz).date()
    since, label = period_start(args, today)

    if not os.path.isdir(args.root):
        sys.exit(f"usage.py: directory not found: {args.root}")
    rows = list(iter_rows(args.root, since, tz))
    if not rows:
        sys.exit(f"usage.py: no requests found ({label}) under {args.root}")

    summary = summarize(rows, prices)
    if args.json:
        out = {k: v for k, v in summary.items() if k != "priced"}
        out["period"] = label
        out["prices_retrieved"] = prices.get("retrieved")
        print(json.dumps(out, indent=2, sort_keys=True))
    else:
        print_report(summary, label, args, prices)
    return 0


if __name__ == "__main__":
    sys.exit(main())
