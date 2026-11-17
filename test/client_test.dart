import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:is_logbook/is_logbook.dart';
import 'package:is_logbook/service.dart';
import 'package:is_logbook_client/is_logbook_client.dart';
import 'package:test/test.dart';

Uint8List bytesOf(String s) => utf8.encode(s);

Kind kind(String name) => Kind.parse(name)!;

/// A server at [path] that answers every connection with [answer], or never
/// answers when it is null.
Future<ServerSocket> fake(String path, String? answer) async {
  final server = await ServerSocket.bind(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
  );
  server.listen((socket) {
    socket.listen((_) {}, onError: (Object _) {});
    if (answer == null) return;
    socket
      ..add(utf8.encode(answer))
      ..close();
  });
  return server;
}

void main() {
  final me = Process.runSync('id', ['-un']).stdout.toString().trim();
  late Directory dir;
  late LogbookService service;
  late LogbookWriter writer;
  late LogbookReader reader;

  setUp(() async {
    // Unix socket paths are short (about 104 bytes on macOS).
    dir = Directory('/tmp').createTempSync('jc');
    service = await LogbookService.start(
      Logbook.open(Directory('${dir.path}/j'))!,
      SenderTable.parse(bytesOf('$me turn witnessed\n')),
      File('${dir.path}/w.sock'),
      readSocket: File('${dir.path}/r.sock'),
    );
    writer = LogbookWriter('${dir.path}/w.sock');
    reader = LogbookReader('${dir.path}/r.sock');
  });
  tearDown(() async {
    await service.close();
    dir.deleteSync(recursive: true);
  });

  Future<EntryHash> write(String k, String body, [EntryHash? previous]) async =>
      switch (await writer.write(kind(k), bytesOf(body), previous: previous)) {
        Written(:final entry) => entry,
        final other => throw StateError('$other'),
      };

  group('the writer', () {
    test('writes an entry and answers its hash', () async {
      final a = await write('turn', 'a');
      final got = await reader.get(a);
      expect(utf8.decode((got as GotEntry).entry.recorded), 'turn\n-\na');
    });

    test('names the tip when previous is not it, and adds nothing', () async {
      final a = await write('turn', 'a');
      final b = await write('turn', 'b', a);
      final answer = await writer.write(
        kind('turn'),
        bytesOf('c'),
        previous: a,
      );
      expect((answer as NotTip).tip, b);
      expect(await reader.tip(a), b);
    });

    test('says refused for a kind the sender may not write', () async {
      final answer = await writer.write(kind('decided'), bytesOf('x'));
      expect((answer as WriteRefused).why, startsWith('kind decided'));
    });

    test('says unanswered when nothing listens', () async {
      final answer = await LogbookWriter('${dir.path}/nobody.sock')
          .write(kind('turn'), bytesOf('x'));
      expect(answer, isA<Unanswered>());
    });

    test('says unanswered when the answer does not come in time', () async {
      final server = await fake('${dir.path}/silent.sock', null);
      final answer = await LogbookWriter(
        '${dir.path}/silent.sock',
        timeout: const Duration(milliseconds: 200),
      ).write(kind('turn'), bytesOf('x'));
      expect((answer as Unanswered).why, startsWith('no answer within'));
      await server.close();
    });

    test('reads the answer strictly', () {
      final hash = EntryHash.of(bytesOf('x')).hex;
      expect(WriteResult.read('ok $hash\n'), isA<Written>());
      expect(WriteResult.read('failed disk full\n'), isA<WriteFailed>());
      expect(WriteResult.read('refused not-tip $hash\n'), isA<NotTip>());
      expect(WriteResult.read('refused not-tip xyz\n'), isA<WriteRefused>());
      for (final bad in [
        'ok $hash',
        'ok xyz\n',
        'ok $hash\nok $hash\n',
        'OK $hash\n',
        'refused\n',
        'maybe\n',
      ]) {
        expect(WriteResult.read(bad), isA<Unanswered>(), reason: bad);
      }
    });
  });

  group('subscribe', () {
    test('sends the backlog, then caught-up, then new entries', () async {
      final a = await write('turn', 'a');
      final w = await write('witnessed', 'w');
      final items = StreamIterator(reader.subscribe(kinds: {kind('turn')}));
      expect(await items.moveNext(), isTrue);
      final first = items.current as Entry;
      expect(first.hash, a);
      expect(first.kind, kind('turn'));
      expect(first.previous, isNull);
      expect(utf8.decode(first.body), 'a');
      expect(first.checked, isFalse);
      expect(await items.moveNext(), isTrue);
      expect((items.current as CaughtUp).head, w);
      final b = await write('turn', 'b', a);
      expect(await items.moveNext(), isTrue);
      expect((items.current as Entry).hash, b);
      expect((items.current as Entry).previous, a);
      await items.cancel();
    });

    test('cancel completes while the subscription waits for entries', () async {
      final arrived = Completer<void>();
      final got = <Subscribed>[];
      final subscription = reader.subscribe(kinds: {kind('turn')}).listen((s) {
        got.add(s);
        if (s is Entry) arrived.complete();
      });
      final a = await write('turn', 'a');
      await arrived.future;
      // Long enough for the subscription to be waiting on the socket again.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await subscription.cancel().timeout(const Duration(seconds: 2));
      expect(got.whereType<Entry>().single.hash, a);
    });

    test('every kind when kinds is null, from a given entry', () async {
      final a = await write('turn', 'a');
      final w = await write('witnessed', 'w');
      final items = await reader.subscribe(from: a).take(2).toList();
      expect((items[0] as Entry).hash, w);
      expect((items[1] as CaughtUp).head, w);
      final all = await reader.subscribe().take(1).toList();
      expect((all.single as Entry).kind, Kind.started);
    });

    test('errors with refused for an entry the service does not know', () {
      expect(
        reader.subscribe(from: EntryHash.of(bytesOf('nothing'))).toList(),
        throwsA(isA<ReadRefused>()),
      );
    });

    test('takes no empty set of kinds', () {
      expect(
        reader.subscribe(kinds: {}).toList(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('errors with unreachable when nothing listens', () {
      expect(
        LogbookReader('${dir.path}/nobody.sock').subscribe().toList(),
        throwsA(isA<ReadUnreachable>()),
      );
    });

    test('errors with broken on a frame the service never sends', () async {
      for (final (name, odd) in [
        ('bad-entry', 'entry x y z 1\nq'),
        ('bad-line', 'hello there\n'),
        ('bad-head', 'caught-up -\n'),
      ]) {
        final server = await fake('${dir.path}/$name.sock', odd);
        await expectLater(
          LogbookReader('${dir.path}/$name.sock').subscribe().toList(),
          throwsA(isA<ReadBroken>()),
          reason: odd,
        );
        await server.close();
      }
    });
  });

  group('tip', () {
    test("answers the chain's tip, refuses an unknown entry", () async {
      final a = await write('turn', 'a');
      expect(await reader.tip(a), a);
      final b = await write('turn', 'b', a);
      expect(await reader.tip(a), b);
      expect(
        reader.tip(EntryHash.of(bytesOf('nothing'))),
        throwsA(isA<ReadRefused>()),
      );
    });
  });

  group('get', () {
    test('answers the entry, checked against its 96 bytes', () async {
      final a = await write('turn', 'a');
      final b = await write('turn', 'b', a);
      final entry = (await reader.get(b) as GotEntry).entry;
      expect(entry.checked, isTrue);
      expect(entry.previous, a);
      expect(utf8.decode(entry.body), 'b');
    });

    test('says none for an entry the logbook does not hold', () async {
      expect(await reader.get(EntryHash.of(bytesOf('x'))), isA<GotNone>());
    });

    test('says unreadable when the bytes are gone', () async {
      final a = await write('turn', 'a');
      final object = ObjectId.of(bytesOf('turn\n-\na')).hex;
      File(
        '${dir.path}/j/objects/${object.substring(0, 2)}/${object.substring(2)}',
      ).deleteSync();
      expect(((await reader.get(a)) as GotUnreadable).why, 'missing');
    });

    test('is broken when the 96 bytes do not check', () async {
      // A real answer, then the same answer with its bytes changed.
      final a = await write('turn', 'a');
      final real = Socket.connect(
        InternetAddress('${dir.path}/r.sock', type: InternetAddressType.unix),
        0,
      );
      final s = await real;
      s.add(bytesOf('get ${a.hex}\n'));
      final answer = utf8.decode(await s.expand((c) => c).toList());
      s.destroy();
      expect(answer, endsWith('turn\n-\na'));
      final lied = '${answer.substring(0, answer.length - 1)}b';
      final server = await fake('${dir.path}/lie.sock', lied);
      expect(
        LogbookReader('${dir.path}/lie.sock').get(a),
        throwsA(
          isA<ReadBroken>().having((e) => e.why, 'why', contains('object')),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await server.close();
    });

    test('is broken when the 96 bytes hash to another entry', () async {
      // The same answer, with one byte of the code's name changed: the bytes
      // are still its object, but the entry is no longer the one asked for.
      final a = await write('turn', 'a');
      final s = await Socket.connect(
        InternetAddress('${dir.path}/r.sock', type: InternetAddressType.unix),
        0,
      );
      s.add(bytesOf('get ${a.hex}\n'));
      final answer = utf8.decode(await s.expand((c) => c).toList());
      s.destroy();
      final words = answer.split(' ');
      final hex = words[5];
      // Hex characters 64 to 127 spell the code's name; flip the first.
      final flipped = hex.replaceRange(64, 65, hex[64] == '0' ? '1' : '0');
      final lied = [...words.sublist(0, 5), flipped].join(' ');
      final server = await fake('${dir.path}/code.sock', lied);
      expect(
        LogbookReader('${dir.path}/code.sock').get(a),
        throwsA(
          isA<ReadBroken>().having((e) => e.why, 'why', contains('elsewhere')),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await server.close();
    });

    test('is broken when the answer names another entry', () async {
      final a = await write('turn', 'a');
      final other = EntryHash.of(bytesOf('other')).hex;
      final server = await fake('${dir.path}/other.sock', 'none $other\n');
      expect(
        LogbookReader('${dir.path}/other.sock').get(a),
        throwsA(isA<ReadBroken>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await server.close();
    });
  });
}
