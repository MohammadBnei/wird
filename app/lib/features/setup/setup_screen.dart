import 'package:flutter/material.dart';

import '../../app.dart';
import '../../data/db.dart';
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';
import '../../widgets/nocturne_segmented.dart';
import '../settings/reciter_list.dart';

/// The first thing a new install shows, once: the language, the order the
/// Qur'an is walked in and whose voice recites it (ADR 0034).
///
/// Every choice arrives made, so Start alone is a complete answer, and each one
/// is in Settings afterwards. It is pushed over home rather than in place of
/// it, so closing it — Start or the system's back — lands where every later
/// launch begins.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  List<Reciter> _reciters = const [];
  Recitation? _recitation;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recitation = Wird.of(context).recitation;
    if (_reciters.isEmpty) _load();
  }

  Future<void> _load() async {
    final all = await reciters(Wird.of(context).db);
    if (mounted) setState(() => _reciters = all);
  }

  /// A sample left playing would carry on over home.
  @override
  void dispose() {
    _recitation?.stopSample();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_done) return;
    _done = true;
    await markSetupDone(Wird.of(context).db);
  }

  Future<void> _start() async {
    await _finish();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final prefs = Wird.of(context).prefs;
    final french = Localizations.localeOf(context).languageCode == 'fr';
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: n.bg,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: prefs,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      n.space('6'),
                      n.space('8'),
                      n.space('6'),
                      n.space('4'),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wird',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        SizedBox(height: n.space('2')),
                        Text(
                          l.setup_intro,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: n.textAt(0.75),
                          ),
                        ),
                        _section(n, l.settingsLanguage),
                        NocturneSegmented(
                          key: const Key('setup language'),
                          options: [
                            l.settingsLanguageEnglish,
                            l.settingsLanguageFrench,
                          ],
                          selected: french ? 1 : 0,
                          // Only a change is written: the phone's language,
                          // left as it is, keeps following the phone.
                          onChanged: (i) {
                            if ((i == 1) == french) return;
                            prefs.setLocale(Locale(i == 1 ? 'fr' : 'en'));
                          },
                        ),
                        _section(n, l.setup_order),
                        NocturneSegmented(
                          key: const Key('setup order'),
                          options: [
                            l.settingsOrderChronological,
                            l.settingsOrderMushaf,
                          ],
                          selected: prefs.order.index,
                          onChanged: (i) =>
                              prefs.setOrder(ReadingOrder.values[i]),
                        ),
                        SizedBox(height: n.space('1')),
                        Text(
                          prefs.order == ReadingOrder.nuzul
                              ? l.setup_orderChronological
                              : l.setup_orderMushaf,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.4,
                            color: n.textAt(0.5),
                          ),
                        ),
                        if (_reciters.isNotEmpty) ...[
                          _section(n, l.setup_reciter),
                          ReciterList(
                            reciters: _reciters,
                            selected: prefs.reciter,
                            onChanged: prefs.setReciter,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    n.space('6'),
                    n.space('2'),
                    n.space('6'),
                    n.space('6'),
                  ),
                  child: NocturneButton(
                    key: const Key('start'),
                    onPressed: _start,
                    child: Text(l.setup_start),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(Nocturne n, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(height: n.space('6')),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 0.11 * 10,
          color: n.accent,
        ),
      ),
      const NocturneRule(fade: 30),
      SizedBox(height: n.space('2')),
    ],
  );
}
