import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/root/root_lookup.dart';

import '../../corpus.dart';

String key(String letters) => almanacUri(letters)!.fragment;

void main() {
  // ربب searched whole sorts after ربا and lands on ربح, six pages past the
  // start of رب in Lane. 153 roots, 4,624 occurrences, are geminate.
  test('a doubled root opens on the biliteral, not past the article', () {
    expect(key('ربب'), 'bwq=rb');
    expect(key('كلل'), 'bwq=kl');
    expect(key('زلزل'), 'bwq=zl');
  });

  // The Almanac's `q` search reads sh, th, dh as one letter; `bwq` must carry
  // them one letter each, and $ and * must not be percent-escaped.
  test('sh, th and dh letters are not folded into one letter', () {
    expect(key('سهل'), 'bwq=shl');
    expect(key('شكر'), r'bwq=$kr');
    expect(key('ذكر'), 'bwq=*kr');
    expect(almanacUri('شكر').toString(), r'https://ejtaal.net/aa/#bwq=$kr');
  });

  test('a hamza root reaches the almanac as ascii, not percent escapes', () {
    expect(key('قرأ'), 'bwq=qrA');
    expect(almanacUri('سأل').toString(), 'https://ejtaal.net/aa/#bwq=sAl');
  });

  test("هأت opens on Lane's هيت", () {
    expect(key('هأت'), 'bwq=hyt');
  });

  test('no corpus root yields a link the almanac cannot read', () async {
    final db = await testCorpus();
    final roots = await db.rawQuery('SELECT letters FROM roots');
    expect(roots, hasLength(greaterThan(1600)));
    final readable = RegExp(r'^https://ejtaal\.net/aa/#bwq=[A-Za-z$*]+$');
    final unreadable = [
      for (final row in roots)
        if (!readable.hasMatch(
          almanacUri(row['letters']! as String)?.toString() ?? '',
        ))
          row['letters'],
    ];
    expect(unreadable, isEmpty);
  });
}
