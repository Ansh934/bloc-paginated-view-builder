import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'paginated_response.dart';
import 'pagination_controller.dart';
import 'pagination_view_state.dart';

/// A BLoC-powered paginated list or grid with search and refresh.
///
/// The caller owns the BLoC and any supplied controllers. Responses must contain
/// one page of items. Use a bounded height unless [shrinkWrap] is true.
class PaginatedViewBuilder<T, B extends Bloc<E, S>, E, S>
    extends StatefulWidget {
  const PaginatedViewBuilder({
    super.key,
    required this.itemBuilder,
    required this.bloc,
    required this.loadEvent,
    required this.paginatedResponseSelector,
    required this.loadingSelector,
    required this.errorSelector,
    this.loadMoreEventBuilder,
    this.searchController,
    this.onSearchChanged,
    this.searchDebounceTime = const Duration(milliseconds: 500),
    this.onError,
    this.loadingWidget,
    this.loadingMoreWidget = const CircularProgressIndicator(),
    this.emptyWidget,
    this.errorWidget,
    this.scrollThreshold = 0.8,
    this.padding,
    this.scrollController,
    this.shrinkWrap = false,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.separatorBuilder,
    this.initialPage = 1,
    this.onItemRemoved,
    this.onItemReplaced,
    this.deletedItemSelector,
    this.updatedItemSelector,
    this.isSortable = false,
    this.itemIdSelector,
    this.headerWidget,
    this.enablePullToRefresh = false,
    this.refreshController,
    this.refreshEventSelector,
    this.gridDelegate,
    this.isGrid = false,
  }) : assert(
         (updatedItemSelector == null && deletedItemSelector == null) ||
             itemIdSelector != null,
         'itemIdSelector is required for item updates and deletions',
       ),
       assert(scrollThreshold >= 0 && scrollThreshold <= 1),
       assert(initialPage >= 0),
       assert(
         !isGrid || gridDelegate != null,
         'gridDelegate is required when isGrid is true',
       );

  /// Builder for list items
  final Widget Function(BuildContext context, T item, int index, List<T> items)
  itemBuilder;

  /// The bloc used for state management
  final B bloc;

  /// Event to trigger initial loading
  final E Function(String? query, int page) loadEvent;

  /// Event builder to create load more events with the next page
  final E Function(String? query, int nextPage)? loadMoreEventBuilder;

  /// Selectors to extract data from state
  final PaginatedResponse<T>? Function(S state) paginatedResponseSelector;
  final bool Function(S state) loadingSelector;
  final String? Function(S state) errorSelector;

  /// Selectors for detecting item modifications
  final String? Function(S state)?
  deletedItemSelector; // Returns ID of deleted item
  final T? Function(S state)? updatedItemSelector; // Returns updated item
  final String Function(T item)?
  itemIdSelector; // Function to extract ID from item
  /// Retained for source compatibility; sort items in your data source.
  final bool isSortable;

  final bool Function(S state)? refreshEventSelector;

  /// Callback when an error occurs
  final void Function(String error)? onError;

  /// Custom widgets
  final Widget? loadingWidget;
  final Widget? loadingMoreWidget;
  final Widget? emptyWidget;
  final Widget Function(String error)? errorWidget;

  /// When to trigger load more (0.8 means 80% of the way to the bottom)
  final double scrollThreshold;

  /// ListView properties
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final int initialPage;

  /// Optional separator builder for ListView.separated
  final Widget Function(BuildContext, int)? separatorBuilder;

  /// TextEditingController for search field (if you want the widget to manage search)
  final TextEditingController? searchController;

  /// Debounce time for search (only used if searchController is provided)
  final Duration searchDebounceTime;

  /// Function to build a load event with search query and page
  final E Function(String? query, int page)? onSearchChanged;

  /// Callback when an item is removed (returns index and item)
  final void Function(int index, T item)? onItemRemoved;

  /// Callback when an item is replaced (returns index, old item, and new item)
  final void Function(int index, T oldItem, T newItem)? onItemReplaced;

  /// Widget to show at the top of the list
  final Widget Function(S state)? headerWidget;

  /// Whether to enable pull-to-refresh functionality
  final bool enablePullToRefresh;

  /// Optional controller to trigger refresh programmatically
  final PaginatedListRefreshController? refreshController;

  /// Grid delegate for grid view mode
  final SliverGridDelegate? gridDelegate;

  /// Whether to display items in a grid
  final bool isGrid;

  @override
  State<PaginatedViewBuilder<T, B, E, S>> createState() =>
      _PaginatedViewBuilderState<T, B, E, S>();
}

/// Triggers a refresh and completes when the request succeeds or fails.
///
/// Attach a controller to one widget at a time. Calling [refresh] while detached
/// completes immediately; repeated calls during a refresh share its future.
class PaginatedListRefreshController {
  Future<void> Function()? _refreshCallback;

