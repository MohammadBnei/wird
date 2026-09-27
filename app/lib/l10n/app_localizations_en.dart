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
  String get progress_kicker => 'UNDERSTOOD, NOT MERELY READ';

  @override
  String get progress_title => 'Your passage';

  @override
  String progress_ayas(String understood, String total) {
    return '$understood of $total ayas';
  }

  @override
  String progress_ringSemantics(String percent, String ayas, int juz, int set) {
    return '$percent of the Qur\'an understood, $ayas. Juz $juz, set $set.';
  }

  @override
  String progress_here(int juz, int set) {
    return 'JUZ $juz · SET $set';
  }

  @override
  String get progress_setsUnderstood => 'sets understood';

  @override
  String get progress_prayersRecorded => 'prayers recorded';

  @override
  String get progress_whereYouAre => 'WHERE YOU ARE';

  @override
  String get progress_allSuras => 'All 114';

  @override
  String get progress_rootsKnown => 'ROOTS YOU NOW KNOW';

  @override
  String get progress_rootsEmpty => 'The roots of every set you understand are collected here.';

  @override
  String progress_rootsCoverage(String roots, int percent) {
    return '$roots roots cover $percent% of the words ahead of you.';
  }
}
