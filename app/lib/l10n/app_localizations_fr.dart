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
  String get progress_kicker => 'COMPRIS, ET PAS SEULEMENT LU';

  @override
  String get progress_title => 'Votre parcours';

  @override
  String progress_ayas(String understood, String total) {
    return '$understood versets sur $total';
  }

  @override
  String progress_ringSemantics(String percent, String ayas, int juz, int set) {
    return '$percent du Coran compris, $ayas. Juz $juz, passage $set.';
  }

  @override
  String progress_here(int juz, int set) {
    return 'JUZ $juz · PASSAGE $set';
  }

  @override
  String get progress_setsUnderstood => 'passages compris';

  @override
  String get progress_prayersRecorded => 'prières enregistrées';

  @override
  String get progress_whereYouAre => 'OÙ VOUS EN ÊTES';

  @override
  String get progress_allSuras => 'Les 114';

  @override
  String get progress_rootsKnown => 'LES RACINES QUE VOUS CONNAISSEZ';

  @override
  String get progress_rootsEmpty => 'Les racines de chaque passage que vous comprenez sont rassemblées ici.';

  @override
  String progress_rootsCoverage(String roots, int percent) {
    return '$roots racines couvrent $percent % des mots qui vous restent à lire.';
  }
}
