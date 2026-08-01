import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/export_outline.dart';
import '../../models/manuscript.dart';
import '../../models/project.dart';
import '../manuscript_service.dart';
import 'manuscript_outline_builder.dart';
import 'markdown_lite.dart';
import 'pdf_widget_builder.dart';

/// A trim size KDP accepts for *some* print binding — paperback and
/// hardcover each have their own fixed preset list (different sizes,
/// different page-count ranges), but both are just a physical width/height
/// in inches as far as the shared print-export engine below cares. Letting
/// `KdpTrimSize` (paperback) and `KdpHardcoverTrimSize` (hardcover, in
/// `kdp_hardcover_exporter.dart`) both implement this lets one exporter
/// engine serve both bindings via structural typing, rather than
/// duplicating the ~350 lines of margin/numbering/header/copyright logic
/// per binding.
abstract interface class KdpPrintTrimSize {
  double get widthIn;
  double get heightIn;
}

/// KDP's paperback trim size presets (inches) — a fixed dropdown, not free
/// entry, since an arbitrary size would produce an invalid submission. See
/// `KDP_CRIBSHEET.md`'s Paperback section for the source. All 16 of KDP's
/// published paperback trim sizes (5 standard + 11 large), confirmed
/// 2026-08-01 against KDP's own trim-size table.
enum KdpTrimSize implements KdpPrintTrimSize {
  in5x8(5.0, 8.0),
  in5_06x7_81(5.06, 7.81),
  in5_25x8(5.25, 8.0),
  in5_5x8_5(5.5, 8.5),
  in6x9(6.0, 9.0), // most common for novels
  in6_14x9_21(6.14, 9.21),
  in6_69x9_61(6.69, 9.61),
  in7x10(7.0, 10.0),
  in7_44x9_69(7.44, 9.69),
  in7_5x9_25(7.5, 9.25),
  in8x10(8.0, 10.0),
  in8_25x6(8.25, 6.0),
  in8_25x8_25(8.25, 8.25),
  in8_5x8_5(8.5, 8.5),
  in8_5x11(8.5, 11.0),
  in8_27x11_69(8.27, 11.69);

  const KdpTrimSize(this.widthIn, this.heightIn);
  @override
  final double widthIn;
  @override
  final double heightIn;
}

/// KDP's paperback ink/paper combinations — each has its own page-count
/// range, and it varies further by trim size (see [KdpTrimSize.pageCountRange]
/// below). Confirmed 2026-08-01 against KDP's own trim-size table.
enum KdpInkPaperType { blackWhite, blackCream, groundwood, standardColor, premiumColor }

/// Resolves a trim size + ink/paper combination to KDP's actual allowed
/// page-count range — this is *not* a single flat number across every trim
/// size, unlike the old hardcoded 24-828 default suggested. Most sizes share
/// one range per ink type, but three trim-size groups (the 8.25" square/
/// wide sizes, the 8.5" square/tall sizes, and 8.27"x11.69") each have their
/// own tighter bands, and standard color ink isn't offered at all for
/// 8.27"x11.69". Returns `null` when KDP doesn't offer that combination.
extension KdpPaperbackPageCountRange on KdpTrimSize {
  (int min, int max)? pageCountRange(KdpInkPaperType inkPaperType) {
    // Most trim sizes share this band.
    const standard = (24, 828);
    const cream = (24, 776);
    const groundwood = (24, 812);
    const color = (72, 600);
    const premium = (24, 828);

    // 8.25"x6" and 8.25"x8.25" share a tighter band.
    const standard825 = (24, 800);
    const cream825 = (24, 750);
    const groundwood825 = (24, 784);
    const premium825 = (24, 800);

    // 8.5"x8.5" and 8.5"x11" share an even tighter band.
    const standard85 = (24, 590);
    const cream85 = (24, 550);
    const groundwood85 = (24, 578);
    const premium85 = (24, 590);

    // 8.27"x11.69" is its own case, and has no standard-color option at all.
    const standard827 = (24, 780);
    const cream827 = (24, 730);
    const groundwood827 = (24, 764);
    const premium827 = (24, 590);

    (int, int)? bandFor((int, int) std, (int, int) crm, (int, int) gw, (int, int)? clr,
        (int, int) prem) {
      return switch (inkPaperType) {
        KdpInkPaperType.blackWhite => std,
        KdpInkPaperType.blackCream => crm,
        KdpInkPaperType.groundwood => gw,
        KdpInkPaperType.standardColor => clr,
        KdpInkPaperType.premiumColor => prem,
      };
    }

    return switch (this) {
      KdpTrimSize.in8_25x6 ||
      KdpTrimSize.in8_25x8_25 =>
        bandFor(standard825, cream825, groundwood825, color, premium825),
      KdpTrimSize.in8_5x8_5 ||
      KdpTrimSize.in8_5x11 =>
        bandFor(standard85, cream85, groundwood85, color, premium85),
      KdpTrimSize.in8_27x11_69 =>
        bandFor(standard827, cream827, groundwood827, null, premium827),
      _ => bandFor(standard, cream, groundwood, color, premium),
    };
  }
}

