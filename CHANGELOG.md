# Changelog

## 0.1.0

- `JournalWriter`: one entry per connection, answered `Written`, `NotTip`,
  `WriteRefused`, `WriteFailed` or `Unanswered`, with a timeout.
- `JournalReader`: `subscribe`, `tip` and `get` on is_journal 0.7.0's read
  socket. `get` checks the entry against its 96 bytes. Everything the
  service sends is read strictly.
