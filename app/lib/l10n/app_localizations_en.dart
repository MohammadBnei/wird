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
  String get report_title => 'Report something';

  @override
  String get report_one_way => 'This goes one way. It reaches whoever keeps Wird running, and nothing comes back — there is no inbox here to check.';

  @override
  String get report_kind_heading => 'WHAT KIND';

  @override
  String get report_kind_bug => 'Bug';

  @override
  String get report_kind_request => 'Request';

  @override
  String get report_kind_improvement => 'Improvement';

  @override
  String get report_words_heading => 'IN YOUR OWN WORDS';

  @override
  String get report_words_hint => 'What happened, or what is missing.';

  @override
  String report_chars_left(int remaining, int max) {
    return '$remaining characters left of $max. The server takes no more than that.';
  }

  @override
  String get report_context_heading => 'SENT WITH IT';

  @override
  String get report_context_only => 'Gathered so you do not have to type it. Nothing else travels: not what you were reading, not what you have kept, not your progress.';

  @override
  String get report_context_loading => 'Reading this build…';

  @override
  String get report_send => 'Send it';

  @override
  String get report_queued_heading => 'QUEUED';

  @override
  String get report_queued_body => 'It is written down on this phone and goes out with the next sync, even if you are offline now.';

  @override
  String get report_write_another => 'Write another';
}
