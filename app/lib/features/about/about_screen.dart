import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_card.dart';
import '../../widgets/nocturne_rule.dart';
import '../../widgets/nocturne_tag.dart';

/// One thing Wird is built on, and the terms it is used under.
@immutable
class Source {
  const Source({
    required this.provides,
    required this.name,
    required this.licence,
    required this.terms,
    this.notice,
    this.url,
  });

  /// What of the app would be missing without it, read from the ARB rather
  /// than carried: it is the kicker over the card, and the only field here a
  /// French reader can be shown in French. The name is a proper noun, and the
  /// licence and its notice are the licensor's own words, which several of
  /// these grants require reproduced rather than rendered.
  final String Function(AppLocalizations) provides;
  final String name;
  final String licence;
  final String terms;

  /// A copyright line the source asks to be carried along with its data.
  final String? notice;

  /// Where a reader goes to check the terms, or to see what has changed since
  /// this build was cut.
  final String? url;
}

/// The Quranic Arabic Corpus grants its use in an application on three
/// conditions, and two of them are addressed to the person holding the phone
/// rather than to whoever reads the repository: its source must be clearly
/// indicated, a link must reach corpus.quran.com, and its copyright notice
/// must travel with the annotation. This list is where that happens.
final sources = [
  Source(
    provides: (l) => l.aboutProvidesMorphology,
    name: 'Quranic Arabic Corpus',
    licence: 'GNU General Public License',
    notice: 'Version 0.4 · Copyright (C) 2011 Kais Dukes',
    url: 'https://corpus.quran.com',
    terms:
        'Every root a word opens into comes from here. Verbatim copies only — '
        'changing the annotation is not allowed. Used on the condition that '
        'its source is clearly indicated and a link is made to '
        'corpus.quran.com, so you can keep track of what has changed since '
        'this build.',
  ),
  Source(
    provides: (l) => l.aboutProvidesText,
    name: 'Tanzil Project',
    licence: 'Verbatim copies, attributed',
    url: 'https://tanzil.net',
    terms:
        'The verified Uthmani text every aya is painted from, which the '
        'Quranic Arabic Corpus also builds on. Copied verbatim; changing the '
        'text is not allowed. Linked so you can keep track of changes.',
  ),
  Source(
    provides: (l) => l.aboutProvidesGloss,
    name: 'Quran Foundation',
    licence: 'Developer Terms',
    url: 'https://quran.foundation',
    terms:
        'The English under each word, served by the quran.com API. Their '
        'terms allow an application to show this content but not to store it '
        'indefinitely without a weekly re-sync, which a bundled corpus does '
        'not do. Unsettled, and recorded as unsettled.',
  ),
  Source(
    provides: (l) => l.aboutProvidesDesign,
    name: 'Nocturne',
    licence: 'Authored for Wird',
    terms:
        'The design system every screen is drawn from. Dark only; there is no '
        'light mode.',
  ),
  Source(
    provides: (l) => l.aboutProvidesArabicFace,
    name: 'Scheherazade New',
    licence: 'SIL Open Font License 1.1',
    url: 'https://openfontlicense.org',
    terms:
        'Bundled unmodified, because platform Arabic faces mangle Qurʼanic '
        'diacritics.',
  ),
  Source(
    provides: (l) => l.aboutProvidesLatinFace,
    name: 'Inter',
    licence: 'SIL Open Font License 1.1',
    url: 'https://openfontlicense.org',
    terms: 'Bundled unmodified.',
  ),
  Source(
    provides: (l) => l.aboutProvidesTimings,
    name: 'quran-align',
    licence: 'Creative Commons Attribution 4.0 International',
    notice: 'Copyright (c) 2016 Collin Fair',
    url: 'https://creativecommons.org/licenses/by/4.0/',
    terms:
        'The millisecond each word is spoken at, which is what lets a word '
        'light up as you hear it. From github.com/cpfair/quran-align, aligned '
        'against this same muʿallim recording. Reindexed for this app: the '
        'published data is zero-based and end-exclusive, and it is stored here '
        'one-based against the word it belongs to. Offered as-is, without '
        'warranties.',
  ),
  Source(
    provides: (l) => l.aboutProvidesRecitation,
    name: 'Maḥmūd Khalīl al-Ḥuṣarī',
    licence: 'Fetched at playback, never redistributed',
    url: 'https://everyayah.com',
    terms:
        'The muʿallim recording is downloaded by your device from everyayah.com '
        'when you press play, the way a browser loads a page, and cached on '
        'your phone. Wird does not bundle it, mirror it, or serve it. The '
        'archive publishes no terms of use, so nothing here is offered as '
        'permission to redistribute it — and that is why this app never does.',
  ),
  Source(
    provides: (l) => l.aboutProvidesVoice,
    name: 'Quran-Lab zipformer_p-arabic-v3',
    licence: 'Quran-Lab No-Profit License 1.2',
    url: 'https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3',
    terms:
        'The recogniser that hears your recitation, downloaded on your word '
        'and run on this phone; nothing you say is sent anywhere. It writes '
        'Qurʼanic phonemes, including the marks of tajwīd. Wird uses that only '
        'to find where in the set you are, and never to judge how you recited: '
        'automatic tajwīd feedback can be wrong, and no software here or '
        'anywhere replaces a qualified teacher. Its licence forbids charging '
        'for the model or for any feature it powers, which Wird does not and '
        'will not do.',
  ),
];

