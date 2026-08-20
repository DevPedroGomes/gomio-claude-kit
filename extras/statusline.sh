#!/usr/bin/env bash
# StatusLine do Claude Code: dir · branch · modelo·effort · contexto% · limite 5h% · limite semanal%
# Recebe o payload JSON do Claude Code via stdin.
# Cores: verde = folga, amarelo = atencao, vermelho = agir agora.

set -uo pipefail
IFS= read -r -d '' INPUT || true
[ -z "${INPUT:-}" ] && exit 0

# --- extrai tudo numa passada so (barato) ---
IFS=$'\t' read -r CWD MODEL EFFORT THINK CTX H5 H5R D7 D7R <<EOF
$(printf '%s' "$INPUT" | jq -r '
  [ (.workspace.current_dir // .cwd // "-")
  , (.model.display_name // "-")
  , (.effort.level // "-")
  , (if .thinking.enabled == false then "off" else "on" end)
  , (.context_window.used_percentage // -1 | floor)
  , (.rate_limits.five_hour.used_percentage  // -1 | floor)
  , (.rate_limits.five_hour.resets_at        // 0)
  , (.rate_limits.seven_day.used_percentage  // -1 | floor)
  , (.rate_limits.seven_day.resets_at        // 0)
  ] | @tsv' 2>/dev/null)
EOF
[ -z "${CWD:-}" ] || [ "$CWD" = "-" ] && exit 0

DIM=$'\033[2m'; RST=$'\033[0m'
GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYA=$'\033[36m'; BLD=$'\033[1m'

# cor por faixa: <warn verde, <crit amarelo, >=crit vermelho
tint() { # $1=valor $2=warn $3=crit
  if   [ "$1" -ge "$3" ]; then printf '%s' "$RED"
  elif [ "$1" -ge "$2" ]; then printf '%s' "$YEL"
  else printf '%s' "$GRN"; fi
}

# "2d", "5h", "12m" ate o reset
until_reset() {
  [ "$1" -le 0 ] && return
  local d=$(( $1 - $(date +%s) ))
  [ "$d" -le 0 ] && { printf '↻agora'; return; }
  if   [ "$d" -ge 86400 ]; then printf '↻%dd' $(( d / 86400 ))
  elif [ "$d" -ge 3600 ];  then printf '↻%dh' $(( d / 3600 ))
  else printf '↻%dm' $(( d / 60 )); fi
}

OUT=""

# --- diretorio (encurtado) + branch ---
TILDE="~"
SHORT="${CWD/#$HOME/$TILDE}"
case "$SHORT" in */*/*/*) PARENT="${SHORT%/*}"; SHORT=".../${PARENT##*/}/${SHORT##*/}";; esac
OUT+="${DIM}${SHORT}${RST}"
if BR=$(git -C "$CWD" symbolic-ref --quiet --short HEAD 2>/dev/null); then
  DIRTY=""; git -C "$CWD" diff --quiet --ignore-submodules HEAD 2>/dev/null || DIRTY="*"
  OUT+=" ${CYA}${BR}${DIRTY}${RST}"
fi

# --- modelo + effort ---
OUT+=" ${DIM}│${RST} ${BLD}${MODEL}${RST}"
[ "$EFFORT" != "-" ] && OUT+="${DIM}·${EFFORT}${RST}"
[ "$THINK" = "off" ] && OUT+="${DIM}·sem-think${RST}"

# --- contexto: a regra dos 50% ---
if [ "$CTX" -ge 0 ]; then
  OUT+=" ${DIM}│${RST} $(tint "$CTX" 50 75)ctx ${CTX}%${RST}"
fi

# --- limites da assinatura (so aparecem apos a 1a resposta da API) ---
if [ "$H5" -ge 0 ]; then
  OUT+=" ${DIM}│${RST} $(tint "$H5" 50 80)5h ${H5}%${RST}${DIM}$(until_reset "$H5R")${RST}"
fi
if [ "$D7" -ge 0 ]; then
  OUT+=" ${DIM}│${RST} $(tint "$D7" 50 80)sem ${D7}%${RST}${DIM}$(until_reset "$D7R")${RST}"
fi

printf '%s' "$OUT"
