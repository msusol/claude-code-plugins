#!/usr/bin/env bash
# Claude Code status line: subscription usage + model + context
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

parts=()

[ -n "$model" ] && parts+=("$model")

if [ -n "$used" ]; then
  parts+=("ctx:$(printf '%.0f' "$used")%")
fi

limits=""
[ -n "$five" ] && limits="5h:$(printf '%.0f' "$five")%"
[ -n "$week" ] && limits="${limits:+$limits }7d:$(printf '%.0f' "$week")%"
[ -n "$limits" ] && parts+=("$limits")

printf '%s' "$(IFS=' | '; echo "${parts[*]}")"
