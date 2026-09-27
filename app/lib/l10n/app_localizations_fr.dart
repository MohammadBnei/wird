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
  String get report_title => 'Signaler quelque chose';

  @override
  String get report_one_way => 'Cela part dans un seul sens. Le message parvient à ceux qui font tourner Wird, et rien ne revient — il n\'y a pas de boîte de réception à consulter ici.';

  @override
  String get report_kind_heading => 'QUEL TYPE';

  @override
  String get report_kind_bug => 'Bogue';

  @override
  String get report_kind_request => 'Demande';

  @override
  String get report_kind_improvement => 'Amélioration';

  @override
  String get report_words_heading => 'DANS VOS PROPRES MOTS';

  @override
  String get report_words_hint => 'Ce qui s\'est passé, ou ce qui manque.';

  @override
  String report_chars_left(int remaining, int max) {
    return '$remaining caractères restants sur $max. Le serveur ne va pas au-delà.';
  }

  @override
  String get report_context_heading => 'ENVOYÉ AVEC';

  @override
  String get report_context_only => 'Recueilli pour que vous n\'ayez pas à le saisir. Rien d\'autre ne part : ni ce que vous lisiez, ni ce que vous avez gardé, ni votre progression.';

  @override
  String get report_context_loading => 'Lecture de cette version…';

  @override
  String get report_send => 'Envoyer';

  @override
  String get report_queued_heading => 'EN ATTENTE';

  @override
  String get report_queued_body => 'C\'est noté sur ce téléphone et partira à la prochaine synchronisation, même si vous êtes hors ligne.';

  @override
  String get report_write_another => 'En écrire un autre';
}