  void _attach(Future<void> Function() callback) {
    _refreshCallback = callback;
  }

  /// Reloads the initial page using the current search text.
  Future<void> refresh() => _refreshCallback?.call() ?? Future<void>.value();

  void _detach() {
    _refreshCallback = null;
  }
}

class _PaginatedViewBuilderState<T, B extends Bloc<E, S>, E, S>
    extends State<PaginatedViewBuilder<T, B, E, S>> {
  late ScrollController _scrollController;
  late ScrollBehavior _scrollBehavior;
  late S _blocState;
  late final PaginationController<T> _pagination;
  Timer? _scrollDebounceTimer;
  bool _hasBoundedHeight = false;
  bool _viewportCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _blocState = widget.bloc.state;
    _pagination = PaginationController<T>(
      onRequest: _dispatchPageRequest,
      onItemRemoved: ({required index, required item}) =>
          widget.onItemRemoved?.call(index, item),
      onItemReplaced:
          ({required index, required previous, required replacement}) =>
              widget.onItemReplaced?.call(index, previous, replacement),
    );
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_onScroll);
    widget.searchController?.addListener(_onSearchChanged);
    widget.refreshController?._attach(_refresh);
    _resetAndLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inherited = ScrollConfiguration.of(context);
    _scrollBehavior = inherited.dragDevices.contains(PointerDeviceKind.mouse)
        ? inherited
        : inherited.copyWith(
            dragDevices: {...inherited.dragDevices, PointerDeviceKind.mouse},
          );
  }

  @override
  void didUpdateWidget(covariant PaginatedViewBuilder<T, B, E, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _scrollDebounceTimer?.cancel();
      _scrollController.removeListener(_onScroll);
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
      _scrollController.addListener(_onScroll);
    }
    if (oldWidget.refreshController != widget.refreshController) {
      oldWidget.refreshController?._detach();
      widget.refreshController?._attach(_refresh);
    }
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController?.removeListener(_onSearchChanged);
      widget.searchController?.addListener(_onSearchChanged);
    }
    if (oldWidget.bloc != widget.bloc ||
        oldWidget.initialPage != widget.initialPage) {
      _blocState = widget.bloc.state;
      _resetAndLoad();
    } else if (oldWidget.searchController != widget.searchController) {
      _onSearchChanged();
    }
  }

  void _resetAndLoad() {
    _scrollDebounceTimer?.cancel();
    _pagination.reset(
      initialPage: widget.initialPage,
      query: widget.searchController?.text,
      previousResponse: widget.paginatedResponseSelector(widget.bloc.state),
    );
  }

  void _dispatchPageRequest({
    required String? query,
    required int page,
    required PaginationRequestKind kind,
  }) {
    final builder = kind == PaginationRequestKind.search
        ? widget.onSearchChanged ?? widget.loadEvent
        : kind == PaginationRequestKind.load
        ? widget.loadEvent
        : widget.loadMoreEventBuilder ?? widget.loadEvent;
    widget.bloc.add(builder(query, page));
  }

  void _onSearchChanged() {
    _scrollDebounceTimer?.cancel();
    _pagination.search(
      query: widget.searchController?.text,
      debounce: widget.searchDebounceTime,
    );
  }

  Future<void> _refresh() => _pagination.refresh();

  void _onStateChanged(BuildContext context, S state) {
    final previous = _blocState;
    _blocState = state;
    final error = widget.errorSelector(state);
    final loading = widget.loadingSelector(state);
    final response = widget.paginatedResponseSelector(state);

    if (widget.refreshEventSelector?.call(state) == true &&
        widget.refreshEventSelector?.call(previous) != true) {
      _refresh();
      if (widget.headerWidget != null) _pagination.invalidateView();
      return;
    }

    final idOf = widget.itemIdSelector;
    final deletedId = widget.deletedItemSelector?.call(state);
    final updated = widget.updatedItemSelector?.call(state);
    final changedDeletedId =
        idOf != null &&
            deletedId != null &&
            deletedId != widget.deletedItemSelector?.call(previous)
        ? deletedId
        : null;
    final T? changedUpdatedItem =
        idOf != null &&
            updated != null &&
            updated != widget.updatedItemSelector?.call(previous)
        ? updated
        : null;
    final itemsChanged = _pagination.apply(
      loading: loading,
      response: response,
      error: error,
      deletedItemId: changedDeletedId,
      updatedItem: changedUpdatedItem,
      itemId: idOf,
      rebuildHeader: widget.headerWidget != null,
    );
    if (itemsChanged) {
      _scheduleViewportCheck();
    } else if (widget.loadingSelector(previous) && !loading) {
      // External BLoC work may have temporarily blocked viewport filling.
      if (widget.headerWidget != null) {
        _scheduleViewportCheck();
      } else {
        _requestNextPage(fillViewport: true);
      }
    }

    if (error != null && error != widget.errorSelector(previous)) {
      widget.onError?.call(error);
    }
  }

  void _onScroll() {
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(
      const Duration(milliseconds: 300),
      () => _requestNextPage(),
    );
  }

  void _scheduleViewportCheck() {
    if (_viewportCheckScheduled || !_pagination.canFillViewport) {
      return;
    }
    _viewportCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportCheckScheduled = false;
      _requestNextPage(fillViewport: true);
    });
  }

  bool _onScrollMetricsChanged(ScrollMetricsNotification notification) {
    if (notification.depth == 0) {
      // Flutter dispatches these after layout. Inspect the completed metrics
      // directly instead of scheduling a frame just to measure them again.
      _requestNextPage(fillViewport: true);
    }
    return false;
  }

  void _requestNextPage({bool fillViewport = false}) {
    if (!mounted ||
        _scrollController.positions.length != 1 ||
        !_pagination.canRequestMore ||
        widget.loadingSelector(widget.bloc.state)) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions ||
        !position.hasViewportDimension ||
        !position.viewportDimension.isFinite ||
        position.viewportDimension <= 0) {
      return;
    }
    if (fillViewport) {
      // Do not drain every page inside an unbounded outer scroll view, retry
      // failed requests in a loop, or keep fetching after an empty response.
      if (!_hasBoundedHeight ||
          !_pagination.canFillViewport ||
          position.maxScrollExtent > position.minScrollExtent) {
        return;
      }
    } else {
      final threshold =
          position.minScrollExtent +
          (position.maxScrollExtent - position.minScrollExtent) *
              widget.scrollThreshold;
      if (position.pixels < threshold) {
        return;
      }
    }
    _pagination.loadMore();
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    widget.searchController?.removeListener(_onSearchChanged);
    widget.refreshController?._detach();
    _pagination.dispose();
    super.dispose();
  }

  Widget _buildListItem(BuildContext context, int index, List<T> items) =>
      widget.itemBuilder(context, items[index], index, items);

  Widget _buildListView(List<T> items) {
    if (widget.isGrid) {
      return GridView.builder(
        gridDelegate: widget.gridDelegate!,
        padding: widget.padding ?? const EdgeInsets.all(8),
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        controller: _scrollController,
        itemCount: items.length,
        itemBuilder: (context, index) => _buildListItem(context, index, items),
      );
    }
    if (widget.separatorBuilder != null) {
      return ListView.separated(
        controller: _scrollController,
        padding: widget.padding,
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        itemCount: items.length,
        separatorBuilder: widget.separatorBuilder!,
        itemBuilder: (context, index) => _buildListItem(context, index, items),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      itemCount: items.length,
      itemBuilder: (context, index) => _buildListItem(context, index, items),
    );
  }

  Widget _buildContent(PaginationViewState<T> view) {
    Widget content;
    if (view.isLoading && view.items.isEmpty) {
      return widget.loadingWidget ??
          const Center(child: CircularProgressIndicator());
    }
    if (view.items.isNotEmpty) {
      content = _buildListView(view.items);
    } else {
      final error = view.error;
      final placeholder = error != null
          ? widget.errorWidget?.call(error) ??
                Center(child: Text('Error: $error'))
          : widget.emptyWidget ?? const Center(child: Text('No items found'));
      if (!widget.enablePullToRefresh) {
        return placeholder;
      }
      content = CustomScrollView(
        controller: _scrollController,
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        slivers: [
          if (widget.shrinkWrap)
            SliverToBoxAdapter(child: placeholder)
          else
            SliverFillRemaining(hasScrollBody: false, child: placeholder),
        ],
      );
    }
    if (widget.enablePullToRefresh) {
      content = RefreshIndicator(onRefresh: _refresh, child: content);
    }
    return content;
  }

  Widget _buildLayout(
    BuildContext context,
    BoxConstraints constraints,
    PaginationViewState<T> view,
  ) {
    _hasBoundedHeight =
        constraints.hasBoundedHeight && constraints.maxHeight > 0;
    final content = _buildContent(view);
    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (widget.headerWidget != null) widget.headerWidget!(_blocState),
        if (!widget.shrinkWrap)
          Expanded(child: content)
        else if (_hasBoundedHeight)
          Flexible(child: content)
        else
          content,
        if (view.isLoading && view.items.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: widget.loadingMoreWidget,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => BlocListener<B, S>(
    bloc: widget.bloc,
    listener: _onStateChanged,
    child: ScrollConfiguration(
      behavior: _scrollBehavior,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onScrollMetricsChanged,
        child: ValueListenableBuilder<PaginationViewState<T>>(
          valueListenable: _pagination,
          builder: (context, view, _) => LayoutBuilder(
            builder: (context, constraints) =>
                _buildLayout(context, constraints, view),
          ),
        ),
      ),
    ),
  );
}
