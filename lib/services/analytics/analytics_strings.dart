import '../app_language.dart';

/// Bilingual strings for the analytics screen — mirrors the `analytics.*`
/// keys in the React app's i18n (en.json / ne.json) one by one.
///
/// Every member returns pure English or pure Devanagari Nepali via
/// [AppLanguage.tr]; parameterised strings are static methods that take the
/// interpolated values. The React `t()` leaves `{{placeholders}}` without a
/// supplied param visible as literal text — a handful of React strings are
/// stale that way (cohort headline/subline/toNext, points row); those are
/// noted below and rendered with the obvious intent instead of the raw
/// `{{braces}}`.
class AnalyticsStrings {
  // ---------- header / gates ----------
  static String get title => AppLanguage.tr('Performance Analytics', 'प्रदर्शन विश्लेषण');
  static String get refresh => AppLanguage.tr('Refresh', 'रिफ्रेस');
  static String get loading => AppLanguage.tr('Loading Analytics...', 'विश्लेषण लोड हुँदैछ...');
  static String get loadingHint => AppLanguage.tr('Preparing your charts and progress', 'तपाईंका चार्ट र प्रगति तयार गर्दै');
  static String get noCourse => AppLanguage.tr('Choose a course to see your analytics', 'विश्लेषण हेर्न कोर्स छान्नुहोस्');
  static String get emptyTitle => AppLanguage.tr('No data yet', 'अझै डाटा छैन');
  static String get emptyDescription => AppLanguage.tr(
      'Your daily snapshot has not run for this sub-course yet. Open the app tomorrow and it will start building.',
      'यो सब-कोर्सको दैनिक स्न्यापशट अझ चलेको छैन। भोलि एप खोल्नुहोस्, बन्दै जानेछ।');
  static String get errorTitle => AppLanguage.tr('Data Not Found', 'डाटा भेटिएन');
  static String get errorDescription => AppLanguage.tr(
      "We couldn't load this content. Please try again.",
      'यो सामग्री लोड हुन सकेन। पुनः प्रयास गर्नुहोस्।');
  static String get retry => AppLanguage.tr('Try Again', 'पुनः प्रयास गर्नुहोस्');

  // ---------- hero ----------
  static String get heroEyebrow => AppLanguage.tr('This period', 'यो अवधि');
  static String get heroPoints => AppLanguage.tr('Points', 'अंक');
  static String get heroRank => AppLanguage.tr('Rank', 'क्रम');
  static String get heroActiveDays => AppLanguage.tr('Active days', 'सक्रिय दिन');
  static String get heroStreak => AppLanguage.tr('Day streak', 'दिनको स्ट्रिक');
  static String get heroSwitch => AppLanguage.tr('Switch sub-course', 'सब-कोर्स फेर्नुहोस्');
  static String get heroFallbackCourse => AppLanguage.tr('Your course', 'तपाईंको कोर्स');

  // ---------- range switcher ----------
  static String get range7d => AppLanguage.tr('7 days', '७ दिन');
  static String get range30d => AppLanguage.tr('30 days', '३० दिन');
  static String get range90d => AppLanguage.tr('90 days', '९० दिन');
  static String get rangeAll => AppLanguage.tr('All time', 'सबै समय');
  static String get rangeAllLabel => AppLanguage.tr('all time', 'सबै समय');
  static String rangeDaysLabel(int days) => AppLanguage.tr('$days days', '$days दिन');
  static String get trackingStarted => AppLanguage.tr('Tracking started', 'ट्र्याकिङ सुरु भयो');
  static String rangeObserved(int days) =>
      AppLanguage.tr('$days recorded day(s)', '$days दिन रेकर्ड भएको');

  // ---------- KPI tiles ----------
  static String get kpiAccuracy => AppLanguage.tr('Accuracy', 'शुद्धता');
  static String get kpiStudyTime => AppLanguage.tr('Study time', 'अध्ययन समय');
  static String get kpiActivities => AppLanguage.tr('Activities', 'गतिविधि');
  static String get kpiActiveDays => AppLanguage.tr('Active days', 'सक्रिय दिन');
  static String get kpiSincePeriodStart =>
      AppLanguage.tr('Since the day you started', 'सुरु गरेको देखि');
  static String vsPrevious(String range) =>
      AppLanguage.tr('vs previous $range', 'अघिल्लो $range भन्दा');

  // ---------- score trend ----------
  static String get trendTitle => AppLanguage.tr('Points trend', 'अंकको प्रवृत्ति');
  static String get trendSubtitle =>
      AppLanguage.tr('How your daily effort has moved', 'तपाईंको दैनिक मेहनत कसरी गयो');
  static String get trendEmpty =>
      AppLanguage.tr('Nothing recorded in this range yet', 'यो अवधिमा अझ केही रेकर्ड भएको छैन');
  static String estimateNote(int days) => AppLanguage.tr(
      'The first $days day(s) of this range are estimated from your totals.',
      'यो अवधिको पहिलो $days दिन तपाईंको कुल अंकबाट अनुमानित छ।');

