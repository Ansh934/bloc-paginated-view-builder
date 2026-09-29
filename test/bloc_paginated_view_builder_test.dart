import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_paginated_view_builder/bloc_paginated_view_builder.dart';

void main() {
  testWidgets('requests the initial page and renders list data', (tester) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc, initialPage: 3);

    await tester.pumpWidget(harness.build());

    expect(bloc.requests, hasLength(1));
    expect(bloc.requests.single.page, 3);
    bloc.publish(const _TestState(loading: true));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    bloc.publish(_page(['Apple', 'Banana'], page: 3, totalPages: 3));
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Banana'), findsOneWidget);
    expect(harness.items, ['Apple', 'Banana']);
  });

  testWidgets('renders grid data using the provided delegate', (tester) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc, isGrid: true);

    await tester.pumpWidget(harness.build());
    bloc.publish(_page(['Apple', 'Banana']));
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets('unrelated Bloc states do not rebuild the loaded items', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc);
    await tester.pumpWidget(harness.build());
    final loaded = _page(['Apple', 'Banana']);
    bloc.publish(loaded);
    await tester.pumpAndSettle();
    final buildsAfterLoad = harness.itemBuilds;
    expect(buildsAfterLoad, greaterThan(0));

    bloc.publish(_TestState(response: loaded.response, headerLabel: 'Unrelated'));
    await tester.pumpAndSettle();
    expect(harness.itemBuilds, buildsAfterLoad);
    expect(bloc.requests, hasLength(1));
  });

  testWidgets('a configured header still receives every Bloc state', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc, showHeader: true);
    await tester.pumpWidget(harness.build());
    final loaded = _page(['Apple']);
    bloc.publish(loaded);
    await tester.pumpAndSettle();
    expect(find.text('Header'), findsOneWidget);

    bloc.publish(_TestState(response: loaded.response, headerLabel: 'Updated'));
    await tester.pumpAndSettle();
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    expect(bloc.requests, hasLength(1));
  });

  testWidgets('deleting an item refills a viewport that can no longer scroll', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc, trackItemChanges: true);
    await tester.pumpWidget(harness.build());
    final loaded = _page(['1:Apple', '2:Banana', '3:Cherry', '4:Date'],
        totalPages: 2);
    bloc.publish(loaded);
    await tester.pumpAndSettle();
    expect(bloc.requests, hasLength(1));

    bloc.publish(_TestState(response: loaded.response, deletedItemId: '1'));
    await tester.pump();
    await tester.pump();
    expect(bloc.requests.map((event) => event.page), [1, 2]);
    expect(harness.removals, [(0, '1:Apple')]);

    bloc.publish(_page(['5:Elderberry'], page: 2, totalPages: 2));
    await tester.pumpAndSettle();
    expect(harness.items, ['2:Banana', '3:Cherry', '4:Date', '5:Elderberry']);
    expect(harness.removals, hasLength(1));
  });

  testWidgets('search debounce blocks automatic requests for the old query', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final search = TextEditingController();
    addTearDown(bloc.close);
    addTearDown(search.dispose);
    final harness = _Harness(bloc, searchController: search);
    await tester.pumpWidget(harness.build());
    search.text = 'new query';
    bloc.publish(_page(['Old result'], totalPages: 3));
    await tester.pump();
    expect(bloc.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bloc.requests.map((event) => event.page), [1, 1]);
    expect(bloc.requests.last.query, 'new query');

    bloc.publish(_page(['New result'], totalPages: 2));
    await tester.pump();
    expect(bloc.requests.map((event) => event.page), [1, 1, 2]);
    expect(bloc.requests.last.query, 'new query');
  });

  for (final isGrid in [false, true]) {
    final mode = isGrid ? 'grid' : 'list';

    testWidgets('$mode fills a short viewport one page at a time', (tester) async {
      final bloc = _TestBloc();
      final scroll = ScrollController();
      addTearDown(bloc.close);
      addTearDown(scroll.dispose);
      final harness = _Harness(bloc, isGrid: isGrid, scrollController: scroll);

      await tester.pumpWidget(harness.build());
      bloc.publish(_page(['First'], totalPages: 5));
      await tester.pump();
      expect(bloc.requests.map((event) => event.page), [1, 2]);

      // Layout changes and rebuilds during the request must not duplicate it.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(harness.build());
      expect(bloc.requests.map((event) => event.page), [1, 2]);

      bloc.publish(_page(['Second'], page: 2, totalPages: 5));
      await tester.pump();
      expect(bloc.requests.map((event) => event.page), [1, 2, 3]);

      bloc.publish(_page(
        List.generate(12, (index) => 'More $index'),
        page: 3,
        totalPages: 5,
      ));
      await tester.pumpAndSettle();
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(bloc.requests.map((event) => event.page), [1, 2, 3]);

      await _scrollToEnd(tester, scroll);
      expect(bloc.requests.map((event) => event.page), [1, 2, 3, 4]);
    });

    testWidgets('$mode stops filling when the last page is still short', (
      tester,
    ) async {
      final bloc = _TestBloc();
      addTearDown(bloc.close);
      await tester.pumpWidget(_Harness(bloc, isGrid: isGrid).build());
      bloc.publish(_page(['First'], totalPages: 2));
      await tester.pump();
      expect(bloc.requests.map((event) => event.page), [1, 2]);
      bloc.publish(_page(['Last'], page: 2, totalPages: 2));
      await tester.pumpAndSettle();
      expect(bloc.requests.map((event) => event.page), [1, 2]);
      expect(find.text('Last'), findsOneWidget);
    });
  }

  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  ]) {
    testWidgets('grid scrolls with ${kind.name} dragging', (tester) async {
      final bloc = _TestBloc();
      final scroll = ScrollController();
      addTearDown(bloc.close);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _Harness(bloc, isGrid: true, scrollController: scroll).build(),
      );
      bloc.publish(_page(List.generate(20, (index) => 'Item $index')));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(GridView),
        const Offset(0, -180),
        kind: kind,
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('grid scrolls with mouse wheel input', (tester) async {
    final bloc = _TestBloc();
    final scroll = ScrollController();
    addTearDown(bloc.close);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _Harness(bloc, isGrid: true, scrollController: scroll).build(),
    );
    bloc.publish(_page(List.generate(20, (index) => 'Item $index')));
    await tester.pumpAndSettle();

    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(find.byType(GridView)),
      scrollDelta: const Offset(0, 160),
    ));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('viewport growth loads more without a scroll event', (tester) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(_Harness(bloc).build());
    bloc.publish(_page(List.generate(4, (index) => 'Item $index'), totalPages: 2));
    await tester.pumpAndSettle();
    expect(bloc.requests, hasLength(1));

    await tester.pumpWidget(_Harness(bloc, height: 480).build());
    await tester.pump();
    expect(bloc.requests.map((event) => event.page), [1, 2]);
  });

  testWidgets('denser grid layout loads more without a scroll event', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(_Harness(bloc, isGrid: true).build());
    bloc.publish(_page(List.generate(4, (index) => 'Item $index'), totalPages: 2));
    await tester.pumpAndSettle();
    expect(bloc.requests, hasLength(1));

    await tester.pumpWidget(
      _Harness(bloc, isGrid: true, gridColumns: 4).build(),
    );
    await tester.pump();
    expect(bloc.requests.map((event) => event.page), [1, 2]);
  });

  testWidgets('viewport filling does not retry errors automatically', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc);
    await tester.pumpWidget(harness.build());
    bloc.publish(_page(['First'], totalPages: 5));
    await tester.pump();
    expect(bloc.requests.map((event) => event.page), [1, 2]);

    bloc.publish(const _TestState(error: 'Unavailable'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness.build());
    await tester.pump(const Duration(seconds: 1));
    expect(bloc.requests.map((event) => event.page), [1, 2]);
  });

  for (final withMetadata in [false, true]) {
    testWidgets('empty page stops viewport filling (metadata: $withMetadata)', (
      tester,
    ) async {
      final bloc = _TestBloc();
      addTearDown(bloc.close);
      await tester.pumpWidget(_Harness(bloc).build());
      bloc.publish(_TestState(response: PaginatedResponse<String>(
        data: ['First'],
        pagination: withMetadata
            ? const Pagination(currentPage: 1, totalPages: 5)
            : null,
      )));
      await tester.pump();
      expect(bloc.requests.map((event) => event.page), [1, 2]);
      bloc.publish(_TestState(response: PaginatedResponse<String>(
        data: [],
        pagination: withMetadata
            ? const Pagination(currentPage: 2, totalPages: 5)
            : null,
      )));
      await tester.pumpAndSettle();
      expect(bloc.requests.map((event) => event.page), [1, 2]);
    });
  }

  testWidgets('unbounded shrink wrap does not fetch all remaining pages', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      _Harness(bloc, shrinkWrap: true).build(unboundedHeight: true),
    );
    bloc.publish(_page(['First'], totalPages: 100));
    await tester.pumpAndSettle();
    expect(bloc.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded shrink wrap fills without overflowing its parent', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final scroll = ScrollController();
    addTearDown(bloc.close);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _Harness(bloc, shrinkWrap: true, scrollController: scroll).build(),
    );
    bloc.publish(_page(['First'], totalPages: 3));
    await tester.pump();
    expect(bloc.requests.map((event) => event.page), [1, 2]);
    bloc.publish(_page(
      List.generate(10, (index) => 'More $index'),
      page: 2,
      totalPages: 3,
    ));
    await tester.pumpAndSettle();
    expect(bloc.requests.map((event) => event.page), [1, 2]);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('appends each page once and stops at the last page', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final scroll = ScrollController();
    addTearDown(bloc.close);
    addTearDown(scroll.dispose);
    final harness = _Harness(bloc, scrollController: scroll);
    final firstPage = List.generate(12, (index) => 'First $index');

    await tester.pumpWidget(harness.build());
    bloc.publish(_page(firstPage, totalPages: 2));
    await tester.pump();
    await _scrollToEnd(tester, scroll);

    expect(bloc.requests.map((event) => event.page), [1, 2]);
    expect(bloc.requests.last.kind, 'more');
    await _scrollToEnd(tester, scroll);
    expect(bloc.requests, hasLength(2));

    bloc.publish(_page(['Second 0', 'Second 1'], page: 2, totalPages: 2));
    await tester.pump();
    expect(harness.items, [...firstPage, 'Second 0', 'Second 1']);

    // A distinct state with the same page must not append that page again.
    bloc.publish(_page(['Second 0', 'Second 1'], page: 2, totalPages: 2));
    await tester.pump();
    await _scrollToEnd(tester, scroll);

    expect(harness.items, [...firstPage, 'Second 0', 'Second 1']);
    expect(bloc.requests, hasLength(2));
  });

  testWidgets('debounces custom search events and resets to the initial page', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final search = TextEditingController(text: 'initial');
    final scroll = ScrollController();
    addTearDown(bloc.close);
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);
    final harness = _Harness(
      bloc,
      searchController: search,
      scrollController: scroll,
      initialPage: 3,
      customSearch: true,
    );

    await tester.pumpWidget(harness.build());
    expect(bloc.requests.single.query, 'initial');
    bloc.publish(
      _page(List.generate(12, (index) => 'Original $index'),
          page: 3, totalPages: 5),
    );
    await tester.pump();
    await _scrollToEnd(tester, scroll);
    expect(bloc.requests.last.page, 4);
    bloc.publish(_page(['Next page'], page: 4, totalPages: 5));
    await tester.pump();

    search.text = 'a';
    await tester.pump(const Duration(milliseconds: 150));
    search.text = 'apple';
    await tester.pump(const Duration(milliseconds: 299));
    expect(bloc.requests, hasLength(2));
    await tester.pump(const Duration(milliseconds: 1));

    expect(bloc.requests, hasLength(3));
    expect(bloc.requests.last.kind, 'search');
    expect(bloc.requests.last.query, 'apple');
    expect(bloc.requests.last.page, 3);
    bloc.publish(_page(['Apple'], page: 3, totalPages: 3));
    await tester.pump();
    expect(harness.items, ['Apple']);
  });

  testWidgets('without page metadata, an empty page ends pagination', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final scroll = ScrollController();
    addTearDown(bloc.close);
    addTearDown(scroll.dispose);
    final harness = _Harness(bloc, scrollController: scroll);
    final firstPage = List.generate(12, (index) => 'First $index');

    await tester.pumpWidget(harness.build());
    final firstResponse = PaginatedResponse<String>(data: firstPage);
    bloc.publish(_TestState(response: firstResponse));
    await tester.pump();
    await _scrollToEnd(tester, scroll);
    expect(bloc.requests.map((event) => event.page), [1, 2]);

    bloc.publish(_TestState(response: firstResponse, loading: true));
    await tester.pump();
    bloc.publish(_TestState(response: firstResponse));
    await tester.pump();
    expect(harness.items, firstPage);
    await _scrollToEnd(tester, scroll);
    expect(bloc.requests.map((event) => event.page), [1, 2]);

    final response = PaginatedResponse<String>(data: ['Second page']);
    bloc.publish(_TestState(response: response));
    await tester.pump();
    expect(harness.items, [...firstPage, 'Second page']);
    // Other state changes can retain the same response object.
    bloc.publish(_TestState(response: response));
    await tester.pump();
    expect(harness.items, [...firstPage, 'Second page']);

    await _scrollToEnd(tester, scroll);
    expect(bloc.requests.map((event) => event.page), [1, 2, 3]);
    bloc.publish(_TestState(response: PaginatedResponse<String>(data: [])));
    await tester.pump();
    await _scrollToEnd(tester, scroll);
    expect(bloc.requests, hasLength(3));
    expect(harness.items, [...firstPage, 'Second page']);
  });

  testWidgets('search falls back to loadEvent when no search builder exists', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final search = TextEditingController();
    addTearDown(bloc.close);
    addTearDown(search.dispose);
    final harness = _Harness(bloc, searchController: search);

    await tester.pumpWidget(harness.build());
    bloc.publish(_page(['Original']));
    await tester.pump();
    search.text = 'query';
    await tester.pump(const Duration(milliseconds: 300));

    expect(bloc.requests, hasLength(2));
    expect(bloc.requests.last.kind, 'load');
    expect(bloc.requests.last.query, 'query');
    expect(bloc.requests.last.page, 1);
  });

  testWidgets('refresh resets pagination so later pages can load again', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final scroll = ScrollController();
    final refresh = PaginatedListRefreshController();
    addTearDown(bloc.close);
    addTearDown(scroll.dispose);
    final harness = _Harness(
      bloc,
      scrollController: scroll,
      refreshController: refresh,
    );
    final firstPage = List.generate(12, (index) => 'Original $index');
    final refreshedPage = List.generate(12, (index) => 'Refreshed $index');

    await tester.pumpWidget(harness.build());
    bloc.publish(_page(firstPage, totalPages: 2));
    await tester.pump();
    await _scrollToEnd(tester, scroll);
    bloc.publish(_page(['Old second page'], page: 2, totalPages: 2));
    await tester.pump();

    final completion = refresh.refresh();
    await tester.pump();
    expect(bloc.requests.map((event) => event.page), [1, 2, 1]);
    bloc.publish(_page(refreshedPage, totalPages: 2));
    await tester.pump();
    await completion;
    expect(harness.items, refreshedPage);

    await _scrollToEnd(tester, scroll);
    expect(bloc.requests.map((event) => event.page), [1, 2, 1, 2]);
    bloc.publish(_page(['New second page'], page: 2, totalPages: 2));
    await tester.pump();
    expect(harness.items, [...refreshedPage, 'New second page']);
  });

  testWidgets('a failed next page can be requested again without skipping it', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final scroll = ScrollController();
    addTearDown(bloc.close);
    addTearDown(scroll.dispose);
    final harness = _Harness(bloc, scrollController: scroll);
    final firstPage = List.generate(12, (index) => 'First $index');

    await tester.pumpWidget(harness.build());
    bloc.publish(_page(firstPage, totalPages: 3));
    await tester.pump();
    await _scrollToEnd(tester, scroll);
    expect(bloc.requests.last.page, 2);

    bloc.publish(const _TestState(error: 'Connection lost'));
    await tester.pump();
    expect(harness.items, firstPage);
    await _scrollToEnd(tester, scroll);

    expect(bloc.requests.map((event) => event.page), [1, 2, 2]);
    bloc.publish(_page(['Recovered'], page: 2, totalPages: 3));
    await tester.pump();
    expect(harness.items, [...firstPage, 'Recovered']);
  });

  testWidgets('refresh calls share a future that waits for successful data', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final refresh = PaginatedListRefreshController();
    addTearDown(bloc.close);
    final harness = _Harness(bloc, refreshController: refresh);

    await tester.pumpWidget(harness.build());
    final original = _page(['Original']);
    bloc.publish(original);
    await tester.pump();

    final completion = refresh.refresh();
    var completed = false;
    completion.then((_) => completed = true);
    expect(refresh.refresh(), same(completion));
    await tester.pump();
    expect(bloc.requests, hasLength(2));
    expect(completed, isFalse);

    bloc.publish(_TestState(response: original.response, loading: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(completed, isFalse);
    expect(refresh.refresh(), same(completion));
    expect(bloc.requests, hasLength(2));

    bloc.publish(_page(['Refreshed']));
    await tester.pump();
    expect(completed, isTrue);
    expect(harness.items, ['Refreshed']);
  });

  testWidgets('refresh completes when the request fails and can be retried', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final refresh = PaginatedListRefreshController();
    addTearDown(bloc.close);
    final harness = _Harness(bloc, refreshController: refresh);

    await tester.pumpWidget(harness.build());
    bloc.publish(_page(['Original']));
    await tester.pump();

    final failedRefresh = refresh.refresh();
    var failedRequestCompleted = false;
    failedRefresh.then((_) => failedRequestCompleted = true);
    await tester.pump();
    expect(failedRequestCompleted, isFalse);

    bloc.publish(const _TestState(error: 'Refresh failed'));
    await tester.pump();
    expect(failedRequestCompleted, isTrue);
    expect(find.text('Problem: Refresh failed'), findsOneWidget);

    final retry = refresh.refresh();
    var retryCompleted = false;
    retry.then((_) => retryCompleted = true);
    await tester.pump();
    expect(retry, isNot(same(failedRefresh)));
    expect(bloc.requests, hasLength(3));
    expect(retryCompleted, isFalse);

    bloc.publish(_page(['Recovered']));
    await tester.pump();
    expect(retryCompleted, isTrue);
    expect(harness.items, ['Recovered']);
  });

  testWidgets('disposing the view completes an outstanding refresh', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final refresh = PaginatedListRefreshController();
    addTearDown(bloc.close);

    await tester.pumpWidget(_Harness(bloc, refreshController: refresh).build());
    bloc.publish(_page(['Original']));
    await tester.pump();

    final completion = refresh.refresh();
    var completed = false;
    completion.then((_) => completed = true);
    await tester.pump();
    expect(completed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(completed, isTrue);
    await refresh.refresh();
    expect(bloc.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('item changes survive retained responses and parent rebuilds', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc, trackItemChanges: true);
    final original = _page(['1:Apple', '2:Banana', '3:Cherry']);

    await tester.pumpWidget(harness.build());
    bloc.publish(original);
    await tester.pump();

    bloc.publish(
      _TestState(response: original.response, updatedItem: '1:Apricot'),
    );
    await tester.pump();
    expect(harness.items, ['1:Apricot', '2:Banana', '3:Cherry']);
    expect(harness.replacements, [(0, '1:Apple', '1:Apricot')]);

    bloc.publish(
      _TestState(
        response: original.response,
        updatedItem: '1:Apricot',
        deletedItemId: '2',
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.items, ['1:Apricot', '3:Cherry']);
    expect(harness.removals, [(1, '2:Banana')]);
    expect(harness.replacements, hasLength(1));

    // Unrelated state transitions and widget rebuilds must not replay page one.
    bloc.publish(_TestState(response: original.response, loading: true));
    await tester.pump();
    bloc.publish(_TestState(response: original.response));
    await tester.pump();
    await tester.pumpWidget(harness.build());

    expect(harness.items, ['1:Apricot', '3:Cherry']);
    expect(find.text('1:Apple'), findsNothing);
    expect(find.text('2:Banana'), findsNothing);
    expect(harness.removals, hasLength(1));
    expect(harness.replacements, hasLength(1));
    expect(bloc.requests, hasLength(1));
  });

  testWidgets('replacing the Bloc resets pages and stops consuming the old Bloc', (
    tester,
  ) async {
    final oldBloc = _TestBloc();
    final newBloc = _TestBloc();
    final scroll = ScrollController();
    addTearDown(oldBloc.close);
    addTearDown(newBloc.close);
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      _Harness(oldBloc, scrollController: scroll).build(),
    );
    oldBloc.publish(
      _page(List.generate(12, (index) => 'Old $index'), totalPages: 3),
    );
    await tester.pump();
    await _scrollToEnd(tester, scroll);
    oldBloc.publish(_page(['Old second page'], page: 2, totalPages: 3));
    await tester.pump();
    expect(oldBloc.requests.map((event) => event.page), [1, 2]);

    final newHarness = _Harness(newBloc, scrollController: scroll);
    await tester.pumpWidget(newHarness.build());
    expect(newBloc.requests.map((event) => event.page), [1]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Old second page'), findsNothing);

    oldBloc.publish(_page(['Late old response']));
    await tester.pump();
    expect(find.text('Late old response'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final newFirstPage = List.generate(12, (index) => 'New $index');
    newBloc.publish(_page(newFirstPage, totalPages: 2));
    await tester.pump();
    expect(newHarness.items, newFirstPage);
    await _scrollToEnd(tester, scroll);
    expect(newBloc.requests.map((event) => event.page), [1, 2]);
    expect(oldBloc.requests.map((event) => event.page), [1, 2]);

    newBloc.publish(_page(['New second page'], page: 2, totalPages: 2));
    await tester.pump();
    oldBloc.publish(_page(['Another old response']));
    await tester.pump();
    expect(newHarness.items, [...newFirstPage, 'New second page']);
    expect(find.text('Another old response'), findsNothing);
  });

  testWidgets('replaces external controllers and detaches listeners on dispose', (
    tester,
  ) async {
    final bloc = _TestBloc();
    final oldSearch = _TrackedSearchController();
    final newSearch = _TrackedSearchController();
    final oldScroll = _TrackedScrollController();
    final newScroll = _TrackedScrollController();
    final oldRefresh = PaginatedListRefreshController();
    final newRefresh = PaginatedListRefreshController();
    addTearDown(bloc.close);
    addTearDown(oldSearch.dispose);
    addTearDown(newSearch.dispose);
    addTearDown(oldScroll.dispose);
    addTearDown(newScroll.dispose);

    await tester.pumpWidget(
      _Harness(bloc,
              searchController: oldSearch,
              scrollController: oldScroll,
              refreshController: oldRefresh)
          .build(),
    );
    bloc.publish(_page(['Item']));
    await tester.pump();
    expect(oldSearch.hasRegisteredListeners, isTrue);
    expect(oldScroll.hasRegisteredListeners, isTrue);

    await tester.pumpWidget(
      _Harness(bloc,
              searchController: newSearch,
              scrollController: newScroll,
              refreshController: newRefresh)
          .build(),
    );
    expect(oldSearch.hasRegisteredListeners, isFalse);
    expect(oldScroll.hasRegisteredListeners, isFalse);
    expect(newSearch.hasRegisteredListeners, isTrue);
    expect(newScroll.hasRegisteredListeners, isTrue);

    final countAfterReplacement = bloc.requests.length;
    oldSearch.text = 'ignored';
    await oldRefresh.refresh();
    await tester.pump(const Duration(milliseconds: 300));
    expect(bloc.requests, hasLength(countAfterReplacement));

    newSearch.text = 'active';
    await tester.pump(const Duration(milliseconds: 300));
    expect(bloc.requests.last.query, 'active');
    expect(bloc.requests, hasLength(countAfterReplacement + 1));
    bloc.publish(_page(['Active']));
    await tester.pump();

    final completion = newRefresh.refresh();
    await tester.pump();
    expect(bloc.requests, hasLength(countAfterReplacement + 2));
    bloc.publish(_page(['Refreshed']));
    await tester.pump();
    await completion;

    // Disposing during a pending search must cancel its timer as well.
    newSearch.text = 'pending';
    await tester.pumpWidget(const SizedBox.shrink());
    expect(newSearch.hasRegisteredListeners, isFalse);
    expect(newScroll.hasRegisteredListeners, isFalse);
    newSearch.text = 'after disposal';
    await newRefresh.refresh();
    await tester.pump(const Duration(seconds: 1));
    expect(bloc.requests, hasLength(countAfterReplacement + 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty and error states supplied by the caller', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(bloc);

    await tester.pumpWidget(harness.build());
    bloc.publish(_page([]));
    await tester.pump();
    expect(find.text('Nothing here'), findsOneWidget);

    bloc.publish(const _TestState(error: 'Unavailable'));
    await tester.pump();
    expect(find.text('Problem: Unavailable'), findsOneWidget);
  });

  testWidgets('empty pull refresh can shrink wrap in an unbounded parent', (
    tester,
  ) async {
    final bloc = _TestBloc();
    addTearDown(bloc.close);
    final harness = _Harness(
      bloc,
      shrinkWrap: true,
      enablePullToRefresh: true,
    );

    await tester.pumpWidget(harness.build(unboundedHeight: true));
    bloc.publish(_page([]));
    await tester.pump();

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _scrollToEnd(
  WidgetTester tester,
  ScrollController controller,
) async {
  controller.jumpTo(0);
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 350));
}

_TestState _page(List<String> data, {int page = 1, int totalPages = 1}) {
  return _TestState(
    response: PaginatedResponse<String>(
      data: data,
      pagination: Pagination(currentPage: page, totalPages: totalPages),
    ),
  );
}

class _Request {
  const _Request(this.query, this.page, this.kind);

  final String? query;
  final int page;
  final String kind;
}

class _TestState {
  const _TestState({
    this.response,
    this.loading = false,
    this.error,
    this.updatedItem,
    this.deletedItemId,
    this.headerLabel,
  });

  final PaginatedResponse<String>? response;
  final bool loading;
  final String? error;
  final String? updatedItem;
  final String? deletedItemId;
  final String? headerLabel;
}

class _TestBloc extends Bloc<_Request, _TestState> {
  _TestBloc() : super(const _TestState()) {
    on<_Request>((event, emit) {});
  }

  final requests = <_Request>[];

  @override
  void onEvent(_Request event) {
    requests.add(event);
    super.onEvent(event);
  }

  void publish(_TestState state) => emit(state);
}

class _Harness {
  _Harness(
    this.bloc, {
    this.scrollController,
    this.searchController,
    this.refreshController,
    this.initialPage = 1,
    this.isGrid = false,
    this.gridColumns = 2,
    this.height = 240,
    this.customSearch = false,
    this.trackItemChanges = false,
    this.shrinkWrap = false,
    this.enablePullToRefresh = false,
    this.showHeader = false,
  });

  final _TestBloc bloc;
  final ScrollController? scrollController;
  final TextEditingController? searchController;
  final PaginatedListRefreshController? refreshController;
  final int initialPage;
  final bool isGrid;
  final int gridColumns;
  final double height;
  final bool customSearch;
  final bool trackItemChanges;
  final bool shrinkWrap;
  final bool enablePullToRefresh;
  final bool showHeader;
  int itemBuilds = 0;
  List<String> items = [];
  final removals = <(int, String)>[];
  final replacements = <(int, String, String)>[];

  Widget build({bool unboundedHeight = false}) {
    final view = PaginatedViewBuilder<String, _TestBloc, _Request, _TestState>(
      key: const ValueKey('paginated-view'),
      bloc: bloc,
      loadEvent: (query, page) => _Request(query, page, 'load'),
      loadMoreEventBuilder: (query, page) =>
          _Request(query, page, 'more'),
      onSearchChanged: customSearch
          ? (query, page) => _Request(query, page, 'search')
          : null,
      paginatedResponseSelector: (state) => state.response,
      loadingSelector: (state) => state.loading,
      errorSelector: (state) => state.error,
      headerWidget: showHeader
          ? (state) => Text(state.headerLabel ?? 'Header')
          : null,
      itemIdSelector: trackItemChanges
          ? (item) => item.split(':').first
          : null,
      updatedItemSelector: trackItemChanges
          ? (state) => state.updatedItem
          : null,
      deletedItemSelector: trackItemChanges
          ? (state) => state.deletedItemId
          : null,
      onItemRemoved: (index, item) => removals.add((index, item)),
      onItemReplaced: (index, oldItem, newItem) =>
          replacements.add((index, oldItem, newItem)),
      initialPage: initialPage,
      scrollController: scrollController,
      searchController: searchController,
      refreshController: refreshController,
      shrinkWrap: shrinkWrap,
      enablePullToRefresh: enablePullToRefresh,
      searchDebounceTime: const Duration(milliseconds: 300),
      isGrid: isGrid,
      gridDelegate: isGrid
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridColumns,
            )
          : null,
      emptyWidget: const Text('Nothing here'),
      errorWidget: (error) => Text('Problem: $error'),
      itemBuilder: (context, item, index, allItems) {
        itemBuilds++;
        items = List<String>.of(allItems);
        return SizedBox(height: 80, child: Text(item));
      },
    );
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: height,
            child: unboundedHeight
                ? SingleChildScrollView(child: view)
                : view,
          ),
        ),
      ),
    );
  }
}

class _TrackedSearchController extends TextEditingController {
  bool get hasRegisteredListeners => hasListeners;
}

class _TrackedScrollController extends ScrollController {
  bool get hasRegisteredListeners => hasListeners;
}
