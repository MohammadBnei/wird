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
  String get settingsTitle => 'Settings';

  @override
  String get settingsReading => 'READING';

  @override
  String get settingsWordGloss => 'Gloss';

  @override
  String get settingsWordTranslit => 'Translit';

  @override
  String get settingsWordBoth => 'Both';

  @override
  String get settingsWordNeither => 'Neither';

  @override
  String get settingsWordCaption => 'What is printed under each Arabic word.';

  @override
  String get settingsOrderChronological => 'Chronological';

  @override
  String get settingsOrderMushaf => 'Muṣḥaf';

  @override
  String get settingsOrderCaption => 'The chronology orders sūras; ayas inside a sūra stay in written order.';

  @override
  String get settingsArabic => 'Arabic';

  @override
  String get settingsArabicCaption => 'How large the Arabic is set on the reading screen.';

  @override
  String get settingsSetWidth => 'HOW MUCH YOU TAKE AT ONCE';

  @override
  String get settingsNoSetWaiting => 'Every aya is understood, so no set is waiting.';

  @override
  String settingsSetAyas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas',
      one: '1 aya',
    );
    return '$_temp0';
  }

  @override
  String get settingsSetWidthCaption => 'A wider set may cross an aya you already understood. It is recited with the rest and stays counted where it is.';

  @override
  String get settingsRecitation => 'RECITATION';

  @override
  String get settingsNoReciter => 'No reciter is named in this corpus.';

  @override
  String settingsRecitedBy(String reciter) {
    return 'Recited by $reciter.';
  }

  @override
  String get settingsMicrophone => 'MICROPHONE';

  @override
  String get settingsAllowMicrophone => 'Allow microphone';

  @override
  String get settingsMicNotAsked => 'Voice-follow needs the microphone. Off by default; never asked for during a prayer.';

  @override
  String get settingsMicGranted => 'Microphone allowed.';

  @override
  String get settingsMicDenied => 'Microphone refused. The prayer screen advances on a tap, as it always does.';

  @override
  String get settingsMicUnavailable => 'The microphone could not be reached last time it was asked for. Try again; the prayer screen advances on a tap either way.';

  @override
  String get settingsAccount => 'ACCOUNT';

  @override
  String settingsStopDownload(int percent) {
    return 'Stop · $percent%';
  }

  @override
  String get settingsCheckRecogniser => 'Check the recogniser';

  @override
  String get settingsRemoveRecogniser => 'Remove recogniser';

  @override
  String settingsDownloadRecogniser(int megabytes) {
    return 'Download recogniser · $megabytes MB';
  }

  @override
  String get settingsRecogniserDownloading => 'Downloading. Stopping keeps what has arrived, and pressing Download again carries on from there.';

  @override
  String get settingsRecogniserReady => 'The prayer screen follows your voice. Your recitation is recognised on this phone and never leaves it.';

  @override
  String get settingsRecogniserNotServed => 'Wird is not serving the recogniser from here. Nothing on this phone changes that, so the button will not bring it either — voice-follow waits until it is published again.';

  @override
  String get settingsRecogniserInterrupted => 'The download stopped before it finished. What arrived is still on the phone, and pressing Download again carries on from there.';

  @override
  String get settingsRecogniserPartial => 'A stopped download is still on the phone. Downloading again carries on from where it stopped.';

  @override
  String get settingsRecogniserAbsent => 'A Qur\'an recogniser that runs on the phone, so nothing you recite is sent anywhere. Downloading it is what turns voice-follow on; the prayer screen advances on a tap until you do, and after you remove it.';

  @override
  String get settingsVoiceCheckTitle => 'Can this phone hear you?';

  @override
  String settingsVoiceCheckSet(String words) {
    return 'the set: $words…';
  }

  @override
  String get settingsVoiceCheckOpening => 'Starting the recogniser…';

  @override
  String get settingsVoiceCheckListening => 'Recite, and the words you say should appear below.';

  @override
  String get settingsVoiceCheckNoModel => 'The recogniser did not start. The download may be incomplete, or this phone may not be able to load it. Voice-follow stays off and the prayer screen answers your tap, as it always has.';

  @override
  String get settingsVoiceCheckNoMicrophone => 'The microphone was refused, so there is nothing to hear.';

  @override
  String settingsVoiceCheckCursor(int word, int total, int moves) {
    return 'the prayer would be on word $word of $total, after $moves moves';
  }

  @override
  String settingsVoiceCheckAudio(String seconds, int millis) {
    return '${seconds}s of voice, slowest answer ${millis}ms';
  }

  @override
  String get settingsVoiceCheckTooLittle => 'heard too little to place';

  @override
  String settingsVoiceCheckBelow(int word, int score, int needed) {
    return 'best word $word fits $score%, needs $needed%';
  }

  @override
  String settingsVoiceCheckAmbiguous(int word, int score, int rival) {
    return 'word $word at $score% but somewhere else fits $rival% — the set says this twice';
  }

  @override
  String settingsVoiceCheckPlaced(int word, int score) {
    return 'word $word at $score%';
  }

  @override
  String settingsSignedInAs(String subject) {
    return 'Signed in as $subject';
  }

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutCaption => 'Signing out stops the sync. Everything you have read, kept and marked stays on this phone.';

  @override
  String get settingsSignedOutCaption => 'Wird works signed out. Signing in carries what you mark and keep to your other devices.';

  @override
  String get settingsSignIn => 'Sign in';

  @override
  String get settingsFinishInBrowser => 'Finish signing in in your browser. This phone is waiting for it to send you back.';

  @override
  String get settingsCancelSignIn => 'Cancel';

  @override
  String get settingsNoBrowser => 'no browser here would open the sign-in address';

  @override
  String get settingsSignInUnreachable => 'The sign-in server could not be reached. Nothing changed.';

  @override
  String settingsParkedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes have not reached the server',
      one: '1 change has not reached the server',
    );
    return '$_temp0';
  }

  @override
  String get settingsParkedCaption => 'They are still on this phone. Send them again, or let them go.';

  @override
  String get settingsSendAgain => 'Send again';

  @override
  String get settingsDiscard => 'Discard';

  @override
  String settingsParkedUnderstood(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas you marked understood',
      one: 'An aya you marked understood',
    );
    return '$_temp0';
  }

  @override
  String get settingsParkedKept => 'Something you kept';

  @override
  String get settingsParkedUnkept => 'Something you removed from Kept';

  @override
  String get settingsParkedSetRead => 'A set you read';

  @override
  String get settingsParkedPrayer => 'A prayer you counted';

  @override
  String get settingsParkedOrder => 'Your reading order';

  @override
  String get settingsParkedReport => 'Something you reported';

  @override
  String get settingsParkedOther => 'A change you made';
}
