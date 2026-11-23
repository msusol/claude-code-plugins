# Kaggle kernel completion alerts

Long-running Kaggle kernels (LLM inference, training) should have a background SMS
alert watcher launched immediately after the kernel is started. Do not rely on manually
polling the Kaggle UI.

## SMS gateway

SMS is sent via the owner's email-to-SMS script (a Google Fi gateway in the original setup), kept in a project the owner names:

```zsh
cd <sms-project-dir>
zsh scripts/send_sms_fi.zsh "<message>"
```

The script reads the phone number and SMTP credentials from that project's config. It
must be invoked from that project's root. Ask the owner once which project it is.

## Watcher pattern

Write a polling script to `/tmp/watch_kernel_<slug>.zsh`, launch it with `nohup`, and
log to `/tmp/watch_kernel_<slug>.log`. Poll every 5 minutes — frequent enough to catch
completion promptly without hammering the Kaggle API.

```zsh
cat > /tmp/watch_kernel_<slug>.zsh << 'EOF'
#!/usr/bin/env zsh
KERNEL="<kaggle-user>/<kernel-id>"
SMS_DIR="<sms-project-dir>"
INTERVAL=300

while true; do
  STATUS=$(kaggle kernels status "$KERNEL" 2>&1)
  echo "[$(date '+%H:%M:%S')] $STATUS"

  if echo "$STATUS" | grep -q "COMPLETE"; then
    cd "$SMS_DIR" && zsh scripts/send_sms_fi.zsh "Kaggle <slug> COMPLETE — check results and leaderboard."
    break
  elif echo "$STATUS" | grep -q "ERROR"; then
    cd "$SMS_DIR" && zsh scripts/send_sms_fi.zsh "Kaggle <slug> ERROR — kernel failed, check log."
    break
  fi

  sleep $INTERVAL
done
EOF

nohup zsh /tmp/watch_kernel_<slug>.zsh >> /tmp/watch_kernel_<slug>.log 2>&1 &
echo "Watcher PID: $!"
```

Always verify the watcher started cleanly:

```zsh
sleep 3 && cat /tmp/watch_kernel_<slug>.log
```

The first log line should show `KernelWorkerStatus.RUNNING`. If the file is empty or
shows an error, the watcher failed to start.

## When to launch

Launch the watcher immediately after confirming the kernel is running in the Kaggle UI
(after stopping the auto-run and re-running with the correct accelerator). There is no
value in launching it before the kernel is actually running — `RUNNING` status confirms
it started correctly.

## Cleanup

The watcher process exits automatically on COMPLETE or ERROR. The `/tmp` script and log
files are ephemeral and do not need manual cleanup.
