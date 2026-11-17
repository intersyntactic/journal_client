# Changelog

## 0.1.3

- Allows is_journal 0.10.0, which renames journey to mission and journey
  path to trajectory. Its renamed kinds parse like any other, and its
  renamed refusals arrive as `WriteRefused`.

## 0.1.2

- Allows is_journal 0.9.0, whose wire is unchanged from 0.8.0. Its renamed
  kinds parse like any other, and its renamed refusals arrive as
  `WriteRefused`.

## 0.1.1

- Allows is_journal 0.8.0, whose wire is unchanged from 0.7.0. Its new
  refusal reasons (chain ownership) arrive as `WriteRefused`.

## 0.1.0

- `JournalWriter`: one entry per connection, answered `Written`, `NotTip`,
  `WriteRefused`, `WriteFailed` or `Unanswered`, with a timeout.
- `JournalReader`: `subscribe`, `tip` and `get` on is_journal 0.7.0's read
  socket. `get` checks the entry against its 96 bytes. Everything the
  service sends is read strictly.
