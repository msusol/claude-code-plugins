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

## Recording findings: always a dedicated docs/investigate entry

When the user says `investigate: <kaggle discussion URL>` (or otherwise asks to look
into a specific competition discussion thread), the findings always get their own
dedicated file — `docs/investigate/YYYY-MM-DD-<topic-slug>.md` — following the
structure in `planning-docs-investigate.md` (Context / Investigation Checklist /
Findings / Actions Taken / Resolution / Follow-ups). One `##` heading per discussion
thread if multiple threads are covered in one investigation pass.

Do not fold external discussion-thread research into `docs/investigate/notebook-runs.md`
or any other run-log file, even if the findings are directly relevant to interpreting
a specific notebook run — cross-reference between the two files instead (a one-line
pointer in each direction) so each file stays scoped to its own kind of content:
`notebook-runs.md` tracks *our own* run results/errors, the dedicated discussion
entry tracks *external* research.
