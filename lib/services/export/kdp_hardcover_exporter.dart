import 'dart:io';
import 'dart:typed_data';

import '../../models/manuscript.dart';
import '../../models/project.dart';
import 'kdp_paperback_exporter.dart';

/// KDP's hardcover trim size presets (inches) — a distinct, smaller list
/// from paperback's. See `KDP_CRIBSHEET.md`'s Hardcover section for the
/// source; KDP's own hardcover help page is a navigation hub pointing at
/// the *same* trim/margin and front/body/back-matter sub-topics used for
/// paperback, rather than a separate table — so the margin/bleed rules
/// below are a working assumption of "same as paperback," not independently
/// confirmed for hardcover specifically. Revisit if that assumption is ever
/// contradicted by KDP's docs (the `kdp-watch` scheduled task will flag if
/// any of the watched pages change).
enum KdpHardcoverTrimSize implements KdpPrintTrimSize {
  in5_5x8_5(5.5, 8.5),
  in6x9(6.0, 9.0),
  in6_14x9_21(6.14, 9.21),
  in7x10(7.0, 10.0),
  in8_25x11(8.25, 11.0);

  const KdpHardcoverTrimSize(this.widthIn, this.heightIn);
  @override
  final double widthIn;
  @override
  final double heightIn;
}

/// KDP-ready hardcover interior PDF. Narrower page-count range than
/// paperback (75–550 vs. 24–828) and its own trim size list, but otherwise
/// reuses `KdpPaperbackExporter`'s engine wholesale (margin/bleed/numbering/
/// header/copyright-page logic) rather than duplicating it — see that
/// class's doc comment for how all of that works, and this file's
/// `KdpHardcoverTrimSize` doc for the one open question (hardcover-specific
/// margin/bleed rules aren't independently confirmed, only assumed
/// identical to paperback's).
///
/// **Cover mechanics are out of scope** (same as paperback) — KDP prints
/// hardcovers as case laminate (no dust jacket, art printed directly on the
/// case), which would make cover handling simpler than paperback's wrap
/// even if it were in scope, but it isn't: this produces the interior file
/// only.
class KdpHardcoverExporter {
  /// [minPageCount]/[maxPageCount] default to KDP's real hardcover range —
  /// overridable for the same reason `KdpPaperbackExporter`'s are.
  KdpHardcoverExporter(
    Directory projectDir, {
    int minPageCount = 75,
    int maxPageCount = 550,
    bool compressPdf = true,
  }) : _engine = KdpPaperbackExporter(
          projectDir,
          minPageCount: minPageCount,
          maxPageCount: maxPageCount,
          compressPdf: compressPdf,
        );

  final KdpPaperbackExporter _engine;

  int get minPageCount => _engine.minPageCount!;
  int get maxPageCount => _engine.maxPageCount!;

  Future<Uint8List> buildBytes(
    Project project,
    ManuscriptStructure structure, {
    required KdpHardcoverTrimSize trimSize,
    bool bleed = false,
  }) {
    return _engine.buildBytes(project, structure, trimSize: trimSize, bleed: bleed);
  }

  Future<File> exportToFile(
    Project project,
    ManuscriptStructure structure,
    String outputPath, {
    required KdpHardcoverTrimSize trimSize,
    bool bleed = false,
  }) {
    return _engine.exportToFile(project, structure, outputPath, trimSize: trimSize, bleed: bleed);
  }
}
