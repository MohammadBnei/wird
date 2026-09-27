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

  /// The heading of the report screen, where a reader says what went wrong, what is missing, or what could be better.
  ///
  /// In en, this message translates to:
  /// **'Report something'**
  String get report_title;

  /// Caption under the report screen's heading, saying that no answer comes back.
  ///
  /// In en, this message translates to:
  /// **'This goes one way. It reaches whoever keeps Wird running, and nothing comes back — there is no inbox here to check.'**
  String get report_one_way;

  /// Section heading on the report screen, over the bug / request / improvement chooser.
  ///
  /// In en, this message translates to:
  /// **'WHAT KIND'**
  String get report_kind_heading;

  /// First option of the kind chooser on the report screen: something is broken.
  ///
  /// In en, this message translates to:
  /// **'Bug'**
  String get report_kind_bug;

  /// Second option of the kind chooser on the report screen: something is missing.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get report_kind_request;

  /// Third option of the kind chooser on the report screen: something could be better.
  ///
  /// In en, this message translates to:
  /// **'Improvement'**
  String get report_kind_improvement;

  /// Section heading on the report screen, over the field the reader writes the report in.
  ///
  /// In en, this message translates to:
  /// **'IN YOUR OWN WORDS'**
  String get report_words_heading;

  /// Placeholder shown inside the empty report field on the report screen.
  ///
  /// In en, this message translates to:
  /// **'What happened, or what is missing.'**
  String get report_words_hint;

  /// Caption under the report field, shown only once the reader is within a paragraph of the length the server accepts.
  ///
  /// In en, this message translates to:
  /// **'{remaining} characters left of {max}. The server takes no more than that.'**
  String report_chars_left(int remaining, int max);

  /// Section heading on the report screen, over the gathered build, platform, screen and corpus version printed as they will be sent.
  ///
  /// In en, this message translates to:
  /// **'SENT WITH IT'**
  String get report_context_heading;

  /// Caption under the gathered context on the report screen, saying what does not leave the phone.
  ///
  /// In en, this message translates to:
  /// **'Gathered so you do not have to type it. Nothing else travels: not what you were reading, not what you have kept, not your progress.'**
  String get report_context_only;

  /// Stands in for the gathered context on the report screen while the corpus is still being asked for its version.
  ///
  /// In en, this message translates to:
  /// **'Reading this build…'**
  String get report_context_loading;

  /// The report screen's one button: it queues the report and returns.
  ///
  /// In en, this message translates to:
  /// **'Send it'**
  String get report_send;

  /// Section heading the report screen shows in place of the form once a report has been queued.
  ///
  /// In en, this message translates to:
  /// **'QUEUED'**
  String get report_queued_heading;

  /// What the report screen says after a send: the report is written locally and flushes with the next sync.
  ///
  /// In en, this message translates to:
  /// **'It is written down on this phone and goes out with the next sync, even if you are offline now.'**
  String get report_queued_body;

  /// Button on the report screen after a send, which empties the form for a second report.
  ///
  /// In en, this message translates to:
  /// **'Write another'**
  String get report_write_another;
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