  // ---------- heatmap ----------
  static String get heatmapTitle => AppLanguage.tr('Activity heatmap', 'गतिविधि हिटम्याप');
  static String get heatmapSubtitle =>
      AppLanguage.tr('Your consistency at a glance', 'तपाईंको निरन्तरता एक नजरमा');
  static String get heatmapEmpty =>
      AppLanguage.tr('No activity recorded yet', 'अझ कुनै गतिविधि रेकर्ड भएको छैन');
  static String get heatmapHint =>
      AppLanguage.tr('Tap a day to see its count', 'दिन थिच्नुहोस्, गतिविधि संख्या देखिन्छ');
  static String get heatmapLess => AppLanguage.tr('less', 'कम');
  static String get heatmapMore => AppLanguage.tr('more', 'बढी');
  static String heatmapDayValue(int count) =>
      AppLanguage.tr('$count activities on this day', 'यो दिन $count गतिविधि');

  // ---------- radar ----------
  static String get radarTitle => AppLanguage.tr('Subject balance', 'विषय सन्तुलन');
  static String get radarSubtitle =>
      AppLanguage.tr("Where your effort actually goes", 'तपाईंको मेहनत कहाँ जान्छ');
  static String get radarEmpty => AppLanguage.tr(
      'Practice more subjects to see the balance', 'सन्तुलन हेर्न थप विषय अभ्यास गर्नुहोस्');
  static String get radarStrongestLabel =>
      AppLanguage.tr('Strongest area', 'सबैभन्दा बलियो क्षेत्र');
  static String radarStrongest(String source, String percent) =>
      AppLanguage.tr('Strongest area: $source · $percent', 'सबैभन्दा बलियो क्षेत्र: $source · $percent');

  // ---------- effort ring ----------
  static String get effortTitle => AppLanguage.tr('Study time', 'अध्ययन समय');
  static String get effortSubtitle =>
      AppLanguage.tr('Time tracked this period', 'यो अवधिको ट्र्याक भएको समय');
  static String get effortSubtitleLifetime =>
      AppLanguage.tr('Time tracked since you started', 'सुरुदेखि ट्र्याक भएको समय');
  static String get effortEmpty =>
      AppLanguage.tr('No sessions timed yet', 'अझ कुनै सेसन समय रेकर्ड भएन');
  static String get effortCenter => AppLanguage.tr('Total study time', 'कुल अध्ययन समय');
  static String get effortTotalTime => AppLanguage.tr('Total', 'जम्मा');
  static String get effortTrackedTime => AppLanguage.tr('tracked', 'ट्र्याक भयो');
  static String get effortAvgSession => AppLanguage.tr('Avg. session', 'औसत सेसन');

  // ---------- points breakdown ----------
  static String get pointsTitle =>
      AppLanguage.tr('Where your points come from', 'तपाईंको अंक कहाँबाट आउँछ');
  static String get pointsSubtitle =>
      AppLanguage.tr('Every source that adds to your score', 'स्कोरमा जोडिने हरेक स्रोत');
  static String get pointsEmpty =>
      AppLanguage.tr('No scored activity yet', 'अझ कुनै स्कोर गतिविधि छैन');
  static String get pointsUnit => AppLanguage.tr('pts', 'अंक');
  static String get pointsEstimateNote => AppLanguage.tr(
      'Points marked as estimated come from days before tracking started.',
      'अनुमानित लेखिएका अंक ट्र्याकिङ सुरु हुनुअघिका दिनका हुन्।');

  /// React's `analytics.points.row` is `"{{source}} · {{count}} activities"`
  /// but the screen passes `{points, share}` — the braces render literally.
  /// This renders the intended row instead.
  static String pointsRow(String label, String compact, int share) =>
      '$label · $compact ${AppLanguage.tr('pts', 'अंक')} ($share%)';

  // ---------- daily effort ----------
  static String get dailyTitle => AppLanguage.tr('Daily effort', 'दैनिक मेहनत');
  static String get dailySubtitle =>
      AppLanguage.tr('Activities recorded each day', 'हरेक दिन रेकर्ड भएका गतिविधि');
  static String get dailyEmpty =>
      AppLanguage.tr('No days recorded in this range', 'यो अवधिमा कुनै दिन रेकर्ड भएन');
  static String get dailyAverage => AppLanguage.tr('Average', 'औसत');
  static String get dailyWeekendNote =>
      AppLanguage.tr('Weekends are shaded.', 'शनिबार-आइतबार छायाँकित छन्।');
  static String get dailySeededDay =>
      AppLanguage.tr('Estimated from totals', 'कुल अंकबाट अनुमानित');
  static String dailyDayValue(int count) =>
      AppLanguage.tr('$count activities', '$count गतिविधि');

