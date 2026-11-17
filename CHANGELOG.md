# Changelog

## 0.1.1

- Cancelling a `subscribe` stream now completes while the subscription is
  waiting for new entries; it used to wait for the next entry, forever if
  none came.

## 0.1.0

- The client for an [is_logbook](https://pub.dev/packages/is_logbook)
  service, replacing is_journal_client 0.1.2. `JournalWriter` and
  `JournalReader` are now `LogbookWriter` and `LogbookReader`; every other
  name is unchanged.
- `LogbookWriter`: one entry per connection, answered `Written`, `NotTip`,
  `WriteRefused`, `WriteFailed` or `Unanswered`, with a timeout.
- `LogbookReader`: `subscribe`, `tip` and `get` on the read socket. `get`
  checks the entry against its 96 bytes. Everything the service sends is
  read strictly.
