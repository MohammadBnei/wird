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

  /// The kicker over the title of the passage screen (1d), saying what the screen counts.
  ///
  /// In en, this message translates to:
  /// **'UNDERSTOOD, NOT MERELY READ'**
  String get progress_kicker;

  /// The title of the passage screen (1d): how far through the Qur'an the reader has come.
  ///
  /// In en, this message translates to:
  /// **'Your passage'**
  String get progress_title;

  /// The caption inside the juz ring on the passage screen (1d), under the percentage. Both counts arrive already grouped with thousands separators.
  ///
  /// In en, this message translates to:
  /// **'{understood} of {total} ayas'**
  String progress_ayas(String understood, String total);

  /// The screen-reader label for the juz ring on the passage screen (1d). The ring's own figures are painted, so this is the only way they are ever spoken.
  ///
  /// In en, this message translates to:
  /// **'{percent} of the Qur\'an understood, {ayas}. Juz {juz}, set {set}.'**
  String progress_ringSemantics(String percent, String ayas, int juz, int set);

  /// The line inside the juz ring on the passage screen (1d) naming where the reader stands.
  ///
  /// In en, this message translates to:
  /// **'JUZ {juz} · SET {set}'**
  String progress_here(int juz, int set);

  /// The label under the first count tile on the passage screen (1d).
  ///
  /// In en, this message translates to:
  /// **'sets understood'**
  String get progress_setsUnderstood;

  /// The label under the second count tile on the passage screen (1d).
  ///
  /// In en, this message translates to:
  /// **'prayers recorded'**
  String get progress_prayersRecorded;

  /// The heading over the sūra rows on the passage screen (1d).
  ///
  /// In en, this message translates to:
  /// **'WHERE YOU ARE'**
  String get progress_whereYouAre;

  /// The button beside that heading on the passage screen (1d); it opens the index of all 114 sūras.
  ///
  /// In en, this message translates to:
  /// **'All 114'**
  String get progress_allSuras;

  /// The heading on the roots card at the foot of the passage screen (1d).
  ///
  /// In en, this message translates to:
  /// **'ROOTS YOU NOW KNOW'**
  String get progress_rootsKnown;

  /// What the roots card on the passage screen (1d) says while the reader has understood nothing yet.
  ///
  /// In en, this message translates to:
  /// **'The roots of every set you understand are collected here.'**
  String get progress_rootsEmpty;

  /// What the roots card on the passage screen (1d) says once there are roots: what they are worth against the text still to come. The count arrives already grouped.
  ///
  /// In en, this message translates to:
  /// **'{roots} roots cover {percent}% of the words ahead of you.'**
  String progress_rootsCoverage(String roots, int percent);
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
