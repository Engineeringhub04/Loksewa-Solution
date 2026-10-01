// Widget tests for the analytics chart kit (lib/widgets/charts/).
//
// Each chart renders with sample data, empty states show at 0/1 data points,
// and tap interactions fire (heatmap select, donut select, bar select toggle).
// All animations are finite draw-ins, so pumps stay bounded — no pumpAndSettle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/widgets/charts/bar_chart.dart';
import 'package:loksewa_solution/widgets/charts/chart_card.dart';
import 'package:loksewa_solution/widgets/charts/donut_chart.dart';
import 'package:loksewa_solution/widgets/charts/heatmap.dart';
import 'package:loksewa_solution/widgets/charts/line_area_chart.dart';
import 'package:loksewa_solution/widgets/charts/radar_chart.dart';
import 'package:loksewa_solution/widgets/charts/stat_tile.dart';

Widget _wrap(Widget child, {double width = 360}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: width, child: child),
    ),
  );
}

/// Lets the finite draw-in animations (400–600ms) finish without an unbounded
/// pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  group('ChartCard', () {
    testWidgets('renders title, subtitle, right and footer', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChartCard(
          title: 'Study time',
          subtitle: 'Last 30 days',
          right: Text('RIGHT'),
          footer: Text('FOOTER'),
          height: 120,
          child: Text('PLOT'),
        ),
      ));
      await _settle(tester);
      expect(find.text('Study time'), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('RIGHT'), findsOneWidget);
      expect(find.text('FOOTER'), findsOneWidget);
      expect(find.text('PLOT'), findsOneWidget);
    });

    testWidgets('loading shows a spinner and hides the footer', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChartCard(
          title: 'T',
          loading: true,
          footer: Text('FOOTER'),
          child: Text('PLOT'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('PLOT'), findsNothing);
      expect(find.text('FOOTER'), findsNothing);
    });

    testWidgets('empty shows icon + label', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChartCard(
          title: 'T',
          empty: true,
          emptyLabel: 'No data yet',
          emptyIcon: Icons.bar_chart_outlined,
          child: Text('PLOT'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No data yet'), findsOneWidget);
      expect(find.byIcon(Icons.bar_chart_outlined), findsOneWidget);
      expect(find.text('PLOT'), findsNothing);
    });
  });

  group('LineAreaChart', () {
    final values = [2.0, 5.0, 3.0, 8.0, 6.0, 9.0, 4.0];
    final labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    testWidgets('renders with sample data', (tester) async {
      await tester.pumpWidget(_wrap(
        LineAreaChart(
          values: values,
          labels: labels,
          color: Colors.blue,
          emptyLabel: 'Nothing here',
        ),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(LineAreaChart), findsOneWidget);
    });

    testWidgets('fewer than 2 values shows the empty label', (tester) async {
      await tester.pumpWidget(_wrap(
        const LineAreaChart(
          values: [5.0],
          color: Colors.blue,
          emptyLabel: 'Nothing here',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('tap selects a point without crashing', (tester) async {
      await tester.pumpWidget(_wrap(
        LineAreaChart(values: values, labels: labels, color: Colors.blue),
      ));
      await _settle(tester);
      await tester.tap(find.byType(LineAreaChart));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('seeded prefix renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(
        LineAreaChart(
          values: values,
          labels: labels,
          color: Colors.blue,
          seededCount: 3,
        ),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('BarChart', () {
    final values = [3.0, 0.0, 7.0, 5.0, 9.0];

    testWidgets('renders with sample data and average line', (tester) async {
      await tester.pumpWidget(_wrap(
        BarChart(
          values: values,
          labels: const ['a', 'b', 'c', 'd', 'e'],
          color: Colors.blue,
          averageValue: 4.8,
          averageLabel: 'avg',
          emptyLabel: 'No bars',
        ),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('empty values show the empty label', (tester) async {
      await tester.pumpWidget(_wrap(
        const BarChart(
          values: [],
          color: Colors.blue,
          emptyLabel: 'No bars',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No bars'), findsOneWidget);
    });

    testWidgets('tap fires onSelect with the bar index', (tester) async {
      int? selected;
      await tester.pumpWidget(_wrap(
        BarChart(
          values: values,
          color: Colors.blue,
          onSelect: (index) => selected = index,
        ),
      ));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('bar-tap-2')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected, 2);
    });

    testWidgets('accent indices and seeded count render without crashing',
        (tester) async {
      await tester.pumpWidget(_wrap(
        BarChart(
          values: values,
          color: Colors.blue,
          accentIndices: const [0, 3],
          accentColor: Colors.orange,
          seededCount: 1,
          selectedIndex: 4,
        ),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('RankedBars', () {
    final rows = [
      const RankedBarRow(
          key: 'gk', label: 'General Knowledge', value: 72, display: '72%'),
      const RankedBarRow(
          key: 'pm',
          label: 'Public Management',
          value: 45,
          display: '45%',
          muted: true),
    ];

    testWidgets('renders one row per entry with display text', (tester) async {
      await tester.pumpWidget(_wrap(
        RankedBars(rows: rows, color: Colors.blue),
      ));
      await _settle(tester);
      expect(find.text('General Knowledge'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      expect(find.text('Public Management'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
    });

    testWidgets('tap fires onSelect with the row key', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(
        RankedBars(
          rows: rows,
          color: Colors.blue,
          onSelect: (key) => selected = key,
        ),
      ));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('ranked-row-pm')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected, 'pm');
    });

    testWidgets('empty rows show the empty label', (tester) async {
      await tester.pumpWidget(_wrap(
        const RankedBars(
          rows: [],
          color: Colors.blue,
          emptyLabel: 'Nothing ranked',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Nothing ranked'), findsOneWidget);
    });
  });

  group('DonutChart', () {
    final data = [
      const DonutDatum(
          key: 'a', label: 'Reading', value: 60, color: Colors.blue),
      const DonutDatum(
          key: 'b', label: 'Practice', value: 40, color: Colors.green),
    ];

    testWidgets('renders ring, centre total and legend', (tester) async {
      await tester.pumpWidget(_wrap(
        DonutChart(
          data: data,
          centerValue: '100',
          centerLabel: 'total',
          emptyLabel: 'No data',
        ),
        width: 420,
      ));
      await _settle(tester);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('total'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);
    });

    testWidgets('legend tap fires onSelect with the key', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(
        DonutChart(
          data: data,
          centerValue: '100',
          centerLabel: 'total',
          onSelect: (key) => selected = key,
        ),
        width: 420,
      ));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('donut-legend-b')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected, 'b');
    });

    testWidgets('zero total shows the empty label', (tester) async {
      await tester.pumpWidget(_wrap(
        const DonutChart(
          data: [],
          centerValue: '0',
          centerLabel: 'total',
          emptyLabel: 'No data',
        ),
        width: 420,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('selected arc renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(
        DonutChart(
          data: data,
          centerValue: '100',
          centerLabel: 'total',
          selectedKey: 'a',
        ),
        width: 420,
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('RadarChart', () {
    List<RadarAxis> axes() => [
          const RadarAxis(key: 'a', label: 'Speed', value: 80),
          const RadarAxis(key: 'b', label: 'Accuracy', value: 60),
          const RadarAxis(key: 'c', label: 'Theory', value: 40),
          const RadarAxis(key: 'd', label: 'GK', value: 90),
          const RadarAxis(key: 'e', label: 'PM', value: 55),
          const RadarAxis(
              key: 'f', label: 'Current', value: 0, untouched: true),
        ];

    testWidgets('draws 6 axes with labels', (tester) async {
      await tester.pumpWidget(_wrap(
        RadarChart(axes: axes(), color: Colors.blue),
      ));
      await _settle(tester);
      for (final label in [
        'Speed',
        'Accuracy',
        'Theory',
        'GK',
        'PM',
        'Current'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('fewer than 3 axes shows the empty label', (tester) async {
      await tester.pumpWidget(_wrap(
        const RadarChart(
          axes: [
            RadarAxis(key: 'a', label: 'Speed', value: 80),
            RadarAxis(key: 'b', label: 'Accuracy', value: 60),
          ],
          color: Colors.blue,
          emptyLabel: 'Need 3+ axes',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Need 3+ axes'), findsOneWidget);
    });
  });

  group('Heatmap', () {
    // 2026-09-27 is a Sunday.
    List<HeatmapDay> days() => List.generate(14, (i) {
          final date = DateTime.utc(2026, 9, 27 + i);
          final key =
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          return HeatmapDay(key: key, value: (i * 7) % 11);
        });

    testWidgets('renders cells and legend', (tester) async {
      await tester.pumpWidget(_wrap(
        SizedBox(
          height: 220,
          child: Heatmap(
            days: days(),
            color: Colors.green,
            weekdayLabels: const [
              'Sun',
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat'
            ],
            monthLabelFor: (key) => key.substring(5, 7) == '09' ? 'Sep' : 'Oct',
            emptyLabel: 'No days',
          ),
        ),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(Heatmap), findsOneWidget);
    });

    testWidgets('cell tap fires onSelect with the day', (tester) async {
      HeatmapDay? selected;
      await tester.pumpWidget(_wrap(
        SizedBox(
          height: 220,
          child: Heatmap(
            days: days(),
            color: Colors.green,
            weekdayLabels: const [
              'Sun',
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat'
            ],
            onSelect: (day) => selected = day,
          ),
        ),
      ));
      await _settle(tester);
      await tester
          .tap(find.byKey(const ValueKey('heatmap-cell-2026-09-28')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected?.key, '2026-09-28');
    });

    testWidgets('no days shows the empty label', (tester) async {
      await tester.pumpWidget(_wrap(
        const SizedBox(
          height: 220,
          child: Heatmap(
            days: [],
            color: Colors.green,
            weekdayLabels: ['S', 'M', 'T', 'W', 'T', 'F', 'S'],
            emptyLabel: 'No days',
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No days'), findsOneWidget);
    });

    testWidgets('legend shows less/more labels', (tester) async {
      await tester.pumpWidget(_wrap(
        const HeatmapLegend(
          color: Colors.green,
          lessLabel: 'Less',
          moreLabel: 'More',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Less'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });
  });

  group('StatTile', () {
    testWidgets('renders icon, value, delta and sparkline', (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(
          icon: Icons.timer_outlined,
          label: 'Study time',
          value: '4h 20m',
          accent: Colors.blue,
          delta: 12.4,
          deltaLabel: 'vs last week',
          trend: [1.0, 2.0, 1.5, 3.0, 2.5],
        ),
      ));
      await _settle(tester);
      expect(find.text('Study time'), findsOneWidget);
      expect(find.text('4h 20m'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.text('vs last week'), findsOneWidget);
      expect(find.byType(Sparkline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('negative delta shows down arrow styling', (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(
          icon: Icons.timer_outlined,
          label: 'Study time',
          value: '1h 0m',
          accent: Colors.blue,
          delta: -8.2,
          trend: [3.0, 2.0, 1.0],
        ),
      ));
      await _settle(tester);
      expect(find.text('8%'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('zero delta hides the delta row', (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(
          icon: Icons.timer_outlined,
          label: 'Study time',
          value: '1h 0m',
          accent: Colors.blue,
          delta: 0,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });

    testWidgets('single value shows a dot, not a line', (tester) async {
      await tester.pumpWidget(_wrap(
        const SizedBox(
          width: 120,
          child: Sparkline(values: [2.0], color: Colors.blue),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Sparkline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
