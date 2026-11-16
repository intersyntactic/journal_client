# is_journal_client

The one client for an [is_journal](https://pub.dev/packages/is_journal)
service: a writer for its write socket and a reader for its read socket. It
replaces the copies of the socket protocol that each program used to carry.

## Writing

    final writer = JournalWriter('/run/record/journal.sock');
    switch (await writer.write(Kind.parse('turn')!, body, previous: tip)) {
      case Written(:final entry): // recorded as entry
      case NotTip(:final tip):    // nothing added; send again after tip
      case WriteRefused(:final why): // nothing added
      case WriteFailed(:final why):  // may be in: read the tip first
      case Unanswered(:final why):   // may be in: read the tip first
    }

One connection per entry. The service knows the sender by the user at the
other end of the socket, and its sender table says which kinds that user may
send. `previous` is the entry before this one in its chain, or null to start
a chain. `timeout` (10 seconds unless given) bounds the wait for an answer.

## Reading

    final reader = JournalReader('/run/record-read/journal.sock');
    await for (final item in reader.subscribe(kinds: {turn}, from: last)) {
      switch (item) {
        case Entry(): // an entry: hash, kind, previous, recorded, body
        case CaughtUp(:final head): // the backlog ended at head
      }
    }

- `subscribe` sends every entry of those kinds (every kind when `kinds` is
  null) after `from` (the journal's start when null), then `CaughtUp`, then
  each new entry while the stream is listened to. `CaughtUp.head` is also a
  place to subscribe from next time.
- `tip(entry)` answers the tip of that entry's chain.
- `get(entry)` answers `GotEntry`, `GotNone`, `GotUnreadable` (`missing` or
  `corrupt`) or `GotFailed`. A `GotEntry` has been checked against the
  entry's 96 bytes: they hash to the entry asked for, and they name the bytes
  as their object.

Entries from `subscribe` are not checked (`checked` is false): the service
sends no 96 bytes with them, so they are its word. Use `get` when you need
the check.

Everything the service sends is read strictly. A failure is a `ReadFailure`:
`ReadUnreachable` (not reached, closed early, or too slow), `ReadRefused`
(the service said `refused`, for example an entry it doesn't know) or
`ReadBroken` (something the service never sends, or bytes that don't check).
