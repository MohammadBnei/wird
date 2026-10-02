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

  /// The index screen's title: every sūra of the Qur'an, listed in the reader's reading order.
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

  /// Under 'Go to …' in the index, when the search is a reference like 2:255: choosing it opens the reader on that aya.
  ///
  /// In en, this message translates to:
  /// **'Opens at this aya'**
  String get index_go_to_hint;

  /// Shown on the kept list in place of the cards when the reader has kept no aya; it names the control on the constellation screen that keeps one.
  ///
  /// In en, this message translates to:
  /// **'No ayas kept yet. “Keep this aya”, on the constellation of a word’s root, keeps one here.'**
  String get kept_empty_ayas;

  /// Shown on the kept list in place of the cards when the reader has no note.
  ///
  /// In en, this message translates to:
  /// **'No notes yet. Nothing in the app writes one yet; an aya and a root are kept without words.'**
  String get kept_empty_notes;

  /// Shown on the kept list in place of the cards when the reader has kept no root.
  ///
  /// In en, this message translates to:
  /// **'No roots kept yet. The keep icon on a root keeps one here.'**
  String get kept_empty_roots;

  /// First option of the segmented filter above the kept list's cards.
  ///
  /// In en, this message translates to:
  /// **'Ayas'**
  String get kept_filter_ayas;

  /// Third option of the segmented filter above the kept list's cards.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get kept_filter_notes;

  /// Second option of the segmented filter above the kept list's cards.
  ///
  /// In en, this message translates to:
  /// **'Roots'**
  String get kept_filter_roots;

  /// Kicker line at the top of a kept card the reader flagged to come back to; the screen draws it uppercased.
  ///
  /// In en, this message translates to:
  /// **'{at} · revisit'**
  String kept_kicker_revisit(String at);

  /// Kicker line at the top of a kept root's card; the screen draws it uppercased.
  ///
  /// In en, this message translates to:
  /// **'Root · {letters}'**
  String kept_kicker_root(String letters);

  /// Kicker line of a kept card whose aya reference is missing, where the kind stands in for it.
  ///
  /// In en, this message translates to:
  /// **'Aya'**
  String get kept_kind_aya;

  /// Kicker line of a kept note's card, which never carries an aya reference.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get kept_kind_note;

  /// Kicker line of a kept root's card that carries neither letters nor an aya reference.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get kept_kind_root;

  /// Right of a kept card's kicker: how long ago the item was kept, always two days or more.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String kept_meta_days_ago(int days);

  /// Right of a kept card's kicker: the root whose constellation surfaced the aya the reader flagged.
  ///
  /// In en, this message translates to:
  /// **'flagged for {letters}'**
  String kept_meta_flagged(String letters);

  /// Right of a kept root card's kicker: the aya the root was kept from, written surah:aya.
  ///
  /// In en, this message translates to:
  /// **'kept from {reference}'**
  String kept_meta_kept_from(String reference);

  /// Right of a kept card's kicker: the item was kept today.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get kept_meta_today;

  /// Right of a kept card's kicker: the item was kept yesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get kept_meta_yesterday;

  /// Shown on the kept list in place of the cards when the reader's search matches nothing they kept.
  ///
  /// In en, this message translates to:
  /// **'Nothing kept matches “{search}”.'**
  String kept_no_match(String search);

  /// Placeholder inside the kept list's search field, naming what the field searches.
  ///
  /// In en, this message translates to:
  /// **'Search ayas, roots, your words'**
  String get kept_search_hint;

  /// The kept list's own title, above its search field.
  ///
  /// In en, this message translates to:
  /// **'Kept'**
  String get kept_title;

  /// Why the play button is dark: the recitation for this set is not on the device.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get notDownloaded;

  /// Kicker at the top left of the prayer screen, drawn in capitals: which prayer, and which rakʿah of how many.
  ///
  /// In en, this message translates to:
  /// **'{prayer} · Rakʿah {rakah} of {count}'**
  String prayer_header(String prayer, int rakah, int count);

  /// Under the kicker on the prayer screen: the sūra being recited and the aya, as in 'Al-Fatihah · 1:4'.
  ///
  /// In en, this message translates to:
  /// **'{sura} · {ref}'**
  String prayer_part(String sura, String ref);

  /// The prayer's name when no preset was chosen: a sunna, a nafl, or a count the reader set.
  ///
  /// In en, this message translates to:
  /// **'Prayer'**
  String get prayer_generic;

  /// The dawn prayer, two rakʿahs.
  ///
  /// In en, this message translates to:
  /// **'Fajr'**
  String get prayer_fajr;

  /// The midday prayer, four rakʿahs.
  ///
  /// In en, this message translates to:
  /// **'Ẓuhr'**
  String get prayer_zuhr;

  /// The afternoon prayer, four rakʿahs.
  ///
  /// In en, this message translates to:
  /// **'ʿAṣr'**
  String get prayer_asr;

  /// The sunset prayer, three rakʿahs.
  ///
  /// In en, this message translates to:
  /// **'Maghrib'**
  String get prayer_maghrib;

  /// The night prayer, four rakʿahs.
  ///
  /// In en, this message translates to:
  /// **'ʿIshāʾ'**
  String get prayer_isha;

  /// Foot of the prayer screen: the voice is followed, and a steady pace takes over when it loses the reciter.
  ///
  /// In en, this message translates to:
  /// **'Voice, pace as fallback'**
  String get prayer_mode_both;

  /// Foot of the prayer screen, only once voice-follow is really running.
  ///
  /// In en, this message translates to:
  /// **'Following your voice'**
  String get prayer_mode_voice;

  /// Foot of the prayer screen: the text moves on its own at this many words a minute.
  ///
  /// In en, this message translates to:
  /// **'Steady · {wpm} wpm'**
  String prayer_mode_pace(int wpm);

  /// Foot of the prayer screen when nothing moves the text but the reader's own taps.
  ///
  /// In en, this message translates to:
  /// **'Tap to advance'**
  String get prayer_mode_tap;

  /// Bottom right of the prayer screen: which rakʿah of how many.
  ///
  /// In en, this message translates to:
  /// **'{rakah} of {count}'**
  String prayer_rakah_count(int rakah, int count);

  /// Over the screen between two rakʿahs, drawn in capitals: the rakʿah that comes next.
  ///
  /// In en, this message translates to:
  /// **'Rakʿah {rakah} of {count}'**
  String prayer_between(int rakah, int count);

  /// Between two rakʿahs, while the voice is followed: the next one starts when the reader recites Al-Fātiḥa, or on a tap.
  ///
  /// In en, this message translates to:
  /// **'Begins when you recite · or tap'**
  String get prayer_between_voice;

  /// Between two rakʿahs, with no voice: the next one starts on a tap.
  ///
  /// In en, this message translates to:
  /// **'Tap to begin'**
  String get prayer_between_tap;

  /// Over the screen for a moment after the last rakʿah, before the prayer closes.
  ///
  /// In en, this message translates to:
  /// **'Prayer complete'**
  String get prayer_complete;

  /// A brief chip while the reader pinches the Arabic: its new size, kept for the next prayer.
  ///
  /// In en, this message translates to:
  /// **'{size} px · remembered'**
  String prayer_size_remembered(int size);

  /// Screen-reader label for the wide tap zone when nothing else moves the text, where a tap moves on one word.
  ///
  /// In en, this message translates to:
  /// **'On to the next word'**
  String get prayer_on_a_word;

  /// Title of the screen where a prayer is set up before it begins.
  ///
  /// In en, this message translates to:
  /// **'Prepare prayer'**
  String get prepare_title;

  /// Kicker above the five prayer presets, drawn in capitals.
  ///
  /// In en, this message translates to:
  /// **'Prayer'**
  String get prepare_kicker_prayer;

  /// Label of the stepper for how many rakʿahs the prayer has.
  ///
  /// In en, this message translates to:
  /// **'Rakʿahs'**
  String get prepare_rakahs;

  /// Under the rakʿah stepper, when the count is the preset's own.
  ///
  /// In en, this message translates to:
  /// **'Set by {prayer}'**
  String prepare_rakahs_set_by(String prayer);

  /// Under the rakʿah stepper, when the reader changed the preset's count — a prayer shortened while travelling.
  ///
  /// In en, this message translates to:
  /// **'{prayer} is usually {count}'**
  String prepare_rakahs_usually(String prayer, int count);

  /// Under the rakʿah stepper, when no preset is chosen.
  ///
  /// In en, this message translates to:
  /// **'Any prayer, sunna or nafl'**
  String get prepare_rakahs_any;

  /// Screen-reader label for the minus of the rakʿah stepper.
  ///
  /// In en, this message translates to:
  /// **'Fewer rakʿahs'**
  String get prepare_fewer_rakahs;

  /// Screen-reader label for the plus of the rakʿah stepper.
  ///
  /// In en, this message translates to:
  /// **'More rakʿahs'**
  String get prepare_more_rakahs;

  /// Kicker above the rakʿah timeline, drawn in capitals.
  ///
  /// In en, this message translates to:
  /// **'What you recite'**
  String get prepare_kicker_recite;

  /// The line at the head of every rakʿah in the timeline: Al-Fātiḥa is always recited.
  ///
  /// In en, this message translates to:
  /// **'Al-Fātiḥa'**
  String get prepare_fatiha;

  /// The empty passage card of the first or second rakʿah.
  ///
  /// In en, this message translates to:
  /// **'Add a passage'**
  String get prepare_add_passage;

  /// Under 'Add a passage': leaving it empty is a choice too.
  ///
  /// In en, this message translates to:
  /// **'Or recite Al-Fātiḥa only'**
  String get prepare_fatiha_only_hint;

  /// A number of ayas, as in a passage card's meta line.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} aya} other{{count} ayas}}'**
  String prepare_ayas(int count);

  /// How long a passage takes at the chosen pace, under a minute.
  ///
  /// In en, this message translates to:
  /// **'about {seconds} s'**
  String prepare_about_seconds(int seconds);

  /// How long a passage takes at the chosen pace, a minute or more.
  ///
  /// In en, this message translates to:
  /// **'about {minutes} min'**
  String prepare_about_minutes(int minutes);

  /// Appended to the second rakʿah's meta line when it repeats the first's passage.
  ///
  /// In en, this message translates to:
  /// **'same as rakʿah 1'**
  String get prepare_same_as_first;

  /// Kicker above the voice and pace options, drawn in capitals.
  ///
  /// In en, this message translates to:
  /// **'How the text moves'**
  String get prepare_kicker_moves;

  /// Checkbox: the prayer follows the reader's recitation.
  ///
  /// In en, this message translates to:
  /// **'Follow my voice'**
  String get prepare_follow_voice;

  /// Under 'Follow my voice' when the microphone is allowed and the model downloaded.
  ///
  /// In en, this message translates to:
  /// **'Recogniser ready on this phone'**
  String get prepare_voice_ready;

  /// Under 'Follow my voice' when it cannot run yet; the checkbox is off and dark.
  ///
  /// In en, this message translates to:
  /// **'Allow the microphone and download the recogniser, below'**
  String get prepare_voice_setup;

  /// Checkbox: the text moves on by itself at a set number of words a minute.
  ///
  /// In en, this message translates to:
  /// **'Keep a steady pace'**
  String get prepare_steady_pace;

  /// Under 'Keep a steady pace': the pace.
  ///
  /// In en, this message translates to:
  /// **'{wpm} words a minute'**
  String prepare_wpm(int wpm);

  /// Screen-reader label for the pace's minus.
  ///
  /// In en, this message translates to:
  /// **'Slower'**
  String get prepare_slower;

  /// Screen-reader label for the pace's plus.
  ///
  /// In en, this message translates to:
  /// **'Faster'**
  String get prepare_faster;

  /// Note under the movement options when both are on.
  ///
  /// In en, this message translates to:
  /// **'Your voice leads. If the recogniser loses you, the text moves on at {wpm} words a minute until it finds you again.'**
  String prepare_note_both(int wpm);

  /// Note under the movement options when only the voice is on.
  ///
  /// In en, this message translates to:
  /// **'The text waits for your voice. Each rakʿah begins when you start reciting.'**
  String get prepare_note_voice;

  /// Note under the movement options when only the pace is on.
  ///
  /// In en, this message translates to:
  /// **'The text moves at {wpm} words a minute. Each rakʿah begins on a tap.'**
  String prepare_note_pace(int wpm);

  /// Note under the movement options when both are off.
  ///
  /// In en, this message translates to:
  /// **'Neither is on: tap the screen to move to the next word.'**
  String get prepare_note_neither;

  /// Kicker above the display options, drawn in capitals.
  ///
  /// In en, this message translates to:
  /// **'On screen'**
  String get prepare_kicker_screen;

  /// Switch: the gloss of the word being recited, under the aya.
  ///
  /// In en, this message translates to:
  /// **'Meaning of the current word'**
  String get prepare_gloss;

  /// Switch: the ayas either side of the one being recited.
  ///
  /// In en, this message translates to:
  /// **'Previous and next aya, faded'**
  String get prepare_around;

  /// Row showing the prayer screen's Arabic size.
  ///
  /// In en, this message translates to:
  /// **'Arabic size'**
  String get prepare_size;

  /// Under 'Arabic size'.
  ///
  /// In en, this message translates to:
  /// **'Pinch on the prayer screen to change it'**
  String get prepare_size_hint;

  /// The Arabic size, in pixels.
  ///
  /// In en, this message translates to:
  /// **'{size} px'**
  String prepare_size_px(int size);

  /// Row reminding the reader to silence the phone; the app cannot do it for them.
  ///
  /// In en, this message translates to:
  /// **'Silence notifications'**
  String get prepare_silence;

  /// Under 'Silence notifications'.
  ///
  /// In en, this message translates to:
  /// **'Turn on Do Not Disturb or a Focus before you begin'**
  String get prepare_silence_hint;

  /// Button opening a looping preview of a rakʿah before the prayer.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get prepare_preview;

  /// The button that starts the prayer.
  ///
  /// In en, this message translates to:
  /// **'Begin {prayer}'**
  String prepare_begin(String prayer);

  /// Title of the passage chooser.
  ///
  /// In en, this message translates to:
  /// **'Choose a passage'**
  String get chooser_title;

  /// Under the chooser's title: which rakʿah the passage is for.
  ///
  /// In en, this message translates to:
  /// **'Rakʿah {rakah} · after Al-Fātiḥa'**
  String chooser_rakah(int rakah);

  /// Placeholder of the chooser's search field.
  ///
  /// In en, this message translates to:
  /// **'Search a sūra, or type 2:255'**
  String get chooser_search;

  /// A row offered when the search is a reference like 2:255.
  ///
  /// In en, this message translates to:
  /// **'Go to {ref}'**
  String chooser_go_to(String ref);

  /// Under 'Go to …'.
  ///
  /// In en, this message translates to:
  /// **'Starts at this aya; you can widen it next'**
  String get chooser_go_to_hint;

  /// Kicker above the chooser's suggestions, drawn in capitals.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get chooser_suggested;

  /// Suggestion for the second rakʿah: repeat the first's passage.
  ///
  /// In en, this message translates to:
  /// **'Same as rakʿah 1'**
  String get chooser_same;

  /// Suggestion: the next unread passage.
  ///
  /// In en, this message translates to:
  /// **'Continue where you left off'**
  String get chooser_continue;

  /// Under a suggestion that was recited in an earlier prayer.
  ///
  /// In en, this message translates to:
  /// **'Recently recited'**
  String get chooser_recent;

  /// Suggestion: no passage in this rakʿah.
  ///
  /// In en, this message translates to:
  /// **'Al-Fātiḥa only'**
  String get chooser_fatiha_only;

  /// Under 'Al-Fātiḥa only'.
  ///
  /// In en, this message translates to:
  /// **'No passage in this rakʿah'**
  String get chooser_fatiha_only_hint;

  /// Kicker above the full sūra list, drawn in capitals.
  ///
  /// In en, this message translates to:
  /// **'All sūras'**
  String get chooser_all;

  /// Shown when the search finds nothing.
  ///
  /// In en, this message translates to:
  /// **'No sūra matches “{query}”.'**
  String chooser_no_match(String query);

  /// The sūra at the top of the range step, as its number and name.
  ///
  /// In en, this message translates to:
  /// **'{number} · {name}'**
  String range_sura(int number, String name);

  /// On the sūra card at the top of the range: goes back to the list of sūras.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get range_change_sura;

  /// Above the grid of aya numbers.
  ///
  /// In en, this message translates to:
  /// **'Tap the first aya, then the last.'**
  String get range_tap_hint;

  /// Chip setting the range to the whole sūra.
  ///
  /// In en, this message translates to:
  /// **'Whole sūra'**
  String get range_whole;

  /// End of the range card's meta line.
  ///
  /// In en, this message translates to:
  /// **'{count} ayas in the sūra'**
  String range_in_sura(int count);

  /// Button choosing this range for the rakʿah.
  ///
  /// In en, this message translates to:
  /// **'Recite {title}'**
  String range_recite(String title);

  /// Tab in the preview sheet choosing which rakʿah to preview.
  ///
  /// In en, this message translates to:
  /// **'R{rakah}'**
  String preview_rakah(int rakah);

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

  /// A door on the dashboard to the prayer's preparation, without a set in hand.
  ///
  /// In en, this message translates to:
  /// **'Prepare a prayer'**
  String get dashboard_doorPray;

  /// Under 'Prepare a prayer'.
  ///
  /// In en, this message translates to:
  /// **'Any passage, any number of rakʿahs'**
  String get dashboard_doorPrayWhy;

  /// The subtitle under the kept row on home.
  ///
  /// In en, this message translates to:
  /// **'The ayas and roots you saved'**
  String get dashboard_doorKeptWhy;

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

  /// Reading screen, the unfolded root panel: opens the deep dive on this aya and this root.
  ///
  /// In en, this message translates to:
  /// **'Constellation'**
  String get study_constellation;

  /// Reading screen, the right chevron in the root panel: it opens the word after the one the panel is showing. Screen-reader label.
  ///
  /// In en, this message translates to:
  /// **'Next word'**
  String get study_nextWord;

  /// Reading screen transport: why the play button is dark when the corpus ships no recitation for these ayas at all, as against notDownloaded, which is one that could still arrive.
  ///
  /// In en, this message translates to:
  /// **'No recitation for this set'**
  String get study_noRecitation;

  /// Reading screen, the left chevron in the root panel: it opens the word before the one the panel is showing. Screen-reader label. It says word rather than set because the footer a band below steps by the set.
  ///
  /// In en, this message translates to:
  /// **'Previous word'**
  String get study_previousWord;

  /// Reading screen root panel, under a word the arrows walked onto that has no root — a particle or a proper noun. It names this one word, unlike study_noRootInSet, which is about the whole set.
  ///
  /// In en, this message translates to:
  /// **'No root'**
  String get study_wordHasNoRoot;

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

  /// Drawn under the core sense heading for a root the fetched pack of senses carries none for, so the absence reads as work not yet done and not as a missing section. Its old wording claimed the sense had been refused because the root's own words in the Qur'an did not bear one out, which was the corpus-derivation standard the served drafts were not written to (ADR 0010).
  ///
  /// In en, this message translates to:
  /// **'The senses are Wird\'s own and they are written one root at a time. None has been written for this root yet. When one is, it reaches this phone without waiting for a new version of the app.'**
  String get root_senseRefused;

  /// The other half of root_senseRefused, drawn under the core sense heading when this device has never fetched a pack of senses at all. One string for both states told a reader who has never had a signal that nobody had written a sense, on every root in the corpus.
  ///
  /// In en, this message translates to:
  /// **'The senses are not part of the download. They are fetched, so a sense can be corrected without a new version of the app — and this phone has not fetched any yet. Settings carries the button.'**
  String get root_senseNotFetched;

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

  /// The heading at the top of the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section heading on the settings screen, over the choice of which language the app and the root senses are read in.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get settingsLanguage;

  /// First option of the settings screen's language control. Written in English in both locales, because a language is named in itself.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Second option of the settings screen's language control. Written in French in both locales, because a language is named in itself.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get settingsLanguageFrench;

  /// Caption under the settings screen's language control, saying what the choice reaches and why a sense can still come up in English.
  ///
  /// In en, this message translates to:
  /// **'The screen and a root\'s sense. The senses were written in English and translated, so a root whose French never arrived is read in English.'**
  String get settingsLanguageCaption;

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

  /// Settings: show each aya's translation under it on the reading screen.
  ///
  /// In en, this message translates to:
  /// **'Aya translated'**
  String get settingsAyaTranslationShown;

  /// Settings: draw no translation under the ayas, only the words and their glosses.
  ///
  /// In en, this message translates to:
  /// **'Arabic only'**
  String get settingsAyaTranslationHidden;

  /// Caption under the aya translation setting: whose translation is shown, by language.
  ///
  /// In en, this message translates to:
  /// **'Pickthall\'s English or Rashid Maash\'s French, under each aya.'**
  String get settingsAyaTranslationCaption;

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

  /// Caption under the settings screen's list of reciters. The reader picks whose voice the audio is in; the word highlight follows that recording's own timings.
  ///
  /// In en, this message translates to:
  /// **'Whose voice recites the set and each word you tap. Words are highlighted in time with this reciter.'**
  String get settingsReciterCaption;

  /// Under a reciter's name in settings: what the Muallim (teaching) style is for.
  ///
  /// In en, this message translates to:
  /// **'Muʿallim · slow and clear, for learning'**
  String get settingsStyleMuallim;

  /// Under a reciter's name in settings: the Murattal style, the usual one, left unexplained so the one row that differs (Muallim) stands out.
  ///
  /// In en, this message translates to:
  /// **'Murattal'**
  String get settingsStyleMurattal;

  /// Tooltip of the button that stops a reciter's sample in settings.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get settingsStopSample;

  /// Tooltip of the button that plays a short sample of a reciter in settings. The name is a person's and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Hear {reciter}'**
  String settingsHearReciter(String reciter);

  /// Settings option: a tapped word plays as its stretch of the chosen reciter's aya recording.
  ///
  /// In en, this message translates to:
  /// **'From the reciter'**
  String get settingsWordFromReciter;

  /// Settings option: a tapped word plays its own recording, spoken alone by quran.com's word-by-word voice.
  ///
  /// In en, this message translates to:
  /// **'Each word alone'**
  String get settingsWordAlone;

  /// Caption under the choice of what a tapped word plays.
  ///
  /// In en, this message translates to:
  /// **'What a tapped word plays: its moment in the reciter\'s aya, or the word spoken on its own, in one voice for every word.'**
  String get settingsWordVoiceCaption;

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

  /// Section heading on the settings screen over the senses panel.
  ///
  /// In en, this message translates to:
  /// **'SENSES'**
  String get settingsSenses;

  /// The button on the settings screen that fetches the senses the server is offering and writes them into this phone's database. No size on it: the button is pressed for a correction that is already on offer, and the number the reader would weigh is the one they cannot see.
  ///
  /// In en, this message translates to:
  /// **'Download the senses'**
  String get settingsDownloadSenses;

  /// The button that repeats the check on the settings screen after the server could not be reached. Without it the only retry is leaving the screen and coming back, which nothing on the screen says.
  ///
  /// In en, this message translates to:
  /// **'Ask again'**
  String get settingsSensesAskAgain;

  /// Caption under the senses panel while the check is in flight.
  ///
  /// In en, this message translates to:
  /// **'Asking the server whether there is anything new.'**
  String get settingsSensesAsking;

  /// Caption under the senses panel when the server is offering a pack this device does not hold.
  ///
  /// In en, this message translates to:
  /// **'There are senses on the server this phone does not have. They are a few hundred kilobytes; nothing downloads until you press.'**
  String get settingsSensesOnOffer;

  /// Caption under the senses panel while the pack is being fetched and written.
  ///
  /// In en, this message translates to:
  /// **'Downloading. Nothing already on the phone is replaced until all of it has arrived.'**
  String get settingsSensesInstalling;

  /// Caption under the senses panel when there is nothing on offer, which is also what a reader sees straight after a download. It restates the provenance rather than saying only that the phone is up to date, because this screen is the one place the whole pack is talked about.
  ///
  /// In en, this message translates to:
  /// **'This phone has the senses the server is serving. A sense is Wird\'s own reading, written by a machine and read by no person; the line under each one says so, and the thumb beside it is how a wrong one gets corrected.'**
  String get settingsSensesCurrent;

  /// Caption under the senses panel when the check or the download failed to reach the server. It says "did not answer" rather than "could not be reached", which is settingsMicUnavailable's wording: the two captions are drawn on the same screen and a test looking for one found both.
  ///
  /// In en, this message translates to:
  /// **'The server did not answer, so whether there are new senses is unknown. Every sense already on the phone is still here, and the app reads with no network.'**
  String get settingsSensesUnreachable;

  /// Caption under the senses panel when the pack was refused because it and the bundled corpus disagree about what a root is called. The install rolled back, so the reader still has whatever they had.
  ///
  /// In en, this message translates to:
  /// **'The senses that arrived name no root this copy of the Qur\'an records, so none of them could ever be read. Nothing was changed on the phone.'**
  String get settingsSensesNotThisCorpus;

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
  /// **'word {word} at {score}% but somewhere else fits {rival}%'**
  String settingsVoiceCheckAmbiguous(int word, int score, int rival);

  /// Voice check: the phrase heard is repeated in the set and order cannot choose.
  ///
  /// In en, this message translates to:
  /// **'word {word} at {score}%, but the set says this more than once and no copy is just ahead'**
  String settingsVoiceCheckRepeat(int word, int score);

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

  /// A parked write: the reading position in one sūra, sent to the reader's other devices.
  ///
  /// In en, this message translates to:
  /// **'Where you are in a sūra'**
  String get settingsParkedPosition;

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

  /// Who rendered the aya, shown under the translation: Pickthall in English, Rashid Maash in French.
  ///
  /// In en, this message translates to:
  /// **'Pickthall'**
  String get study_ayaTranslated;

  /// Said once above the reading, where the aya is translated: whose the per-word glosses are, and that a few stay English.
  ///
  /// In en, this message translates to:
  /// **'The meanings under each word are from The Last Dialogue; the few words it does not cover keep their English.'**
  String get study_glossesSource;

  /// Shown once a verdict has been recorded.
  ///
  /// In en, this message translates to:
  /// **'Noted — thank you.'**
  String get root_senseJudgeThanks;

  /// Screen-reader label for the yes control.
  ///
  /// In en, this message translates to:
  /// **'This sense is right'**
  String get root_senseJudgeGoodLabel;

  /// Screen-reader label for the no control.
  ///
  /// In en, this message translates to:
  /// **'This sense is wrong'**
  String get root_senseJudgeBadLabel;

  /// The drawer's row for the home screen.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get nav_home;

  /// The drawer's row for the reading screen, which shows the set being read.
  ///
  /// In en, this message translates to:
  /// **'The set'**
  String get nav_theSet;

  /// The drawer's row for the sources and licences screen.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get nav_sources;

  /// The button in the bar at the foot of every screen that silences what is sounding.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get shell_stop;

  /// The eyebrow of the bar at the foot of every screen while a single word is being sounded.
  ///
  /// In en, this message translates to:
  /// **'SOUNDING ONE WORD'**
  String get shell_soundingWord;

  /// The eyebrow of the bar at the foot of every screen while one aya is recited on its own.
  ///
  /// In en, this message translates to:
  /// **'RECITING ONE AYA'**
  String get shell_recitingAya;

  /// Tooltip of the play button beside the open aya's reference, which recites that one aya alone.
  ///
  /// In en, this message translates to:
  /// **'Recite this aya'**
  String get study_reciteAya;

  /// The eyebrow of the bar at the foot of every screen while the whole set is being recited.
  ///
  /// In en, this message translates to:
  /// **'RECITING THE SET'**
  String get shell_recitingSet;

  /// The eyebrow at the head of the drawer, over the app's name.
  ///
  /// In en, this message translates to:
  /// **'NOT SIGNED IN'**
  String get shell_notSignedIn;

  /// The sentence under the app's name at the head of the drawer.
  ///
  /// In en, this message translates to:
  /// **'Everything you have read and kept is on this phone. Accounts arrive with the server they sync to.'**
  String get shell_drawerBlurb;

  /// The only thing on screen when the bundled corpus fails to open at launch. `error` is the raw error, untranslated.
  ///
  /// In en, this message translates to:
  /// **'The corpus would not open.\n\n{error}'**
  String appCorpusWouldNotOpen(String error);

  /// The kicker on The Last Dialogue card of the sources screen: what of the app would be missing without it.
  ///
  /// In en, this message translates to:
  /// **'French word-by-word gloss'**
  String get aboutProvidesFrenchGloss;

  /// The licence tag on the Tanzil Project card of the sources screen. Tanzil's terms have no title, so this describes them.
  ///
  /// In en, this message translates to:
  /// **'Verbatim copies, attributed'**
  String get aboutLicenceVerbatim;

  /// The licence tag on the Nocturne card of the sources screen: the design system was written for this app.
  ///
  /// In en, this message translates to:
  /// **'Authored for Wird'**
  String get aboutLicenceAuthored;

  /// The licence tag on the recitation card of the sources screen. The archive publishes no terms, so this says how the recording is used instead.
  ///
  /// In en, this message translates to:
  /// **'Fetched at playback, never redistributed'**
  String get aboutLicenceFetched;

  /// The licence tag on The Last Dialogue card of the sources screen: the use was granted by email rather than under a published licence.
  ///
  /// In en, this message translates to:
  /// **'Used by permission'**
  String get aboutLicencePermission;

  /// The body of the Quranic Arabic Corpus card of the sources screen: what it provides and the conditions it is used on.
  ///
  /// In en, this message translates to:
  /// **'Every root a word opens into comes from here. Verbatim copies only — changing the annotation is not allowed. Used on the condition that its source is clearly indicated and a link is made to corpus.quran.com, so you can keep track of what has changed since this build.'**
  String get aboutTermsCorpus;

  /// The body of the Tanzil Project card of the sources screen.
  ///
  /// In en, this message translates to:
  /// **'The verified Uthmani text every aya is painted from, which the Quranic Arabic Corpus also builds on. Copied verbatim; changing the text is not allowed. Linked so you can keep track of changes.'**
  String get aboutTermsTanzil;

  /// The body of the Quran Foundation card of the sources screen. The French adds that a French reader sees The Last Dialogue's glosses, with the English only as the fallback.
  ///
  /// In en, this message translates to:
  /// **'The English under each word, served by the quran.com API. Their terms allow an application to show this content but not to store it indefinitely without a weekly re-sync, which a bundled corpus does not do. Unsettled, and recorded as unsettled.'**
  String get aboutTermsQuranFoundation;

  /// The body of The Last Dialogue card of the sources screen.
  ///
  /// In en, this message translates to:
  /// **'The French under each word, for a reader who reads Wird in French. The site marks its word-by-word as in beta. They granted Wird its use by email on 30 September 2026 without requiring attribution; Wird names them anyway, because it names every source.'**
  String get aboutTermsLastDialogue;

  /// The body of the Nocturne card of the sources screen.
  ///
  /// In en, this message translates to:
  /// **'The design system every screen is drawn from. Dark only; there is no light mode.'**
  String get aboutTermsNocturne;

  /// The body of the Scheherazade New card of the sources screen. Feminine in French: it agrees with « police ».
  ///
  /// In en, this message translates to:
  /// **'Bundled unmodified, because platform Arabic faces mangle Qurʼanic diacritics.'**
  String get aboutTermsScheherazade;

  /// The body of the Inter card of the sources screen. Feminine in French: it agrees with « police ».
  ///
  /// In en, this message translates to:
  /// **'Bundled unmodified.'**
  String get aboutTermsInter;

  /// The body of the quran-align card of the sources screen. CC BY 4.0 requires that changes be indicated, which is what the reindexing sentence does; keep it in every locale.
  ///
  /// In en, this message translates to:
  /// **'The millisecond each word is spoken at, which is what lets a word light up as you hear it. From github.com/cpfair/quran-align, aligned against this same muʿallim recording. Reindexed for this app: the published data is zero-based and end-exclusive, and it is stored here one-based against the word it belongs to. Offered as-is, without warranties.'**
  String get aboutTermsTimings;

  /// The body of the recitation card of the sources screen.
  ///
  /// In en, this message translates to:
  /// **'The muʿallim recording is downloaded by your device from everyayah.com when you press play, the way a browser loads a page, and cached on your phone. Wird does not bundle it, mirror it, or serve it. The archive publishes no terms of use, so nothing here is offered as permission to redistribute it — and that is why this app never does.'**
  String get aboutTermsRecitation;

  /// The body of the recogniser card of the sources screen. Its licence requires an app built on it to say that automatic tajwīd feedback can be wrong and does not replace a qualified teacher; keep both in every locale.
  ///
  /// In en, this message translates to:
  /// **'The recogniser that hears your recitation, downloaded on your word and run on this phone; nothing you say is sent anywhere. It writes Qurʼanic phonemes, including the marks of tajwīd. Wird uses that only to find where in the set you are, and never to judge how you recited: automatic tajwīd feedback can be wrong, and no software here or anywhere replaces a qualified teacher. Its licence forbids charging for the model or for any feature it powers, which Wird does not and will not do.'**
  String get aboutTermsVoice;

  /// The body of the first card of the sources screen, Wird's own terms. The licence title stays in English: it is the licence's own name.
  ///
  /// In en, this message translates to:
  /// **'Wird is free software under the GNU Affero General Public License, version 3 or later. AGPL rather than GPL because Wird has a server: anyone running it as a service owes its users the source of what they are running.'**
  String get aboutSelfTerms;

  /// Screen-reader label of the root sheet's handle while the sūra fills the top half.
  ///
  /// In en, this message translates to:
  /// **'Show counts, forms and other ayas'**
  String get study_expandSheet;

  /// Screen-reader label of the root sheet's handle while it fills the screen.
  ///
  /// In en, this message translates to:
  /// **'Show the whole sūra again'**
  String get study_collapseSheet;

  /// Small heading over the numbered senses of the root.
  ///
  /// In en, this message translates to:
  /// **'Senses'**
  String get study_senses;

  /// Under a word that has no root, at the foot of the root sheet.
  ///
  /// In en, this message translates to:
  /// **'Particles and pronouns have no three-letter root. Swipe on to the next word.'**
  String get study_particleNote;

  /// The row that opens the lower part of the root sheet.
  ///
  /// In en, this message translates to:
  /// **'Counts, forms, other ayas'**
  String get study_moreRow;

  /// Heading over the three count tiles.
  ///
  /// In en, this message translates to:
  /// **'Across the Qur\'an'**
  String get study_acrossQuran;

  /// Under the number of words in the Qur'an built on this root.
  ///
  /// In en, this message translates to:
  /// **'this root'**
  String get study_countRoot;

  /// Before the Arabic of the word's lemma, under the number of times that lemma is read.
  ///
  /// In en, this message translates to:
  /// **'as'**
  String get study_countLemma;

  /// Under the number of words of the sūra on screen built on this root.
  ///
  /// In en, this message translates to:
  /// **'in this sūra'**
  String get study_countSurah;

  /// Caption under the ring of the root's lemmas.
  ///
  /// In en, this message translates to:
  /// **'Its forms, and how often each is read'**
  String get study_ringCaption;

  /// Heading over the list of other ayas the root is read in.
  ///
  /// In en, this message translates to:
  /// **'Other ayas'**
  String get study_otherAyas;

  /// Top right of the reading screen: the aya and word open, and where that word falls in the sūra.
  ///
  /// In en, this message translates to:
  /// **'{ref} · word {n}/{total}'**
  String study_position(String ref, int n, int total);

  /// Button that leaves another aya and returns to the reading position.
  ///
  /// In en, this message translates to:
  /// **'Back to {ref}'**
  String study_backTo(String ref);

  /// Under another aya: opens that aya's sūra at that aya.
  ///
  /// In en, this message translates to:
  /// **'Read this sūra from here'**
  String get study_readFromHere;

  /// App bar action on the reading screen: pray the ayas around the one open.
  ///
  /// In en, this message translates to:
  /// **'Pray'**
  String get study_pray;

  /// Screen-reader label of the play button in the reading screen's app bar.
  ///
  /// In en, this message translates to:
  /// **'Recite'**
  String get study_recite;

  /// Screen-reader label of the play button while it is reciting.
  ///
  /// In en, this message translates to:
  /// **'Pause the recitation'**
  String get study_pauseRecitation;

  /// Screen-reader label of an aya's number circle, which marks the aya understood.
  ///
  /// In en, this message translates to:
  /// **'Mark aya {ref} understood'**
  String study_markUnderstood(String ref);

  /// Screen-reader label of the root letters in the reading screen's sheet, which open the root's own screen.
  ///
  /// In en, this message translates to:
  /// **'Open the root {root}'**
  String study_openRoot(String root);

  /// Home: heading over the sūras the reader is part-way through, each opening where they stopped.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE READING'**
  String get dashboard_continueReading;

  /// Small heading in the reading screen's sheet over the word's parsing: its part of speech and features, as the corpus reads this occurrence.
  ///
  /// In en, this message translates to:
  /// **'Form'**
  String get study_form;

  /// On the prepare screen when the database did not answer.
  ///
  /// In en, this message translates to:
  /// **'The Qur\'an could not be read on this device. Try again; if it keeps failing, close Wird and open it again.'**
  String get prepare_trouble;

  /// Button under prepare_trouble.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get prepare_retry;
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
