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
  String get kept_empty_ayas =>
      'No ayas kept yet. “Keep this aya”, on the constellation of a word’s root, keeps one here.';

  @override
  String get kept_empty_notes =>
      'No notes yet. Nothing in the app writes one yet; an aya and a root are kept without words.';

  @override
  String get kept_empty_roots =>
      'No roots kept yet. The keep icon on a root keeps one here.';

  @override
  String get kept_filter_ayas => 'Ayas';

  @override
  String get kept_filter_notes => 'Notes';

  @override
  String get kept_filter_roots => 'Roots';

  @override
  String kept_kicker_revisit(String at) {
    return '$at · revisit';
  }

  @override
  String kept_kicker_root(String letters) {
    return 'Root · $letters';
  }

  @override
  String get kept_kind_aya => 'Aya';

  @override
  String get kept_kind_note => 'Note';

  @override
  String get kept_kind_root => 'Root';

  @override
  String kept_meta_days_ago(int days) {
    return '$days days ago';
  }

  @override
  String kept_meta_flagged(String letters) {
    return 'flagged for $letters';
  }

  @override
  String kept_meta_kept_from(String reference) {
    return 'kept from $reference';
  }

  @override
  String get kept_meta_today => 'today';

  @override
  String get kept_meta_yesterday => 'yesterday';

  @override
  String kept_no_match(String search) {
    return 'Nothing kept matches “$search”.';
  }

  @override
  String get kept_search_hint => 'Search ayas, roots, your words';

  @override
  String get kept_title => 'Kept';

  @override
  String get markSetUnderstood => 'Mark set understood';

  @override
  String get nextSet => 'Next set';

  @override
  String get notDownloaded => 'Not downloaded';
}
