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
  String root_openAya(String ref) {
    return 'Ouvrir $ref';
  }

  @override
  String get root_thisAya => 'CE VERSET';

  @override
  String root_weightWithForm(String form, int occurrences) {
    return 'Forme $form · $occurrences×';
  }

  @override
  String get root_previousForm => 'Précédent';

  @override
  String get root_nextForm => 'Suivant';

  @override
  String root_dialPosition(int index, int count) {
    return '$index sur $count · faites glisser l’anneau';
  }

  @override
  String get root_kicker => 'Racine';

  @override
  String get root_kickerSpine => 'Racine dépliée';

  @override
  String root_unknownRoot(String letters) {
    return 'Le corpus ne porte aucune racine écrite $letters.';
  }

  @override
  String get root_kinHeading => 'Sa parenté dans le Coran';

  @override
  String root_kinFormsAndOccurrences(int forms, int occurrences) {
    return '$forms formes · $occurrences occurrences';
  }

  @override
  String root_formCount(int forms) {
    return '$forms formes';
  }

  @override
  String root_cardWeight(int occurrences) {
    return '$occurrences× DANS LE CORAN';
  }

  @override
  String root_cardWeightWithForm(String form, int occurrences) {
    return 'FORME $form · $occurrences×';
  }

  @override
  String get root_readTheAya => 'Lire le verset';

  @override
  String get root_keepThisRoot => 'Garder cette racine';

  @override
  String get root_keptTapToUndo => 'Gardée · touchez pour annuler';

  @override
  String get root_back => 'Retour';

  @override
  String get root_keep => 'Garder';

  @override
  String get root_keptTapToUndoLabel => 'Gardée, touchez pour annuler';

  @override
  String get root_coreSense => 'Sens fondamental';

  @override
  String get root_senseRefused => 'Wird n’écrit le sens d’une racine que là où les mots de cette racine dans le Coran l’attestent. Ceux-ci ne l’attestent pas, donc rien n’est affirmé ici.';

  @override
  String root_senseByApp(String borne) {
    return 'La lecture propre à cette application$borne';
  }

  @override
  String root_senseBySource(String source, String borne) {
    return 'La lecture de $source$borne';
  }

  @override
  String root_senseBorne(int words) {
    return ', attestée par $words des mots propres à la racine';
  }

  @override
  String get root_whoseReading => 'De qui est cette lecture';

  @override
  String get root_wordsReadFrom => 'Les mots dont elle a été lue';

  @override
  String root_wordCount(int words) {
    return '$words mots';
  }

  @override
  String root_formTag(String form) {
    return 'FORME $form';
  }

  @override
  String get root_tafsir => 'Tafsir';

  @override
  String root_tafsirAt(String ref) {
    return 'Tafsir · $ref';
  }

  @override
  String get root_tafsirPending => 'Le tafsir est récupéré verset par verset. Rien n’a encore été téléchargé, donc rien n’est attribué ici.';

  @override
  String get root_irab => 'Iʿrāb';

  @override
  String root_irabAsReadAt(String where) {
    return 'tel qu’il se lit en $where';
  }

  @override
  String get root_noParsing => 'Le corpus ne porte aucune analyse pour ce mot.';

  @override
  String root_irabProvenance(String work) {
    return 'Provenance : $work ; les noms des fonctions sont rédigés pour Wird';
  }

  @override
  String root_spineWeight(String translit, int occurrences, int suras) {
    return '$translit · $occurrences dans $suras sourates';
  }

  @override
  String get root_sourcesHeading => 'Sources';

  @override
  String root_provenance(String sources) {
    return 'Provenance : $sources';
  }
}
