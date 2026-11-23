# Emails Claude sends: who they come from

When Claude sends an email on the owner's behalf (a question to a client, a notice, a test), the sender is labeled as the AI, never as the owner.

## Rules

- **Send through the project's own mail tool** (the sending code or package its docs name). Never send through a mail connector that sends as the owner's personal account.
- **From display name: the AI label the owner chose**, kept in the owner's memory or the project's `CLAUDE.md`. If there is none, ask once and record the answer. Use it on every send, including a message written in the owner's voice. The text may be signed with the owner's name only when the owner asked for their voice; the sender line still carries the AI label.
- **From address:** the mailbox login the project's mail tool already uses. Use another address on the same domain only when the owner asks, and test it first with one message to the owner.
- **Copy the owner** on every email Claude sends, and never change the subject of a reply: keep the thread's exact subject so it stays together.
- **Questions go in the format of `planning-email-questions.md`:** `Action needed:`, bold, one per line, under about 120 words.
- **A test message goes only to the owner's own address**, once. After a refusal as spam, stop: do not retry the same message.
- **Never put a repo path, a file name or a link to internal docs in an email to a client**: they cannot open them.
- **Every message needs a `Date` and a `Message-ID` header.** Most mail libraries do not add them, and a message without them can be refused as spam. Check that the project's mail tool adds both before sending.

## Why

- A message once went out under the owner's name when the owner wanted the AI label. Using one label everywhere means the same sender means the same thing, and a reader can tell an AI-written message from one the owner wrote.
- Five messages were refused as spam in one day. The cause was the missing `Date` and `Message-ID` headers, found by comparing the refused messages with one sent from the provider's own webmail, which was delivered. Adding the two headers fixed it.

## Related

- `planning-email-questions.md`: how to word and lay out questions.
- `planning-dm-pbcopy.md`: when the owner will send a message themselves, hand over a draft file and a `pbcopy` line instead.
