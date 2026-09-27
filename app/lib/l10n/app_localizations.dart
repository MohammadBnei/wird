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

  /// The kicker over the index screen's title, naming what the index covers.
  ///
  /// In en, this message translates to:
  /// **'THE WHOLE QUR’AN'**
  String get index_kicker;

  /// The index screen's title: every sūra of the Qur'an, in written order.
  ///
  /// In en, this message translates to:
  /// **'All 114'**
  String get index_title;

  /// Under the index screen's title: how the two taps on a sūra row differ.
  ///
  /// In en, this message translates to:
  /// **'A sūra opens at its first aya. The arrow picks one inside it.'**
  String get index_hint;

  /// Under each sūra row in the index: where that sūra falls in the order of revelation, which is the other order the Qur'an is read in. `order` arrives already spelled as an ordinal of this locale — "83rd", "83e" — because gen-l10n rejects ICU selectordinal.
  ///
  /// In en, this message translates to:
  /// **'{order} to be revealed'**
  String index_revealed_nth(String order);

  /// Screen-reader label for the arrow at the end of a sūra row in the index, which unfolds that sūra's aya numbers.
  ///
  /// In en, this message translates to:
  /// **'Pick an aya of {sura}'**
  String index_pick_aya(String sura);

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

  /// Kicker beside the dot at the top of the prayer screen, while nothing is following the reciter.
  ///
  /// In en, this message translates to:
  /// **'IN PRAYER'**
  String get prayer_in_prayer;

  /// The same kicker at the top of the prayer screen, but only once voice-follow is really running.
  ///
  /// In en, this message translates to:
  /// **'FOLLOWING YOUR VOICE'**
  String get prayer_following_your_voice;

  /// The ghost button at the top right of the prayer screen, the one way out of the prayer.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get prayer_exit;

  /// Screen-reader label for the narrow tap zone down the left edge of the prayer field, which steps back an aya.
  ///
  /// In en, this message translates to:
  /// **'Back an aya'**
  String get prayer_back_an_aya;

  /// Screen-reader label for the wide tap zone filling the rest of the prayer field, which moves on an aya.
  ///
  /// In en, this message translates to:
  /// **'On to the next aya'**
  String get prayer_on_to_the_next_aya;

  /// The hint under the progress strip at the foot of the prayer screen, when the prayer answers taps only.
  ///
  /// In en, this message translates to:
  /// **'Screen stays awake · tap to go on · left edge steps back'**
  String get prayer_foot_taps_only;

  /// The same hint at the foot of the prayer screen once voice-follow is running, where a tap is a correction rather than the only way on.
  ///
  /// In en, this message translates to:
  /// **'Screen stays awake · tap any time · left edge steps back'**
  String get prayer_foot_following;
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
