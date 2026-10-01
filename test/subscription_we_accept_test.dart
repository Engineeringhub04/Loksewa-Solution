// Widget tests for the "We Accept" watermark redesign and the memory-only
// logo precache in lib/screens/shop/subscription_screen.dart.
//
// Network images are served by a mock HttpOverrides returning a 1x1 PNG,
// so no test touches the network. Animation note: the screen's sections
// enter through SyllabusEntrance (and PreloadingWidget runs an infinite
// animation while loading), so pumps stay small and repeated instead of
// one big pumpAndSettle (per the AGENTS.md widget-test lessons).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/shop/subscription_screen.dart';
import 'package:loksewa_solution/services/subscription_service.dart';

/// Mirrors the private `_paymentLogos` list in the screen under test.
const List<String> _kLogoUris = [
  'https://i.ibb.co/HLpHmnQz/esewa-icon-large.png',
  'https://i.ibb.co/tMHZRHKQ/Khalti-Logo-New-3.png',
  'https://i.ibb.co/YBT7bXZQ/fonepay-logo-png-seeklogo-385625.png',
];

/// 1x1 transparent PNG served for every network image request.
const List<int> _kPng = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
  120, 218, 99, 252, 207, 192, 80, 15, 0, 4, 133, 1, 128, 132, 169, 140, 33,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

class _PngHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _PngHttpClient();
}

class _PngHttpClient implements HttpClient {
  /// Counts every network image request served by the mock.
  static int requests = 0;

  @override
  bool autoUncompress = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return const _PngHttpClientRequest();
  }
}

class _PngHttpClientRequest implements HttpClientRequest {
  const _PngHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientResponse> close() async => const _PngHttpClientResponse();
}

class _PngHttpClientResponse implements HttpClientResponse {
  const _PngHttpClientResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _kPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_kPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

SubscriptionScreenData _data() => const SubscriptionScreenData(
      plans: [
        SubscriptionPlan(
          id: 'monthly',
          name: 'Monthly Pro',
          billingCycle: BillingCycle.monthly,
          price: 199,
          currency: 'NPR',
          durationDays: 30,
          features: [],
          isActive: true,
          order: 0,
          colorFrom: '#7C3AED',
          colorTo: '#DB2777',
        ),
      ],
      history: [],
    );

/// Pumps the screen with the loader seam and settles the load plus the
/// SyllabusEntrance choreography using small repeated pumps (tall surface
/// so lazily-built sections all build at once).
Future<void> _pumpLoaded(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1080, 8000);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: SubscriptionScreen(loader: () async => _data()),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final HttpOverrides? previous = HttpOverrides.current;

  setUp(() {
    HttpOverrides.global = _PngHttpOverrides();
    _PngHttpClient.requests = 0;
  });

  tearDown(() {
    HttpOverrides.global = previous;
  });

  testWidgets('precaches the payment logos during the preloading phase',
      (WidgetTester tester) async {
    // Hold the loader open so the screen stays in its preloading phase.
    final gate = Completer<SubscriptionScreenData>();
    tester.view.physicalSize = const Size(1080, 8000);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionScreen(loader: () => gate.future),
      ),
    );
    // Waiting branch: PreloadingWidget is on screen and the in-memory
    // logo warmup fires here, before any data arrives.
    await tester.pump();
    // Flush the async network-image load through the mock HTTP client.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final cache = PaintingBinding.instance.imageCache;
    for (final uri in _kLogoUris) {
      expect(
        cache.containsKey(NetworkImage(uri)),
        isTrue,
        reason: 'expected $uri to be precached during preloading',
      );
    }
  });

  testWidgets('renders the We Accept title and watermark logos without boxes',
      (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpLoaded(tester);

    // Title row kept.
    expect(find.text('We Accept'), findsOneWidget);
    // The three brand logos are the only Image widgets on the page.
    expect(find.byType(Image), findsNWidgets(3));
    // The logos Row: the only Row ancestor of the logo images
    // (one hit per logo, all the same Row).
    final logoRowFinder =
        find.ancestor(of: find.byType(Image), matching: find.byType(Row));
    expect(logoRowFinder, findsNWidgets(3));
    final logoRow = find.byWidget(logoRowFinder.evaluate().first.widget);
    // No white bordered boxes anywhere around the logos — they sit
    // directly on the page background.
    final whiteBoxesInRow = find.descendant(
      of: logoRow,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.white,
      ),
    );
    expect(whiteBoxesInRow, findsNothing);
    // Each logo sits directly on the page background as a subtle
    // watermark: reduced opacity, no chip.
    final logoOpacities = find.descendant(
      of: logoRow,
      matching: find.byType(Opacity),
    );
    expect(logoOpacities, findsNWidgets(3));
    for (final element in logoOpacities.evaluate()) {
      final opacity = (element.widget as Opacity).opacity;
      expect(opacity, lessThan(1.0));
      expect(opacity, 0.55);
    }
  });

  testWidgets('watermark logos stay legible in dark mode',      (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpLoaded(tester, dark: true);

    expect(find.text('We Accept'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3));
    final logoRowFinder =
        find.ancestor(of: find.byType(Image), matching: find.byType(Row));
    expect(logoRowFinder, findsNWidgets(3));
    final logoRow = find.byWidget(logoRowFinder.evaluate().first.widget);
    final logoOpacities = find.descendant(
      of: logoRow,
      matching: find.byType(Opacity),
    );
    expect(logoOpacities, findsNWidgets(3));
    for (final element in logoOpacities.evaluate()) {
      // A touch stronger in dark mode so the light-background brand
      // marks stay legible, still watermark-subtle.
      expect((element.widget as Opacity).opacity, 0.7);
    }
  });

  testWidgets('reopening the page serves logos from memory without reload',
      (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(1080, 8000);

    // Start from a cold memory cache so this test owns the request count.
    PaintingBinding.instance.imageCache.clear();

    // First open: the logos load and land in Flutter's in-memory
    // image cache (the mock serves one request per logo).
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionScreen(loader: () async => _data()),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Image), findsNWidgets(3));
    final before = _PngHttpClient.requests;
    expect(before, greaterThan(0));

    // Back + reopen within the same session: a fresh page instance.
    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionScreen(loader: () async => _data()),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Image), findsNWidgets(3));
    // Zero new network traffic: the logos rendered straight from the
    // in-memory cache — no reload flicker.
    expect(_PngHttpClient.requests, before);
  });
}
