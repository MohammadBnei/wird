import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// Heading over the gloss of the selected word in the aya it was tapped in.
  ///
  /// In en, this message translates to:
  /// **'IN THIS AYA'**
  String get inThisAya;

  /// The reading screen's one action: it advances the reader through the Qur'an.
  ///
  /// In en, this message translates to:
  /// **'Mark set understood'**
  String get markSetUnderstood;

  /// What the same button says once every aya of the set is understood.
  ///
  /// In en, this message translates to:
  /// **'Next set'**
  String get nextSet;

  /// Why the play button is dark: the recitation for this set is not on the device.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get notDownloaded;

  /// The heading at the top of the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section heading on the settings screen, over the word display and the reading order.
  ///
  /// In en, this message translates to:
  /// **'READING'**
  String get settingsReading;

  /// First option of the settings screen's word-display segmented control: print the meaning under each Arabic word.
  ///
  /// In en, this message translates to:
  /// **'Gloss'**
  String get settingsWordGloss;

  /// Second option of the settings screen's word-display segmented control: print the transliteration under each Arabic word. Abbreviated to fit the control.
  ///
  /// In en, this message translates to:
  /// **'Translit'**
  String get settingsWordTranslit;

  /// Third option of the settings screen's word-display segmented control: print gloss and transliteration under each Arabic word.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get settingsWordBoth;

  /// Fourth option of the settings screen's word-display segmented control: print nothing under the Arabic.
  ///
  /// In en, this message translates to:
  /// **'Neither'**
  String get settingsWordNeither;

  /// Caption under the word-display segmented control on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'What is printed under each Arabic word.'**
  String get settingsWordCaption;

  /// First option of the settings screen's reading-order segmented control: walk the suras in the order they were revealed.
  ///
  /// In en, this message translates to:
  /// **'Chronological'**
  String get settingsOrderChronological;

  /// Second option of the settings screen's reading-order segmented control: walk the suras in the written order of the codex, whose transliterated Arabic name this is.
  ///
  /// In en, this message translates to:
  /// **'Muṣḥaf'**
  String get settingsOrderMushaf;

  /// Caption under the reading-order segmented control on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'The chronology orders sūras; ayas inside a sūra stay in written order.'**
  String get settingsOrderCaption;

  /// Label beside the Arabic-size slider on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get settingsArabic;

  /// Caption under the Arabic-size slider on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'How large the Arabic is set on the reading screen.'**
  String get settingsArabicCaption;

  /// Section heading on the settings screen, over the control that widens or narrows the waiting set.
  ///
  /// In en, this message translates to:
  /// **'HOW MUCH YOU TAKE AT ONCE'**
  String get settingsSetWidth;

  /// Stands in for the set-width control on the settings screen when the walk has no set left to propose.
  ///
  /// In en, this message translates to:
  /// **'Every aya is understood, so no set is waiting.'**
  String get settingsNoSetWaiting;

  /// How wide the waiting set is, printed between the narrow and widen buttons on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 aya} other{{count} ayas}}'**
  String settingsSetAyas(int count);

  /// Caption under the set-width stepper on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'A wider set may cross an aya you already understood. It is recited with the rest and stays counted where it is.'**
  String get settingsSetWidthCaption;

  /// Section heading on the settings screen, over the name of who recites the audio.
  ///
  /// In en, this message translates to:
  /// **'RECITATION'**
  String get settingsRecitation;

  /// Caption in the settings screen's recitation section when the bundled corpus names nobody.
  ///
  /// In en, this message translates to:
  /// **'No reciter is named in this corpus.'**
  String get settingsNoReciter;

  /// Caption in the settings screen's recitation section naming who recites. The name is a person's, read out of the corpus, and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Recited by {reciter}.'**
  String settingsRecitedBy(String reciter);

  /// Section heading on the settings screen, over the microphone permission and the recogniser download.
  ///
  /// In en, this message translates to:
  /// **'MICROPHONE'**
  String get settingsMicrophone;

  /// The button on the settings screen that raises the system microphone prompt.
  ///
  /// In en, this message translates to:
  /// **'Allow microphone'**
  String get settingsAllowMicrophone;

  /// Caption under the Allow microphone button on the settings screen, before the reader has been asked.
  ///
  /// In en, this message translates to:
  /// **'Voice-follow needs the microphone. Off by default; never asked for during a prayer.'**
  String get settingsMicNotAsked;

  /// Caption in the settings screen's microphone section once the reader has said yes.
  ///
  /// In en, this message translates to:
  /// **'Microphone allowed.'**
  String get settingsMicGranted;

  /// Caption in the settings screen's microphone section after the reader has said no.
  ///
  /// In en, this message translates to:
  /// **'Microphone refused. The prayer screen advances on a tap, as it always does.'**
  String get settingsMicDenied;

  /// Caption in the settings screen's microphone section after the request threw rather than being answered.
  ///
  /// In en, this message translates to:
  /// **'The microphone could not be reached last time it was asked for. Try again; the prayer screen advances on a tap either way.'**
  String get settingsMicUnavailable;

  /// Section heading at the foot of the settings screen, over the sign-in panel.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get settingsAccount;

  /// The button that cancels the recogniser download in the settings screen's microphone section, carrying how much has arrived.
  ///
  /// In en, this message translates to:
  /// **'Stop · {percent}%'**
  String settingsStopDownload(int percent);

  /// The button in the settings screen's microphone section that opens the screen where the reader recites and sees what was heard.
  ///
  /// In en, this message translates to:
  /// **'Check the recogniser'**
  String get settingsCheckRecogniser;

  /// The button in the settings screen's microphone section that deletes the downloaded recogniser, and so turns voice-follow off.
  ///
  /// In en, this message translates to:
  /// **'Remove recogniser'**
  String get settingsRemoveRecogniser;

  /// The button in the settings screen's microphone section that fetches the recogniser, carrying its size in megabytes. Pressing it is what turns voice-follow on.
  ///
  /// In en, this message translates to:
  /// **'Download recogniser · {megabytes} MB'**
  String settingsDownloadRecogniser(int megabytes);

  /// Caption under the recogniser button on the settings screen while the download is running.
  ///
  /// In en, this message translates to:
  /// **'Downloading. Stopping keeps what has arrived, and pressing Download again carries on from there.'**
  String get settingsRecogniserDownloading;

  /// Caption under the recogniser buttons on the settings screen once the model is on the phone.
  ///
  /// In en, this message translates to:
  /// **'The prayer screen follows your voice. Your recitation is recognised on this phone and never leaves it.'**
  String get settingsRecogniserReady;

  /// Caption under the recogniser button on the settings screen after the host answered that it has no model to give.
  ///
  /// In en, this message translates to:
  /// **'Wird is not serving the recogniser from here. Nothing on this phone changes that, so the button will not bring it either — voice-follow waits until it is published again.'**
  String get settingsRecogniserNotServed;

  /// Caption under the recogniser button on the settings screen after the download was cut off part way.
  ///
  /// In en, this message translates to:
  /// **'The download stopped before it finished. What arrived is still on the phone, and pressing Download again carries on from there.'**
  String get settingsRecogniserInterrupted;

  /// Caption under the recogniser button on the settings screen when part of the model is already on disk from an earlier attempt.
  ///
  /// In en, this message translates to:
  /// **'A stopped download is still on the phone. Downloading again carries on from where it stopped.'**
  String get settingsRecogniserPartial;

  /// Caption under the recogniser button on the settings screen on a phone that has never downloaded it.
  ///
  /// In en, this message translates to:
  /// **'A Qur\'an recogniser that runs on the phone, so nothing you recite is sent anywhere. Downloading it is what turns voice-follow on; the prayer screen advances on a tap until you do, and after you remove it.'**
  String get settingsRecogniserAbsent;

  /// The app bar title of the recogniser check screen, opened from the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Can this phone hear you?'**
  String get settingsVoiceCheckTitle;

  /// On the recogniser check screen, the opening Arabic words of the set the prayer would be following.
  ///
  /// In en, this message translates to:
  /// **'the set: {words}…'**
  String settingsVoiceCheckSet(String words);

  /// What the recogniser check screen says while the model is being loaded.
  ///
  /// In en, this message translates to:
  /// **'Starting the recogniser…'**
  String get settingsVoiceCheckOpening;

  /// What the recogniser check screen says once the microphone is open.
  ///
  /// In en, this message translates to:
  /// **'Recite, and the words you say should appear below.'**
  String get settingsVoiceCheckListening;

  /// What the recogniser check screen says when the model would not open.
  ///
  /// In en, this message translates to:
  /// **'The recogniser did not start. The download may be incomplete, or this phone may not be able to load it. Voice-follow stays off and the prayer screen answers your tap, as it always has.'**
  String get settingsVoiceCheckNoModel;

  /// What the recogniser check screen says when the microphone was refused.
  ///
  /// In en, this message translates to:
  /// **'The microphone was refused, so there is nothing to hear.'**
  String get settingsVoiceCheckNoMicrophone;

  /// On the recogniser check screen, where the matcher would have put a prayer on the set.
  ///
  /// In en, this message translates to:
  /// **'the prayer would be on word {word} of {total}, after {moves} moves'**
  String settingsVoiceCheckCursor(int word, int total, int moves);

  /// The last line of the recogniser check screen: how much voice reached the model, and how slow its slowest answer was.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s of voice, slowest answer {millis}ms'**
  String settingsVoiceCheckAudio(String seconds, int millis);

  /// On the recogniser check screen, why the prayer would not have moved: not enough was heard to match anything.
  ///
  /// In en, this message translates to:
  /// **'heard too little to place'**
  String get settingsVoiceCheckTooLittle;

  /// On the recogniser check screen, why the prayer would not have moved: the best place in the set is below the threshold.
  ///
  /// In en, this message translates to:
  /// **'best word {word} fits {score}%, needs {needed}%'**
  String settingsVoiceCheckBelow(int word, int score, int needed);

  /// On the recogniser check screen, why the prayer would not have moved: two places in the set fit about equally well.
  ///
  /// In en, this message translates to:
  /// **'word {word} at {score}% but somewhere else fits {rival}% — the set says this twice'**
  String settingsVoiceCheckAmbiguous(int word, int score, int rival);

  /// On the recogniser check screen, where the matcher placed the reciter and how well it fitted.
  ///
  /// In en, this message translates to:
  /// **'word {word} at {score}%'**
  String settingsVoiceCheckPlaced(int word, int score);

  /// Who the phone is signed in as, in the settings screen's account panel. The subject comes from the identity server and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {subject}'**
  String settingsSignedInAs(String subject);

  /// The button in the settings screen's account panel that forgets the tokens.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// Caption under the Sign out button in the settings screen's account panel.
  ///
  /// In en, this message translates to:
  /// **'Signing out stops the sync. Everything you have read, kept and marked stays on this phone.'**
  String get settingsSignOutCaption;

  /// Caption over the Sign in button in the settings screen's account panel.
  ///
  /// In en, this message translates to:
  /// **'Wird works signed out. Signing in carries what you mark and keep to your other devices.'**
  String get settingsSignedOutCaption;

  /// The button in the settings screen's account panel that opens the identity server in the phone's own browser.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get settingsSignIn;

  /// Caption in the settings screen's account panel while a sign-in is waiting on the browser.
  ///
  /// In en, this message translates to:
  /// **'Finish signing in in your browser. This phone is waiting for it to send you back.'**
  String get settingsFinishInBrowser;

  /// The button in the settings screen's account panel that drops a sign-in the browser never came back from.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsCancelSignIn;

  /// The trouble line in the settings screen's account panel when no browser on the device would take the sign-in address.
  ///
  /// In en, this message translates to:
  /// **'no browser here would open the sign-in address'**
  String get settingsNoBrowser;

  /// The trouble line in the settings screen's account panel when the identity server answered nothing.
  ///
  /// In en, this message translates to:
  /// **'The sign-in server could not be reached. Nothing changed.'**
  String get settingsSignInUnreachable;

  /// Heading of the parked-writes panel on the settings screen: how many writes the server refused.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change has not reached the server} other{{count} changes have not reached the server}}'**
  String settingsParkedCount(int count);

  /// Caption under the parked-writes heading on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'They are still on this phone. Send them again, or let them go.'**
  String get settingsParkedCaption;

  /// The button beside a parked write on the settings screen that puts it back on the next flush.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get settingsSendAgain;

  /// The button beside a parked write on the settings screen that throws it away.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get settingsDiscard;

  /// A parked write named in the settings screen's parked-writes panel: ayas the reader marked understood.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{An aya you marked understood} other{{count} ayas you marked understood}}'**
  String settingsParkedUnderstood(int count);

  /// A parked write named in the settings screen's parked-writes panel: an item the reader kept.
  ///
  /// In en, this message translates to:
  /// **'Something you kept'**
  String get settingsParkedKept;

  /// A parked write named in the settings screen's parked-writes panel: an item the reader removed from the Kept screen, which the drawer still names in English.
  ///
  /// In en, this message translates to:
  /// **'Something you removed from Kept'**
  String get settingsParkedUnkept;

  /// A parked write named in the settings screen's parked-writes panel: a set the reader read.
  ///
  /// In en, this message translates to:
  /// **'A set you read'**
  String get settingsParkedSetRead;

  /// A parked write named in the settings screen's parked-writes panel: a prayer the reader counted.
  ///
  /// In en, this message translates to:
  /// **'A prayer you counted'**
  String get settingsParkedPrayer;

  /// A parked write named in the settings screen's parked-writes panel: the reading order the reader chose.
  ///
  /// In en, this message translates to:
  /// **'Your reading order'**
  String get settingsParkedOrder;

  /// A parked write named in the settings screen's parked-writes panel: a bug or request the reader wrote.
  ///
  /// In en, this message translates to:
  /// **'Something you reported'**
  String get settingsParkedReport;

  /// A parked write named in the settings screen's parked-writes panel when its kind is one this build does not know.
  ///
  /// In en, this message translates to:
  /// **'A change you made'**
  String get settingsParkedOther;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'fr': return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
