import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Help Center — mirrors app/settings/help-center.tsx.
/// Search across all FAQs, topic chips, one-open-at-a-time accordion,
/// quick actions and reach-us rows. FAQ copy is the English set from the
/// app's locale file (help.faq.*).
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _Faq {
  final String id;
  final String topic;
  final Color color;
  final String question;
  final String answer;
  const _Faq(this.id, this.topic, this.color, this.question, this.answer);
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  static const _topics = [
    ('start', 'Getting started', Color(0xFF6366F1)),
    ('study', 'Study & practice', Color(0xFF10B981)),
    ('exams', 'Exams', Color(0xFFF59E0B)),
    ('daily', 'Daily Test', Color(0xFF0EA5E9)),
    ('current', 'Current affairs', Color(0xFF14B8A6)),
    ('progress', 'Progress & points', Color(0xFFA855F7)),
    ('account', 'Account', Color(0xFFEC4899)),
    ('app', 'App & settings', Color(0xFF64748B)),
  ];

  static const _faqs = [
    // start
    _Faq('start.1', 'start', Color(0xFF6366F1), 'How do I choose my course?',
        'On your first login the app asks for a course and a sub-course. You can change it any time from Profile → Edit Profile.'),
    _Faq('start.2', 'start', Color(0xFF6366F1), 'Is the app free to use?',
        'Most practice material is free. A few exam sets and premium notes need a purchase, and that is always marked on the card before you open it.'),
    _Faq('start.3', 'start', Color(0xFF6366F1), 'Do I need internet all the time?',
        'Internet is needed to load new content and to save your progress. Pages you already opened stay readable from cache for a short while.'),
    // study
    _Faq('study.1', 'study', Color(0xFF10B981), 'Where do I practise a subject?',
        'Open Subjects, pick a subject, then a chapter and a unit, and choose Read or Practice.'),
    _Faq('study.2', 'study', Color(0xFF10B981), 'Can I save a question for later?',
        'Yes. Tap the bookmark icon on any question or article. Everything you save is in Profile → Bookmarks.'),
    _Faq('study.3', 'study', Color(0xFF10B981), 'Why does it say my bookmark slots are full?',
        'Each sub-course allows 15 bookmarks. Remove one from the Bookmarks page to free a slot.'),
    // exams
    _Faq('exams.1', 'exams', Color(0xFFF59E0B), 'When can I start an exam set?',
        'A scheduled set unlocks at its start time. The countdown on the card shows exactly when that is.'),
    _Faq('exams.2', 'exams', Color(0xFFF59E0B), 'What happens if I leave an exam midway?',
        'The timer keeps running. Come back before it ends and your answers are still there.'),
    _Faq('exams.3', 'exams', Color(0xFFF59E0B), 'Where do I see my rank?',
        'Once results are published, open the Ranking tab on that exam, or the Leaderboard tab for the overall standing.'),
    // daily
    _Faq('daily.1', 'daily', Color(0xFF0EA5E9), 'How often can I take the Daily Test?',
        'Once a day. A fresh set arrives each morning and the previous one closes.'),
    _Faq('daily.2', 'daily', Color(0xFF0EA5E9), 'Do Daily Test points count?',
        'Yes. They feed your points, your streak and Analytics exactly like any other activity.'),
    _Faq('daily.3', 'daily', Color(0xFF0EA5E9), 'I missed yesterday — can I still take it?',
        'Past Daily Tests cannot be reopened. Missing one only breaks your streak; the points you already earned stay.'),
    // current
    _Faq('current.1', 'current', Color(0xFF14B8A6), 'Where does the GK material come from?',
        'Our team prepares and publishes it. New notes appear under GK & Current Affairs.'),
    _Faq('current.2', 'current', Color(0xFF14B8A6), 'How often is it updated?',
        'New material is added regularly, and the app sends you a notification when it lands.'),
    _Faq('current.3', 'current', Color(0xFF14B8A6), 'Can I read older material?',
        'Yes. The list keeps earlier entries — scroll down or use the topic filter to find them.'),
    // progress
    _Faq('progress.1', 'progress', Color(0xFFA855F7), 'How is my profile percentage calculated?',
        'It is coverage: how much of all available content you have completed. It is not your accuracy — accuracy is shown as a separate number.'),
    _Faq('progress.2', 'progress', Color(0xFFA855F7), 'Why did my percentage go down?',
        'When new content is added the total grows, so the same work covers a smaller share. It climbs back as you keep studying.'),
    _Faq('progress.3', 'progress', Color(0xFFA855F7), 'How often does Analytics refresh?',
        'A snapshot is stored once a day, so today\'s activity can take a few hours to appear in the trend charts.'),
    // account
    _Faq('account.1', 'account', Color(0xFFEC4899), 'Can I use one account on two phones?',
        'No. An account works on one device at a time. Logging in somewhere else signs the older device out.'),
    _Faq('account.2', 'account', Color(0xFFEC4899), 'How do I change my name or photo?',
        'Go to Profile → Edit Profile, update the field and save.'),
    _Faq('account.3', 'account', Color(0xFFEC4899), 'How do I delete my account?',
        'Write to us from Help Center → Contact us and we will remove it for you.'),
    // app
    _Faq('app.1', 'app', Color(0xFF64748B), 'How do I switch language or theme?',
        'Both live in Settings — the language toggle, and Light, Dark or System theme.'),
    _Faq('app.2', 'app', Color(0xFF64748B), 'I am not getting notifications.',
        'Allow notifications for the app in your phone settings, then open the app once so it can register this device.'),
    _Faq('app.3', 'app', Color(0xFF64748B), 'How do I report a problem?',
        'Help Center → Report a problem, or tap the report icon on the screen where the problem happened.'),
  ];

  final _search = TextEditingController();
  String? _topic;
  String? _openId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Faq> get _items {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      return _faqs
          .where((f) =>
              f.question.toLowerCase().contains(q) ||
              f.answer.toLowerCase().contains(q))
          .toList();
    }
    if (_topic != null) {
      return _faqs.where((f) => f.topic == _topic).toList();
    }
    return _faqs;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Help Center'),
          Expanded(
            child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.navy,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Help Center',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Answers to the questions we hear most.',
                    style: TextStyle(color: Color(0xFFD7E3FF)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search FAQs',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _openId = null),
          ),
          if (_search.text.trim().isEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('All topics', AppColors.navy, _topic == null,
                    () => setState(() {
                          _topic = null;
                          _openId = null;
                        })),
                ..._topics.map((t) => _chip(
                      t.$2,
                      t.$3,
                      _topic == t.$1,
                      () => setState(() {
                        _topic = _topic == t.$1 ? null : t.$1;
                        _openId = null;
                      }),
                    )),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.search_off,
                        size: 28, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No FAQ available yet',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text(
                      'We are writing the answers — check back soon.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16),
                    _faqRow(items[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          const Text('Still stuck?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _actionRow(
                  Icons.warning_amber_outlined,
                  Colors.red,
                  'Report a Problem',
                  'Describe what went wrong — it reaches the team.',
                  () => context.push('/settings/report-problem'),
                ),
                const Divider(height: 1, indent: 16),
                _actionRow(
                  Icons.chat_bubble_outline,
                  const Color(0xFF0EA5E9),
                  'Contact Us',
                  'Email or call us directly.',
                  () => context.push('/contact-us'),
                ),
                const Divider(height: 1, indent: 16),
                _actionRow(
                  Icons.star_outline,
                  const Color(0xFFF59E0B),
                  'Feedback',
                  'Tell us what you like or what to improve.',
                  () => context.push('/feedback'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Still stuck? Reach us directly',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                _ContactRow(
                  icon: Icons.mail_outline,
                  label: 'Email us',
                  value: 'contact@kbr.com.np',
                ),
                Divider(height: 1, indent: 16),
                _ContactRow(
                  icon: Icons.call_outlined,
                  label: 'Call us',
                  value: '+977-9810768297',
                ),
                Divider(height: 1, indent: 16),
                _ContactRow(
                  icon: Icons.language,
                  label: 'Visit our website',
                  value: 'kbr.com.np',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Most reports get a response within 1-2 working days.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
      String label, Color color, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active ? color : Colors.transparent,
          border: Border.all(
              color: active ? color : Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _faqRow(_Faq item) {
    final open = _openId == item.id;
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.help_outline,
                size: 14, color: item.color),
          ),
          title: Text(item.question,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey),
          onTap: () =>
              setState(() => _openId = open ? null : item.id),
        ),
        if (open)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(54, 0, 16, 16),
            child: Text(
              item.answer,
              style: const TextStyle(
                  color: Colors.grey, fontSize: 13, height: 1.5),
            ),
          ),
      ],
    );
  }

  Widget _actionRow(IconData icon, Color color, String title,
      String desc, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(desc,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing:
          const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

/// A contact row — mirrors the contact rows in app/settings/help-center.tsx:
/// primary-tinted icon box, label above the value, open icon on the right.
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ContactRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(icon, size: 19, color: AppColors.navy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.open_in_new,
              size: 17, color: Colors.grey),
        ],
      ),
    );
  }
}
