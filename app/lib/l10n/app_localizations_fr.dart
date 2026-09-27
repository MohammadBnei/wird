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
  String get markSetUnderstood => 'Marquer comme compris';

  @override
  String get nextSet => 'Passage suivant';

  @override
  String get notDownloaded => 'Non téléchargé';

  @override
  String get study_backToTheWalk => 'Retour au parcours';

  @override
  String get study_constellation => 'Constellation';

  @override
  String get study_everyAyaUnderstood => 'Tous les versets de ce passage sont compris';

  @override
  String get study_goTo => 'Aller à…';

  @override
  String get study_goToAnyAya => 'Aller à n\'importe quelle sourate ou verset';

  @override
  String get study_kinOpensItsAya => 'Un mot apparenté ouvre le verset où il paraît pour la première fois.';

  @override
  String get study_noAyaUnderstoodYet => 'Aucun verset encore marqué comme compris';

  @override
  String get study_noRecitation => 'Aucune récitation pour ce passage';

  @override
  String get study_noRootInSet => 'Aucun mot de ce passage ne porte de racine.';

  @override
  String get study_nothingLeftToServe => 'Tous les versets sont compris. Il ne reste rien à servir.';

  @override
  String study_numbersAnd(Object first, Object last) {
    return '$first et $last';
  }

  @override
  String get study_previousSet => 'Passage précédent';

  @override
  String get study_prayThisSet => 'Prier ce passage';

  @override
  String study_progressSplit(Object done, Object open) {
    return 'Verset $done marqué comme compris · verset $open à lire';
  }

  @override
  String study_revelationKicker(Object order, Object place) {
    return 'Révélation $order · $place';
  }

  @override
  String study_surahKicker(Object surah, Object place) {
    return 'Sourate $surah · $place';
  }

  @override
  String get study_visiting => 'En visite';
}
