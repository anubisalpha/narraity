import '../data/publishing_guidance.dart';

/// A project's Publishing Hub state — which route it's pursuing, the genre
/// used to fill guidance placeholders, and which checklist items are
/// checked off. Mirrors `planning/publishing_checklist.json`.
class PublishingChecklistState {
  PublishingChecklistState({
    this.selectedRoute,
    this.genre = '',
    Set<String>? checkedItemIds,
  }) : checkedItemIds = checkedItemIds ?? {};

  PublishingRoute? selectedRoute;
  String genre;
  final Set<String> checkedItemIds;

  PublishingChecklistState copyWith({
    PublishingRoute? selectedRoute,
    bool clearSelectedRoute = false,
    String? genre,
    Set<String>? checkedItemIds,
  }) => PublishingChecklistState(
    selectedRoute: clearSelectedRoute ? null : (selectedRoute ?? this.selectedRoute),
    genre: genre ?? this.genre,
    checkedItemIds: checkedItemIds ?? this.checkedItemIds,
  );

  Map<String, dynamic> toJson() => {
    if (selectedRoute != null) 'selectedRoute': selectedRoute!.name,
    'genre': genre,
    'checkedItemIds': checkedItemIds.toList(),
  };

  factory PublishingChecklistState.fromJson(Map<String, dynamic> json) =>
      PublishingChecklistState(
        selectedRoute: _routeFromName(json['selectedRoute'] as String?),
        genre: json['genre'] as String? ?? '',
        checkedItemIds:
            (json['checkedItemIds'] as List<dynamic>? ?? []).cast<String>().toSet(),
      );
}

PublishingRoute? _routeFromName(String? name) {
  if (name == null) return null;
  for (final route in PublishingRoute.values) {
    if (route.name == name) return route;
  }
  return null;
}
