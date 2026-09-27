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
  String root_openAya(String ref) {
    return 'Open $ref';
  }

  @override
  String get root_thisAya => 'THIS AYA';

  @override
  String root_weightWithForm(String form, int occurrences) {
    return 'Form $form · $occurrences×';
  }

  @override
  String get root_previousForm => 'Previous';

  @override
  String get root_nextForm => 'Next';

  @override
  String root_dialPosition(int index, int count) {
    return '$index of $count · swipe the ring';
  }

  @override
  String get root_kicker => 'Root';

  @override
  String get root_kickerSpine => 'Root spine';

  @override
  String root_unknownRoot(String letters) {
    return 'The corpus carries no root spelled $letters.';
  }

  @override
  String get root_kinHeading => 'Its kin in the Qur\'an';

  @override
  String root_kinFormsAndOccurrences(int forms, int occurrences) {
    return '$forms forms · $occurrences occurrences';
  }

  @override
  String root_formCount(int forms) {
    return '$forms forms';
  }

  @override
  String root_cardWeight(int occurrences) {
    return '$occurrences× IN THE QUR’AN';
  }

  @override
  String root_cardWeightWithForm(String form, int occurrences) {
    return 'FORM $form · $occurrences×';
  }

  @override
  String get root_readTheAya => 'Read the aya';

  @override
  String get root_keepThisRoot => 'Keep this root';

  @override
  String get root_keptTapToUndo => 'Kept · tap to undo';

  @override
  String get root_back => 'Back';

  @override
  String get root_keep => 'Keep';

  @override
  String get root_keptTapToUndoLabel => 'Kept, tap to undo';

  @override
  String get root_coreSense => 'Core sense';

  @override
  String get root_senseRefused => 'Wird writes a root\'s sense only where that root\'s own words in the Qur\'an bear it out. These do not, so nothing is claimed here.';

  @override
  String root_senseByApp(String borne) {
    return 'This app\'s own reading$borne';
  }

  @override
  String root_senseBySource(String source, String borne) {
    return '$source\'s reading$borne';
  }

  @override
  String root_senseBorne(int words) {
    return ', borne out by $words of the root\'s own words';
  }

  @override
  String get root_whoseReading => 'Whose reading this is';

  @override
  String get root_wordsReadFrom => 'The words it was read from';

  @override
  String root_wordCount(int words) {
    return '$words words';
  }

  @override
  String root_formTag(String form) {
    return 'FORM $form';
  }

  @override
  String get root_tafsir => 'Tafsir';

  @override
  String root_tafsirAt(String ref) {
    return 'Tafsir · $ref';
  }

  @override
  String get root_tafsirPending => 'Tafsir is fetched per aya. Nothing is downloaded yet, so nothing is attributed here.';

  @override
  String get root_irab => 'Iʿrāb';

  @override
  String root_irabAsReadAt(String where) {
    return 'as read at $where';
  }

  @override
  String get root_noParsing => 'The corpus carries no parsing for this word.';

  @override
  String root_irabProvenance(String work) {
    return 'Provenance: $work; the role names are written for Wird';
  }

  @override
  String root_spineWeight(String translit, int occurrences, int suras) {
    return '$translit · $occurrences in $suras sūras';
  }

  @override
  String get root_sourcesHeading => 'Sources';

  @override
  String root_provenance(String sources) {
    return 'Provenance: $sources';
  }
}