/// Wird's own terms, kept beside the sources because it is the answer to the
/// copyleft the first entry carries.
const _selfNotice = 'Copyright (C) 2026 Mohammad Bnei';
const _selfTerms =
    'Wird is free software under the GNU Affero General Public License, '
    'version 3 or later. AGPL rather than GPL because Wird has a server: '
    'anyone running it as a service owes its users the source of what they '
    'are running.';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            n.space('6'),
            n.space('2'),
            n.space('6'),
            n.space('8'),
          ),
          children: [
            _header(context, n, l),
            const NocturneRule(),
            NocturneCard(
              // 'Wird' is the app's own name and stays as it is in every
              // locale; the kicker over it does not.
              kicker: l.aboutThisApp,
              title: 'Wird',
              body: _selfTerms,
              meta: const [
                NocturneTag('AGPL-3.0-or-later'),
                Flexible(child: SourceLink('https://www.gnu.org/licenses/')),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(top: n.space('1')),
              child: Text(
                _selfNotice,
                style: TextStyle(fontSize: 11, color: n.textAt(0.45)),
              ),
            ),
            const NocturneRule(),
            for (final source in sources) ...[
              NocturneCard(
                kicker: source.provides(l),
                title: source.name,
                body: source.terms,
                meta: [
                  NocturneTag(source.licence),
                  if (source.url != null)
                    Flexible(child: SourceLink(source.url!)),
                ],
              ),
              if (source.notice != null)
                Padding(
                  padding: EdgeInsets.only(top: n.space('1')),
                  child: Text(
                    source.notice!,
                    style: TextStyle(fontSize: 11, color: n.textAt(0.45)),
                  ),
                ),
              SizedBox(height: n.space('3')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Nocturne n, AppLocalizations l) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.aboutBuiltOn,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              letterSpacing: 0.11 * 10,
              color: n.accent,
            ),
          ),
          SizedBox(height: n.space('1')),
          Text(l.aboutTitle, style: Theme.of(context).textTheme.displaySmall),
        ],
      );
}

/// A source's address, shown in full and copied on a tap.
///
/// ponytail: the tap copies rather than opens — opening a URL needs
/// `url_launcher`, which is a dependency and a platform-manifest change this
/// screen does not own. Swap the body for `launchUrl` once that lands; the
/// address is on screen either way, which is what the terms ask for.
class SourceLink extends StatelessWidget {
  const SourceLink(this.url, {super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final label = url.replaceFirst(RegExp(r'^https?://'), '');
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.aboutCopied(url)),
          ),
        );
      },
      child: Semantics(
        link: true,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            color: n.accent,
            decoration: TextDecoration.underline,
            decorationColor: n.accent,
          ),
        ),
      ),
    );
  }
}
