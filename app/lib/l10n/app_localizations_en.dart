// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String deepdive_aya_kicker(String surah, int number) {
    return '$surah · aya $number';
  }

  @override
  String get deepdive_back => 'Back';

  @override
  String deepdive_form(String form) {
    return 'form $form';
  }

  @override
  String get deepdive_keep => 'Keep this aya';

  @override
  String get deepdive_kept => 'Kept · tap to undo';

  @override
  String deepdive_kicker(String ref) {
    return 'DEEP DIVE · $ref';
  }

  @override
  String deepdive_occurrences(String translit, int count) {
    return '$translit · $count occurrences';
  }

  @override
  String get deepdive_root_heading => 'ROOT CONSTELLATION';

  @override
  String deepdive_star(String form, String ref) {
    return '$form · open $ref';
  }

  @override
  String deepdive_this_aya(String ref) {
    return 'THIS AYA · $ref';
  }

  @override
  String deepdive_unknown(String ref, String letters) {
    return 'The corpus carries no aya $ref with a root spelled $letters.';
  }

  @override
  String get deepdive_view_constellation => 'Constellation';

  @override
  String get deepdive_view_list => 'List';

  @override
  String get inThisAya => 'IN THIS AYA';

  @override
  String get markSetUnderstood => 'Mark set understood';

  @override
  String get nextSet => 'Next set';

  @override
  String get notDownloaded => 'Not downloaded';
}
