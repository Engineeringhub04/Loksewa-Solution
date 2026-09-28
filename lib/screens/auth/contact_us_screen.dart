import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Contact Us — mirrors app/contact-us.tsx.
/// Channels, socials and a message form. Channel/social links render as text
/// (url_launcher is not a dependency). Message submission posts to the team's
/// Google Form — the POST helper lives in the messaging service (next batch),
/// so submit currently validates and reports that it isn't connected yet.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_message.text.trim().isEmpty) return;
    setState(() => _sending = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Message submission is not connected in this build yet. Please email contact@kbr.com.np.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Contact Us'),
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
                    'Contact Us',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'We usually reply within one working day. Pick whichever channel suits you.',
                    style:
                        TextStyle(color: Color(0xFFD7E3FF), height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(title: 'Reach us', children: const [
            ListTile(
              leading: Icon(Icons.mail_outline, color: AppColors.navy),
              title: Text('Email us'),
              subtitle: Text('contact@kbr.com.np'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: Icon(Icons.call_outlined, color: AppColors.navy),
              title: Text('Call us'),
              subtitle: Text('+977-9810768297'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: Icon(Icons.language, color: AppColors.navy),
              title: Text('Website'),
              subtitle: Text('kbr.com.np'),
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          const SizedBox(height: 12),
          _sectionCard(title: 'Follow us', children: const [
            ListTile(
              title: Text('Facebook'),
              subtitle: Text('facebook.com — Loksewa Solution',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              title: Text('Instagram'),
              subtitle: Text('@loksewasolution',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              title: Text('YouTube'),
              subtitle: Text('loksewasolution0',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              title: Text('X (Twitter)'),
              subtitle: Text('@loksewa_soln',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Send Message',
            subtitle: 'Reach out to our support team',
            children: [
              TextField(
                controller: _message,
                maxLines: 4,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write your message…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: (_message.text.trim().isEmpty || _sending)
                    ? null
                    : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Send Message'),
              ),
            ],
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
      {required String title,
      String? subtitle,
      required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