  // ---------- accuracy by source ----------
  static String get accuracyTitle => AppLanguage.tr('Accuracy', 'शुद्धता');
  static String get accuracySubtitle => AppLanguage.tr(
      'Correct answers across practice and tests', 'अभ्यास र परीक्षाका सही उत्तरहरू');
  static String get accuracyEmpty =>
      AppLanguage.tr('No answers recorded yet', 'अझ कुनै उत्तर रेकर्ड भएन');
  static String get accuracyUntouched => AppLanguage.tr(
      'Answer a few questions to unlock this', 'पहिले केही प्रश्न उत्तर दिनुहोस्');

  // ---------- insights ----------
  static String get insightTitle => AppLanguage.tr('Insights', 'इनसाइट');
  static String get insightStrengthEyebrow =>
      AppLanguage.tr('Your strength', 'तपाईंको बलियो पक्ष');
  static String get insightStrengthBody => AppLanguage.tr(
      'This is your highest-scoring area — keep the momentum going.',
      'यो तपाईंको सबैभन्दा उच्च स्कोरको क्षेत्र हो — गति नरोक्नुहोस्।');
  static String get insightFocusEyebrow =>
      AppLanguage.tr('Needs attention', 'ध्यान दिनुपर्ने');
  static String get insightFocusBody => AppLanguage.tr(
      'You have not touched this area in a while. A short session today would move your score.',
      'यो क्षेत्र केही समयदेखि छोइएको छैन। आज छोटो सेसनले स्कोर बढाउँछ।');
  static String get insightFocusUntouchedBody => AppLanguage.tr(
      'This area is still untouched. One short practice is all it takes to start.',
      'यो क्षेत्र अझ छोइएको छैन। एउटा छोटो अभ्यासले सुरु गर्न सकिन्छ।');
  static String get insightKeepGoing => AppLanguage.tr('Keep going', 'जारी राख्नुहोस्');
  static String get insightPracticeNow =>
      AppLanguage.tr('Practice now', 'अहिले अभ्यास गर्नुहोस्');

  // ---------- consistency ----------
  static String get weekTitle => AppLanguage.tr('This week', 'यो हप्ता');
  static String get weekSubtitle =>
      AppLanguage.tr('Your recent rhythm', 'तपाईंको हालको लय');
  static String get weekEmpty =>
      AppLanguage.tr('Nothing recorded this week', 'यो हप्ता केही रेकर्ड भएन');

  /// React renders `t('analytics.week.streak', {days})` — the string has no
  /// placeholder, so the header chip reads exactly this.
  static String get weekStreakLabel =>
      AppLanguage.tr('Current streak', 'हालको स्ट्रिक');
  static String get weekPeakDay => AppLanguage.tr('Peak day', 'उच्च दिन');
  static String get weekBestStreak => AppLanguage.tr('Best streak', 'उत्कृष्ट स्ट्रिक');
  static String dayStreak(int n) =>
      AppLanguage.tr('$n day streak', '$n दिनको स्ट्रिक');

  // ---------- cohort ----------
  static String get cohortTitle =>
      AppLanguage.tr('Compare with your cohort', 'आफ्नो समूहसँग तुलना');
  static String get cohortSubtitle => AppLanguage.tr(
      'Everyone enrolled in the same sub-course', 'उही सब-कोर्समा दर्ता सबै सिकारु');
  static String get cohortPrompt => AppLanguage.tr(
      'See how your effort compares with others studying the same sub-course.',
      'उही सब-कोर्स पढ्नेहरूसँग तपाईंको मेहनतको तुलना हेर्नुहोस्।');
  static String get cohortLoad => AppLanguage.tr('Load comparison', 'तुलना ल्याउनुहोस्');
  static String get cohortEmpty => AppLanguage.tr(
      'Not enough learners to compare yet', 'तुलना गर्न पर्याप्त सिकारु छैनन्');
  static String get cohortMedian => AppLanguage.tr('Median', 'मध्यमा');
  static String get cohortYou => AppLanguage.tr('You', 'तपाईं');

  /// React's `analytics.cohort.toNext` is `"{{points}} pts to the next rank"`
  /// but the screen passes no params — the braces render literally. The cell
  /// value already carries the `+N`, so the label is just this.
  static String get cohortToNext => AppLanguage.tr('To next rank', 'अर्को क्रममा');
  static String get cohortBoardLabel =>
      AppLanguage.tr('View leaderboard', 'लिडरबोर्ड हेर्नुहोस्');

  /// React's headline string is the static "Where you stand" (its
  /// `{rank, size}` params are unused by the i18n text).
  static String get cohortHeadline =>
      AppLanguage.tr('Where you stand', 'तपाईं कहाँ हुनुहुन्छ');