/// Thrown when the manuscript can't be exported as a valid KDP print book
/// (paperback or hardcover) — currently just the page-count range, but the
/// shape covers future checks too (mirrors `EpubExportException`'s "fail
/// loud rather than hand back a file KDP will reject" approach). Shared
/// across both bindings rather than named after just one of them.
class KdpPrintExportException implements Exception {
  KdpPrintExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Old name, kept as a type alias so existing call sites/imports referring
/// to the paperback-specific name keep working unchanged.
typedef KdpPaperbackExportException = KdpPrintExportException;

/// KDP-ready paperback interior PDF — trim size, bleed, and margins scaled
/// to the actual resulting page count, per KDP's own rules (see
/// `KDP_CRIBSHEET.md`'s Paperback section). Cover generation is explicitly
/// out of scope (see PLAN.md's Export feature section) — this produces the
/// interior file only.
///
/// **Scope note (2026-08-01):** margins are symmetric (same value on every
/// edge of every page), not true mirrored odd/even binding-side margins —
/// a deliberate v1 simplification (the `pdf` package has no built-in
/// per-page-parity margin support; true mirroring would need custom
/// per-page layout, a separate piece of work). The left/right margin uses
/// the page-count band's *inside* (gutter) value — the larger, binding-
/// critical figure — applied uniformly, so the KDP-mandated minimum holds
/// on whichever edge ends up as the real binding side once true mirroring
/// is built. Top/bottom use the *outside* minimum.
///
/// **Copyright page** (added 2026-08-01): auto-generated and always
/// prepended as front matter's own first page (roman "i"), ahead of any of
/// the project's own front-matter `SpecialSection`s (dedication, preface,
/// etc.) — a real book's copyright page isn't optional/user-authored
/// content the way a dedication is, and Narraity has no dedicated content
/// type for it yet. Uses `project.title`/`project.author` and the *current
/// export date's* year (there's no dedicated "publication year" field on
/// `Project` to prefer instead) for a standard boilerplate notice — this is
/// a reasonable default, not legal advice; a real author may want to edit
/// the exact wording, which isn't customizable yet. **Half-title page and
/// true recto/verso (right/left-facing) placement are still out of scope**
/// — KDP's guidance that half-title/title always land on a right-facing
/// page (inserting a blank left-facing page if needed to keep it so) needs
/// blank-page-insertion logic this export doesn't have; see
/// CONSIDERATIONS.md.
///
/// **Page numbering** (added 2026-08-01): front matter gets lowercase roman
/// numerals (i, ii, iii...), body + back matter get Arabic numerals
/// restarting at 1 — each section is its own `pw.MultiPage`, and each
/// section's footer callback lazily captures the *global* page number
/// (`Context.pageNumber`, a running index across the whole `Document`) the
/// first time it fires, then subtracts that captured offset on every
/// subsequent page — no extra build pass needed to "learn" how many pages
/// preceded a section, since by the time a later `MultiPage`'s pages are
/// laid out, every earlier section's pages already exist in the shared
/// `Document`.
///
/// **Running headers** (added 2026-08-01, chapter-opening suppression added
/// 2026-08-01): alternate by page parity — odd page = book title (right-
/// facing/recto convention), even page = author name (left-facing/verso) —
/// shown on every body/back-matter page **except each chapter's own first
/// page**, per KDP's guidance. Achieved by giving every chapter-boundary
/// group (see `ManuscriptOutlineBuilder`/`ExportSection.startsNewPage`) its
/// *own* `pw.MultiPage`, rather than one continuous body-wide `MultiPage` —
/// each chapter's header callback can then suppress specifically on its own
/// first page (a fresh, per-chapter "have I painted this chapter's first
/// page yet" flag), which a single shared `MultiPage` has no way to detect.
/// Page numbering still reads as one continuous Arabic sequence across
/// every chapter, via one page-index closure created once for the whole
/// body and shared across all of that body's per-chapter `MultiPage`s —
/// distinct from the *per-chapter* header-suppression flag, which is
/// deliberately fresh for each chapter.
class KdpPaperbackExporter {
  KdpPaperbackExporter(
    this.projectDir, {
    this.minPageCount,
    this.maxPageCount,
    this.compressPdf = true,
  });

