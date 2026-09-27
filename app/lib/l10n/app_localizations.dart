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

  /// Screen-reader label on an aya reference in a root's family — the panel under screen 1a's aya, screen 3a's spine and screen 1c's constellation all draw it.
  ///
  /// In en, this message translates to:
  /// **'Open {ref}'**
  String root_openAya(String ref);

  /// Mark on the one row of a root's spine whose form the aya on screen in front of the reader spells.
  ///
  /// In en, this message translates to:
  /// **'THIS AYA'**
  String get root_thisAya;

  /// The second line of every row of a root's spine: which shape the form is and how often it is read.
  ///
  /// In en, this message translates to:
  /// **'Form {form} · {occurrences}×'**
  String root_weightWithForm(String form, int occurrences);

  /// Screen-reader label on the left chevron under the root dial on screens 3a and 1c, which turns the ring back one form.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get root_previousForm;

  /// Screen-reader label on the right chevron under the root dial on screens 3a and 1c, which turns the ring on one form.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get root_nextForm;

  /// The line between the two chevrons under the root dial: where on the ring the reader stands, and the gesture that moves it.
  ///
  /// In en, this message translates to:
  /// **'{index} of {count} · swipe the ring'**
  String root_dialPosition(int index, int count);

  /// The kicker across the top of screen 3a, the root read on its dial.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get root_kicker;

  /// The kicker across the top of screen 2b, the same root read as a spine with the dial taken away.
  ///
  /// In en, this message translates to:
  /// **'Root spine'**
  String get root_kickerSpine;

  /// Drawn in the middle of screens 3a and 2b when the letters asked for name no root in the bundled corpus.
  ///
  /// In en, this message translates to:
  /// **'The corpus carries no root spelled {letters}.'**
  String root_unknownRoot(String letters);

  /// Heading over the spine of derivatives on screens 3a and 2b.
  ///
  /// In en, this message translates to:
  /// **'Its kin in the Qur\'an'**
  String get root_kinHeading;

  /// Beside the kin heading on screen 3a: how many forms the root has and how often they are read in all.
  ///
  /// In en, this message translates to:
  /// **'{forms} forms · {occurrences} occurrences'**
  String root_kinFormsAndOccurrences(int forms, int occurrences);

  /// Beside the kin heading on screen 2b, which gives the count of forms and not the occurrences.
  ///
  /// In en, this message translates to:
  /// **'{forms} forms'**
  String root_formCount(int forms);

  /// The kicker inside screen 3a's detail card for a form the corpus assigns no shape to.
  ///
  /// In en, this message translates to:
  /// **'{occurrences}× IN THE QUR’AN'**
  String root_cardWeight(int occurrences);

  /// The kicker inside screen 3a's detail card: the shape of the form on the dial and how often it is read.
  ///
  /// In en, this message translates to:
  /// **'FORM {form} · {occurrences}×'**
  String root_cardWeightWithForm(String form, int occurrences);

  /// The left button in screen 3a's detail card, which answers the reading screen with the aya the form is first met in.
  ///
  /// In en, this message translates to:
  /// **'Read the aya'**
  String get root_readTheAya;

  /// The right button in screen 3a's detail card while the root is not on the kept list.
  ///
  /// In en, this message translates to:
  /// **'Keep this root'**
  String get root_keepThisRoot;

  /// What that same button in screen 3a's detail card says once the root is kept.
  ///
  /// In en, this message translates to:
  /// **'Kept · tap to undo'**
  String get root_keptTapToUndo;

  /// Screen-reader label on the chevron at the top left of screens 3a and 2b.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get root_back;

  /// Screen-reader label on the bookmark at the top right of screens 3a and 2b while the root is not kept.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get root_keep;

  /// Screen-reader label on that same bookmark once the root is kept; it presses the same handler, so it says the press undoes.
  ///
  /// In en, this message translates to:
  /// **'Kept, tap to undo'**
  String get root_keptTapToUndoLabel;

  /// Heading over the sentence saying what a root means, on screens 3a, 2b, 1a's root panel and 1c.
  ///
  /// In en, this message translates to:
  /// **'Core sense'**
  String get root_coreSense;

  /// Drawn under the core sense heading for the two roots in three that ship no sense, so the absence reads as a refusal to claim and not as a missing section.
  ///
  /// In en, this message translates to:
  /// **'Wird writes a root\'s sense only where that root\'s own words in the Qur\'an bear it out. These do not, so nothing is claimed here.'**
  String get root_senseRefused;

  /// Under the core sense on screens 3a, 2b and 1c: whose reading the sentence above is, where it is the app's own. Ends in root_senseBorne, or in nothing.
  ///
  /// In en, this message translates to:
  /// **'This app\'s own reading{borne}'**
  String root_senseByApp(String borne);

  /// The same line where the sense does come from a named work. Ends in root_senseBorne, or in nothing.
  ///
  /// In en, this message translates to:
  /// **'{source}\'s reading{borne}'**
  String root_senseBySource(String source, String borne);

  /// The tail of that same line, naming how many of the root's own words the sense was read from. Tapping the line raises them.
  ///
  /// In en, this message translates to:
  /// **', borne out by {words} of the root\'s own words'**
  String root_senseBorne(int words);

  /// Heading in the sheet of evidence behind a core sense, over the paragraph saying why the sense is kept.
  ///
  /// In en, this message translates to:
  /// **'Whose reading this is'**
  String get root_whoseReading;

  /// Heading in that same sheet, over the root's own words the sense rests on.
  ///
  /// In en, this message translates to:
  /// **'The words it was read from'**
  String get root_wordsReadFrom;

  /// Beside that heading in the sheet of evidence: how many words the sense was read from.
  ///
  /// In en, this message translates to:
  /// **'{words} words'**
  String root_wordCount(int words);

  /// Under a word's gloss in the sheet of evidence, giving the shape that word is in.
  ///
  /// In en, this message translates to:
  /// **'FORM {form}'**
  String root_formTag(String form);

  /// Heading over the tafsir section where it is drawn with no aya named.
  ///
  /// In en, this message translates to:
  /// **'Tafsir'**
  String get root_tafsir;

  /// Heading over the tafsir section on screens 3a and 1c, naming the aya the commentary would be fetched for.
  ///
  /// In en, this message translates to:
  /// **'Tafsir · {ref}'**
  String root_tafsirAt(String ref);

  /// Under the tafsir heading and the works it will quote, saying plainly that it quotes none of them on this build.
  ///
  /// In en, this message translates to:
  /// **'Tafsir is fetched per aya. Nothing is downloaded yet, so nothing is attributed here.'**
  String get root_tafsirPending;

  /// Heading over the parsing of one word on screens 3a, 2b and 1c.
  ///
  /// In en, this message translates to:
  /// **'Iʿrāb'**
  String get root_irab;

  /// Beside the iʿrāb heading, naming the one occurrence being parsed — case and mood are the verse's, not the form's.
  ///
  /// In en, this message translates to:
  /// **'as read at {where}'**
  String root_irabAsReadAt(String where);

  /// Drawn under the iʿrāb heading where the corpus has no segments for the word, rather than leaving a gap that reads as an oversight.
  ///
  /// In en, this message translates to:
  /// **'The corpus carries no parsing for this word.'**
  String get root_noParsing;

  /// The last line of the iʿrāb section on screens 3a, 2b and 1c. {work} is the upstream corpus named and linked verbatim, which is what its licence asks for; the sentence around it is Wird's own.
  ///
  /// In en, this message translates to:
  /// **'Provenance: {work}; the role names are written for Wird'**
  String root_irabProvenance(String work);

  /// Beside the root's letters at the top of screen 2b: how it is read aloud, how often it occurs, and across how many sūras.
  ///
  /// In en, this message translates to:
  /// **'{translit} · {occurrences} in {suras} sūras'**
  String root_spineWeight(String translit, int occurrences, int suras);

  /// Heading over the provenance line at the foot of screen 2b.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get root_sourcesHeading;

  /// The provenance line under that heading. {sources} is the corpus the row itself names, carried verbatim from the data.
  ///
  /// In en, this message translates to:
  /// **'Provenance: {sources}'**
  String root_provenance(String sources);
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
