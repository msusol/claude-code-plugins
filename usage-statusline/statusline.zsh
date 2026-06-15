#!/usr/bin/env zsh
# Claude Code status line: model | ctx | 5h/7d rate limits | session cost
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

parts=()

[ -n "$model" ] && parts+=("$model")

if [ -n "$used" ]; then
  parts+=("ctx:$(printf '%.0f' "$used")%")
fi

limits=""
if [ -n "$five" ]; then
  five_str="5h:$(printf '%.0f' "$five")%"
  if awk "BEGIN{exit !($five > 75)}"; then
    five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    if [ -n "$five_resets" ]; then
      now=$(date +%s)
      if [ "$five_resets" -gt "$now" ]; then
        diff=$((five_resets - now))
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

if [ -n "$week" ]; then
  week_str="7d:$(printf '%.0f' "$week")%"
  if [ -n "$week_resets" ]; then
    reset_day=$(date -r "$week_resets" +%a)
    week_str="$week_str (resets $reset_day)"
  fi
  limits="${limits:+$limits }$week_str"
fi

[ -n "$limits" ] && parts+=("$limits")

if [ -n "$cost" ]; then
  parts+=("$(printf '$%.2f' "$cost")")
fi

printf '%s' "$(IFS=' | '; echo "${parts[*]}")"