  final Directory projectDir;

  /// Overrides the page-count range that would otherwise be looked up from
  /// [KdpTrimSize.pageCountRange] for the trim size + ink/paper type passed
  /// to [buildBytes]/[exportToFile] — tests use this to hit a boundary
  /// without needing a pathologically large (or literally empty) real
  /// manuscript, same rationale as `EpubExporter`'s injectable limits.
  final int? minPageCount;
  final int? maxPageCount;

  /// [compressPdf] defaults to on (real output); tests set it `false` so
  /// footer/header text lands as plain greppable bytes in the PDF content
  /// stream instead of Flate-compressed, letting the roman/Arabic
  /// numbering and alternating-header logic be verified against actual
  /// rendered text rather than only via page-count/structural proxies.
  final bool compressPdf;
  final _widgets = const PdfWidgetBuilder();

  /// Bleed adds this many inches to each edge beyond the trim line, per
  /// KDP's spec — e.g. a 6"×9" bled page becomes 6.125"×9.25".
  static const double bleedInches = 0.125;

  /// Inside (gutter) margin in inches, banded by final page count — the
  /// binding-critical figure. Table straight from KDP's own docs. Public
  /// (not `_`-prefixed) so tests can verify the exact banding without
  /// parsing PDF bytes for it.
  static double gutterInches(int pageCount) => switch (pageCount) {
        <= 150 => 0.375,
        <= 300 => 0.5,
        <= 500 => 0.625,
        <= 700 => 0.75,
        _ => 0.875,
      };

  /// Outside-edge minimum, which also stands in for top/bottom here (see
  /// class doc's scope note) — differs only by whether bleed is in use.
  static double outsideMinInches(bool bleed) => bleed ? 0.375 : 0.25;

  /// Resolves trim size + bleed + page count to a concrete [PdfPageFormat]
  /// — public for the same direct-testability reason as [gutterInches].
  static PdfPageFormat pageFormatFor(KdpPrintTrimSize trimSize, bool bleed, int pageCount) {
    final bleedPad = bleed ? bleedInches : 0.0;
    // KDP bleeds top+bottom but only the outer edge of width — the inner
    // (spine/gutter) edge never bleeds. E.g. 6"x9" with bleed -> 6.125"x9.25".
    final widthIn = trimSize.widthIn + bleedPad;
    final heightIn = trimSize.heightIn + bleedPad * 2;

    final gutter = gutterInches(pageCount);
    final outside = outsideMinInches(bleed);

    return PdfPageFormat(
      widthIn * PdfPageFormat.inch,
      heightIn * PdfPageFormat.inch,
      marginLeft: gutter * PdfPageFormat.inch,
      marginRight: gutter * PdfPageFormat.inch,
      marginTop: outside * PdfPageFormat.inch,
      marginBottom: outside * PdfPageFormat.inch,
    );
  }

