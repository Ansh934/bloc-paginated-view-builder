# bloc_paginated_view_builder

A highly customizable, **BLoC-powered paginated view builder** for Flutter lists and grids.

`PaginatedViewBuilder` is intentionally tightly coupled to BLoC. It does not try to eliminate or replace BLoC: it uses your BLoC as the foundation. **Business logic stays in your BLoC, and control over data fetching and business decisions stays with it.**

Provide a basic BLoC with a load event and loading, success, and error states. The widget abstracts away the repetitive pagination UI code: detecting when to load more, accumulating pages for display, debouncing search, refreshing the view, showing loading and error content, and reflecting item updates or deletions.

Once you understand its event builders and state selectors, the API is straightforward to reuse. A screen connects its BLoC, selects its state, and builds its items in a small widget declaration. Pagination mechanics live in one reusable component, keeping screen code short and maintainable as features grow.

## Built around BLoC

The package fits a scalable BLoC architecture: each feature owns its events, state, business rules, and repository integration, while the same paginated widget handles presentation across screens.

| Responsibility | Owner |
| --- | --- |
| Business rules, permissions, query/filter decisions, and error policy | Your BLoC and application layer |
| API calls, persistence, authentication, and response parsing | Your repositories and services, called by the BLoC |
| Request concurrency and ignoring obsolete results | Your BLoC |
| Scroll thresholds, page requests, displayed item accumulation, and pagination reset | `PaginatedViewBuilder` |
| Search debounce, refresh gestures, and loading/empty/error presentation | `PaginatedViewBuilder`, configured by you |
| Item appearance, headers, separators, and list/grid layout | Your widget builders and configuration |

The widget dispatches **your events** and observes **your states**. It keeps local presentation state, including the displayed items and page position. Your BLoC decides how requests are fulfilled and which results or errors are emitted. There are no API calls or application business rules inside the widget.

You can use your existing feature BLoC. There is no package-specific BLoC superclass to adopt beyond the normal `Bloc<E, S>` contract, and no required event or state class names. A basic implementation can start small and grow with your feature without moving its business logic into the screen.

## What the widget handles

- Automatic next-page requests near the end of a list or grid.
- Automatic loading when a page does not fill the available viewport.
- Page accumulation, duplicate-page handling, and stopping at the last page.
- Search debouncing and restarting from the initial page.
- Pull-to-refresh, programmatic refresh, and refresh signals from BLoC state.
- Initial loading, additional-page loading, empty, and error views.
- Display updates and removals selected from BLoC state.
- Controller attachment and listener cleanup.

