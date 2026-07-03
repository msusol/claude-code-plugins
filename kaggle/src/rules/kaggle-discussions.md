# Reading Kaggle competition discussions

Always use the `kaggle` CLI to read competition discussion threads — never browser
automation (`claude-in-chrome`) or `WebFetch`. Kaggle's discussion pages are
client-rendered and return no usable content to `WebFetch`, and browser automation
is slower and less reliable than the CLI for this.

## Commands

List discussion topics for a competition (title, author, comment count, votes):

```zsh
kaggle competitions topics list <competition-slug>
```

Read a full thread (original post + all replies), given a topic id from the list above:

```zsh
kaggle competitions topic-messages <competition-slug> <topic_id> -s old -n -1
```

- `-s old` sorts chronologically (oldest first) so a thread reads top-to-bottom as
  it happened; use `-s hot`/`-s top` for triage across many threads instead of
  reading one in full.
- `-n -1` returns all top-level messages (default page size truncates long threads).
- Add `-v` for CSV output, which is more reliably parseable than the default table
  format when a thread has long code blocks or embedded images — pipe to a file if
  the output is large rather than trying to read it directly in the terminal.

## When to use

Any time you need to read, search, or summarize a Kaggle competition's Discussion
tab — competitor write-ups, EDA findings, leaderboard chatter, rules clarifications,
data-leak reports. This applies during EDA, when investigating a plateaued
leaderboard score, or whenever the user asks to check "what people are saying" about
a competition.
