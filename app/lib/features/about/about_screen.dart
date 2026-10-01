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

  /// What of the app would be missing without it: the kicker over the card.
  final String Function(AppLocalizations) provides;

  /// A proper noun, the same in every locale.
  final String name;

  /// A licence's official title is the licensor's own words, which several of
  /// these grants require reproduced rather than rendered, so those stay as
  /// they are; a source with no titled licence gets a description from the ARB.
  final String Function(AppLocalizations) licence;

  /// What it provides and the conditions it is used on, from the ARB.
  final String Function(AppLocalizations) terms;

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
    licence: (_) => 'GNU General Public License',
    notice: 'Version 0.4 · Copyright (C) 2011 Kais Dukes',
    url: 'https://corpus.quran.com',
    terms: (l) => l.aboutTermsCorpus,
  ),
  Source(
    provides: (l) => l.aboutProvidesText,
    name: 'Tanzil Project',
    licence: (l) => l.aboutLicenceVerbatim,
    url: 'https://tanzil.net',
    terms: (l) => l.aboutTermsTanzil,
  ),
  Source(
    provides: (l) => l.aboutProvidesGloss,
    name: 'Quran Foundation',
    licence: (_) => 'Developer Terms',
    url: 'https://quran.foundation',
    terms: (l) => l.aboutTermsQuranFoundation,
  ),
  Source(
    provides: (l) => l.aboutProvidesFrenchGloss,
    name: 'The Last Dialogue',
    licence: (l) => l.aboutLicencePermission,
    url: 'https://www.thelastdialogue.org/coran-mot-a-mot-francais/',
    terms: (l) => l.aboutTermsLastDialogue,
  ),
  Source(
    provides: (l) => l.aboutProvidesDesign,
    name: 'Nocturne',
    licence: (l) => l.aboutLicenceAuthored,
    terms: (l) => l.aboutTermsNocturne,
  ),
  Source(
    provides: (l) => l.aboutProvidesArabicFace,
    name: 'Scheherazade New',
    licence: (_) => 'SIL Open Font License 1.1',
    url: 'https://openfontlicense.org',
    terms: (l) => l.aboutTermsScheherazade,
  ),
  Source(
    provides: (l) => l.aboutProvidesLatinFace,
    name: 'Inter',
    licence: (_) => 'SIL Open Font License 1.1',
    url: 'https://openfontlicense.org',
    terms: (l) => l.aboutTermsInter,
  ),
  Source(
    provides: (l) => l.aboutProvidesTimings,
    name: 'quran-align',
    licence: (_) => 'Creative Commons Attribution 4.0 International',
    notice: 'Copyright (c) 2016 Collin Fair',
    url: 'https://creativecommons.org/licenses/by/4.0/',
    terms: (l) => l.aboutTermsTimings,
  ),
  Source(
    provides: (l) => l.aboutProvidesRecitation,
    name: 'Maḥmūd Khalīl al-Ḥuṣarī',
    licence: (l) => l.aboutLicenceFetched,
    url: 'https://everyayah.com',
    terms: (l) => l.aboutTermsRecitation,
  ),
  Source(
    provides: (l) => l.aboutProvidesVoice,
    name: 'Quran-Lab zipformer_p-arabic-v3',
    licence: (_) => 'Quran-Lab No-Profit License 1.2',
    url: 'https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3',
    terms: (l) => l.aboutTermsVoice,
  ),
];

/// Wird's own copyright line. Its terms, `aboutSelfTerms`, are kept beside the
/// sources because they are the answer to the copyleft the first entry carries.
const _selfNotice = 'Copyright (C) 2026 Mohammad Bnei';

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
              body: l.aboutSelfTerms,
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
                body: source.terms(l),
                meta: [
                  NocturneTag(source.licence(l)),
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
