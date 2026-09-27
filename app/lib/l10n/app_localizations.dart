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

  /// Two places on the reading screen, and the same words in both: what the mark button says once every aya of the set is understood, and the down arrow in the footer that steps to the set after this one.
  ///
  /// In en, this message translates to:
  /// **'Next set'**
  String get nextSet;

  /// Why the play button is dark: the recitation for this set is not on the device.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get notDownloaded;

  /// Reading screen header, shown only while the reader is visiting an aya they asked for: it puts them back on the walk's next set.
  ///
  /// In en, this message translates to:
  /// **'Back to the walk'**
  String get study_backToTheWalk;

  /// Reading screen, the unfolded root panel: opens the deep dive on this aya and this root.
  ///
  /// In en, this message translates to:
  /// **'Constellation'**
  String get study_constellation;

  /// Reading screen, the sentence under the progress rule in the unfolded header, when no aya of the set is still open.
  ///
  /// In en, this message translates to:
  /// **'Every aya in this set is understood'**
  String get study_everyAyaUnderstood;

  /// Reading screen footer, the middle control: it opens the sūra index, which answers with any aya of the Qur'an.
  ///
  /// In en, this message translates to:
  /// **'Go to…'**
  String get study_goTo;

  /// Screen-reader label for the reading screen footer's middle control, whose visible face says only "Go to…".
  ///
  /// In en, this message translates to:
  /// **'Go to any sūra or aya'**
  String get study_goToAnyAya;

  /// Reading screen, the unfolded root panel: what pressing one of the kin tags above it does.
  ///
  /// In en, this message translates to:
  /// **'A kin opens the aya it is first met in.'**
  String get study_kinOpensItsAya;

  /// Reading screen, the sentence under the progress rule in the unfolded header, when no aya of the set has been marked.
  ///
  /// In en, this message translates to:
  /// **'No aya marked understood yet'**
  String get study_noAyaUnderstoodYet;

  /// Reading screen transport: why the play button is dark when the corpus ships no recitation for these ayas at all, as against notDownloaded, which is one that could still arrive.
  ///
  /// In en, this message translates to:
  /// **'No recitation for this set'**
  String get study_noRecitation;

  /// Reading screen, in place of the root panel's contents when not one word of the set on screen bears a root.
  ///
  /// In en, this message translates to:
  /// **'No word in this set carries a root.'**
  String get study_noRootInSet;

  /// The whole of the reading screen once the reader has marked every aya of the Qur'an understood and the walk has no set left to hand them.
  ///
  /// In en, this message translates to:
  /// **'Every aya is understood. There is nothing left to serve.'**
  String get study_nothingLeftToServe;

  /// How the last of a list of aya numbers is joined to the ones before it, inside the sentences under the reading screen's progress rule.
  ///
  /// In en, this message translates to:
  /// **'{first} and {last}'**
  String study_numbersAnd(Object first, Object last);

  /// Reading screen footer, the up arrow: it steps to the set before this one. Also its screen-reader label, which the aya numbers are appended to.
  ///
  /// In en, this message translates to:
  /// **'Previous set'**
  String get study_previousSet;

  /// Reading screen header, the act the reading is for: it opens the prayer screen on this set.
  ///
  /// In en, this message translates to:
  /// **'Pray this set'**
  String get study_prayThisSet;

  /// Reading screen, the sentence under the progress rule in the unfolded header, when some ayas of the set are marked and some are still open.
  ///
  /// In en, this message translates to:
  /// **'Aya {done} marked understood · aya {open} open'**
  String study_progressSplit(Object done, Object open);

  /// Reading screen, the kicker in the unfolded header when the reader is in the order of revelation: where this set sits. The place is the sūra's own revelation_place from the corpus, a place name, and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Revelation {order} · {place}'**
  String study_revelationKicker(Object order, Object place);

  /// Reading screen, the kicker in the unfolded header when the reader is in the written order: where this set sits. The place is the sūra's own revelation_place from the corpus, a place name, and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Sūra {surah} · {place}'**
  String study_surahKicker(Object surah, Object place);

  /// Reading screen, the kicker before the set's title: the reader asked for this aya rather than being handed it by the walk.
  ///
  /// In en, this message translates to:
  /// **'Visiting'**
  String get study_visiting;
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
