#!/usr/bin/env bash
#
# Claude Code status line:
#   directory  branch*  |  model.effort  |  ctx 42%  |  5h 23% ↻3h  |  7d 41% ↻4d
#
# Reads the JSON that Claude Code sends on stdin (see the statusLine docs).
# Requires jq. The 5h and 7d limits appear only on Pro and Max plans, after the
# first response of a session; behind a gateway with a spend limit, "spend"
# appears instead.
#
# Colors: green = room left, yellow = watch it, red = act now.
# Thresholds (percent), overridable through the environment:
#   STATUSLINE_CTX_WARN=50  STATUSLINE_CTX_CRIT=75
#   STATUSLINE_LIMIT_WARN=50  STATUSLINE_LIMIT_CRIT=80

set -uo pipefail

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  printf 'statusline: jq not found (install jq to see model, context and limits)'
  exit 0
fi

CTX_WARN=${STATUSLINE_CTX_WARN:-50}
CTX_CRIT=${STATUSLINE_CTX_CRIT:-75}
LIM_WARN=${STATUSLINE_LIMIT_WARN:-50}
LIM_CRIT=${STATUSLINE_LIMIT_CRIT:-80}

# One jq pass. Every field has a non-empty default so tab splitting stays aligned.
IFS=$'\t' read -r CWD MODEL EFFORT THINK CTX H5 H5R D7 D7R SPEND SPENDR <<EOF_FIELDS
$(printf '%s' "$INPUT" | jq -r '
  [ (.workspace.current_dir // .cwd // "-")
  , (.model.display_name // .model.id // "-")
  , (.effort.level // "-")
  , (if .thinking.enabled == false then "off" else "on" end)
  , (.context_window.used_percentage // -1 | floor)
  , (.rate_limits.five_hour.used_percentage // -1 | floor)
  , (.rate_limits.five_hour.resets_at // 0)
  , (.rate_limits.seven_day.used_percentage // -1 | floor)
  , (.rate_limits.seven_day.resets_at // 0)
  , (.rate_limits.spend_limit.used_percentage // -1 | floor)
  , (.rate_limits.spend_limit.resets_at // 0)
  ] | @tsv' 2>/dev/null)
EOF_FIELDS

if [ -z "${CWD:-}" ] || [ "$CWD" = "-" ]; then
  exit 0
fi

DIM=$'\033[2m'; RST=$'\033[0m'; BLD=$'\033[1m'
GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYA=$'\033[36m'
SEP=" ${DIM}|${RST} "

tint() { # value warn crit
  if [ "$1" -ge "$3" ]; then printf '%s' "$RED"
  elif [ "$1" -ge "$2" ]; then printf '%s' "$YEL"
  else printf '%s' "$GRN"; fi
}

until_reset() { # epoch seconds -> "↻2d", "↻5h", "↻12m", "↻now"
  [ "$1" -le 0 ] && return 0
  local d=$(( $1 - $(date +%s) ))
  if [ "$d" -le 0 ]; then printf ' ↻now'
  elif [ "$d" -ge 86400 ]; then printf ' ↻%dd' $(( d / 86400 ))
  elif [ "$d" -ge 3600 ]; then printf ' ↻%dh' $(( d / 3600 ))
  else printf ' ↻%dm' $(( d / 60 )); fi
}

OUT=""

# Directory, shortened to the last two components, and git branch (* = uncommitted changes)
TILDE="~"
SHORT="${CWD/#$HOME/$TILDE}"
case "$SHORT" in */*/*/*) PARENT="${SHORT%/*}"; SHORT=".../${PARENT##*/}/${SHORT##*/}" ;; esac
OUT+="${DIM}${SHORT}${RST}"
if BRANCH=$(git -C "$CWD" symbolic-ref --quiet --short HEAD 2>/dev/null); then
  DIRTY=""
  git -C "$CWD" diff --quiet --ignore-submodules HEAD 2>/dev/null || DIRTY="*"
  OUT+=" ${CYA}${BRANCH}${DIRTY}${RST}"
fi

# Model and effort
OUT+="${SEP}${BLD}${MODEL}${RST}"
[ "$EFFORT" != "-" ] && OUT+="${DIM}.${EFFORT}${RST}"
[ "$THINK" = "off" ] && OUT+="${DIM}.no-thinking${RST}"

# Context window used
if [ "$CTX" -ge 0 ]; then
  OUT+="${SEP}$(tint "$CTX" "$CTX_WARN" "$CTX_CRIT")ctx ${CTX}%${RST}"
fi

# Plan limits and spend limit
if [ "$H5" -ge 0 ]; then
  OUT+="${SEP}$(tint "$H5" "$LIM_WARN" "$LIM_CRIT")5h ${H5}%${RST}${DIM}$(until_reset "$H5R")${RST}"
fi
if [ "$D7" -ge 0 ]; then
  OUT+="${SEP}$(tint "$D7" "$LIM_WARN" "$LIM_CRIT")7d ${D7}%${RST}${DIM}$(until_reset "$D7R")${RST}"
fi
if [ "$SPEND" -ge 0 ]; then
  OUT+="${SEP}$(tint "$SPEND" "$LIM_WARN" "$LIM_CRIT")spend ${SPEND}%${RST}${DIM}$(until_reset "$SPENDR")${RST}"
fi

printf '%s' "$OUT"