  /// A standard boilerplate copyright notice, centered near the page's
  /// vertical middle (conventional placement) — see the class doc's
  /// "Copyright page" note for what this does and doesn't cover.
  List<pw.Widget> _copyrightPageWidgets(Project project) {
    final year = DateTime.now().year;
    final holder = (project.author != null && project.author!.isNotEmpty)
        ? project.author!
        : project.title;
    return [
      pw.SizedBox(height: 280),
      pw.Center(
        child: pw.Text(
          'Copyright © $year ${_widgets.pdfSafeText(holder)}',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'All rights reserved.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'No part of this book may be reproduced in any form without permission '
          'in writing from the author, except by a reviewer who may quote brief '
          'passages in a review.',
          style: const pw.TextStyle(fontSize: 9),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'This is a work of fiction. Names, characters, places, and incidents '
          'either are products of the author\'s imagination or are used '
          'fictitiously.',
          style: const pw.TextStyle(fontSize: 9),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ];
  }

  /// Renders [sections] (already filtered to one kind) into a flat widget
  /// list — used for front matter, which stays one continuous `MultiPage`
  /// (no per-chapter header-suppression concern there).
  Future<List<pw.Widget>> _sectionWidgets(List<ExportSection> sections) async {
    final manuscript = ManuscriptService(projectDir);
    final widgets = <pw.Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      if (section.startsNewPage && i > 0) {
        widgets.add(pw.NewPage());
      }
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      if (section.showTitle) {
        widgets.addAll(_widgets.sectionHeadingWidgets(section.title, section.depth));
      }
      for (final block in MarkdownLite.parse(doc.content)) {
        widgets.addAll(_widgets.blockWidgets(block));
      }
    }
    return widgets;
  }

  /// Renders [sections] into one widget list *per chapter-boundary group*
  /// (a boundary section plus every non-boundary section — e.g. Scenes —
  /// that follows it before the next boundary), instead of one flat list —
  /// so the body can become one `pw.MultiPage` per chapter, letting each
  /// chapter's header be suppressed specifically on its own first page. No
  /// `pw.NewPage()` is inserted between groups here (unlike the old flat
  /// version): each group becomes its own separately-`addPage()`d
  /// `MultiPage`, which already starts fresh on its own page.
  Future<List<List<pw.Widget>>> _groupedSectionWidgets(List<ExportSection> sections) async {
    final manuscript = ManuscriptService(projectDir);
    final groups = <List<pw.Widget>>[];

    for (final section in sections) {
      if (groups.isEmpty || section.startsNewPage) {
        groups.add(<pw.Widget>[]);
      }
      final doc = await manuscript.readScene(section.id, fallbackTitle: section.title);
      if (section.showTitle) {
        groups.last.addAll(_widgets.sectionHeadingWidgets(section.title, section.depth));
      }
      for (final block in MarkdownLite.parse(doc.content)) {
        groups.last.addAll(_widgets.blockWidgets(block));
      }
    }
    return groups;
  }

  /// Returns a fresh `pw.Context -> int` local-page-index function, scoped
  /// to exactly one call site via closure — **not** a shared instance field.
  /// An earlier version used one instance field for every section's offset
  /// capture; since all three sections' `MultiPage`s get `addPage()`d
  /// synchronously (during `_build`, before `save()` ever triggers any
  /// footer/header callback), resetting a *shared* field "before" each
  /// section only ever reset it before the *next* section actually painted,
  /// not before that section's own callbacks ran — so the body section
  /// silently inherited front matter's already-captured offset instead of
  /// getting its own. Caught by a real test (`front matter is numbered with
  /// lowercase roman numerals...`) throwing a Roman-numeral range assertion
  /// deep in the `pdf` package. A closure-local variable, freshly allocated
  /// per section per `_build` call, has no such cross-section or
  /// cross-build-pass contamination possible.
  int Function(pw.Context) _localPageIndexFactory() {
    int? sectionStart;
    return (context) {
      sectionStart ??= context.pageNumber;
      return context.pageNumber - sectionStart!;
    };
  }

  /// A footer builder using [localPageIndex] (shared across every
  /// `MultiPage` in one section, so numbering reads as one continuous
  /// sequence even when the body is split into several per-chapter
  /// `MultiPage`s) to render either roman-lowercase or Arabic numerals.
  pw.Widget Function(pw.Context) _numberedFooter(
    int Function(pw.Context) localPageIndex,
    PdfPageLabelStyle numeralStyle,
  ) {
    return (context) {
      final label = switch (numeralStyle) {
        PdfPageLabelStyle.romanLower => PdfPageLabel.romanLower().asString(localPageIndex(context)),
        _ => '${localPageIndex(context) + 1}',
      };
      return pw.Center(child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)));
    };
  }

  pw.MultiPage _numberedMultiPage({
    required PdfPageFormat pageFormat,
    required List<pw.Widget> widgets,
    required PdfPageLabelStyle numeralStyle,
    int Function(pw.Context)? sharedLocalPageIndex,
    pw.Widget Function(pw.Context, int pageNumber)? header,
  }) {
    final localPageIndex = sharedLocalPageIndex ?? _localPageIndexFactory();
    return pw.MultiPage(
      pageFormat: pageFormat,
      maxPages: 100000,
      header: header == null ? null : (context) => header(context, localPageIndex(context) + 1),
      footer: _numberedFooter(localPageIndex, numeralStyle),
      build: (context) => widgets,
    );
  }

