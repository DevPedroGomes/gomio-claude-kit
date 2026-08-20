#!/usr/bin/env python3
"""Consumo local do Claude Code: le ~/.claude/projects/*.jsonl e mostra
onde o limite semanal esta indo (por dia, modelo, projeto e sessao).

  python3 ~/.claude/scripts/uso.py              # semana atual (dom -> hoje)
  python3 ~/.claude/scripts/uso.py --dias 30    # ultimos 30 dias
  python3 ~/.claude/scripts/uso.py --sessoes    # ranking de sessoes do periodo

Valores em US$ sao preco de API usados como PESO relativo. O plano Max nao
cobra assim, mas o limite semanal e proporcional ao mesmo consumo de compute.
Nada sai da maquina.
"""
import argparse, collections, datetime, glob, json, os, sys

ROOT = os.path.expanduser("~/.claude/projects")
TZ = datetime.timezone(datetime.timedelta(hours=-3))

# USD por milhao de tokens: (input, output). cache_write = 1.25x input, cache_read = 0.10x input
PRICES = {
    "claude-fable-5":             (10.0, 50.0),
    "claude-mythos-5":            (10.0, 50.0),
    "claude-opus-5":              ( 5.0, 25.0),
    "claude-opus-4-8":            ( 5.0, 25.0),
    "claude-opus-4-7":            ( 5.0, 25.0),
    "claude-opus-4-6":            ( 5.0, 25.0),
    "claude-sonnet-5":            ( 3.0, 15.0),
    "claude-sonnet-4-6":          ( 3.0, 15.0),
    "claude-haiku-4-5-20251001":  ( 1.0,  5.0),
}
ALVO_DIA = 130.0  # ritmo que fecha a semana com folga


def custo(r):
    p = PRICES.get(r["model"])
    if not p:
        return 0.0
    i, o = p
    return (r["inp"] * i + r["cc"] * i * 1.25 + r["cr"] * i * 0.10 + r["out"] * o) / 1e6


def carregar(desde):
    seen, rows = set(), []
    for path in glob.glob(os.path.join(ROOT, "**", "*.jsonl"), recursive=True):
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except (ValueError, TypeError):
                    continue
                m = d.get("message") or {}
                u = m.get("usage") or {}
                if not u or m.get("role") != "assistant":
                    continue
                key = d.get("requestId") or m.get("id")
                ts = d.get("timestamp")
                if not key or key in seen or not ts:
                    continue
                try:
                    dt = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(TZ)
                except ValueError:
                    continue
                if dt.date() < desde:
                    continue
                seen.add(key)
                rows.append({
                    "dt": dt, "dia": dt.strftime("%Y-%m-%d"),
                    "model": m.get("model") or "?",
                    "sess": d.get("sessionId") or "?",
                    "proj": d.get("cwd") or os.path.basename(os.path.dirname(path)),
                    "side": bool(d.get("isSidechain")),
                    "inp": u.get("input_tokens") or 0,
                    "out": u.get("output_tokens") or 0,
                    "cc":  u.get("cache_creation_input_tokens") or 0,
                    "cr":  u.get("cache_read_input_tokens") or 0,
                })
    return rows


def barra(v, vmax, larg=22):
    if vmax <= 0:
        return ""
    return "#" * max(1, int(round(v / vmax * larg)))


def main():
    ap = argparse.ArgumentParser(description="Consumo local do Claude Code")
    ap.add_argument("--dias", type=int, default=None, help="ultimos N dias (padrao: semana atual desde domingo)")
    ap.add_argument("--sessoes", action="store_true", help="mostrar ranking de sessoes")
    a = ap.parse_args()

    hoje = datetime.datetime.now(TZ).date()
    if a.dias:
        desde, rotulo = hoje - datetime.timedelta(days=a.dias - 1), f"ultimos {a.dias} dias"
    else:
        desde = hoje - datetime.timedelta(days=(hoje.weekday() + 1) % 7)  # domingo
        rotulo = f"semana atual (desde domingo {desde.strftime('%d/%m')})"

    if not os.path.isdir(ROOT):
        sys.exit(f"nao encontrei {ROOT}")

    rows = carregar(desde)
    if not rows:
        sys.exit(f"nenhum request encontrado desde {desde}")

    total = sum(custo(r) for r in rows)
    dias = sorted({r["dia"] for r in rows})
    print(f"\n  CONSUMO CLAUDE CODE - {rotulo}")
    print(f"  {'-' * 62}")
    print(f"  {len(rows):,} requests | US$ {total:,.0f} equivalente | US$ {total/len(rows):.3f}/request")
    print(f"  ritmo: US$ {total/len(dias):,.0f}/dia   (alvo <= US$ {ALVO_DIA:.0f}/dia)")
    if not a.dias:
        proj = total / len(dias) * 7
        print(f"  projecao da semana: US$ {proj:,.0f}  ->  {'FOLGA' if proj <= ALVO_DIA*7 else 'ACIMA DO ALVO'}")

    por_dia = collections.Counter()
    for r in rows:
        por_dia[r["dia"]] += custo(r)
    vmax = max(por_dia.values())
    print(f"\n  POR DIA")
    for d in dias:
        v = por_dia[d]
        flag = "  <-- acima" if v > ALVO_DIA else ""
        print(f"    {d}  US$ {v:>7,.0f}  {barra(v, vmax):<22}{flag}")

    for titulo, chave in (("POR MODELO", "model"), ("POR PROJETO", "proj")):
        agg = collections.defaultdict(lambda: [0, 0.0])
        for r in rows:
            b = agg[r[chave]]
            b[0] += 1
            b[1] += custo(r)
        print(f"\n  {titulo}")
        for k, (n, v) in sorted(agg.items(), key=lambda x: -x[1][1])[:8]:
            if v < 0.5:
                continue
            nome = (k.replace("claude-", "") if chave == "model" else os.path.basename(k.rstrip("/")) or k)
            print(f"    {nome[:34]:<34} US$ {v:>7,.0f}  {v/total*100:>4.1f}%  ({n:,} req)")

    mains = [r for r in rows if not r["side"]]
    subs  = [r for r in rows if r["side"]]
    print(f"\n  ONDE O REQUEST RODA")
    for nome, grp in (("thread principal", mains), ("subagente", subs)):
        if not grp:
            continue
        c = sum(custo(r) for r in grp)
        ctx = sum(r["cr"] for r in grp) / len(grp)
        print(f"    {nome:<18} US$ {c:>7,.0f}  {c/total*100:>4.1f}%  "
              f"US$ {c/len(grp):.3f}/req  ctx {ctx/1000:,.0f}k")

    if a.sessoes:
        agg = collections.defaultdict(lambda: [0, 0.0, None, None, ""])
        for r in rows:
            b = agg[r["sess"]]
            b[0] += 1
            b[1] += custo(r)
            b[2] = r["dt"] if b[2] is None else min(b[2], r["dt"])
            b[3] = r["dt"] if b[3] is None else max(b[3], r["dt"])
            b[4] = r["proj"]
        print(f"\n  TOP SESSOES")
        for _, (n, v, t0, t1, p) in sorted(agg.items(), key=lambda x: -x[1][1])[:12]:
            h = (t1 - t0).total_seconds() / 3600
            print(f"    US$ {v:>7,.0f} | {n:>5} req | {h:>5.1f}h | "
                  f"{t0.strftime('%d/%m %H:%M')} | {os.path.basename(p.rstrip('/'))[:30]}")
    print()


if __name__ == "__main__":
    main()
