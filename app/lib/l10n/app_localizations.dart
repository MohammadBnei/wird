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

  /// The deep dive's aya pane kicker, drawn uppercased over the printed aya — the head of the screen in the three-pane layout. The surah name comes from the corpus and is not translated.
  ///
  /// In en, this message translates to:
  /// **'{surah} · aya {number}'**
  String deepdive_aya_kicker(String surah, int number);

  /// Screen-reader label on the deep dive's back arrow, at the head of its first column.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get deepdive_back;

  /// Caption under a constellation node when the corpus glossed no occurrence of that form, so only its morphological form number is known. Shown inside the drawn constellation.
  ///
  /// In en, this message translates to:
  /// **'form {form}'**
  String deepdive_form(String form);

  /// The deep dive's one action button, before the aya has been kept.
  ///
  /// In en, this message translates to:
  /// **'Keep this aya'**
  String get deepdive_keep;

  /// What the same deep dive button says once the aya is kept: it stays live and carries its own undo.
  ///
  /// In en, this message translates to:
  /// **'Kept · tap to undo'**
  String get deepdive_kept;

  /// The kicker beside the back arrow at the top of the deep dive when its three panes are stacked into one column. {ref} is a surah:aya reference.
  ///
  /// In en, this message translates to:
  /// **'DEEP DIVE · {ref}'**
  String deepdive_kicker(String ref);

  /// Beside the root's Arabic spelling in the deep dive's centre pane: how the root is transliterated and how many times it occurs in the Qur'an.
  ///
  /// In en, this message translates to:
  /// **'{translit} · {count} occurrences'**
  String deepdive_occurrences(String translit, int count);

  /// Heading over the root's spelling in the deep dive's centre pane, above the constellation or the list of its family.
  ///
  /// In en, this message translates to:
  /// **'ROOT CONSTELLATION'**
  String get deepdive_root_heading;

  /// Screen-reader label on one node of the drawn constellation, which behaves as a button opening the aya it names. The nodes are painted onto a canvas, so this label is the whole screen-reader surface of the drawing.
  ///
  /// In en, this message translates to:
  /// **'{form} · open {ref}'**
  String deepdive_star(String form, String ref);

  /// Caption under the one constellation node that marks the form the reader has open, drawn inside the constellation.
  ///
  /// In en, this message translates to:
  /// **'THIS AYA · {ref}'**
  String deepdive_this_aya(String ref);

  /// Shown in place of the whole deep dive when the corpus holds no such aya, or the aya holds no such root.
  ///
  /// In en, this message translates to:
  /// **'The corpus carries no aya {ref} with a root spelled {letters}.'**
  String deepdive_unknown(String ref, String letters);

  /// The drawing, as the deep dive's segmented control names it — offered only where the centre pane is wide enough to draw it.
  ///
  /// In en, this message translates to:
  /// **'Constellation'**
  String get deepdive_view_constellation;

  /// The root's family read as a list, the other option of the deep dive's segmented control.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get deepdive_view_list;

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