  /// Odd page = book title (right-facing/recto), even page = author name
  /// (left-facing/verso) — standard novel-typesetting convention. [pageNumber]
  /// here is the whole-body continuous page number (the same one printed in
  /// the footer), since recto/verso parity is a whole-book physical-page
  /// concept — *not* the chapter-relative index used elsewhere to decide
  /// whether to suppress the header entirely (see `_build`'s per-chapter
  /// loop, which composes that separately). Conflating the two in an
  /// earlier version broke suppression: see that version's own doc comment,
  /// removed here, for what went wrong and how it was caught by testing.
  pw.Widget _runningHeader(pw.Context context, int pageNumber, Project project) {
    final text = pageNumber.isOdd
        ? _widgets.pdfSafeText(project.title)
        : (project.author != null && project.author!.isNotEmpty
            ? _widgets.pdfSafeText(project.author!)
            : _widgets.pdfSafeText(project.title));
    return pw.Container(
      alignment: pageNumber.isOdd ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
  }

  Future<pw.Document> _build(
    Project project,
    ManuscriptStructure structure,
    PdfPageFormat pageFormat,
  ) async {
    final sections = ManuscriptOutlineBuilder.build(structure);
    final frontMatterSections =
        sections.where((s) => s.kind == ExportSectionKind.frontMatter).toList();
    final bodySections = sections.where((s) => s.kind != ExportSectionKind.frontMatter).toList();

    // Widget lists are all read up front (this method is async; `MultiPage.
    // build` isn't), then each section's synchronous `build:` callback just
    // returns its already-computed list.
    //
    // `titlePageWidgets` ends with a trailing `pw.NewPage()` — needed when
    // `PdfExporter` flows title + body through one continuous `MultiPage`,
    // but harmful here: title is its own separate `MultiPage` (each
    // `addPage()` call already starts fresh on its own page), so that
    // trailing NewPage would otherwise produce a stray blank second page
    // with nothing on it.
    final titleWidgets = _widgets.titlePageWidgets(project)..removeLast();

    // Copyright page always comes first in front matter (roman "i") — see
    // the class doc's "Copyright page" note for why this isn't optional or
    // user-authored the way the rest of front matter is. A NewPage only
    // gets inserted before the user's own front matter if there is any.
    final userFrontMatterWidgets = await _sectionWidgets(frontMatterSections);
    final frontMatterWidgets = [
      ..._copyrightPageWidgets(project),
      if (userFrontMatterWidgets.isNotEmpty) pw.NewPage(),
      ...userFrontMatterWidgets,
    ];

    final bodyChapterGroups = await _groupedSectionWidgets(bodySections);

    final pdfDoc = pw.Document(compress: compressPdf);

    // Title page: no header/footer.
    pdfDoc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        maxPages: 100000,
        build: (context) => titleWidgets,
      ),
    );

    if (frontMatterWidgets.isNotEmpty) {
      pdfDoc.addPage(_numberedMultiPage(
        pageFormat: pageFormat,
        widgets: frontMatterWidgets,
        numeralStyle: PdfPageLabelStyle.romanLower,
      ));
    }

    // One `MultiPage` per chapter — not one continuous body-wide MultiPage —
    // so each chapter's header can be suppressed specifically on its own
    // first page (see the class doc's "Running headers" note). Every
    // chapter shares the *same* `bodyPageIndex` closure so Arabic numbering
    // (and title/author recto-verso parity, a whole-book physical-page
    // concept) still reads as one continuous sequence across chapter
    // boundaries. Suppression, in contrast, needs a *chapter-relative*
    // notion of "is this page 1 of this specific chapter" — composed here
    // via a second, fresh-per-chapter index (`chapterPageIndex`), kept
    // entirely separate from `bodyPageIndex` rather than trying to derive
    // one from the other.
    final bodyPageIndex = _localPageIndexFactory();
    for (final chapterWidgets in bodyChapterGroups) {
      final chapterPageIndex = _localPageIndexFactory();
      pdfDoc.addPage(_numberedMultiPage(
        pageFormat: pageFormat,
        widgets: chapterWidgets,
        numeralStyle: PdfPageLabelStyle.arabic,
        sharedLocalPageIndex: bodyPageIndex,
        header: (context, wholeBodyPageNumber) {
          final isChaptersFirstPage = chapterPageIndex(context) == 0;
          return isChaptersFirstPage
              ? pw.SizedBox()
              : _runningHeader(context, wholeBodyPageNumber, project);
        },
      ));
    }

