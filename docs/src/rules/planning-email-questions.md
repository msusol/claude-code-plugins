# Emails that ask a question: make the questions easy to see

When drafting an email to someone who must answer a question (a client, a partner, a teammate), put every question where the reader cannot miss it.

## Rules

- Put each question that needs an answer under an `Action needed:` heading, one per numbered or bulleted line.
- Write the question itself in bold (HTML `<strong>`, or `**bold**` in a draft that is converted when sent). The explanation around it stays plain.
- One question per line, as one sentence ending in "?", with the options after it. Do not bury a question inside a paragraph.
- Anything that needs no answer goes under `FYI:` in plain text, after the questions.
- Keep the email short and in plain language. State the count of questions in the opening line ("two questions for you").
- Send the bold as HTML and a plain-text version alongside it, so a client that shows only text still reads the question lines.
- Never change the subject of a reply (see the recipient thread's own subject); the questions go in the body.

## Why

Found live 2026-11-20: three questions sent as plain text inside paragraphs were hard to find; the sender's own screenshot showed the reader had to underline them by hand. A person who has to hunt for the question may answer only part of the email, or none of it.

## Example

```
Hi Pat,

Two questions for you.

Action needed:
1. **Should we clear a bounced email in GHL, or leave it?** Your workflow already records it in PF Bad Emails.
2. **Do you want us to send leads with neither phone nor email so they can get a postcard?**

FYI:
- We trace co-owners in the daily flow starting tomorrow.
```
