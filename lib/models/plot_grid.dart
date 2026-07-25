/// Plot Grid — plot lines (rows) crossed with manuscript scenes (columns),
/// each intersection optionally holding a plot point. Mirrors
/// `plot-grid/plotlines.json` and `plot-grid/plotpoints.json` (see PLAN.md
/// "Data model").
library;

/// A colour-coded thread running through the manuscript (main plot, a
/// subplot, a POV character's arc, ...). Rows in the grid.
class PlotLine {
  final String id;
  String name;

  /// ARGB int, i.e. `Color.value` — stored as a plain int so this model has
  /// no Flutter dependency and stays unit-testable without a widget test.
  int color;

  PlotLine({required this.id, required this.name, required this.color});

  PlotLine copyWith({String? name, int? color}) => PlotLine(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};

  factory PlotLine.fromJson(Map<String, dynamic> json) => PlotLine(
        id: json['id'] as String,
        name: json['name'] as String,
        color: json['color'] as int,
      );
}

/// One grid cell: a beat on [plotlineId] that happens in [sceneId]. `notes`
/// is longer-form detail shown when the card is expanded; `title` is the
/// short label shown on the grid cell itself.
class PlotPoint {
  final String id;
  final String plotlineId;
  final String sceneId;
  String title;
  String notes;

  PlotPoint({
    required this.id,
    required this.plotlineId,
    required this.sceneId,
    required this.title,
    this.notes = '',
  });

  PlotPoint copyWith({String? title, String? notes}) => PlotPoint(
        id: id,
        plotlineId: plotlineId,
        sceneId: sceneId,
        title: title ?? this.title,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plotlineId': plotlineId,
        'sceneId': sceneId,
        'title': title,
        'notes': notes,
      };

  factory PlotPoint.fromJson(Map<String, dynamic> json) => PlotPoint(
        id: json['id'] as String,
        plotlineId: json['plotlineId'] as String,
        sceneId: json['sceneId'] as String,
        title: json['title'] as String,
        notes: json['notes'] as String? ?? '',
      );
}