Customization is built into the API: supply your own items, headers, separators, grid delegate, status widgets, event builders, state selectors, callbacks, scroll controller, padding, physics, and debounce settings. The [API guide](#api-guide) lists the available options.

## How the package stays maintainable

The implementation has three small roles. `PaginatedViewBuilder` connects your BLoC to the view, owns Flutter controllers, and checks scroll position. The internal `PaginationController` tracks requested pages, accumulated items, search debounce, refresh completion, and item changes. `PaginationViewState` contains only the values needed to render the view. A BLoC emission is translated into one controller update, which notifies the widget when its displayed content changes. There are no empty `setState` calls in the widget.

Your BLoC only needs to fetch a requested page and emit loading, data, or an error. Keep business decisions and request concurrency there. The package handles the repetitive UI coordination. The list and grid use Flutter's lazy builders; `shrinkWrap` remains opt-in because it can cost more layout work. Automatic viewport filling checks happen after page or layout changes and stop when pages are exhausted, an empty page arrives, or the viewport can scroll.

## Requirements

Requires Flutter 3.32 or newer and Dart 3.8 or newer.

## Installation

Add this package and `flutter_bloc` to your application's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^9.1.1
  bloc_paginated_view_builder: ^0.1.0
```

Run `flutter pub get`, then import:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_paginated_view_builder/bloc_paginated_view_builder.dart';
```

## Keep the screen small

Provide event builders and state selectors. Here, `CatalogBloc extends Bloc<LoadCatalog, CatalogState>`, matching the [runnable example](example/lib/main.dart):

```dart
Expanded(
  child: PaginatedViewBuilder<
      CatalogItem, CatalogBloc, LoadCatalog, CatalogState>(
    bloc: catalogBloc,
    loadEvent: (query, page) => LoadCatalog(query, page),
    paginatedResponseSelector: (state) => state.response,
    loadingSelector: (state) => state.isLoading,
    errorSelector: (state) => state.error,
    itemBuilder: (context, item, index, loadedItems) {
      return ListTile(title: Text(item.title));
    },
  ),
)
```

The widget dispatches the initial event when mounted. Place it in a layout with a bounded height, such as `Expanded` inside a `Column`, or a `SizedBox`. Its supplied BLoC remains owned by the caller; close it when the owning screen or provider is disposed.

The API has three main connections:

1. **Event builders** tell the widget which BLoC event to dispatch for a query and page.
2. **State selectors** tell it where to find the current page, loading flag, and error.
3. **Widget builders** tell it how to display your data.

Learn those connections once, then reuse the same pattern across feature screens. Business logic remains independently testable in the BLoC, and layout changes stay in the view.

## A basic BLoC is enough

Your BLoC needs to accept a page request, call your repository, and emit loading, success, or error state. These can be separate state classes or fields on a state object, as below. The widget's selectors support either structure.

This template uses application-defined `CatalogItem` and `CatalogRepository` types. The repository's `fetchPage({String? query, required int page})` returns a `Future<PaginatedResponse<CatalogItem>>`; map your backend response at that boundary when needed.

<details>
<summary>Show a basic BLoC template</summary>

```dart
class LoadCatalog {
  const LoadCatalog(this.query, this.page);

  final String? query;
  final int page;
}

class CatalogState {
  const CatalogState({this.isLoading = false, this.response, this.error});

  final bool isLoading;
  final PaginatedResponse<CatalogItem>? response;
  final String? error;
}

class CatalogBloc extends Bloc<LoadCatalog, CatalogState> {
  CatalogBloc(this.repository) : super(const CatalogState()) {
    on<LoadCatalog>(_load);
  }

  final CatalogRepository repository;
  int _requestVersion = 0;

  Future<void> _load(
    LoadCatalog event,
    Emitter<CatalogState> emit,
  ) async {
    final version = ++_requestVersion;
    emit(const CatalogState(isLoading: true));

    try {
      final response = await repository.fetchPage(
        query: event.query,
        page: event.page,
      );
      if (emit.isDone || version != _requestVersion) return;
      emit(CatalogState(response: response));
    } catch (error) {
      if (emit.isDone || version != _requestVersion) return;
      emit(CatalogState(error: error.toString()));
    }
  }
}
```

</details>

The version check lets a newer search or refresh supersede an older request's result. Your BLoC can apply the concurrency and error-handling policy appropriate to your application. Repository calls, validation, filters, and other business decisions remain under its control.

The screen does not need to maintain a second pagination implementation, attach scroll listeners, manage debounce timers, or append each page itself.

## Page response contract

Each successful response should contain **only the requested page**, not the cumulative list. The widget replaces its items on the initial page and appends later pages. Return a new response for each completed request. Loading and error states should clear the response or retain the same response instance; avoid manufacturing a new response from stale page data on unrelated state changes.

```dart
PaginatedResponse<CatalogItem>(
  data: itemsForThisPage,
  pagination: Pagination(
    currentPage: requestedPage,
    totalPages: totalPagesFromApi,
  ),
)
```

Pages default to starting at `1`; set `initialPage` for an API that uses a different start. `Pagination.totalPages` is the **last page number**: this is also the page count for a one-based API. For a zero-based API with ten pages, set `initialPage: 0` and `totalPages: 9`. Without `pagination`, a nonempty response permits another page and an empty response ends pagination. Explicit metadata avoids an extra request after the last nonempty page.

Search and refresh can overlap an in-flight request. Your BLoC should cancel obsolete requests or ignore their results so an old query cannot replace newer results. The example demonstrates a request version counter.

### Short pages and scrolling

When the loaded items do not fill a bounded viewport, the widget requests another
page after layout without waiting for a scroll gesture. It loads one page at a
time until the list or grid can scroll, the last page is reached, a response is
empty, or a request fails. Resizing the viewport or changing the grid's column
count rechecks whether more items are needed. Each request still goes through
your BLoC's event builder.

Both list and grid views support touch swipes, wheel/trackpad scrolling, and
mouse dragging. Your configured scroll physics still apply. Use a bounded layout
such as `Expanded` or `SizedBox` for the widget to manage its own scrolling.
Automatic viewport filling is disabled when `shrinkWrap: true` is used inside an
unbounded outer scroll view, avoiding automatic loading of the entire dataset.

### Rebuilds and pagination state

One BLoC listener applies changes to the widget's display state. Unrelated states
do not rebuild the list or grid; a configured `headerWidget` still receives each
state because it may display other feature information. Viewport checks follow
content changes or scroll-dimension changes, rather than every widget build.

An internal page buffer groups request, response, error, and reset transitions.
It appends items to the existing list and supplies a read-only live view to
`itemBuilder`. Copy that list if you need to retain a snapshot.
Business decisions and data fetching remain in your BLoC. `shrinkWrap` defaults to
`false`, preserving lazy list/grid layout for bounded screens.

## Search, refresh, and grid mode

Create controllers in your `State` and dispose the `TextEditingController` with the screen. Pass it both to your search field and to the paginated widget:

```dart
final searchController = TextEditingController();
final refreshController = PaginatedListRefreshController();

// Within PaginatedViewBuilder(...):
searchController: searchController,
searchDebounceTime: const Duration(milliseconds: 350),
onSearchChanged: (query, page) => LoadCatalog(query, page),
enablePullToRefresh: true,
refreshController: refreshController,
```

`onSearchChanged` builds an event; return the event instead of adding it to the BLoC yourself. Search resets to `initialPage` after the debounce. If omitted, search uses `loadEvent`. Refresh uses `loadEvent` with the current query and `initialPage`.

To refresh from a button:

```dart
await refreshController.refresh();
```

Use one refresh controller per mounted view. The widget manages its attachment. The future completes when the refresh finishes; use `errorSelector` and `onError` for application error handling.

To show a grid:

```dart
// Within PaginatedViewBuilder(...):
isGrid: true,
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 2,
  crossAxisSpacing: 12,
  mainAxisSpacing: 12,
),
```

## API guide

The package exports `PaginatedViewBuilder`, `PaginatedResponse`, `Pagination`, and `PaginatedListRefreshController` through a single library.

| Parameter | Purpose |
| --- | --- |
| `bloc` | Existing `Bloc<E, S>` that receives load events. |
| `loadEvent` | Required `E Function(String? query, int page)` for initial loading and refresh. |
| `loadMoreEventBuilder` | Optional event builder for subsequent pages; defaults to `loadEvent`. |
| `paginatedResponseSelector` | Extracts `PaginatedResponse<T>?` from the state. |
| `loadingSelector`, `errorSelector` | Extract the loading flag and nullable error message. |
| `itemBuilder` | Builds an item from its context, value, index, and loaded items. |
| `searchController`, `onSearchChanged`, `searchDebounceTime` | Connect a search field and optional search-specific event builder. |
| `enablePullToRefresh`, `refreshController` | Enable gesture refresh and programmatic refresh. |
| `refreshEventSelector` | Triggers a refresh when its selected value changes to `true`. Reset the flag before signaling another refresh. |
| `scrollThreshold` | Fraction of the scroll extent that triggers the next page; defaults to `0.8`. |
| `initialPage` | First page to request; defaults to `1`. |
| `loadingWidget`, `loadingMoreWidget`, `emptyWidget`, `errorWidget` | Customize first-load, additional-load, empty, and error content. |
| `onError` | Receives selected error messages. |
| `separatorBuilder`, `headerWidget` | Add list separators and a state-aware header. |
| `isGrid`, `gridDelegate` | Enable a grid and control its layout. |
| `padding`, `scrollController`, `physics`, `shrinkWrap` | Configure the underlying scroll view. Caller-supplied scroll controllers remain caller-owned. |
| `itemIdSelector`, `deletedItemSelector`, `updatedItemSelector` | Apply item removals and replacements by stable string ID. Supply an ID selector with the mutation selectors. |
| `onItemRemoved`, `onItemReplaced` | Receive item mutation callbacks, including the affected index. |
| `isSortable` | Has no effect; sort items in your data source. |

## Adapt an existing API response

This package has no dependency on application-specific response models. Map your backend response to the package model at your application boundary. For example, an application response with `results`, `page`, and `pageCount` can be adapted as follows:

```dart
PaginatedResponse<Product> toPaginatedResponse(ApiPage<Product> apiPage) {
  return PaginatedResponse<Product>(
    data: apiPage.results,
    pagination: Pagination(
      currentPage: apiPage.page,
      totalPages: apiPage.pageCount,
    ),
  );
}
```

`ApiPage` and `Product` above represent your own application types. This example assumes one-based page numbering; translate a zero-based API's page count to its last page number. Store the mapped response in your BLoC state so the selector returns a stable value between completed requests. HTTP calls and JSON parsing stay in your application or repository.

## Run the example

The [example app](example/lib/main.dart) uses deterministic local data and needs no API key or backend. It demonstrates automatic pagination, list/grid switching, debounced search, pull-to-refresh, and a refresh button.

This repository uses FVM with Flutter **3.47.4**, as pinned in [`.fvmrc`](.fvmrc). From the package directory:

```sh
fvm use 3.47.4
cd example
fvm flutter pub get
fvm flutter run -d chrome
```

The example inherits the root FVM configuration. The web entry point is included. To add native runners from the example directory, run `fvm flutter create --platforms=android,ios .`, then select a device with `fvm flutter run`. Native builds require the corresponding platform toolchains.

## Package checks

Validation with FVM Flutter 3.47.4 passes: `fvm flutter analyze`, all 35 widget tests with
`fvm flutter test`, and the example web build with `fvm flutter build web`.
You can rerun the checks with the commands below.

From the package directory:

```sh
fvm flutter pub get
fvm dart format lib test example/lib
fvm flutter analyze
fvm flutter test
```

To build the web example:

```sh
cd example
fvm flutter pub get
fvm flutter build web
```
