import 'package:flutter/foundation.dart';

/// One page of items returned by an application's data source.
///
/// Map your API response to this type in the widget's response selector.
/// When [pagination] is omitted, an empty page ends pagination.
@immutable
class PaginatedResponse<T> {
  /// Creates a response with an unmodifiable snapshot of [data].
  PaginatedResponse({required List<T> data, this.pagination})
    : data = List<T>.unmodifiable(data);

  /// Items belonging to this page, rather than all previously loaded pages.
  final List<T> data;

  /// Optional page information supplied by the data source.
  final Pagination? pagination;
}

/// The current page and last available page in a paginated response.
@immutable
class Pagination {
  /// Creates page information. Page numbers may start at zero or one.
  ///
  /// [totalPages] is the last available page number, and may be zero for an
  /// empty result. For zero-based APIs, map a page count to its final index.
  const Pagination({required this.currentPage, required this.totalPages})
    : assert(currentPage >= 0),
      assert(totalPages >= 0);

  /// Page represented by the response.
  final int currentPage;

  /// Last available page number (a page count for one-based APIs).
  final int totalPages;
}
