// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutBuiltOn => 'BUILT ON';

  @override
  String get aboutTitle => 'Sources and licences';

  @override
  String get aboutThisApp => 'This app';

  @override
  String aboutCopied(String url) {
    return 'Copied $url';
  }

  @override
  String get aboutProvidesMorphology => 'Roots, word forms and morphology';

  @override
  String get aboutProvidesText => 'The Qurʼanic text';

  @override
  String get aboutProvidesGloss => 'Word-by-word gloss and transliteration';

  @override
  String get aboutProvidesDesign => 'Colour, space and type';

  @override
  String get aboutProvidesArabicFace => 'The Arabic face';

  @override
  String get aboutProvidesLatinFace => 'The Latin face';

  @override
  String get aboutProvidesTimings => 'Per-word recitation timings';

  @override
  String get aboutProvidesRecitation => 'Recitation';

  @override
  String get aboutProvidesVoice => 'Following your voice in prayer';

  @override
  String get inThisAya => 'IN THIS AYA';

  @override
  String get markSetUnderstood => 'Mark set understood';

  @override
  String get nextSet => 'Next set';

  @override
  String get notDownloaded => 'Not downloaded';
}
