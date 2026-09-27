// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get index_kicker => 'TOUT LE CORAN';

  @override
  String get index_title => 'Les 114';

  @override
  String get index_hint => 'Une sourate s’ouvre à son premier verset. La flèche en choisit un à l’intérieur.';

  @override
  String index_revealed_nth(String order) {
    return '$order sourate révélée';
  }

  @override
  String index_pick_aya(String sura) {
    return 'Choisir un verset de $sura';
  }

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

  @override
  String get prayer_in_prayer => 'EN PRIÈRE';

  @override
  String get prayer_following_your_voice => 'SUIT VOTRE VOIX';

  @override
  String get prayer_exit => 'Quitter';

  @override
  String get prayer_back_an_aya => 'Revenir au verset précédent';

  @override
  String get prayer_on_to_the_next_aya => 'Aller au verset suivant';

  @override
  String get prayer_foot_taps_only => 'Écran maintenu allumé · touchez pour avancer · le bord gauche revient en arrière';

  @override
  String get prayer_foot_following => 'Écran maintenu allumé · touchez à tout moment · le bord gauche revient en arrière';
}
