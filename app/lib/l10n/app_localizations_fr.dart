// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get inThisAya => 'DANS CE VERSET';

  @override
  String get kept_empty_ayas =>
      'Aucun verset gardé pour l’instant. « Garder ce verset », sur la constellation de la racine d’un mot, en garde un ici.';

  @override
  String get kept_empty_notes =>
      'Aucune note pour l’instant. Rien dans l’application n’en écrit encore ; un verset et une racine se gardent sans mots.';

  @override
  String get kept_empty_roots =>
      'Aucune racine gardée pour l’instant. L’icône de garde sur une racine en garde une ici.';

  @override
  String get kept_filter_ayas => 'Versets';

  @override
  String get kept_filter_notes => 'Notes';

  @override
  String get kept_filter_roots => 'Racines';

  @override
  String kept_kicker_revisit(String at) {
    return '$at · à revoir';
  }

  @override
  String kept_kicker_root(String letters) {
    return 'Racine · $letters';
  }

  @override
  String get kept_kind_aya => 'Verset';

  @override
  String get kept_kind_note => 'Note';

  @override
  String get kept_kind_root => 'Racine';

  @override
  String kept_meta_days_ago(int days) {
    return 'il y a $days jours';
  }

  @override
  String kept_meta_flagged(String letters) {
    return 'signalé pour $letters';
  }

  @override
  String kept_meta_kept_from(String reference) {
    return 'gardé depuis $reference';
  }

  @override
  String get kept_meta_today => 'aujourd’hui';

  @override
  String get kept_meta_yesterday => 'hier';

  @override
  String kept_no_match(String search) {
    return 'Rien de gardé ne correspond à « $search ».';
  }

  @override
  String get kept_search_hint =>
      'Rechercher des versets, des racines, vos mots';

  @override
  String get kept_title => 'Gardés';

  @override
  String get markSetUnderstood => 'Marquer comme compris';

  @override
  String get nextSet => 'Passage suivant';

  @override
  String get notDownloaded => 'Non téléchargé';
}
