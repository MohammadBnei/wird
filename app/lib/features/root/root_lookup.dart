import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';

/// One letter of Buckwalter per radical, the alphabet the Arabic Almanac's
/// `bwq` search reads. The inverse of `one` in server/internal/lane/lane.go.
/// Every hamza seat is `A`: our roots fold hamza onto أ (data/SOURCES.md), and
/// the Almanac folds it onto bare alef, so the two meet there.
const _buckwalter = {
  'ا': 'A', 'أ': 'A', 'إ': 'A', 'آ': 'A', 'ؤ': 'A', 'ئ': 'A', 'ء': 'A', //
  'ب': 'b', 'ت': 't', 'ث': 'v', 'ج': 'j', 'ح': 'H', 'خ': 'x', 'د': 'd',
  'ذ': '*', 'ر': 'r', 'ز': 'z', 'س': 's', 'ش': r'$', 'ص': 'S', 'ض': 'D',
  'ط': 'T', 'ظ': 'Z', 'ع': 'E', 'غ': 'g', 'ف': 'f', 'ق': 'q', 'ك': 'k',
  'ل': 'l', 'م': 'm', 'ن': 'n', 'ه': 'h', 'و': 'w', 'ي': 'y', 'ى': 'y',
};

/// The Almanac's page. A literal of its own so the gate's URL ledger sees it.
const _almanac = 'https://ejtaal.net/aa/';

/// Roots the hamza fold spells as no lexicon does. Lane files هات under هيت.
const _filedElsewhere = {'هأت': 'هيت'};

/// The Arabic Almanac opened at [letters]: Hans Wehr, Lane, Kazimirski and
/// Lisan al-ʿArab, each at the page holding that root. Null when a letter has
/// no Buckwalter, so no link is drawn rather than one that lands anywhere.
///
/// `bwq`, never `q`. The Almanac never percent-decodes its hash, so Arabic
/// arrives as `%D9%82…`, and its `q` search reads `sh`, `th`, `kh`, `dh` and
/// `gh` as one letter each, so سهل would open at شل. `bwq` maps one ASCII
/// letter to one Arabic letter. The string is built by hand because
/// `Uri.encodeComponent` would turn `$` into `%24`.
///
/// A geminate root (ربب) and a reduplicated one (زلزل) are filed under their
/// two distinct letters in Hans Wehr, Lane and Kazimirski, the same folds
/// `lane.Look` makes; searched whole they sort past the article. Lisan keeps
/// three letters, so it is the one book that opens a page early.
///
/// ponytail: Lane writes a final weak radical as ى, which `bwq` cannot spell,
/// so the 101 roots ending in ي open one page past their Lane article (Hans
/// Wehr is right). لألأ opens on the لب page. A per-book page table fixes both
/// if readers notice.
Uri? almanacUri(String letters) {
  var root = [...(_filedElsewhere[letters] ?? letters).runes]
      .map(String.fromCharCode)
      .toList();
  if (root.length == 3 && root[1] == root[2]) {
    root = root.sublist(0, 2);
  } else if (root.length == 4 && root[0] == root[2] && root[1] == root[3]) {
    root = root.sublist(0, 2);
  }
  final key = StringBuffer();
  for (final letter in root) {
    final b = _buckwalter[letter];
    if (b == null) return null;
    key.write(b);
  }
  return Uri.parse('$_almanac#bwq=$key');
}

Future<bool> _inTheBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// The way out to the dictionaries, under a root's sense or the notice that
/// stands in for one. A reader who doubts a sense is owed the books it was
/// checked against, and a root with no sense needs them most.
class RootLookUp extends StatelessWidget {
  const RootLookUp({
    super.key,
    required this.letters,
    this.open,
    this.compact = false,
  });

  final String letters;

  /// A book the size of the sense verdict's thumbs, for the senses' own
  /// heading row, where the sentence does not fit. The sentence stays its
  /// tooltip and what a screen reader says.
  final bool compact;

  /// Opens the address. Null is the phone's own browser; tests hand one in.
  final Future<bool> Function(Uri)? open;

  @override
  Widget build(BuildContext context) {
    final uri = almanacUri(letters);
    if (uri == null) return const SizedBox.shrink();
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    if (compact) {
      return Tooltip(
        message: l.root_lookUp,
        child: Semantics(
          link: true,
          label: l.root_lookUp,
          hint: l.root_lookUpHint,
          excludeSemantics: true,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _go(context, uri),
            child: SizedBox.square(
              dimension: 32,
              child: Icon(
                Icons.menu_book_outlined,
                size: 14,
                color: n.textAt(0.55),
              ),
            ),
          ),
        ),
      );
    }
    // Underlined, no trailing arrow, for the reason CoreSense's own line gives:
    // an icon wraps alone onto the second row in the deep dive's centre pane.
    return Semantics(
      link: true,
      hint: l.root_lookUpHint,
      child: InkWell(
        onTap: () => _go(context, uri),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              l.root_lookUp,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: n.accent,
                decoration: TextDecoration.underline,
                decorationColor: n.accent.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _go(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final noBrowser = AppLocalizations.of(context)!.root_lookUpNoBrowser;
    var opened = false;
    try {
      opened = await (open ?? _inTheBrowser)(uri);
    } on Exception {
      // A PlatformException from a phone with no browser says the same thing
      // as a false, and the reader is told either way.
    }
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(noBrowser)));
  }
}