    return pdfDoc;
  }

  /// Builds the print-ready interior PDF. Margins depend on the final page
  /// count, which depends on the margins — resolved with up to two build
  /// passes: an initial guess (the smallest page-count band) produces a
  /// real page count, and if that count falls in a different band than
  /// assumed, one rebuild with the correct margins follows. Margin changes
  /// between adjacent bands are modest (a fraction of an inch) relative to
  /// a real trim size, so a second pass is expected to converge in
  /// practice; not iterated further than that.
  /// Resolves the effective (min, max) page-count range: an explicit
  /// [minPageCount]/[maxPageCount] override always wins (this is how
  /// `KdpHardcoverExporter` supplies its own fixed 75-550 range, and how
  /// tests hit boundaries); otherwise, for a real paperback [KdpTrimSize],
  /// [inkPaperType] is required and the range comes from
  /// [KdpPaperbackPageCountRange.pageCountRange] — KDP's range varies by
  /// trim size *and* ink/paper type, not one flat number.
  (int min, int max) _resolvePageCountRange(KdpPrintTrimSize trimSize, KdpInkPaperType? inkPaperType) {
    if (minPageCount != null && maxPageCount != null) {
      return (minPageCount!, maxPageCount!);
    }
    if (trimSize is! KdpTrimSize) {
      throw ArgumentError(
        'minPageCount/maxPageCount must be supplied explicitly for a non-paperback trim size',
      );
    }
    if (inkPaperType == null) {
      throw ArgumentError('inkPaperType is required to resolve KDP\'s paperback page-count range');
    }
    final range = trimSize.pageCountRange(inkPaperType);
    if (range == null) {
      throw KdpPrintExportException(
        'KDP does not offer ${inkPaperType.name} for trim size '
        '${trimSize.widthIn}"x${trimSize.heightIn}".',
      );
    }
    return range;
  }

  Future<Uint8List> buildBytes(
    Project project,
    ManuscriptStructure structure, {
    required KdpPrintTrimSize trimSize,
    bool bleed = false,
    KdpInkPaperType? inkPaperType,
  }) async {
    final (effectiveMin, effectiveMax) = _resolvePageCountRange(trimSize, inkPaperType);

    // `_build` reads and renders the manuscript fresh each call, deliberately
    // not sharing widgets across the two `pw.Document`s below — `pw.Widget`s
    // carry internal layout/paint state that isn't safe to replay into a
    // second, separate Document build (reusing the same instances threw a
    // RangeError deep in the `pdf` package's own `RichText.paint` on the
    // second pass when this was first tried).
    var pageFormat = pageFormatFor(trimSize, bleed, effectiveMin);
    var pdfDoc = await _build(project, structure, pageFormat);
    var bytes = await pdfDoc.save();
    var pageCount = pdfDoc.document.pdfPageList.pages.length;

    final rebandedFormat = pageFormatFor(trimSize, bleed, pageCount);
    if (rebandedFormat.marginLeft != pageFormat.marginLeft) {
      pdfDoc = await _build(project, structure, rebandedFormat);
      bytes = await pdfDoc.save();
      pageCount = pdfDoc.document.pdfPageList.pages.length;
    }

    if (pageCount < effectiveMin || pageCount > effectiveMax) {
      throw KdpPrintExportException(
        'This manuscript would be $pageCount pages, outside KDP\'s paperback range of '
        '$effectiveMin–$effectiveMax pages.',
      );
    }

    return bytes;
  }

  Future<File> exportToFile(
    Project project,
    ManuscriptStructure structure,
    String outputPath, {
    required KdpPrintTrimSize trimSize,
    bool bleed = false,
    KdpInkPaperType? inkPaperType,
  }) async {
    final bytes = await buildBytes(
      project,
      structure,
      trimSize: trimSize,
      bleed: bleed,
      inkPaperType: inkPaperType,
    );
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }
}
