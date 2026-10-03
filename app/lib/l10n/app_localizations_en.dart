// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get index_kicker => 'THE WHOLE QUR’AN';

  @override
  String get index_title => 'All 114';

  @override
  String get index_hint => 'A sūra opens at its first aya. The arrow picks one inside it.';

  @override
  String index_revealed_nth(String order) {
    return '$order to be revealed';
  }

  @override
  String index_pick_aya(String sura) {
    return 'Pick an aya of $sura';
  }

  @override
  String get index_go_to_hint => 'Opens at this aya';

  @override
  String get kept_empty_ayas => 'No ayas kept yet. “Keep this aya”, on the constellation of a word’s root, keeps one here.';

  @override
  String get kept_empty_notes => 'No notes yet. Nothing in the app writes one yet; an aya and a root are kept without words.';

  @override
  String get kept_empty_roots => 'No roots kept yet. The keep icon on a root keeps one here.';

  @override
  String get kept_filter_ayas => 'Ayas';

  @override
  String get kept_filter_notes => 'Notes';

  @override
  String get kept_filter_roots => 'Roots';

  @override
  String kept_kicker_revisit(String at) {
    return '$at · revisit';
  }

  @override
  String kept_kicker_root(String letters) {
    return 'Root · $letters';
  }

  @override
  String get kept_kind_aya => 'Aya';

  @override
  String get kept_kind_note => 'Note';

  @override
  String get kept_kind_root => 'Root';

  @override
  String kept_meta_days_ago(int days) {
    return '$days days ago';
  }

  @override
  String kept_meta_flagged(String letters) {
    return 'flagged for $letters';
  }

  @override
  String kept_meta_kept_from(String reference) {
    return 'kept from $reference';
  }

  @override
  String get kept_meta_today => 'today';

  @override
  String get kept_meta_yesterday => 'yesterday';

  @override
  String kept_no_match(String search) {
    return 'Nothing kept matches “$search”.';
  }

  @override
  String get kept_search_hint => 'Search ayas, roots, your words';

  @override
  String get kept_title => 'Kept';

  @override
  String prayer_header(String prayer, int rakah, int count) {
    return '$prayer · Rakʿah $rakah of $count';
  }

  @override
  String prayer_part(String sura, String ref) {
    return '$sura · $ref';
  }

  @override
  String get prayer_generic => 'Prayer';

  @override
  String get prayer_fajr => 'Fajr';

  @override
  String get prayer_zuhr => 'Ẓuhr';

  @override
  String get prayer_asr => 'ʿAṣr';

  @override
  String get prayer_maghrib => 'Maghrib';

  @override
  String get prayer_isha => 'ʿIshāʾ';

  @override
  String get prayer_mode_both => 'Voice, pace as fallback';

  @override
  String get prayer_mode_voice => 'Following your voice';

  @override
  String prayer_mode_pace(int wpm) {
    return 'Steady · $wpm wpm';
  }

  @override
  String get prayer_mode_tap => 'Tap to advance';

  @override
  String prayer_rakah_count(int rakah, int count) {
    return '$rakah of $count';
  }

  @override
  String prayer_between(int rakah, int count) {
    return 'Rakʿah $rakah of $count';
  }

  @override
  String get prayer_between_voice => 'Begins when you recite · or tap';

  @override
  String get prayer_between_tap => 'Tap to begin';

  @override
  String get prayer_complete => 'Prayer complete';

  @override
  String prayer_size_remembered(int size) {
    return '$size px · remembered';
  }

  @override
  String get prayer_on_a_word => 'On to the next word';

  @override
  String get prepare_title => 'Prepare prayer';

  @override
  String get prepare_kicker_prayer => 'Prayer';

  @override
  String get prepare_rakahs => 'Rakʿahs';

  @override
  String prepare_rakahs_set_by(String prayer) {
    return 'Set by $prayer';
  }

  @override
  String prepare_rakahs_usually(String prayer, int count) {
    return '$prayer is usually $count';
  }

  @override
  String get prepare_rakahs_any => 'Any prayer, sunna or nafl';

  @override
  String get prepare_fewer_rakahs => 'Fewer rakʿahs';

  @override
  String get prepare_more_rakahs => 'More rakʿahs';

  @override
  String get prepare_kicker_recite => 'What you recite';

  @override
  String get prepare_fatiha => 'Al-Fātiḥa';

  @override
  String get prepare_add_passage => 'Add a passage';

  @override
  String get prepare_fatiha_only_hint => 'Or recite Al-Fātiḥa only';

  @override
  String prepare_ayas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas',
      one: '$count aya',
    );
    return '$_temp0';
  }

  @override
  String prepare_about_seconds(int seconds) {
    return 'about $seconds s';
  }

  @override
  String prepare_about_minutes(int minutes) {
    return 'about $minutes min';
  }

  @override
  String get prepare_same_as_first => 'same as rakʿah 1';

  @override
  String get prepare_kicker_moves => 'How the text moves';

  @override
  String get prepare_follow_voice => 'Follow my voice';

  @override
  String get prepare_voice_ready => 'Recogniser ready on this phone';

  @override
  String get prepare_voice_setup => 'Allow the microphone and download the recogniser, below';

  @override
  String get prepare_steady_pace => 'Keep a steady pace';

  @override
  String prepare_wpm(int wpm) {
    return '$wpm words a minute';
  }

  @override
  String get prepare_slower => 'Slower';

  @override
  String get prepare_faster => 'Faster';

  @override
  String prepare_note_both(int wpm) {
    return 'Your voice leads. If the recogniser loses you, the text moves on at $wpm words a minute until it finds you again.';
  }

  @override
  String get prepare_note_voice => 'The text waits for your voice. Each rakʿah begins when you start reciting.';

  @override
  String prepare_note_pace(int wpm) {
    return 'The text moves at $wpm words a minute. Each rakʿah begins on a tap.';
  }

  @override
  String get prepare_note_neither => 'Neither is on: tap the screen to move to the next word.';

  @override
  String get prepare_kicker_screen => 'On screen';

  @override
  String get prepare_gloss => 'Meaning of the current word';

  @override
  String get prepare_around => 'Previous and next aya, faded';

  @override
  String get prepare_size => 'Arabic size';

  @override
  String get prepare_size_hint => 'Pinch on the prayer screen to change it';

  @override
  String prepare_size_px(int size) {
    return '$size px';
  }

  @override
  String get prepare_silence => 'Silence notifications';

  @override
  String get prepare_silence_hint => 'Turn on Do Not Disturb or a Focus before you begin';

  @override
  String get prepare_preview => 'Preview';

  @override
  String prepare_begin(String prayer) {
    return 'Begin $prayer';
  }

  @override
  String get chooser_title => 'Choose a passage';

  @override
  String chooser_rakah(int rakah) {
    return 'Rakʿah $rakah · after Al-Fātiḥa';
  }

  @override
  String get chooser_search => 'Sūra, 2:255, or words';

  @override
  String get picker_clear => 'Clear the search';

  @override
  String get picker_mushaf => 'Muṣḥaf';

  @override
  String get picker_revelation => 'Revelation';

  @override
  String picker_juz(int juz) {
    return 'Juzʾ $juz';
  }

  @override
  String get picker_makki => 'Makkī';

  @override
  String get picker_madani => 'Madanī';

  @override
  String picker_sura_sub(int count, String place) {
    return '$count ayas · $place';
  }

  @override
  String picker_mushaf_n(int number) {
    return 'Muṣḥaf $number';
  }

  @override
  String get picker_suras => 'Sūras';

  @override
  String picker_containing(String query) {
    return 'Ayas containing “$query”';
  }

  @override
  String picker_root(String root, String translit) {
    return 'Root $root · $translit';
  }

  @override
  String chooser_go_to(String ref) {
    return 'Go to $ref';
  }

  @override
  String get chooser_go_to_hint => 'Starts at this aya; you can widen it next';

  @override
  String get chooser_same => 'Same as rakʿah 1';

  @override
  String get chooser_continue => 'Continue';

  @override
  String get chooser_left_off => 'Where you left off';

  @override
  String chooser_after(int rakah) {
    return 'After rakʿah $rakah';
  }

  @override
  String chooser_follows(String title) {
    return 'Follows $title';
  }

  @override
  String get chooser_recent => 'Recent';

  @override
  String get chooser_fatiha_only => 'Al-Fātiḥa only';

  @override
  String get chooser_fatiha_only_hint => 'No passage in this rakʿah';

  @override
  String chooser_all(String order) {
    return 'All sūras · $order';
  }

  @override
  String get picker_order_mushaf => 'Muṣḥaf order';

  @override
  String get picker_order_revelation => 'revelation order';

  @override
  String chooser_no_match(String query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String range_about(int count, String place, String order) {
    return '$count ayas · $place · $order of 114 revealed';
  }

  @override
  String get range_tap_hint => 'Tap the first aya, then the last';

  @override
  String get range_last_hint => 'Now tap the last aya';

  @override
  String range_meta(int count, String time, int juz) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas',
      one: '1 aya',
    );
    return '$_temp0 · $time · Juzʾ $juz';
  }

  @override
  String get range_overview => 'Jump to a point in the sūra';

  @override
  String get range_three => '3 ayas';

  @override
  String get range_minute => '~1 min';

  @override
  String get range_whole => 'Whole sūra';

  @override
  String range_recite(String title) {
    return 'Recite $title';
  }

  @override
  String preview_rakah(int rakah) {
    return 'R$rakah';
  }

  @override
  String get prayer_exit => 'Exit';

  @override
  String get prayer_back_an_aya => 'Back an aya';

  @override
  String get prayer_on_to_the_next_aya => 'On to the next aya';

  @override
  String get progress_kicker => 'UNDERSTOOD, NOT MERELY READ';

  @override
  String get progress_title => 'Your passage';

  @override
  String progress_ayas(String understood, String total) {
    return '$understood of $total ayas';
  }

  @override
  String progress_ringSemantics(String percent, String ayas, int juz, int set) {
    return '$percent of the Qur\'an understood, $ayas. Juz $juz, set $set.';
  }

  @override
  String progress_here(int juz, int set) {
    return 'JUZ $juz · SET $set';
  }

  @override
  String get progress_setsUnderstood => 'sets understood';

  @override
  String get progress_prayersRecorded => 'prayers recorded';

  @override
  String get progress_whereYouAre => 'WHERE YOU ARE';

  @override
  String get progress_allSuras => 'All 114';

  @override
  String get progress_rootsKnown => 'ROOTS YOU NOW KNOW';

  @override
  String get progress_rootsEmpty => 'The roots of every set you understand are collected here.';

  @override
  String progress_rootsCoverage(String roots, int percent) {
    return '$roots roots cover $percent% of the words ahead of you.';
  }

  @override
  String get aboutBuiltOn => 'BUILT ON';

  @override
  String get aboutTitle => 'Sources and licences';

  @override
  String get aboutThisApp => 'This app';

  @override
  String aboutCopied(String url) {
    return 'Copied $url';
  }

  @override
  String get aboutProvidesMorphology => 'Roots, word forms and morphology';

  @override
  String get aboutProvidesText => 'The Qurʼanic text';

  @override
  String get aboutProvidesGloss => 'Word-by-word gloss and transliteration';

  @override
  String get aboutProvidesDesign => 'Colour, space and type';

  @override
  String get aboutProvidesArabicFace => 'The Arabic face';

  @override
  String get aboutProvidesLatinFace => 'The Latin face';

  @override
  String get aboutProvidesTimings => 'Per-word recitation timings';

  @override
  String get aboutProvidesRecitation => 'Recitation';

  @override
  String get aboutProvidesVoice => 'Following your voice in prayer';

  @override
  String deepdive_aya_kicker(String surah, int number) {
    return '$surah · aya $number';
  }

  @override
  String get deepdive_back => 'Back';

  @override
  String deepdive_form(String form) {
    return 'form $form';
  }

  @override
  String get deepdive_keep => 'Keep this aya';

  @override
  String get deepdive_kept => 'Kept · tap to undo';

  @override
  String deepdive_kicker(String ref) {
    return 'DEEP DIVE · $ref';
  }

  @override
  String deepdive_occurrences(String translit, int count) {
    return '$translit · $count occurrences';
  }

  @override
  String get deepdive_root_heading => 'ROOT CONSTELLATION';

  @override
  String deepdive_star(String form, String ref) {
    return '$form · open $ref';
  }

  @override
  String deepdive_this_aya(String ref) {
    return 'THIS AYA · $ref';
  }

  @override
  String deepdive_unknown(String ref, String letters) {
    return 'The corpus carries no aya $ref with a root spelled $letters.';
  }

  @override
  String get deepdive_view_constellation => 'Constellation';

  @override
  String get deepdive_view_list => 'List';

  @override
  String dashboard_setWaiting(int number) {
    return 'SET $number · WAITING';
  }

  @override
  String dashboard_ayaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas',
      one: '1 aya',
    );
    return '$_temp0';
  }

  @override
  String dashboard_prayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'prayed $count times',
      two: 'prayed twice',
      one: 'prayed once',
      zero: 'no prayer on it yet',
    );
    return '$_temp0';
  }

  @override
  String get dashboard_praySet => 'Pray this set';

  @override
  String get dashboard_readFirst => 'Read it first';

  @override
  String get dashboard_allUnderstood => 'Every aya is understood.';

  @override
  String get dashboard_allUnderstoodWhy => 'There is nothing left to serve. The index opens any sūra again.';

  @override
  String get dashboard_whereToGo => 'WHERE TO GO';

  @override
  String get dashboard_doorIndex => 'Sūra index';

  @override
  String get dashboard_doorIndexWhy => 'Open any aya you want';

  @override
  String get dashboard_doorProgress => 'Your passage';

  @override
  String get dashboard_doorProgressWhy => 'How much you have understood';

  @override
  String get dashboard_doorKept => 'Kept';

  @override
  String get dashboard_doorPray => 'Prepare a prayer';

  @override
  String get dashboard_doorPrayWhy => 'Any passage, any number of rakʿahs';

  @override
  String get dashboard_doorKeptWhy => 'The ayas and roots you saved';

  @override
  String get report_title => 'Report something';

  @override
  String get report_one_way => 'This goes one way: Wird\'s maintainers read it, and may summarise it — never quote it — in Wird\'s public issue tracker. Nothing comes back here.';

  @override
  String get report_kind_heading => 'WHAT KIND';

  @override
  String get report_kind_bug => 'Bug';

  @override
  String get report_kind_request => 'Request';

  @override
  String get report_kind_improvement => 'Improvement';

  @override
  String get report_words_heading => 'IN YOUR OWN WORDS';

  @override
  String get report_words_hint => 'What happened, or what is missing.';

  @override
  String report_chars_left(int remaining, int max) {
    return '$remaining characters left of $max. The server takes no more than that.';
  }

  @override
  String get report_context_heading => 'SENT WITH IT';

  @override
  String get report_context_only => 'Gathered so you do not have to type it. Nothing else travels: not what you were reading, not what you have kept, not your progress.';

  @override
  String get report_context_loading => 'Reading this build…';

  @override
  String get report_failed => 'Not saved on this phone. Your words are still here — try again.';

  @override
  String get report_send => 'Send it';

  @override
  String get report_queued_heading => 'QUEUED';

  @override
  String get report_queued_body => 'It is written down on this phone and goes out with the next sync, even if you are offline now.';

  @override
  String get report_write_another => 'Write another';

  @override
  String get study_constellation => 'Constellation';

  @override
  String get study_nextWord => 'Next word';

  @override
  String get study_noRecitation => 'No recitation for this sūra';

  @override
  String get study_previousWord => 'Previous word';

  @override
  String get study_wordHasNoRoot => 'No root';

  @override
  String root_openAya(String ref) {
    return 'Open $ref';
  }

  @override
  String get root_thisAya => 'THIS AYA';

  @override
  String root_weightWithForm(String form, int occurrences) {
    return 'Form $form · $occurrences×';
  }

  @override
  String get root_previousForm => 'Previous';

  @override
  String get root_nextForm => 'Next';

  @override
  String root_dialPosition(int index, int count) {
    return '$index of $count · swipe the ring';
  }

  @override
  String get root_kicker => 'Root';

  @override
  String get root_kickerSpine => 'Root spine';

  @override
  String root_unknownRoot(String letters) {
    return 'The corpus carries no root spelled $letters.';
  }

  @override
  String get root_kinHeading => 'Its kin in the Qur\'an';

  @override
  String root_kinFormsAndOccurrences(int forms, int occurrences) {
    return '$forms forms · $occurrences occurrences';
  }

  @override
  String root_formCount(int forms) {
    return '$forms forms';
  }

  @override
  String root_cardWeight(int occurrences) {
    return '$occurrences× IN THE QUR’AN';
  }

  @override
  String root_cardWeightWithForm(String form, int occurrences) {
    return 'FORM $form · $occurrences×';
  }

  @override
  String get root_readTheAya => 'Read the aya';

  @override
  String get root_keepThisRoot => 'Keep this root';

  @override
  String get root_keptTapToUndo => 'Kept · tap to undo';

  @override
  String get root_back => 'Back';

  @override
  String get root_keep => 'Keep';

  @override
  String get root_keptTapToUndoLabel => 'Kept, tap to undo';

  @override
  String get root_coreSense => 'Core sense';

  @override
  String get root_senseRefused => 'The senses are Wird\'s own and they are written one root at a time. None has been written for this root yet. When one is, it reaches this phone without waiting for a new version of the app.';

  @override
  String get root_senseNotFetched => 'The senses are not part of the download. They are fetched, so a sense can be corrected without a new version of the app — and this phone has not fetched any yet. Settings carries the button.';

  @override
  String root_senseByApp(String borne) {
    return 'This app\'s own reading$borne';
  }

  @override
  String root_senseBySource(String source, String borne) {
    return '$source\'s reading$borne';
  }

  @override
  String root_senseBorne(int words) {
    return ', borne out by $words of the root\'s own words';
  }

  @override
  String get root_whoseReading => 'Whose reading this is';

  @override
  String get root_wordsReadFrom => 'The words it was read from';

  @override
  String root_wordCount(int words) {
    return '$words words';
  }

  @override
  String root_formTag(String form) {
    return 'FORM $form';
  }

  @override
  String get root_tafsir => 'Tafsir';

  @override
  String root_tafsirAt(String ref) {
    return 'Tafsir · $ref';
  }

  @override
  String get root_tafsirPending => 'Tafsir is fetched per aya. Nothing is downloaded yet, so nothing is attributed here.';

  @override
  String get root_irab => 'Iʿrāb';

  @override
  String root_irabAsReadAt(String where) {
    return 'as read at $where';
  }

  @override
  String get root_noParsing => 'The corpus carries no parsing for this word.';

  @override
  String root_irabProvenance(String work) {
    return 'Provenance: $work; the role names are written for Wird';
  }

  @override
  String root_spineWeight(String translit, int occurrences, int suras) {
    return '$translit · $occurrences in $suras sūras';
  }

  @override
  String get root_sourcesHeading => 'Sources';

  @override
  String root_provenance(String sources) {
    return 'Provenance: $sources';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'LANGUAGE';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageFrench => 'Français';

  @override
  String get settingsLanguageCaption => 'The screen and a root\'s sense. The senses were written in English and translated, so a root whose French never arrived is read in English.';

  @override
  String get settingsReading => 'READING';

  @override
  String get settingsWordGloss => 'Gloss';

  @override
  String get settingsWordTranslit => 'Translit';

  @override
  String get settingsWordBoth => 'Both';

  @override
  String get settingsWordNeither => 'Neither';

  @override
  String get settingsAyaTranslationShown => 'Aya translated';

  @override
  String get settingsAyaTranslationHidden => 'Arabic only';

  @override
  String get settingsAyaTranslationCaption => 'Pickthall\'s English or Rashid Maash\'s French, under each aya.';

  @override
  String get settingsWordCaption => 'What is printed under each Arabic word.';

  @override
  String get settingsOrderChronological => 'Chronological';

  @override
  String get settingsOrderMushaf => 'Muṣḥaf';

  @override
  String get settingsOrderCaption => 'The chronology orders sūras; ayas inside a sūra stay in written order.';

  @override
  String get settingsArabic => 'Arabic';

  @override
  String get settingsArabicCaption => 'How large the Arabic is set on the reading screen.';

  @override
  String get settingsSetWidth => 'HOW MUCH YOU TAKE AT ONCE';

  @override
  String get settingsNoSetWaiting => 'Every aya is understood, so no set is waiting.';

  @override
  String settingsSetAyas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas',
      one: '1 aya',
    );
    return '$_temp0';
  }

  @override
  String get settingsSetWidthCaption => 'A wider set may cross an aya you already understood. It is recited with the rest and stays counted where it is.';

  @override
  String get settingsRecitation => 'RECITATION';

  @override
  String get settingsNoReciter => 'No reciter is named in this corpus.';

  @override
  String get settingsReciterCaption => 'Whose voice recites the set and each word you tap. Words are highlighted in time with this reciter.';

  @override
  String get settingsStyleMuallim => 'Muʿallim · slow and clear, for learning';

  @override
  String get settingsStyleMurattal => 'Murattal';

  @override
  String get settingsStopSample => 'Stop';

  @override
  String settingsHearReciter(String reciter) {
    return 'Hear $reciter';
  }

  @override
  String get settingsWordFromReciter => 'From the reciter';

  @override
  String get settingsWordAlone => 'Each word alone';

  @override
  String get settingsWordVoiceCaption => 'What a tapped word plays: its moment in the reciter\'s aya, or the word spoken on its own, in one voice for every word.';

  @override
  String get settingsMicrophone => 'MICROPHONE';

  @override
  String get settingsAllowMicrophone => 'Allow microphone';

  @override
  String get settingsMicNotAsked => 'Voice-follow needs the microphone. Off by default; never asked for during a prayer.';

  @override
  String get settingsMicGranted => 'Microphone allowed.';

  @override
  String get settingsMicDenied => 'Microphone refused. The prayer screen advances on a tap, as it always does.';

  @override
  String get settingsMicUnavailable => 'The microphone could not be reached last time it was asked for. Try again; the prayer screen advances on a tap either way.';

  @override
  String settingsVersion(String version) {
    return 'Wird $version';
  }

  @override
  String get settingsAccount => 'ACCOUNT';

  @override
  String settingsStopDownload(int percent) {
    return 'Stop · $percent%';
  }

  @override
  String get settingsCheckRecogniser => 'Check the recogniser';

  @override
  String get settingsRemoveRecogniser => 'Remove recogniser';

  @override
  String settingsDownloadRecogniser(int megabytes) {
    return 'Download recogniser · $megabytes MB';
  }

  @override
  String get settingsRecogniserDownloading => 'Downloading. Stopping keeps what has arrived, and pressing Download again carries on from there.';

  @override
  String get settingsRecogniserReady => 'The prayer screen follows your voice. Your recitation is recognised on this phone and never leaves it.';

  @override
  String get settingsRecogniserNotServed => 'Wird is not serving the recogniser from here. Nothing on this phone changes that, so the button will not bring it either — voice-follow waits until it is published again.';

  @override
  String get settingsRecogniserInterrupted => 'The download stopped before it finished. What arrived is still on the phone, and pressing Download again carries on from there.';

  @override
  String get settingsRecogniserPartial => 'A stopped download is still on the phone. Downloading again carries on from where it stopped.';

  @override
  String get settingsRecogniserAbsent => 'A Qur\'an recogniser that runs on the phone, so nothing you recite is sent anywhere. Downloading it is what turns voice-follow on; the prayer screen advances on a tap until you do, and after you remove it.';

  @override
  String get settingsSenses => 'SENSES';

  @override
  String get settingsDownloadSenses => 'Download the senses';

  @override
  String get settingsSensesAskAgain => 'Ask again';

  @override
  String get settingsSensesAsking => 'Asking the server whether there is anything new.';

  @override
  String get settingsSensesOnOffer => 'There are senses on the server this phone does not have. They are a few hundred kilobytes; nothing downloads until you press.';

  @override
  String get settingsSensesInstalling => 'Downloading. Nothing already on the phone is replaced until all of it has arrived.';

  @override
  String get settingsSensesCurrent => 'This phone has the senses the server is serving. A sense is Wird\'s own reading, written by a machine and read by no person; the line under each one says so, and the thumb beside it is how a wrong one gets corrected.';

  @override
  String get settingsSensesUnreachable => 'The server did not answer, so whether there are new senses is unknown. Every sense already on the phone is still here, and the app reads with no network.';

  @override
  String get settingsSensesNotThisCorpus => 'The senses that arrived name no root this copy of the Qur\'an records, so none of them could ever be read. Nothing was changed on the phone.';

  @override
  String get settingsVoiceCheckTitle => 'Can this phone hear you?';

  @override
  String settingsVoiceCheckSet(String words) {
    return 'the set: $words…';
  }

  @override
  String get settingsVoiceCheckOpening => 'Starting the recogniser…';

  @override
  String get settingsVoiceCheckListening => 'Recite, and the words you say should appear below.';

  @override
  String get settingsVoiceCheckNoModel => 'The recogniser did not start. The download may be incomplete, or this phone may not be able to load it. Voice-follow stays off and the prayer screen answers your tap, as it always has.';

  @override
  String get settingsVoiceCheckNoMicrophone => 'The microphone was refused, so there is nothing to hear.';

  @override
  String settingsVoiceCheckCursor(int word, int total, int moves) {
    return 'the prayer would be on word $word of $total, after $moves moves';
  }

  @override
  String settingsVoiceCheckAudio(String seconds, int millis) {
    return '${seconds}s of voice, slowest answer ${millis}ms';
  }

  @override
  String get settingsVoiceCheckTooLittle => 'heard too little to place';

  @override
  String settingsVoiceCheckBelow(int word, int score, int needed) {
    return 'best word $word fits $score%, needs $needed%';
  }

  @override
  String settingsVoiceCheckAmbiguous(int word, int score, int rival) {
    return 'word $word at $score% but somewhere else fits $rival%';
  }

  @override
  String settingsVoiceCheckRepeat(int word, int score) {
    return 'word $word at $score%, but the set says this more than once and no copy is just ahead';
  }

  @override
  String settingsVoiceCheckPlaced(int word, int score) {
    return 'word $word at $score%';
  }

  @override
  String settingsSignedInAs(String subject) {
    return 'Signed in as $subject';
  }

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutCaption => 'Signing out stops the sync. Everything you have read, kept and marked stays on this phone.';

  @override
  String get settingsSignedOutCaption => 'Wird works signed out. Signing in carries what you mark and keep to your other devices.';

  @override
  String get settingsSignIn => 'Sign in';

  @override
  String get settingsFinishInBrowser => 'Finish signing in in your browser. This phone is waiting for it to send you back.';

  @override
  String get settingsCancelSignIn => 'Cancel';

  @override
  String get settingsNoBrowser => 'no browser here would open the sign-in address';

  @override
  String get settingsSignInUnreachable => 'The sign-in server could not be reached. Nothing changed.';

  @override
  String settingsParkedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes have not reached the server',
      one: '1 change has not reached the server',
    );
    return '$_temp0';
  }

  @override
  String get settingsParkedCaption => 'They are still on this phone. Send them again, or let them go.';

  @override
  String get settingsSendAgain => 'Send again';

  @override
  String get settingsDiscard => 'Discard';

  @override
  String settingsParkedUnderstood(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ayas you marked understood',
      one: 'An aya you marked understood',
    );
    return '$_temp0';
  }

  @override
  String get settingsParkedKept => 'Something you kept';

  @override
  String get settingsParkedUnkept => 'Something you removed from Kept';

  @override
  String get settingsParkedSetRead => 'A set you read';

  @override
  String get settingsParkedPrayer => 'A prayer you counted';

  @override
  String get settingsParkedOrder => 'Your reading order';

  @override
  String get settingsParkedPosition => 'Where you are in a sūra';

  @override
  String get settingsParkedReport => 'Something you reported';

  @override
  String get settingsParkedOther => 'A change you made';

  @override
  String get study_ayaTranslated => 'Pickthall';

  @override
  String get study_glossesSource => 'The meanings under each word are from The Last Dialogue; the few words it does not cover keep their English.';

  @override
  String get root_senseJudgeThanks => 'Noted — thank you.';

  @override
  String get root_senseJudgeFailed => 'Not saved — try again';

  @override
  String get root_senseJudgeGoodLabel => 'This sense is right';

  @override
  String get root_senseJudgeBadLabel => 'This sense is wrong';

  @override
  String get nav_home => 'Home';

  @override
  String get nav_theSet => 'The set';

  @override
  String get nav_sources => 'Sources';

  @override
  String get shell_stop => 'Stop';

  @override
  String get shell_soundingWord => 'SOUNDING ONE WORD';

  @override
  String get shell_recitingAya => 'RECITING ONE AYA';

  @override
  String get study_reciteAya => 'Recite this aya';

  @override
  String get study_hideRoot => 'Hide the root';

  @override
  String get study_showRoot => 'Show the root';

  @override
  String get shell_recitingSet => 'RECITING THE SET';

  @override
  String get shell_notSignedIn => 'NOT SIGNED IN';

  @override
  String get shell_drawerBlurb => 'Everything you have read and kept is on this phone. Accounts arrive with the server they sync to.';

  @override
  String appCorpusWouldNotOpen(String error) {
    return 'The corpus would not open.\n\n$error';
  }

  @override
  String get aboutProvidesFrenchGloss => 'French word-by-word gloss';

  @override
  String get aboutLicenceVerbatim => 'Verbatim copies, attributed';

  @override
  String get aboutLicenceAuthored => 'Authored for Wird';

  @override
  String get aboutLicenceFetched => 'Fetched at playback, never redistributed';

  @override
  String get aboutLicencePermission => 'Used by permission';

  @override
  String get aboutTermsCorpus => 'Every root a word opens into comes from here. Verbatim copies only — changing the annotation is not allowed. Used on the condition that its source is clearly indicated and a link is made to corpus.quran.com, so you can keep track of what has changed since this build.';

  @override
  String get aboutTermsTanzil => 'The verified Uthmani text every aya is painted from, which the Quranic Arabic Corpus also builds on. Copied verbatim; changing the text is not allowed. Linked so you can keep track of changes.';

  @override
  String get aboutTermsQuranFoundation => 'The English under each word, served by the quran.com API. Their terms allow an application to show this content but not to store it indefinitely without a weekly re-sync, which a bundled corpus does not do. Unsettled, and recorded as unsettled.';

  @override
  String get aboutTermsLastDialogue => 'The French under each word, for a reader who reads Wird in French. The site marks its word-by-word as in beta. They granted Wird its use by email on 30 September 2026 without requiring attribution; Wird names them anyway, because it names every source.';

  @override
  String get aboutTermsNocturne => 'The design system every screen is drawn from. Dark only; there is no light mode.';

  @override
  String get aboutTermsScheherazade => 'Bundled unmodified, because platform Arabic faces mangle Qurʼanic diacritics.';

  @override
  String get aboutTermsInter => 'Bundled unmodified.';

  @override
  String get aboutTermsTimings => 'The millisecond each word is spoken at, which is what lets a word light up as you hear it. From github.com/cpfair/quran-align, aligned against this same muʿallim recording. Reindexed for this app: the published data is zero-based and end-exclusive, and it is stored here one-based against the word it belongs to. Offered as-is, without warranties.';

  @override
  String get aboutTermsRecitation => 'The muʿallim recording is downloaded by your device from everyayah.com when you press play, the way a browser loads a page, and cached on your phone. Wird does not bundle it, mirror it, or serve it. The archive publishes no terms of use, so nothing here is offered as permission to redistribute it — and that is why this app never does.';

  @override
  String get aboutTermsVoice => 'The recogniser that hears your recitation, downloaded on your word and run on this phone; nothing you say is sent anywhere. It writes Qurʼanic phonemes, including the marks of tajwīd. Wird uses that only to find where in the set you are, and never to judge how you recited: automatic tajwīd feedback can be wrong, and no software here or anywhere replaces a qualified teacher. Its licence forbids charging for the model or for any feature it powers, which Wird does not and will not do.';

  @override
  String get aboutSelfTerms => 'Wird is free software under the GNU Affero General Public License, version 3 or later. AGPL rather than GPL because Wird has a server: anyone running it as a service owes its users the source of what they are running.';

  @override
  String get study_expandSheet => 'Show counts, forms and other ayas';

  @override
  String get study_collapseSheet => 'Show the whole sūra again';

  @override
  String get study_senses => 'Senses';

  @override
  String get study_particleNote => 'Particles and pronouns have no three-letter root. Swipe on to the next word.';

  @override
  String get study_moreRow => 'Counts, forms, other ayas';

  @override
  String get study_acrossQuran => 'Across the Qur\'an';

  @override
  String get study_countRoot => 'this root';

  @override
  String get study_countLemma => 'as';

  @override
  String get study_countSurah => 'in this sūra';

  @override
  String get study_ringCaption => 'Its forms, and how often each is read';

  @override
  String get study_otherAyas => 'Other ayas';

  @override
  String study_position(String ref, int n, int total) {
    return '$ref · word $n/$total';
  }

  @override
  String study_backTo(String ref) {
    return 'Back to $ref';
  }

  @override
  String get study_readFromHere => 'Read this sūra from here';

  @override
  String get study_previousSura => 'Previous sūra';

  @override
  String get study_nextSura => 'Next sūra';

  @override
  String get study_pray => 'Pray';

  @override
  String get study_recite => 'Recite from this word · hold for the whole sūra';

  @override
  String get study_pauseRecitation => 'Pause the recitation';

  @override
  String study_markUnderstood(String ref) {
    return 'Mark aya $ref understood';
  }

  @override
  String study_openRoot(String root) {
    return 'Open the root $root';
  }

  @override
  String get dashboard_continueReading => 'CONTINUE READING';

  @override
  String get study_form => 'Form';

  @override
  String get prepare_trouble => 'The Qur\'an could not be read on this device. Try again; if it keeps failing, close Wird and open it again.';

  @override
  String get prepare_retry => 'Try again';
}
