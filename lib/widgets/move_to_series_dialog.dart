import 'package:flutter/material.dart';

import '../models/series.dart';
import 'new_series_dialog.dart';

/// Either an existing series was picked, or [newSeriesTitle] was supplied to
/// have the caller create one first — a plain nullable `Series?` return
/// can't distinguish "cancelled" from "make me a new one".
class MoveToSeriesResult {
  final Series? existingSeries;
  final String? newSeriesTitle;

  const MoveToSeriesResult.existing(Series this.existingSeries) : newSeriesTitle = null;
  const MoveToSeriesResult.newSeries(String this.newSeriesTitle) : existingSeries = null;
}

Future<MoveToSeriesResult?> showMoveToSeriesDialog(
  BuildContext context, {
  required List<Series> existingSeries,
}) async {
  return showDialog<MoveToSeriesResult>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add to Series'),
      children: [
        for (final series in existingSeries)
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(MoveToSeriesResult.existing(series)),
            child: Text(series.title),
          ),
        if (existingSeries.isNotEmpty) const Divider(),
        SimpleDialogOption(
          onPressed: () async {
            final title = await showNewSeriesDialog(context);
            if (title == null) return;
            if (context.mounted) {
              Navigator.of(context).pop(MoveToSeriesResult.newSeries(title));
            }
          },
          child: const Row(
            children: [Icon(Icons.add), SizedBox(width: 8), Text('New Series…')],
          ),
        ),
      ],
    ),
  );
}
