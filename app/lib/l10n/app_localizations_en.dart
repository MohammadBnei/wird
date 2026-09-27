// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get index_kicker => 'THE WHOLE QUR’AN';

  @override
  String get index_title => 'All 114';

  @override
  String get index_hint => 'A sūra opens at its first aya. The arrow picks one inside it.';

  @override
  String index_revealed_nth(String order) {
    return '$order to be revealed';
  }

  @override
  String index_pick_aya(String sura) {
    return 'Pick an aya of $sura';
  }

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

  @override
  String get prayer_in_prayer => 'IN PRAYER';

  @override
  String get prayer_following_your_voice => 'FOLLOWING YOUR VOICE';

  @override
  String get prayer_exit => 'Exit';

  @override
  String get prayer_back_an_aya => 'Back an aya';

  @override
  String get prayer_on_to_the_next_aya => 'On to the next aya';

  @override
  String get prayer_foot_taps_only => 'Screen stays awake · tap to go on · left edge steps back';

  @override
  String get prayer_foot_following => 'Screen stays awake · tap any time · left edge steps back';
}
