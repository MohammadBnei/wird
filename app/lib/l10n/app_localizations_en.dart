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
  String get inThisAya => 'IN THIS AYA';

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
  String get markSetUnderstood => 'Mark set understood';

  @override
  String get nextSet => 'Next set';

  @override
  String get notDownloaded => 'Not downloaded';

  @override
  String get prayer_in_prayer => 'IN PRAYER';

  @override
  String get prayer_following_your_voice => 'FOLLOWING YOUR VOICE';

  @override
  String get prayer_exit => 'Exit';

  @override
  String get prayer_back_an_aya => 'Back an aya';

  @override
  String get prayer_on_to_the_next_aya => 'On to the next aya';

  @override
  String get prayer_foot_taps_only => 'Screen stays awake · tap to go on · left edge steps back';

  @override
  String get prayer_foot_following => 'Screen stays awake · tap any time · left edge steps back';

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
  String get dashboard_doorKeptWhy => 'The ayas and roots you saved';

  @override
  String get report_title => 'Report something';

  @override
  String get report_one_way => 'This goes one way. It reaches whoever keeps Wird running, and nothing comes back — there is no inbox here to check.';

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
  String get report_send => 'Send it';

  @override
  String get report_queued_heading => 'QUEUED';

  @override
  String get report_queued_body => 'It is written down on this phone and goes out with the next sync, even if you are offline now.';

  @override
  String get report_write_another => 'Write another';

  @override
  String get study_backToTheWalk => 'Back to the walk';

  @override
  String get study_constellation => 'Constellation';

  @override
  String get study_everyAyaUnderstood => 'Every aya in this set is understood';

  @override
  String get study_goTo => 'Go to…';

  @override
  String get study_goToAnyAya => 'Go to any sūra or aya';

  @override
  String get study_kinOpensItsAya => 'A kin opens the aya it is first met in.';

  @override
  String get study_noAyaUnderstoodYet => 'No aya marked understood yet';

  @override
  String get study_noRecitation => 'No recitation for this set';

  @override
  String get study_noRootInSet => 'No word in this set carries a root.';

  @override
  String get study_nothingLeftToServe => 'Every aya is understood. There is nothing left to serve.';

  @override
  String study_numbersAnd(Object first, Object last) {
    return '$first and $last';
  }

  @override
  String get study_previousSet => 'Previous set';

  @override
  String get study_prayThisSet => 'Pray this set';

  @override
  String study_progressSplit(Object done, Object open) {
    return 'Aya $done marked understood · aya $open open';
  }

  @override
  String study_revelationKicker(Object order, Object place) {
    return 'Revelation $order · $place';
  }

  @override
  String study_surahKicker(Object surah, Object place) {
    return 'Sūra $surah · $place';
  }

  @override
  String get study_visiting => 'Visiting';

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
  String get settingsLanguagePhone => 'Your phone\'s';

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
  String settingsRecitedBy(String reciter) {
    return 'Recited by $reciter.';
  }

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
    return 'word $word at $score% but somewhere else fits $rival% — the set says this twice';
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
  String get settingsParkedReport => 'Something you reported';

  @override
  String get settingsParkedOther => 'A change you made';

  @override
  String get study_ayaTranslated => 'Rashid Maash';

  @override
  String get study_glossesStayEnglish => 'The word meanings under each word are in English; no word-by-word rendering exists in your language.';

  @override
  String get root_senseJudgeThanks => 'Noted — thank you.';

  @override
  String get root_senseJudgeGoodLabel => 'This sense is right';

  @override
  String get root_senseJudgeBadLabel => 'This sense is wrong';
}
