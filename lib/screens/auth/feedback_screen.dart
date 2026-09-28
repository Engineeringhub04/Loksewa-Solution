import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Feedback — mirrors app/feedback.tsx.
/// 1–5 star rating (gated) + optional message. Submission posts to the team's
/// Google Form — the POST helper lives in the messaging service (next batch),
/// so submit currently validates and reports that it isn't connected yet.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const _labels = ['', 'Very poor', 'Poor', 'Okay', 'Good', 'Excellent'];

  int _rating = 0;
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Color _tone() {
    if (_rating >= 4) return Colors.green;
    if (_rating == 3) return Colors.orange;
    if (_rating > 0) return Colors.red;
    return Colors.grey;
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please choose a star rating first')),
      );
      return;
    }
    setState(() => _sending = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feedback submission is not connected in this build yet.'),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.red.shade700,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feedback',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your feedback directly shapes what we build next. Thank you for taking a moment.',
                    style: TextStyle(
                        color: Colors.white70, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How would you rate the app?',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final value = i + 1;
                      return IconButton(
                        onPressed: () =>
                            setState(() => _rating = value),
                        icon: Icon(
                          value <= _rating
                              ? Icons.star
                              : Icons.star_border,
                          size: 36,
                          color: value <= _rating
                              ? _tone()
                              : Colors.grey.shade400,
                        ),
                      );
                    }),
                  ),
                  SizedBox(
                    height: 30,
                    child: Center(
                      child: _rating > 0
                          ? Chip(
                              label: Text(_labels[_rating]),
                              backgroundColor:
                                  _tone().withValues(alpha: 0.15),
                            )
                          : const Text(
                              'Tap a star to rate',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 13),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tell us more (optional)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'What did you like? What should we improve?',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _message,
                    maxLines: 5,
                    minLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Write your feedback…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          (_rating == 0 || _sending) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
