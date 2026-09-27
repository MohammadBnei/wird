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
