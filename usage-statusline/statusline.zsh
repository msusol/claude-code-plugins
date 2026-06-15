#!/usr/bin/env zsh
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
if [ -n "$five" ]; then
  five_str="5h:$(printf '%.0f' "$five")%"
  if awk "BEGIN{exit !($five > 75)}"; then
    resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    if [ -n "$resets_at" ]; then
      now=$(date +%s)
      if [ "$resets_at" -gt "$now" ]; then
        diff=$((resets_at - now))
        hrs=$((diff / 3600))
        mins=$(( (diff % 3600) / 60 ))
        if [ "$hrs" -gt 0 ]; then
          five_str="$five_str (resets in ${hrs}hr)"
        else
          five_str="$five_str (resets in ${mins}m)"
        fi
      fi
    fi
  fi
  limits="$five_str"
fi
[ -n "$week" ] && limits="${limits:+$limits }7d:$(printf '%.0f' "$week")%"
[ -n "$limits" ] && parts+=("$limits")

printf '%s' "$(IFS=' | '; echo "${parts[*]}")"
