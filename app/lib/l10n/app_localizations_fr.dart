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
  String get study_backToTheWalk => 'Retour au parcours';

  @override
  String get study_constellation => 'Constellation';

  @override
  String get study_everyAyaUnderstood => 'Tous les versets de ce passage sont compris';

  @override
  String get study_goTo => 'Aller à…';

  @override
  String get study_goToAnyAya => 'Aller à n\'importe quelle sourate ou verset';

  @override
  String get study_kinOpensItsAya => 'Un mot apparenté ouvre le verset où il paraît pour la première fois.';

  @override
  String get study_noAyaUnderstoodYet => 'Aucun verset encore marqué comme compris';

  @override
  String get study_noRecitation => 'Aucune récitation pour ce passage';

  @override
  String get study_noRootInSet => 'Aucun mot de ce passage ne porte de racine.';

  @override
  String get study_nothingLeftToServe => 'Tous les versets sont compris. Il ne reste rien à servir.';

  @override
  String study_numbersAnd(Object first, Object last) {
    return '$first et $last';
  }

  @override
  String get study_previousSet => 'Passage précédent';

  @override
  String get study_prayThisSet => 'Prier ce passage';

  @override
  String study_progressSplit(Object done, Object open) {
    return 'Verset $done marqué comme compris · verset $open à lire';
  }

  @override
  String study_revelationKicker(Object order, Object place) {
    return 'Révélation $order · $place';
  }

  @override
  String study_surahKicker(Object surah, Object place) {
    return 'Sourate $surah · $place';
  }

  @override
  String get study_visiting => 'En visite';

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
  String settingsRecitedBy(String reciter) {
    return 'Récité par $reciter.';
  }

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
    return 'mot $word à $score %, mais un autre endroit correspond à $rival % — le passage le dit deux fois';
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
  String get settingsParkedReport => 'Quelque chose que vous avez signalé';

  @override
  String get settingsParkedOther => 'Une modification que vous avez faite';

  @override
  String get study_ayaTranslated => 'Rashid Maash';

  @override
  String get study_glossesStayEnglish => 'Le sens de chaque mot est en anglais : il n’existe pas de traduction mot à mot dans votre langue.';

  @override
  String get root_senseJudgeThanks => 'C’est noté — merci.';

  @override
  String get root_senseJudgeGoodLabel => 'Ce sens est juste';

  @override
  String get root_senseJudgeBadLabel => 'Ce sens est faux';
}