  /// React's subline (`"Against {{count}} learner(s) in {{subcourse}}"`) gets a
  /// `{percent}` param it never uses — the braces render literally. This
  /// renders the intended line instead.
  static String cohortSubline(int percent) =>
      AppLanguage.tr('Top $percent%', 'शीर्ष $percent%');

  // ---------- milestones ----------
  static String get milestoneTitle => AppLanguage.tr('Milestones', 'उपलब्धिहरू');
  static String get milestoneSubtitle =>
      AppLanguage.tr('Small wins that add up', 'जोडिँदै जाने साना जितहरू');
  static String get milestoneEmpty => AppLanguage.tr(
      'Complete your first activity to unlock milestones',
      'पहिलो गतिविधि पूरा गर्नुहोस्, उपलब्धिहरू खुल्छन्');
  static String get milestoneDone => AppLanguage.tr('done', 'पूरा');
  static String milestonePoints(String target) =>
      AppLanguage.tr('Reach $target points', '$target अंक पुर्‍याउनुहोस्');
  static String milestoneStreak(String target) =>
      AppLanguage.tr('Study $target days in a row', 'लगातार $target दिन अध्ययन गर्नुहोस्');
  static String milestoneAccuracy(String target) =>
      AppLanguage.tr('Hold $target accuracy', '$target शुद्धता कायम राख्नुहोस्');
  static String milestoneHours(String target) =>
      AppLanguage.tr('Study $target in total', 'जम्मा $target अध्ययन गर्नुहोस्');

  // ---------- method footer ----------
  static String get methodTitle =>
      AppLanguage.tr('How these numbers are built', 'यी अंकहरू कसरी बन्छन्');
  static String get methodIntro => AppLanguage.tr(
      'Every day the app stores a snapshot of your totals, so trends survive without re-reading your whole history.',
      'एपले हरेक दिन तपाईंको कुल अंकको स्न्यापशट राख्छ, ताकि प्रवृत्ति पुरै इतिहास नपढी देखिन्छ।');
  static String get methodWeightsTitle =>
      AppLanguage.tr('Scoring weights', 'स्कोरिङ वजन');
  static String methodTimeNote(int hours) => AppLanguage.tr(
      'Study time counts ${hours}h per activity-day.',
      'अध्ययन समय प्रति गतिविधि-दिन $hoursघण्टा गनिन्छ।');
  static String get methodEstimateNote => AppLanguage.tr(
      'Days before your first snapshot are estimated, never invented.',
      'पहिलो स्न्यापशटअघिका दिन अनुमानित हुन्छन्, बनाइएका होइनन्।');
  static String get methodPrivacyNote => AppLanguage.tr(
      'All of this data is private to your account.',
      'यो सबै डाटा तपाईंको खातामा मात्र सीमित छ।');
  static String get methodExpand => AppLanguage.tr('Show details', 'विवरण हेर्नुहोस्');
  static String get methodCollapse =>
      AppLanguage.tr('Hide details', 'विवरण लुकाउनुहोस्');
  static String updatedJustNow() =>
      AppLanguage.tr('Updated just now', 'भर्खरै अपडेट भयो');
  static String updatedMinutesAgo(int value) =>
      AppLanguage.tr('Updated $value min ago', '$value मिनेटअघि अपडेट भयो');
  static String updatedHoursAgo(int value) =>
      AppLanguage.tr('Updated $value hr ago', '$value घण्टाअघि अपडेट भयो');

  // ---------- subcourse picker ----------
  static String get pickerTitle => AppLanguage.tr('Sub-course', 'सब-कोर्स');
  static String get pickerSubtitle => AppLanguage.tr(
      'Analytics follow your enrolled sub-course',
      'विश्लेषण तपाईंको छानेको सब-कोर्सअनुसार');
  static String get pickerUnnamed =>
      AppLanguage.tr('Unnamed sub-course', 'बेनाम सब-कोर्स');

  // ---------- source labels (analytics.sources.*) ----------
  static String get sourceExam => AppLanguage.tr('Exam', 'परीक्षा');
  static String get sourceDailyTest => AppLanguage.tr('Daily Test', 'दैनिक परीक्षा');
  static String get sourcePractice => AppLanguage.tr('Practice', 'अभ्यास');
  static String get sourceQotd =>
      AppLanguage.tr('Question of the Day', 'दिनको प्रश्न');
  static String get sourceGkPm =>
      AppLanguage.tr('GK & Current Affairs', 'सामान्य ज्ञान र समसामयिक');
  static String get sourceReading => AppLanguage.tr('Reading', 'पठन');
  static String get sourceTime => AppLanguage.tr('Study Time', 'अध्ययन समय');
  static String get sourceBonus => AppLanguage.tr('Bonus', 'बोनस');
}
