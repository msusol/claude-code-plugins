# DM and email drafts as tmp file + pbcopy

When drafting a DM, Slack message, or email, always:
1. Use the Bash tool to write the message to `/tmp/<descriptive-name>.txt` — do NOT show a cat command for the user to run, as copy/paste destroys formatting.
2. Then give the user a single `pbcopy` one-liner to run themselves.

## Format

Step 1 — run via Bash tool:
```zsh
cat > /tmp/dm-recipient-topic.txt << 'EOF'
<message text here>
EOF
```

Step 2 — show to user:
```zsh
pbcopy < /tmp/dm-recipient-topic.txt
```

Never output the message as plain prose. Never show the `cat` block for the user to run.
