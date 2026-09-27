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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// The eyebrow over the heading of the sources screen, reached from the drawer's Sources row.
  ///
  /// In en, this message translates to:
  /// **'BUILT ON'**
  String get aboutBuiltOn;

  /// The heading of the sources screen, under the BUILT ON eyebrow.
  ///
  /// In en, this message translates to:
  /// **'Sources and licences'**
  String get aboutTitle;

  /// The kicker on the first card of the sources screen, the one carrying Wird's own terms.
  ///
  /// In en, this message translates to:
  /// **'This app'**
  String get aboutThisApp;

  /// The snack bar shown on the sources screen once a source's address has been tapped and copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied {url}'**
  String aboutCopied(String url);

  /// The kicker on the Quranic Arabic Corpus card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'Roots, word forms and morphology'**
  String get aboutProvidesMorphology;

  /// The kicker on the Tanzil Project card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'The Qurʼanic text'**
  String get aboutProvidesText;

  /// The kicker on the Quran Foundation card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'Word-by-word gloss and transliteration'**
  String get aboutProvidesGloss;

  /// The kicker on the Nocturne card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'Colour, space and type'**
  String get aboutProvidesDesign;

  /// The kicker on the Scheherazade New card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'The Arabic face'**
  String get aboutProvidesArabicFace;

  /// The kicker on the Inter card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'The Latin face'**
  String get aboutProvidesLatinFace;

  /// The kicker on the quran-align card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'Per-word recitation timings'**
  String get aboutProvidesTimings;

  /// The kicker on the al-Ḥuṣarī recitation card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'Recitation'**
  String get aboutProvidesRecitation;

  /// The kicker on the Quran-Lab recogniser card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'Following your voice in prayer'**
  String get aboutProvidesVoice;

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
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
