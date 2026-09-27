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
}
