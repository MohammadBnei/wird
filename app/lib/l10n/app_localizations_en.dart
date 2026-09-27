// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get inThisAya => 'IN THIS AYA';

  @override
  String get markSetUnderstood => 'Mark set understood';

  @override
  String get nextSet => 'Next set';

  @override
  String get notDownloaded => 'Not downloaded';

  @override
  String get study_backToTheWalk => 'Back to the walk';

  @override
  String get study_constellation => 'Constellation';

  @override
  String get study_everyAyaUnderstood => 'Every aya in this set is understood';

  @override
  String get study_goTo => 'Go to…';

  @override
  String get study_goToAnyAya => 'Go to any sūra or aya';

  @override
  String get study_kinOpensItsAya => 'A kin opens the aya it is first met in.';

  @override
  String get study_noAyaUnderstoodYet => 'No aya marked understood yet';

  @override
  String get study_noRecitation => 'No recitation for this set';

  @override
  String get study_noRootInSet => 'No word in this set carries a root.';

  @override
  String get study_nothingLeftToServe => 'Every aya is understood. There is nothing left to serve.';

  @override
  String study_numbersAnd(Object first, Object last) {
    return '$first and $last';
  }

  @override
  String get study_previousSet => 'Previous set';

  @override
  String get study_prayThisSet => 'Pray this set';

  @override
  String study_progressSplit(Object done, Object open) {
    return 'Aya $done marked understood · aya $open open';
  }

  @override
  String study_revelationKicker(Object order, Object place) {
    return 'Revelation $order · $place';
  }

  @override
  String study_surahKicker(Object surah, Object place) {
    return 'Sūra $surah · $place';
  }

  @override
  String get study_visiting => 'Visiting';
}
