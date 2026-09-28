import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/theme/app_theme.dart';

/// Constitution section reader — mirrors app/constitution/[sectionId].tsx.
///
/// Fetches `parts/{sectionId}` from the static constitution JSON host and
/// renders the content nodes recursively (heading/article/note/list-item/
/// table/row/cell/paragraph), with an NP/EN language toggle and the legal
/// reference header.
class ConstitutionSectionScreen extends StatefulWidget {
  final String sectionId;
  const ConstitutionSectionScreen({super.key, required this.sectionId});

  @override
  State<ConstitutionSectionScreen> createState() =>
      _ConstitutionSectionScreenState();
}

class _ConstitutionSectionScreenState extends State<ConstitutionSectionScreen> {
  static const _base = 'https://nepal-constitution-json.pages.dev';
  late Future<Map<String, dynamic>> _future;
  String _lang = 'np';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final filename = Uri.decodeComponent(widget.sectionId).split('/').last;
    final res = await http.get(Uri.parse('$_base/parts/$filename'));
    if (res.statusCode != 200) {
      throw Exception('part: ${res.statusCode}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Constitution'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'np', label: Text('ने')),
                ButtonSegment(value: 'en', label: Text('EN')),
              ],
              selected: {_lang},
              onSelectionChanged: (s) => setState(() => _lang = s.first),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load section:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final part = snap.data!;
          final title = _lang == 'np'
              ? (part['titleNp'] ?? '').toString()
              : (part['titleEn'] ?? '').toString();
          final legalRef = _lang == 'np'
              ? (part['legalReferenceNp'] ?? '').toString()
              : (part['legalReferenceEn'] ?? '').toString();
          final nodes = part[_lang == 'np' ? 'containnp' : 'containen'];
          final List nodeList = nodes is List ? nodes : [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (title.isNotEmpty)
                Text(title,
                    style: Theme.of(context).textTheme.headlineSmall),
              if (legalRef.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(legalRef,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
              ],
              const Divider(height: 24),
              for (final n in nodeList)
                if (n is Map) _node(Map<String, dynamic>.from(n), 0),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _childNodes(Map<String, dynamic> n) {
    final out = <Map<String, dynamic>>[];
    for (final k in ['children', 'items', 'content']) {
      final v = n[k];
      if (v is List) {
        out.addAll(v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  Widget _node(Map<String, dynamic> n, int depth) {
    final tag = (n['tag'] ?? 'paragraph').toString();
    final title = (n['title'] ?? '').toString();
    final text = (n['text'] ?? '').toString();
    final number = (n['number'] ?? n['articleNo'] ?? '').toString();
    final children = _childNodes(n);

    switch (tag) {
      case 'heading':
        {
          final level = n['level'] is int ? n['level'] as int : 2;
          final size = level <= 1 ? 20.0 : (level == 2 ? 18.0 : 16.0);
          final headingText =
              [number, title.isNotEmpty ? title : text].where((s) => s.isNotEmpty).join(' ');
          return Padding(
            padding: EdgeInsets.only(top: depth == 0 ? 16 : 10, bottom: 6),
            child: Text(headingText,
                style: TextStyle(
                    fontSize: size, fontWeight: FontWeight.bold)),
          );
        }
      case 'article':
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (number.isNotEmpty || title.isNotEmpty)
                  Text(
                      [number, title].where((s) => s.isNotEmpty).join(' '),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(text,
                        style: const TextStyle(height: 1.6)),
                  ),
                for (final c in children) _node(c, depth + 1),
              ],
            ),
          ),
        );
      case 'note':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text([title, text].where((s) => s.isNotEmpty).join(' '),
              style: const TextStyle(
                  fontStyle: FontStyle.italic, height: 1.5)),
        );
      case 'list-item':
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(number.isNotEmpty ? '$number ' : '• ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                    if (text.isNotEmpty)
                      Text(text,
                          style: const TextStyle(height: 1.5)),
                    for (final c in children) _node(c, depth + 1),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'table':
        {
          final rows = n['rows'];
          final List rowList = rows is List ? rows : [];
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(color: Colors.grey.shade300),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                for (final r in rowList)
                  if (r is Map)
                    TableRow(
                      children: [
                        for (final cell in ((r['cells'] is List)
                            ? (r['cells'] as List)
                            : []))
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: cell is Map
                                ? _node(
                                    Map<String, dynamic>.from(cell),
                                    depth + 1)
                                : Text(cell.toString()),
                          ),
                      ],
                    ),
              ],
            ),
          );
        }
      case 'row':
      case 'cell':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty)
              Text(text, style: const TextStyle(height: 1.5)),
            for (final c in children) _node(c, depth + 1),
          ],
        );
      default:
        {
          final body =
              [title, text].where((s) => s.isNotEmpty).join(' ');
          if (body.isEmpty && children.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (body.isNotEmpty)
                  Text(body,
                      style: const TextStyle(height: 1.6, fontSize: 15)),
                for (final c in children) _node(c, depth + 1),
              ],
            ),
          );
        }
    }
  }
}
