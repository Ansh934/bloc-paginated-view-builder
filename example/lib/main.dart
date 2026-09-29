import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_paginated_view_builder/bloc_paginated_view_builder.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paginated View Builder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff345b4c)),
        useMaterial3: true,
      ),
      home: const CatalogPage(),
    );
  }
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _bloc = CatalogBloc();
  final _searchController = TextEditingController();
  final _refreshController = PaginatedListRefreshController();
  bool _isGrid = false;

  @override
  void dispose() {
    _searchController.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field notes'),
        actions: [
          IconButton(
            tooltip: 'Refresh the current search',
            onPressed: () async {
              await _refreshController.refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Scroll for more, search the collection, or pull down to '
                    'refresh. All data is generated locally.',
                  ),
                ),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search notes',
                    hintText: 'Try “forest” or “12”',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Clear search',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('List'),
                          icon: Icon(Icons.view_list_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Grid'),
                          icon: Icon(Icons.grid_view),
                        ),
                      ],
                      selected: {_isGrid},
                      onSelectionChanged: (selection) {
                        setState(() => _isGrid = selection.single);
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: PaginatedViewBuilder<
                      CatalogItem,
                      CatalogBloc,
                      LoadCatalog,
                      CatalogState>(
                    bloc: _bloc,
                    loadEvent: (query, page) => LoadCatalog(query, page),
                    loadMoreEventBuilder: (query, page) =>
                        LoadCatalog(query, page),
                    onSearchChanged: (query, page) => LoadCatalog(query, page),
                    paginatedResponseSelector: (state) => state.response,
                    loadingSelector: (state) => state.isLoading,
                    errorSelector: (state) => state.error,
                    searchController: _searchController,
                    searchDebounceTime: const Duration(milliseconds: 350),
                    refreshController: _refreshController,
                    enablePullToRefresh: true,
                    isGrid: _isGrid,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 300,
                      mainAxisExtent: 154,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    padding: const EdgeInsets.only(bottom: 24),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    emptyWidget: const Center(
                      child: Text('No matching notes. Try another search.'),
                    ),
                    errorWidget: (error) => Center(child: Text(error)),
                    itemBuilder: (context, item, index, items) {
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Note ${item.id} · ${index + 1} of '
                                '${items.length} loaded',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.description,
  });

  final int id;
  final String title;
  final String description;
}

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
  CatalogBloc() : super(const CatalogState()) {
    on<LoadCatalog>(_load);
  }

  static const _pageSize = 12;
  static const _categories = ['Forest', 'Coast', 'Mountain', 'Desert'];
  static final _catalog = List<CatalogItem>.generate(120, (index) {
    final category = _categories[index % _categories.length];
    return CatalogItem(
      id: index + 1,
      title: '$category journal ${index + 1}',
      description: 'Observations, routes, and small discoveries from the '
          '${category.toLowerCase()}.',
    );
  });

  int _requestVersion = 0;

  Future<void> _load(
    LoadCatalog event,
    Emitter<CatalogState> emit,
  ) async {
    // A later search or refresh invalidates any earlier in-flight request.
    final requestVersion = ++_requestVersion;
    emit(const CatalogState(isLoading: true));
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (emit.isDone || requestVersion != _requestVersion) {
      return;
    }

    final query = event.query?.trim().toLowerCase() ?? '';
    final matches = _catalog
        .where((item) => item.title.toLowerCase().contains(query))
        .toList();
    final totalPages = math.max(1, (matches.length / _pageSize).ceil());
    final items = matches
        .skip((event.page - 1) * _pageSize)
        .take(_pageSize)
        .toList();

    emit(
      CatalogState(
        response: PaginatedResponse<CatalogItem>(
          data: items,
          pagination: Pagination(
            currentPage: event.page,
            totalPages: totalPages,
          ),
        ),
      ),
    );
  }
}
