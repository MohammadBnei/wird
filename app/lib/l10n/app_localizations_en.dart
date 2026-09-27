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
  String dashboard_setWaiting(int number) {
    return 'SET $number · WAITING';
  }

  @override
  String dashboard_ayaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas',
      one: '1 aya',
    );
    return '$_temp0';
  }

  @override
  String dashboard_prayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'prayed $count times',
      two: 'prayed twice',
      one: 'prayed once',
      zero: 'no prayer on it yet',
    );
    return '$_temp0';
  }

  @override
  String get dashboard_praySet => 'Pray this set';

  @override
  String get dashboard_readFirst => 'Read it first';

  @override
  String get dashboard_allUnderstood => 'Every aya is understood.';

  @override
  String get dashboard_allUnderstoodWhy => 'There is nothing left to serve. The index opens any sūra again.';

  @override
  String get dashboard_whereToGo => 'WHERE TO GO';

  @override
  String get dashboard_doorIndex => 'Sūra index';

  @override
  String get dashboard_doorIndexWhy => 'Open any aya you want';

  @override
  String get dashboard_doorProgress => 'Your passage';

  @override
  String get dashboard_doorProgressWhy => 'How much you have understood';

  @override
  String get dashboard_doorKept => 'Kept';

  @override
  String get dashboard_doorKeptWhy => 'The ayas and roots you saved';
}
