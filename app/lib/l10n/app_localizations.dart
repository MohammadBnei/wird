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

  /// Kicker over the waiting set on home, above its title. The number is how far along the walk the reader has come.
  ///
  /// In en, this message translates to:
  /// **'SET {number} · WAITING'**
  String dashboard_setWaiting(int number);

  /// How long the waiting set is, on the line under its Arabic name on home. Joined to the prayer count by a middle dot.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 aya} other{{count} ayas}}'**
  String dashboard_ayaCount(int count);

  /// How often the waiting set has been prayed, on the same line on home as the aya count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no prayer on it yet} =1{prayed once} =2{prayed twice} other{prayed {count} times}}'**
  String dashboard_prayerCount(int count);

  /// Home's primary button: it opens the prayer on the waiting set.
  ///
  /// In en, this message translates to:
  /// **'Pray this set'**
  String get dashboard_praySet;

  /// Home's second button, under the prayer one: it opens the reading screen on the waiting set.
  ///
  /// In en, this message translates to:
  /// **'Read it first'**
  String get dashboard_readFirst;

  /// What home says in place of a waiting set once the reader has finished the whole walk.
  ///
  /// In en, this message translates to:
  /// **'Every aya is understood.'**
  String get dashboard_allUnderstood;

  /// The line under that on home, telling the finished reader where they can still go.
  ///
  /// In en, this message translates to:
  /// **'There is nothing left to serve. The index opens any sūra again.'**
  String get dashboard_allUnderstoodWhy;

  /// Kicker over the list of destinations at the bottom of home.
  ///
  /// In en, this message translates to:
  /// **'WHERE TO GO'**
  String get dashboard_whereToGo;

  /// Home's destination row for the sūra index.
  ///
  /// In en, this message translates to:
  /// **'Sūra index'**
  String get dashboard_doorIndex;

  /// The subtitle under the sūra index row on home.
  ///
  /// In en, this message translates to:
  /// **'Open any aya you want'**
  String get dashboard_doorIndexWhy;

  /// Home's destination row for the progress screen.
  ///
  /// In en, this message translates to:
  /// **'Your passage'**
  String get dashboard_doorProgress;

  /// The subtitle under the progress row on home.
  ///
  /// In en, this message translates to:
  /// **'How much you have understood'**
  String get dashboard_doorProgressWhy;

  /// Home's destination row for the ayas and roots the reader saved.
  ///
  /// In en, this message translates to:
  /// **'Kept'**
  String get dashboard_doorKept;

  /// The subtitle under the kept row on home.
  ///
  /// In en, this message translates to:
  /// **'The ayas and roots you saved'**
  String get dashboard_doorKeptWhy;
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
