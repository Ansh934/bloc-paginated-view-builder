import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'paginated_response.dart';
import 'pagination_view_state.dart';

/// Chooses which of the widget's event builders receives a request.
enum PaginationRequestKind { load, loadMore, search }

typedef PaginationRequestCallback =
    void Function({
      required String? query,
      required int page,
      required PaginationRequestKind kind,
    });

typedef PaginationItemRemovedCallback<T> =
    void Function({required int index, required T item});

typedef PaginationItemReplacedCallback<T> =
    void Function({
      required int index,
      required T previous,
      required T replacement,
    });

/// Internal pagination mechanics. The supplied callback dispatches BLoC events;
/// this controller never fetches data or depends on application state classes.
class PaginationController<T> extends ValueNotifier<PaginationViewState<T>> {
  PaginationController({
    required this.onRequest,
    this.onItemRemoved,
    this.onItemReplaced,
  }) : super(PaginationViewState<T>(items: List<T>.empty()));

  final PaginationRequestCallback onRequest;
  final PaginationItemRemovedCallback<T>? onItemRemoved;
  final PaginationItemReplacedCallback<T>? onItemReplaced;

  final List<T> _items = [];
  late final List<T> _readOnlyItems = UnmodifiableListView<T>(_items);
  int _initialPage = 1;
  int _currentPage = 1;
  int _lastPage = 1;
  int? _requestedPage;
  String? _query;
  String? _error;
  PaginatedResponse<T>? _lastResponse;
  PaginatedResponse<T>? _observedResponse;
  Timer? _searchTimer;
  Completer<void>? _refreshCompleter;
  bool _sourceLoading = false;
  bool _disposed = false;

  bool get canRequestMore =>
      !_disposed &&
      _requestedPage == null &&
      !_sourceLoading &&
      !(_searchTimer?.isActive ?? false) &&
      _currentPage < _lastPage;

  bool get canFillViewport =>
      canRequestMore &&
      _error == null &&
      (_lastResponse?.data.isNotEmpty ?? false);

  /// Rebuilds a header whose content depends on an otherwise unrelated BLoC state.
  void invalidateView() {
    if (!_disposed) _publish();
  }

  /// Starts a new session when mounted or when the BLoC/initial page changes.
  void reset({
    required int initialPage,
    String? query,
    PaginatedResponse<T>? previousResponse,
  }) {
    if (_disposed) return;
    _finishRefresh();
    _initialPage = initialPage;
    _query = query;
    _observedResponse = previousResponse;
    _sourceLoading = false;
    _reload(kind: PaginationRequestKind.load);
  }

  void loadMore() {
    if (canRequestMore) {
      _request(page: _currentPage + 1, kind: PaginationRequestKind.loadMore);
    }
  }

  void search({required String? query, required Duration debounce}) {
    if (_disposed || query == _query) return;
    _query = query;
    _searchTimer?.cancel();
    _searchTimer = Timer(debounce, () {
      _finishRefresh();
      _reload(kind: PaginationRequestKind.search);
    });
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    if (_refreshCompleter != null) return _refreshCompleter!.future;
    final completion = Completer<void>();
    _refreshCompleter = completion;
    _reload(kind: PaginationRequestKind.load);
    return completion.future;
  }

  /// Consumes one BLoC emission and notifies the view at most once.
  ///
  /// Item mutations are supplied only when their selected values change.
  /// Returns whether item content changed and needs a viewport check.
  bool apply({
    required bool loading,
    PaginatedResponse<T>? response,
    String? error,
    String? deletedItemId,
    T? updatedItem,
    String Function(T)? itemId,
    bool rebuildHeader = false,
  }) {
    if (_disposed) return false;
    _sourceLoading = loading;
    _observedResponse = response;
    var itemsChanged = false;
    var displayChanged = false;

    if (error != null) {
      displayChanged = _error != error || _requestedPage != null;
      _error = error;
      _requestedPage = null;
      _finishRefresh();
    } else if (!loading && response != null) {
      itemsChanged = _accept(response: response);
      displayChanged = itemsChanged;
    }

    final removed = deletedItemId != null && itemId != null
        ? _remove(id: deletedItemId, idOf: itemId)
        : null;
    final replaced = updatedItem != null && itemId != null
        ? _replace(replacement: updatedItem, idOf: itemId)
        : null;
    itemsChanged = itemsChanged || removed != null || replaced != null;
    if (displayChanged || itemsChanged || rebuildHeader) {
      _publish();
    }
    if (!_disposed && removed != null) {
      onItemRemoved?.call(index: removed.index, item: removed.item);
    }
    if (!_disposed && replaced != null) {
      onItemReplaced?.call(
        index: replaced.index,
        previous: replaced.previous,
        replacement: replaced.replacement,
      );
    }
    return itemsChanged;
  }

  void _reload({required PaginationRequestKind kind}) {
    _searchTimer?.cancel();
    _items.clear();
    _currentPage = _initialPage;
    _lastPage = _initialPage;
    _lastResponse = _observedResponse;
    _request(page: _initialPage, kind: kind);
  }

  void _request({required int page, required PaginationRequestKind kind}) {
    _requestedPage = page;
    _error = null;
    _publish();
    onRequest(query: _query, page: page, kind: kind);
  }

  bool _accept({required PaginatedResponse<T> response}) {
    final page = response.pagination?.currentPage ?? _requestedPage;
    if (page == null ||
        page != _requestedPage ||
        identical(response, _lastResponse)) {
      return false;
    }
    if (page == _initialPage) {
      _items.clear();
    }
    _items.addAll(response.data);
    _currentPage = page;
    _lastPage =
        response.pagination?.totalPages ??
        (response.data.isEmpty ? page : page + 1);
    _lastResponse = response;
    _requestedPage = null;
    _error = null;
    _finishRefresh();
    return true;
  }

  ({int index, T item})? _remove({
    required String id,
    required String Function(T) idOf,
  }) {
    final index = _items.indexWhere((item) => idOf(item) == id);
    return index == -1 ? null : (index: index, item: _items.removeAt(index));
  }

  ({int index, T previous, T replacement})? _replace({
    required T replacement,
    required String Function(T) idOf,
  }) {
    final id = idOf(replacement);
    final index = _items.indexWhere((item) => idOf(item) == id);
    if (index == -1 || _items[index] == replacement) return null;
    final previous = _items[index];
    _items[index] = replacement;
    return (index: index, previous: previous, replacement: replacement);
  }

  void _publish() {
    value = PaginationViewState<T>(
      items: _readOnlyItems,
      isLoading: _requestedPage != null,
      error: _error,
    );
  }

  void _finishRefresh() {
    _refreshCompleter?.complete();
    _refreshCompleter = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _finishRefresh();
    super.dispose();
  }
}
