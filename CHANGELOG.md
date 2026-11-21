# Changelog

## 0.3.0

For [is_logbook 0.3.0](https://pub.dev/packages/is_logbook/versions/0.3.0),
so a package on is_logbook 0.3.0 can use this client. Nothing in this
package's API or on the wire changes.

- A service on is_logbook 0.3.0 refuses a sender table naming user 65534
  (`nobody`) or 4294967294–4294967295, and closes a trajectory on
  `trajectory-closed` (`Kind.trajectoryClosed`); writes to a closed
  trajectory come back as `WriteRefused` with why
  `trajectory-closed <trajectory>`.

## 0.2.0

For [is_logbook 0.2.0](https://pub.dev/packages/is_logbook/versions/0.2.0),
where an entry's id is the sha256 of its bytes. Breaking:

- Ids are `ObjectId`, re-exported from this package; `EntryHash` is no
  longer exported. `Entry.hash` is now `Entry.id`.
- Every entry is checked against its id, from `subscribe` as well as `get`,
  so `Entry.checked` is gone. Its header must match its frame's kind and
  previous.
- New `AlreadyRecorded`: the same bytes were already recorded. Sending the
  same bytes again after `WriteFailed` or `Unanswered` is now safe.
- The writer checks that `ok` and `refused duplicate` name the id of what it
  sent; any other id is `Unanswered`.
- `Entry.kind` is no longer nullable. Bytes without a header, which only
  `get` can return, are `GotEntryWithoutHeader`.
- `GotUnreadable.why` is an `Unreadable` enum: `missing` or `corrupt`.
- The README's socket paths are placeholders.

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
