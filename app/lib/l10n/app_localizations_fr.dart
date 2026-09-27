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
  String dashboard_setWaiting(int number) {
    return 'PASSAGE $number · EN ATTENTE';
  }

  @override
  String dashboard_ayaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '1 verset',
    );
    return '$_temp0';
  }

  @override
  String dashboard_prayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'prié $count fois',
      two: 'prié deux fois',
      one: 'prié une fois',
      zero: 'aucune prière dessus pour le moment',
    );
    return '$_temp0';
  }

  @override
  String get dashboard_praySet => 'Prier ce passage';

  @override
  String get dashboard_readFirst => 'Le lire d\'abord';

  @override
  String get dashboard_allUnderstood => 'Chaque verset est compris.';

  @override
  String get dashboard_allUnderstoodWhy => 'Il ne reste rien à servir. L\'index ouvre de nouveau n\'importe quelle sourate.';

  @override
  String get dashboard_whereToGo => 'OÙ ALLER';

  @override
  String get dashboard_doorIndex => 'Index des sourates';

  @override
  String get dashboard_doorIndexWhy => 'Ouvrir le verset que vous voulez';

  @override
  String get dashboard_doorProgress => 'Votre progression';

  @override
  String get dashboard_doorProgressWhy => 'Ce que vous avez compris';

  @override
  String get dashboard_doorKept => 'Gardés';

  @override
  String get dashboard_doorKeptWhy => 'Les versets et les racines que vous avez gardés';
}
