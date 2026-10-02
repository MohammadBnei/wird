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
  String get index_go_to_hint => 'S’ouvre à ce verset';

  @override
  String get kept_empty_ayas => 'Aucun verset gardé pour l’instant. « Garder ce verset », sur la constellation de la racine d’un mot, en garde un ici.';

  @override
  String get kept_empty_notes => 'Aucune note pour l’instant. Rien dans l’application n’en écrit encore ; un verset et une racine se gardent sans mots.';

  @override
  String get kept_empty_roots => 'Aucune racine gardée pour l’instant. L’icône de garde sur une racine en garde une ici.';

  @override
  String get kept_filter_ayas => 'Versets';

  @override
  String get kept_filter_notes => 'Notes';

  @override
  String get kept_filter_roots => 'Racines';

  @override
  String kept_kicker_revisit(String at) {
    return '$at · à revoir';
  }

  @override
  String kept_kicker_root(String letters) {
    return 'Racine · $letters';
  }

  @override
  String get kept_kind_aya => 'Verset';

  @override
  String get kept_kind_note => 'Note';

  @override
  String get kept_kind_root => 'Racine';

  @override
  String kept_meta_days_ago(int days) {
    return 'il y a $days jours';
  }

  @override
  String kept_meta_flagged(String letters) {
    return 'signalé pour $letters';
  }

  @override
  String kept_meta_kept_from(String reference) {
    return 'gardé depuis $reference';
  }

  @override
  String get kept_meta_today => 'aujourd’hui';

  @override
  String get kept_meta_yesterday => 'hier';

  @override
  String kept_no_match(String search) {
    return 'Rien de gardé ne correspond à « $search ».';
  }

  @override
  String get kept_search_hint => 'Rechercher des versets, des racines, vos mots';

  @override
  String get kept_title => 'Gardés';

  @override
  String get notDownloaded => 'Non téléchargé';

  @override
  String prayer_header(String prayer, int rakah, int count) {
    return '$prayer · Rakʿa $rakah sur $count';
  }

  @override
  String prayer_part(String sura, String ref) {
    return '$sura · $ref';
  }

  @override
  String get prayer_generic => 'Prière';

  @override
  String get prayer_fajr => 'Fajr';

  @override
  String get prayer_zuhr => 'Ẓuhr';

  @override
  String get prayer_asr => 'ʿAṣr';

  @override
  String get prayer_maghrib => 'Maghrib';

  @override
  String get prayer_isha => 'ʿIshāʾ';

  @override
  String get prayer_mode_both => 'La voix, le rythme en relais';

  @override
  String get prayer_mode_voice => 'Suit votre voix';

  @override
  String prayer_mode_pace(int wpm) {
    return 'Régulier · $wpm mots/min';
  }

  @override
  String get prayer_mode_tap => 'Touchez pour avancer';

  @override
  String prayer_rakah_count(int rakah, int count) {
    return '$rakah sur $count';
  }

  @override
  String prayer_between(int rakah, int count) {
    return 'Rakʿa $rakah sur $count';
  }

  @override
  String get prayer_between_voice => 'Commence quand vous récitez · ou touchez';

  @override
  String get prayer_between_tap => 'Touchez pour commencer';

  @override
  String get prayer_complete => 'Prière terminée';

  @override
  String prayer_size_remembered(int size) {
    return '$size px · retenu';
  }

  @override
  String get prayer_on_a_word => 'Aller au mot suivant';

  @override
  String get prepare_title => 'Préparer la prière';

  @override
  String get prepare_kicker_prayer => 'Prière';

  @override
  String get prepare_rakahs => 'Rakʿas';

  @override
  String prepare_rakahs_set_by(String prayer) {
    return 'Fixé par $prayer';
  }

  @override
  String prepare_rakahs_usually(String prayer, int count) {
    return '$prayer compte d’ordinaire $count';
  }

  @override
  String get prepare_rakahs_any => 'Toute prière, sunna ou nafl';

  @override
  String get prepare_fewer_rakahs => 'Moins de rakʿas';

  @override
  String get prepare_more_rakahs => 'Plus de rakʿas';

  @override
  String get prepare_kicker_recite => 'Ce que vous récitez';

  @override
  String get prepare_fatiha => 'Al-Fātiḥa';

  @override
  String get prepare_add_passage => 'Ajouter un passage';

  @override
  String get prepare_fatiha_only_hint => 'Ou réciter Al-Fātiḥa seule';

  @override
  String prepare_ayas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '$count verset',
    );
    return '$_temp0';
  }

  @override
  String prepare_about_seconds(int seconds) {
    return 'environ $seconds s';
  }

  @override
  String prepare_about_minutes(int minutes) {
    return 'environ $minutes min';
  }

  @override
  String get prepare_same_as_first => 'comme la rakʿa 1';

  @override
  String get prepare_kicker_moves => 'Comment le texte avance';

  @override
  String get prepare_follow_voice => 'Suivre ma voix';

  @override
  String get prepare_voice_ready => 'Reconnaissance prête sur ce téléphone';

  @override
  String get prepare_voice_setup => 'Autorisez le micro et téléchargez la reconnaissance, ci-dessous';

  @override
  String get prepare_steady_pace => 'Garder un rythme régulier';

  @override
  String prepare_wpm(int wpm) {
    return '$wpm mots par minute';
  }

  @override
  String get prepare_slower => 'Plus lent';

  @override
  String get prepare_faster => 'Plus rapide';

  @override
  String prepare_note_both(int wpm) {
    return 'Votre voix mène. Si la reconnaissance vous perd, le texte avance à $wpm mots par minute jusqu’à vous retrouver.';
  }

  @override
  String get prepare_note_voice => 'Le texte attend votre voix. Chaque rakʿa commence quand vous récitez.';

  @override
  String prepare_note_pace(int wpm) {
    return 'Le texte avance à $wpm mots par minute. Chaque rakʿa commence d’un toucher.';
  }

  @override
  String get prepare_note_neither => 'Ni l’un ni l’autre : touchez l’écran pour passer au mot suivant.';

  @override
  String get prepare_kicker_screen => 'À l’écran';

  @override
  String get prepare_gloss => 'Sens du mot en cours';

  @override
  String get prepare_around => 'Versets précédent et suivant, estompés';

  @override
  String get prepare_size => 'Taille de l’arabe';

  @override
  String get prepare_size_hint => 'Pincez l’écran de prière pour la changer';

  @override
  String prepare_size_px(int size) {
    return '$size px';
  }

  @override
  String get prepare_silence => 'Couper les notifications';

  @override
  String get prepare_silence_hint => 'Activez Ne pas déranger ou un mode Concentration avant de commencer';

  @override
  String get prepare_preview => 'Aperçu';

  @override
  String prepare_begin(String prayer) {
    return 'Commencer $prayer';
  }

  @override
  String get chooser_title => 'Choisir un passage';

  @override
  String chooser_rakah(int rakah) {
    return 'Rakʿa $rakah · après Al-Fātiḥa';
  }

  @override
  String get chooser_search => 'Chercher une sourate, ou taper 2:255';

  @override
  String chooser_go_to(String ref) {
    return 'Aller à $ref';
  }

  @override
  String get chooser_go_to_hint => 'Commence à ce verset ; vous pourrez l’élargir ensuite';

  @override
  String get chooser_suggested => 'Suggestions';

  @override
  String get chooser_same => 'Comme la rakʿa 1';

  @override
  String get chooser_continue => 'Reprendre là où vous en étiez';

  @override
  String get chooser_recent => 'Récité récemment';

  @override
  String get chooser_fatiha_only => 'Al-Fātiḥa seule';

  @override
  String get chooser_fatiha_only_hint => 'Pas de passage dans cette rakʿa';

  @override
  String get chooser_all => 'Toutes les sourates';

  @override
  String chooser_no_match(String query) {
    return 'Aucune sourate ne correspond à « $query ».';
  }

  @override
  String range_sura(int number, String name) {
    return '$number · $name';
  }

  @override
  String get range_change_sura => 'Changer';

  @override
  String get range_tap_hint => 'Touchez le premier aya, puis le dernier.';

  @override
  String get range_whole => 'Sourate entière';

  @override
  String range_in_sura(int count) {
    return '$count versets dans la sourate';
  }

  @override
  String range_recite(String title) {
    return 'Réciter $title';
  }

  @override
  String preview_rakah(int rakah) {
    return 'R$rakah';
  }

  @override
  String get prayer_exit => 'Quitter';

  @override
  String get prayer_back_an_aya => 'Revenir au verset précédent';

  @override
  String get prayer_on_to_the_next_aya => 'Aller au verset suivant';

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
  String get aboutProvidesMorphology => 'Racines, formes des mots et morphologie';

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
  String deepdive_aya_kicker(String surah, int number) {
    return '$surah · verset $number';
  }

  @override
  String get deepdive_back => 'Retour';

  @override
  String deepdive_form(String form) {
    return 'forme $form';
  }

  @override
  String get deepdive_keep => 'Garder ce verset';

  @override
  String get deepdive_kept => 'Gardé · touchez pour annuler';

  @override
  String deepdive_kicker(String ref) {
    return 'EXPLORATION · $ref';
  }

  @override
  String deepdive_occurrences(String translit, int count) {
    return '$translit · $count occurrences';
  }

  @override
  String get deepdive_root_heading => 'CONSTELLATION DE LA RACINE';

  @override
  String deepdive_star(String form, String ref) {
    return '$form · ouvrir $ref';
  }

  @override
  String deepdive_this_aya(String ref) {
    return 'CE VERSET · $ref';
  }

  @override
  String deepdive_unknown(String ref, String letters) {
    return 'Le corpus ne contient aucun verset $ref dont un mot vienne de la racine épelée $letters.';
  }

  @override
  String get deepdive_view_constellation => 'Constellation';

  @override
  String get deepdive_view_list => 'Liste';

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
      one: '$count verset',
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
  String get dashboard_doorProgress => 'Votre parcours';

  @override
  String get dashboard_doorProgressWhy => 'Ce que vous avez compris';

  @override
  String get dashboard_doorKept => 'Gardés';

  @override
  String get dashboard_doorPray => 'Préparer une prière';

  @override
  String get dashboard_doorPrayWhy => 'N’importe quel passage, autant de rakʿas que voulu';

  @override
  String get dashboard_doorKeptWhy => 'Les versets et les racines que vous avez gardés';

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

  @override
  String get study_constellation => 'Constellation';

  @override
  String get study_nextWord => 'Mot suivant';

  @override
  String get study_noRecitation => 'Aucune récitation pour ce passage';

  @override
  String get study_previousWord => 'Mot précédent';

  @override
  String get study_wordHasNoRoot => 'Pas de racine';

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
  String get root_senseRefused => 'Les sens sont ceux de Wird et ils sont écrits une racine à la fois. Aucun n’a encore été écrit pour cette racine. Quand ce sera fait, il atteindra ce téléphone sans attendre une nouvelle version de l’application.';

  @override
  String get root_senseNotFetched => 'Les sens ne font pas partie du téléchargement. Ils sont récupérés, afin qu’un sens puisse être corrigé sans nouvelle version de l’application — et ce téléphone n’en a encore récupéré aucun. Les réglages portent le bouton.';

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

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsLanguage => 'LANGUE';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageFrench => 'Français';

  @override
  String get settingsLanguageCaption => 'L\'écran et le sens d\'une racine. Les sens ont été écrits en anglais puis traduits : une racine dont le français n\'est pas arrivé se lit en anglais.';

  @override
  String get settingsReading => 'LECTURE';

  @override
  String get settingsWordGloss => 'Glose';

  @override
  String get settingsWordTranslit => 'Translit.';

  @override
  String get settingsWordBoth => 'Les deux';

  @override
  String get settingsWordNeither => 'Aucun';

  @override
  String get settingsAyaTranslationShown => 'Verset traduit';

  @override
  String get settingsAyaTranslationHidden => 'Arabe seul';

  @override
  String get settingsAyaTranslationCaption => 'La traduction de Rashid Maash, ou l’anglais de Pickthall, sous chaque verset.';

  @override
  String get settingsWordCaption => 'Ce qui est imprimé sous chaque mot arabe.';

  @override
  String get settingsOrderChronological => 'Chronologique';

  @override
  String get settingsOrderMushaf => 'Muṣḥaf';

  @override
  String get settingsOrderCaption => 'La chronologie ordonne les sourates ; à l’intérieur d’une sourate, les versets restent dans l’ordre écrit.';

  @override
  String get settingsArabic => 'Arabe';

  @override
  String get settingsArabicCaption => 'La taille de l’arabe sur l’écran de lecture.';

  @override
  String get settingsSetWidth => 'CE QUE VOUS PRENEZ À LA FOIS';

  @override
  String get settingsNoSetWaiting => 'Tous les versets sont compris : aucun passage n’attend.';

  @override
  String settingsSetAyas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '$count verset',
    );
    return '$_temp0';
  }

  @override
  String get settingsSetWidthCaption => 'Un passage plus large peut englober un verset que vous avez déjà compris. Il est récité avec les autres et reste compté là où il est.';

  @override
  String get settingsRecitation => 'RÉCITATION';

  @override
  String get settingsNoReciter => 'Aucun récitant n’est nommé dans ce corpus.';

  @override
  String get settingsReciterCaption => 'La voix qui récite le passage et chaque mot touché. Les mots s’allument au rythme de ce récitant.';

  @override
  String get settingsStyleMuallim => 'Muʿallim · lent et clair, pour apprendre';

  @override
  String get settingsStyleMurattal => 'Murattal';

  @override
  String get settingsStopSample => 'Arrêter';

  @override
  String settingsHearReciter(String reciter) {
    return 'Écouter $reciter';
  }

  @override
  String get settingsWordFromReciter => 'Du récitant';

  @override
  String get settingsWordAlone => 'Chaque mot seul';

  @override
  String get settingsWordVoiceCaption => 'Ce que joue un mot touché : son passage dans le verset du récitant, ou le mot prononcé seul, d’une même voix pour chaque mot.';

  @override
  String get settingsMicrophone => 'MICROPHONE';

  @override
  String get settingsAllowMicrophone => 'Autoriser le microphone';

  @override
  String get settingsMicNotAsked => 'Le suivi vocal a besoin du microphone. Désactivé par défaut ; jamais demandé pendant une prière.';

  @override
  String get settingsMicGranted => 'Microphone autorisé.';

  @override
  String get settingsMicDenied => 'Microphone refusé. L’écran de prière avance d’une touche, comme il l’a toujours fait.';

  @override
  String get settingsMicUnavailable => 'Le microphone n’a pas pu être atteint la dernière fois qu’il a été demandé. Réessayez ; dans tous les cas, l’écran de prière avance d’une touche.';

  @override
  String get settingsAccount => 'COMPTE';

  @override
  String settingsStopDownload(int percent) {
    return 'Arrêter · $percent %';
  }

  @override
  String get settingsCheckRecogniser => 'Tester le reconnaisseur';

  @override
  String get settingsRemoveRecogniser => 'Supprimer le reconnaisseur';

  @override
  String settingsDownloadRecogniser(int megabytes) {
    return 'Télécharger le reconnaisseur · $megabytes Mo';
  }

  @override
  String get settingsRecogniserDownloading => 'Téléchargement en cours. L’arrêter conserve ce qui est déjà arrivé, et appuyer de nouveau sur Télécharger reprend à partir de là.';

  @override
  String get settingsRecogniserReady => 'L’écran de prière suit votre voix. Votre récitation est reconnue sur ce téléphone et ne le quitte jamais.';

  @override
  String get settingsRecogniserNotServed => 'Wird ne sert pas le reconnaisseur depuis cette adresse. Rien sur ce téléphone n’y changera quoi que ce soit, et le bouton ne le fera pas venir non plus — le suivi vocal attend qu’il soit publié à nouveau.';

  @override
  String get settingsRecogniserInterrupted => 'Le téléchargement s’est arrêté avant la fin. Ce qui est arrivé est toujours sur le téléphone, et appuyer de nouveau sur Télécharger reprend à partir de là.';

  @override
  String get settingsRecogniserPartial => 'Un téléchargement interrompu est toujours sur le téléphone. Le relancer reprend là où il s’est arrêté.';

  @override
  String get settingsRecogniserAbsent => 'Un reconnaisseur du Coran qui fonctionne sur le téléphone : rien de ce que vous récitez n’est envoyé ailleurs. Le télécharger est ce qui active le suivi vocal ; jusque-là, et après l’avoir supprimé, l’écran de prière avance d’une touche.';

  @override
  String get settingsSenses => 'SENS';

  @override
  String get settingsDownloadSenses => 'Télécharger les sens';

  @override
  String get settingsSensesAskAgain => 'Redemander';

  @override
  String get settingsSensesAsking => 'Nous demandons au serveur s’il y a du nouveau.';

  @override
  String get settingsSensesOnOffer => 'Le serveur propose des sens que ce téléphone n’a pas. Ils pèsent quelques centaines de kilooctets ; rien ne se télécharge avant que vous n’appuyiez.';

  @override
  String get settingsSensesInstalling => 'Téléchargement en cours. Rien de ce qui est déjà sur le téléphone n’est remplacé avant que tout soit arrivé.';

  @override
  String get settingsSensesCurrent => 'Ce téléphone a les sens que le serveur sert. Un sens est la lecture propre à Wird, écrite par une machine et lue par personne ; la ligne sous chacun le dit, et le pouce à côté est ce qui permet de corriger un sens erroné.';

  @override
  String get settingsSensesUnreachable => 'Le serveur n’a pas répondu : on ne sait donc pas s’il y a de nouveaux sens. Tous les sens déjà sur le téléphone y sont toujours, et l’application se lit sans réseau.';

  @override
  String get settingsSensesNotThisCorpus => 'Les sens arrivés ne nomment aucune racine que cet exemplaire du Coran enregistre : aucun d’eux ne pourrait jamais être lu. Rien n’a été modifié sur le téléphone.';

  @override
  String get settingsVoiceCheckTitle => 'Ce téléphone vous entend-il ?';

  @override
  String settingsVoiceCheckSet(String words) {
    return 'le passage : $words…';
  }

  @override
  String get settingsVoiceCheckOpening => 'Démarrage du reconnaisseur…';

  @override
  String get settingsVoiceCheckListening => 'Récitez : les mots que vous dites devraient apparaître ci-dessous.';

  @override
  String get settingsVoiceCheckNoModel => 'Le reconnaisseur n’a pas démarré. Le téléchargement est peut-être incomplet, ou ce téléphone n’arrive pas à le charger. Le suivi vocal reste désactivé et l’écran de prière répond à votre touche, comme il l’a toujours fait.';

  @override
  String get settingsVoiceCheckNoMicrophone => 'Le microphone a été refusé : il n’y a rien à entendre.';

  @override
  String settingsVoiceCheckCursor(int word, int total, int moves) {
    return 'la prière serait au mot $word sur $total, après $moves déplacements';
  }

  @override
  String settingsVoiceCheckAudio(String seconds, int millis) {
    return '$seconds s de voix, réponse la plus lente $millis ms';
  }

  @override
  String get settingsVoiceCheckTooLittle => 'trop peu entendu pour situer';

  @override
  String settingsVoiceCheckBelow(int word, int score, int needed) {
    return 'le meilleur mot, $word, correspond à $score % alors qu’il en faut $needed %';
  }

  @override
  String settingsVoiceCheckAmbiguous(int word, int score, int rival) {
    return 'mot $word à $score %, mais un autre endroit correspond à $rival %';
  }

  @override
  String settingsVoiceCheckRepeat(int word, int score) {
    return 'mot $word à $score %, mais le passage le dit plusieurs fois et aucune occurrence n’est juste devant';
  }

  @override
  String settingsVoiceCheckPlaced(int word, int score) {
    return 'mot $word à $score %';
  }

  @override
  String settingsSignedInAs(String subject) {
    return 'Connecté en tant que $subject';
  }

  @override
  String get settingsSignOut => 'Se déconnecter';

  @override
  String get settingsSignOutCaption => 'Se déconnecter arrête la synchronisation. Tout ce que vous avez lu, gardé et marqué reste sur ce téléphone.';

  @override
  String get settingsSignedOutCaption => 'Wird fonctionne sans compte. Se connecter porte ce que vous marquez et gardez vers vos autres appareils.';

  @override
  String get settingsSignIn => 'Se connecter';

  @override
  String get settingsFinishInBrowser => 'Terminez la connexion dans votre navigateur. Ce téléphone attend qu’il vous renvoie ici.';

  @override
  String get settingsCancelSignIn => 'Annuler';

  @override
  String get settingsNoBrowser => 'aucun navigateur ici n’ouvrirait l’adresse de connexion';

  @override
  String get settingsSignInUnreachable => 'Le serveur de connexion n’a pas pu être atteint. Rien n’a changé.';

  @override
  String settingsParkedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifications n’ont pas atteint le serveur',
      one: '$count modification n’a pas atteint le serveur',
    );
    return '$_temp0';
  }

  @override
  String get settingsParkedCaption => 'Elles sont toujours sur ce téléphone. Envoyez-les à nouveau, ou laissez-les partir.';

  @override
  String get settingsSendAgain => 'Envoyer à nouveau';

  @override
  String get settingsDiscard => 'Abandonner';

  @override
  String settingsParkedUnderstood(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets que vous avez marqués compris',
      one: 'Un verset que vous avez marqué compris',
    );
    return '$_temp0';
  }

  @override
  String get settingsParkedKept => 'Quelque chose que vous avez gardé';

  @override
  String get settingsParkedUnkept => 'Quelque chose que vous avez retiré de Gardés';

  @override
  String get settingsParkedSetRead => 'Un passage que vous avez lu';

  @override
  String get settingsParkedPrayer => 'Une prière que vous avez comptée';

  @override
  String get settingsParkedOrder => 'Votre ordre de lecture';

  @override
  String get settingsParkedPosition => 'Où vous en êtes dans une sourate';

  @override
  String get settingsParkedReport => 'Quelque chose que vous avez signalé';

  @override
  String get settingsParkedOther => 'Une modification que vous avez faite';

  @override
  String get study_ayaTranslated => 'Rashid Maash';

  @override
  String get study_glossesSource => 'Le sens sous chaque mot vient de The Last Dialogue ; les quelques mots qu’il ne couvre pas restent en anglais.';

  @override
  String get root_senseJudgeThanks => 'C’est noté — merci.';

  @override
  String get root_senseJudgeGoodLabel => 'Ce sens est juste';

  @override
  String get root_senseJudgeBadLabel => 'Ce sens est faux';

  @override
  String get nav_home => 'Accueil';

  @override
  String get nav_theSet => 'Le passage';

  @override
  String get nav_sources => 'Sources';

  @override
  String get shell_stop => 'Arrêter';

  @override
  String get shell_soundingWord => 'UN MOT EN LECTURE';

  @override
  String get shell_recitingSet => 'RÉCITATION DU PASSAGE';

  @override
  String get shell_notSignedIn => 'NON CONNECTÉ';

  @override
  String get shell_drawerBlurb => 'Tout ce que vous avez lu et gardé est sur ce téléphone. Les comptes arriveront avec le serveur avec lequel ils se synchronisent.';

  @override
  String appCorpusWouldNotOpen(String error) {
    return 'Le corpus n’a pas pu s’ouvrir.\n\n$error';
  }

  @override
  String get aboutProvidesFrenchGloss => 'Glose mot à mot en français';

  @override
  String get aboutLicenceVerbatim => 'Copies à l’identique, avec attribution';

  @override
  String get aboutLicenceAuthored => 'Conçu pour Wird';

  @override
  String get aboutLicenceFetched => 'Récupéré à la lecture, jamais redistribué';

  @override
  String get aboutLicencePermission => 'Utilisé avec autorisation';

  @override
  String get aboutTermsCorpus => 'Chaque racine vers laquelle un mot s’ouvre vient d’ici. Copies à l’identique uniquement — modifier l’annotation n’est pas permis. Utilisé à condition que sa source soit clairement indiquée et qu’un lien mène à corpus.quran.com, pour que vous puissiez suivre ce qui a changé depuis cette version.';

  @override
  String get aboutTermsTanzil => 'Le texte uthmani vérifié d’après lequel chaque verset est dessiné, et sur lequel le Quranic Arabic Corpus s’appuie aussi. Copié à l’identique ; modifier le texte n’est pas permis. Lié pour que vous puissiez suivre les modifications.';

  @override
  String get aboutTermsQuranFoundation => 'L’anglais sous chaque mot, servi par l’API de quran.com. En français, ce sont les gloses de The Last Dialogue qui s’affichent ; l’anglais ne reste que là où le français manque. Leurs conditions permettent à une application d’afficher ce contenu, mais pas de le conserver indéfiniment sans une resynchronisation hebdomadaire, ce que ne fait pas un corpus embarqué. Non réglé, et consigné comme non réglé.';

  @override
  String get aboutTermsLastDialogue => 'Le français sous chaque mot, pour qui lit Wird en français. Le site signale que son mot à mot est en version bêta. Ils en ont accordé l’usage à Wird par courriel le 30 septembre 2026, sans exiger d’être cités ; Wird les nomme tout de même, parce qu’il nomme chacune de ses sources.';

  @override
  String get aboutTermsNocturne => 'Le système de design d’après lequel chaque écran est dessiné. Sombre uniquement ; il n’y a pas de mode clair.';

  @override
  String get aboutTermsScheherazade => 'Embarquée sans modification, parce que les polices arabes du système abîment les signes diacritiques coraniques.';

  @override
  String get aboutTermsInter => 'Embarquée sans modification.';

  @override
  String get aboutTermsTimings => 'La milliseconde à laquelle chaque mot est prononcé : c’est ce qui permet à un mot de s’allumer au moment où vous l’entendez. Tiré de github.com/cpfair/quran-align, aligné sur ce même enregistrement muʿallim. Réindexé pour cette application : les données publiées comptent à partir de zéro et excluent leur borne de fin, et elles sont stockées ici à partir de un, rattachées au mot auquel elles appartiennent. Fourni tel quel, sans garantie.';

  @override
  String get aboutTermsRecitation => 'L’enregistrement muʿallim est téléchargé par votre appareil depuis everyayah.com quand vous appuyez sur lecture, comme un navigateur charge une page, puis mis en cache sur votre téléphone. Wird ne l’embarque pas, n’en fait pas de copie miroir et ne le sert pas. Les archives ne publient aucune condition d’utilisation : rien ici ne vaut donc permission de le redistribuer — et c’est pourquoi cette application ne le fait jamais.';

  @override
  String get aboutTermsVoice => 'Le reconnaisseur qui entend votre récitation, téléchargé à votre demande et exécuté sur ce téléphone ; rien de ce que vous dites n’est envoyé ailleurs. Il écrit des phonèmes coraniques, y compris les marques du tajwīd. Wird s’en sert uniquement pour savoir où vous en êtes dans le passage, et jamais pour juger votre récitation : un retour automatique sur le tajwīd peut se tromper, et aucun logiciel, ici ou ailleurs, ne remplace un enseignant qualifié. Sa licence interdit de faire payer le modèle ou toute fonction qu’il alimente, ce que Wird ne fait pas et ne fera pas.';

  @override
  String get aboutSelfTerms => 'Wird est un logiciel libre sous GNU Affero General Public License, version 3 ou ultérieure. L’AGPL plutôt que la GPL, parce que Wird a un serveur : quiconque le fait tourner comme service doit à ses utilisateurs le code source de ce qu’ils utilisent.';

  @override
  String get study_expandSheet => 'Afficher les nombres, les formes et les autres versets';

  @override
  String get study_collapseSheet => 'Revoir toute la sourate';

  @override
  String get study_senses => 'Sens';

  @override
  String get study_particleNote => 'Les particules et les pronoms n’ont pas de racine trilitère. Glissez jusqu’au mot suivant.';

  @override
  String get study_moreRow => 'Nombres, formes, autres versets';

  @override
  String get study_acrossQuran => 'Dans tout le Coran';

  @override
  String get study_countRoot => 'cette racine';

  @override
  String get study_countLemma => 'sous la forme';

  @override
  String get study_countSurah => 'dans cette sourate';

  @override
  String get study_ringCaption => 'Ses formes, et combien de fois chacune est lue';

  @override
  String get study_otherAyas => 'Autres versets';

  @override
  String study_position(String ref, int n, int total) {
    return '$ref · mot $n/$total';
  }

  @override
  String study_backTo(String ref) {
    return 'Retour à $ref';
  }

  @override
  String get study_readFromHere => 'Lire cette sourate à partir d’ici';

  @override
  String get study_pray => 'Prier';

  @override
  String get study_recite => 'Réciter';

  @override
  String get study_pauseRecitation => 'Mettre la récitation en pause';

  @override
  String study_markUnderstood(String ref) {
    return 'Marquer le verset $ref comme compris';
  }

  @override
  String study_openRoot(String root) {
    return 'Ouvrir la racine $root';
  }

  @override
  String get dashboard_continueReading => 'REPRENDRE LA LECTURE';

  @override
  String get study_form => 'Forme';

  @override
  String get prepare_trouble => 'Le Coran n\'a pas pu être lu sur cet appareil. Réessayez ; si cela persiste, fermez Wird et rouvrez-le.';

  @override
  String get prepare_retry => 'Réessayer';
}
