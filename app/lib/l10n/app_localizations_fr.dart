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
      one: '1 verset',
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
    return 'Arrêter · $percent %';
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
    return 'le meilleur mot, $word, correspond à $score % alors qu’il en faut $needed %';
  }

  @override
  String settingsVoiceCheckAmbiguous(int word, int score, int rival) {
    return 'mot $word à $score %, mais un autre endroit correspond à $rival % — le passage le dit deux fois';
  }

  @override
  String settingsVoiceCheckPlaced(int word, int score) {
    return 'mot $word à $score %';
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
      one: '1 modification n’a pas atteint le serveur',
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
  String get settingsParkedUnkept => 'Quelque chose que vous avez retiré de Kept';

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
}
