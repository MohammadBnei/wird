// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get aboutBuiltOn => 'CONSTRUIT SUR';

  @override
  String get aboutTitle => 'Sources et licences';

  @override
  String get aboutThisApp => 'Cette application';

  @override
  String aboutCopied(String url) {
    return 'Adresse copiée : $url';
  }

  @override
  String get aboutProvidesMorphology =>
      'Racines, formes des mots et morphologie';

  @override
  String get aboutProvidesText => 'Le texte coranique';

  @override
  String get aboutProvidesGloss => 'Glose mot à mot et translittération';

  @override
  String get aboutProvidesDesign => 'Couleur, espace et typographie';

  @override
  String get aboutProvidesArabicFace => 'La police arabe';

  @override
  String get aboutProvidesLatinFace => 'La police latine';

  @override
  String get aboutProvidesTimings => 'Minutage de la récitation, mot par mot';

  @override
  String get aboutProvidesRecitation => 'Récitation';

  @override
  String get aboutProvidesVoice => 'Le suivi de votre voix pendant la prière';

  @override
  String get inThisAya => 'DANS CE VERSET';

  @override
  String get markSetUnderstood => 'Marquer comme compris';

  @override
  String get nextSet => 'Passage suivant';

  @override
  String get notDownloaded => 'Non téléchargé';
}
