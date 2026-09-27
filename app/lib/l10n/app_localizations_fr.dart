// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String deepdive_aya_kicker(String surah, int number) {
    return '$surah · verset $number';
  }

  @override
  String get deepdive_back => 'Retour';

  @override
  String deepdive_form(String form) {
    return 'forme $form';
  }

  @override
  String get deepdive_keep => 'Garder ce verset';

  @override
  String get deepdive_kept => 'Gardé · toucher pour annuler';

  @override
  String deepdive_kicker(String ref) {
    return 'EXPLORATION · $ref';
  }

  @override
  String deepdive_occurrences(String translit, int count) {
    return '$translit · $count occurrences';
  }

  @override
  String get deepdive_root_heading => 'CONSTELLATION DE LA RACINE';

  @override
  String deepdive_star(String form, String ref) {
    return '$form · ouvrir $ref';
  }

  @override
  String deepdive_this_aya(String ref) {
    return 'CE VERSET · $ref';
  }

  @override
  String deepdive_unknown(String ref, String letters) {
    return 'Le corpus ne contient aucun verset $ref dont un mot vienne de la racine épelée $letters.';
  }

  @override
  String get deepdive_view_constellation => 'Constellation';

  @override
  String get deepdive_view_list => 'Liste';

  @override
  String get inThisAya => 'DANS CE VERSET';

  @override
  String get markSetUnderstood => 'Marquer comme compris';

  @override
  String get nextSet => 'Passage suivant';

  @override
  String get notDownloaded => 'Non téléchargé';
}
