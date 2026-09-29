/// The internal controller's projection used to render the paginated view.
///
/// [items] is a read-only live view owned by the controller, not a historical
/// snapshot. The controller notifies listeners after each complete transition.
class PaginationViewState<T> {
  const PaginationViewState({
    required this.items,
    this.isLoading = false,
    this.error,
  });

  final List<T> items;
  final bool isLoading;
  final String? error;
}
