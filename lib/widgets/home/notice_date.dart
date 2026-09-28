/// Exact replication of the Expo date fallback
/// `new Date(millis).toLocaleDateString('ne-NP', { year: 'numeric', month: 'short', day: 'numeric' })`
/// as produced with full ICU data: "{year} {month} {day}" with Devanagari
/// digits, e.g. "२०२६ सेप्टेम्बर २९" — verified against Node's full-ICU
/// output for all 12 months (short == long month names in ne-NP).
///
/// The admin-typed `dateLabel` still wins verbatim; this is only the
/// `publishedAt` fallback. Mirrors formatNoticeDate in app/(tabs)/index.tsx
/// and formatLatest in app/notices.tsx.
const _neMonths = [
  'जनवरी',
  'फेब्रुअरी',
  'मार्च',
  'अप्रिल',
  'मे',
  'जुन',
  'जुलाई',
  'अगस्ट',
  'सेप्टेम्बर',
  'अक्टोबर',
  'नोभेम्बर',
  'डिसेम्बर',
];

const _devaDigits = '०१२३४५६७८९';

String _toDeva(int n) => n.toString().split('').map((c) {
      final d = int.tryParse(c);
      return d == null ? c : _devaDigits[d];
    }).join();

/// Formats [d] like the Expo ne-NP fallback. The instant is rendered in the
/// device's local timezone, exactly like `new Date(millis)` on the phone.
String noticeNeDate(DateTime d) {
  final local = d.toLocal();
  return '${_toDeva(local.year)} ${_neMonths[local.month - 1]} ${_toDeva(local.day)}';
}
