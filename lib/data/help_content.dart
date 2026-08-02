import 'package:flutter/material.dart';

import '../models/help_topic.dart';

/// Every Help segment, in the order the Help page shows them: roughly the
/// order a new user would actually meet the screens, starting from the
/// Library. Content lives here rather than inline in `HelpScreen` so a
/// future in-context help icon on any given screen can import just this
/// list and jump to its own segment (see `openHelpTopic`) without dragging
/// in the whole settings UI.
///
/// Keep entries factual and short — one or two sentences on *what it does
/// and why you'd use it*, not a restatement of the label. If a description
/// would need three sentences, the feature probably wants its own topic
/// instead of a longer entry.
const List<HelpTopic> helpTopics = [
  HelpTopic(
    id: 'library',
    title: 'Library (Home)',
    icon: Icons.home_outlined,
    intro:
        'The screen you land on when the app opens — every standalone project '
        'and every series as cards, plus the app-wide tools that aren\'t tied '
        'to one manuscript.',
    entries: [
      HelpEntry(
        icon: Icons.add,
        title: 'New Project',
        description:
            'Starts a blank novel, comic, or script project and opens it '
            'straight into the manuscript editor.',
      ),
      HelpEntry(
        icon: Icons.collections_bookmark_outlined,
        title: 'New Series',
        description:
            'Creates a Series — a shared container for two or more related '
            'projects (a trilogy, a book-per-POV set) with its own Characters, '
            'World, Notes, and To-dos that every book inside it can see.',
      ),
      HelpEntry(
        icon: Icons.lightbulb_outline,
        title: 'New Idea',
        description:
            'Quick-capture a stray idea without leaving the Library — goes '
            'into Global Ideas rather than any one project.',
      ),
      HelpEntry(
        icon: Icons.tips_and_updates_outlined,
        title: 'Global Ideas',
        description:
            'Every idea captured app-wide (not tied to a project), in one '
            'list — the inbox for things you don\'t want to lose before you '
            'know which book they belong to.',
      ),
      HelpEntry(
        icon: Icons.flag_circle_outlined,
        title: 'App-Wide Goals',
        description:
            'Writing goals that track across every project at once, separate '
            'from a single project\'s own Goals (see the project toolbar).',
      ),
      HelpEntry(
        icon: Icons.rate_review_outlined,
        title: 'Review a Manuscript',
        description:
            'Manage manuscripts you\'ve sent out for external/AI review and '
            'bring their feedback back in — the other end of a project\'s own '
            'Export / Import for Review action.',
      ),
      HelpEntry(
        icon: Icons.file_upload_outlined,
        title: 'Import Manuscript',
        description:
            'Bring in an existing manuscript file (e.g. from another app) as '
            'a new project, splitting it into chapters/scenes automatically.',
      ),
      HelpEntry(
        icon: Icons.campaign_outlined,
        title: 'News',
        description:
            'What\'s changed recently — release notes for new versions as '
            'they land.',
      ),
      HelpEntry(
        icon: Icons.inventory_2_outlined,
        title: 'Archived & Deleted Projects',
        description:
            'Projects you\'ve archived or deleted — restore one, or confirm '
            'it\'s really gone. Nothing here is touched by the vault backup '
            'process.',
      ),
      HelpEntry(
        icon: Icons.settings_outlined,
        title: 'Settings',
        description: 'App-wide preferences — this Help page lives here too.',
      ),
      HelpEntry(
        icon: Icons.more_vert,
        title: 'Project card menu',
        description:
            'On each card: Add to Series…, Card style… (novel/comic/script '
            'frame), Archive, and Delete.',
      ),
    ],
  ),
  HelpTopic(
    id: 'series',
    title: 'Series',
    icon: Icons.collections_bookmark_outlined,
    intro:
        'Opened by clicking a series\' stacked card in the Library. Its own '
        'Characters, World, Notes, and To-dos are shared storage — separate '
        'from any one book\'s own, and visible from every project inside the '
        'series.',
    entries: [
      HelpEntry(
        icon: Icons.people_outline,
        title: 'Characters / World / Notes / To-dos tabs',
        description:
            'Content that belongs to the series as a whole (a recurring '
            'antagonist, the shared magic system) rather than one book. '
            'Works exactly like a project\'s own tabs of the same name.',
      ),
      HelpEntry(
        icon: Icons.add,
        title: 'New Project in Series',
        description: 'Adds another book to this series.',
      ),
      HelpEntry(
        icon: Icons.arrow_back,
        title: 'Back button (inside a series project)',
        description:
            'Opening a project from inside a series and pressing Back '
            'returns you to that series\' screen, not straight to the '
            'Library — so you don\'t lose your place in the series.',
      ),
    ],
  ),
  HelpTopic(
    id: 'manuscript',
    title: 'Manuscript Tab',
    icon: Icons.menu_book_outlined,
    intro:
        'The default tab when a project opens: the chapter/scene tree on the '
        'left, the editor for whatever\'s selected on the right.',
    entries: [
      HelpEntry(
        icon: Icons.menu_book_outlined,
        title: 'Chapters & scenes',
        description:
            'The tree mirrors your manuscript\'s structure. Click a scene to '
            'open it; the ⋮ menu on each chapter/scene renames, deletes, or '
            'moves it.',
      ),
      HelpEntry(
        icon: Icons.add,
        title: 'Section',
        description:
            'Adds a new chapter (a "Section" in publishing terms) to the '
            'manuscript.',
      ),
      HelpEntry(
        icon: Icons.image_outlined,
        title: 'Add Front Cover',
        description:
            'Attaches a cover image to the project — shown on its Library '
            'card and used by ebook/paperback export.',
      ),
      HelpEntry(
        icon: Icons.auto_stories_outlined,
        title: 'Front/back matter',
        description:
            'Title page, dedication, acknowledgements — pages that sit '
            'outside the numbered chapter flow but still export with the '
            'manuscript.',
      ),
    ],
  ),
  HelpTopic(
    id: 'sceneEditor',
    title: 'Scene Editor Toolbar',
    icon: Icons.edit_note,
    intro:
        'The formatting bar above a scene\'s text. Saves are automatic — '
        'there\'s no explicit save action to look for.',
    entries: [
      HelpEntry(
        icon: Icons.format_bold,
        title: 'Bold / Italic / Strikethrough',
        description: 'Standard inline formatting for the selected text.',
      ),
      HelpEntry(
        icon: Icons.horizontal_rule,
        title: 'Scene break',
        description:
            'Inserts a visual break (e.g. a centred "* * *") for a scene '
            'shift without a full chapter break.',
      ),
      HelpEntry(
        icon: Icons.format_quote,
        title: 'Block quote',
        description: 'Sets a paragraph off as a quotation.',
      ),
      HelpEntry(
        icon: Icons.title,
        title: 'Heading',
        description: 'Marks a paragraph as a heading within the scene.',
      ),
      HelpEntry(
        icon: Icons.undo,
        title: 'Undo / Redo',
        description:
            'Ctrl+Z / Ctrl+Y also work — this is just the visible fallback.',
      ),
      HelpEntry(
        icon: Icons.search,
        title: 'Find & Replace',
        description: 'Search and replace text within the open scene.',
      ),
      HelpEntry(
        icon: Icons.history,
        title: 'Version History',
        description:
            'Every save is kept as a signed, tamper-evident entry — restore '
            'an earlier version of this scene, or verify nothing\'s been '
            'altered outside the app.',
      ),
      HelpEntry(
        icon: Icons.mic_none,
        title: 'Dictation',
        description:
            'Offline voice-to-text — dictate straight into the scene. '
            'Language and accuracy are set in Settings > Dictation.',
      ),
      HelpEntry(
        icon: Icons.volume_up_outlined,
        title: 'Read Aloud',
        description:
            'Reads the scene back to you — voice, speed, and pitch are set '
            'in Settings > Read Aloud.',
      ),
      HelpEntry(
        icon: Icons.spellcheck,
        title: 'Spell check indicator',
        description:
            'Shows a badge while a pass is still checking a long page, so '
            'a page full of red squiggles reads as "still working," not '
            '"something\'s wrong." Right-click a flagged word for '
            'suggestions or to add it to your dictionary.',
      ),
      HelpEntry(
        icon: Icons.comment_outlined,
        title: 'Comment',
        description: 'Leaves a margin note on the scene without editing the prose itself.',
      ),
    ],
  ),
  HelpTopic(
    id: 'charactersWorld',
    title: 'Characters & World',
    icon: Icons.people_outline,
    intro:
        'Two tabs, one shared design: characters are a flat list, world '
        'entries group under a category (Location, Faction, …). Everything '
        'below applies to both, and to their series-level equivalents.',
    entries: [
      HelpEntry(
        icon: Icons.add,
        title: 'New character / New entry',
        description:
            'Creates a profile with a starter set of fields (Role, Age, '
            'Appearance, … for a character; just Description for a world '
            'entry) — every field can be renamed, removed, or added to.',
      ),
      HelpEntry(
        icon: Icons.star_outline,
        title: 'Quick-reference fields',
        description:
            'Star a field on a profile and it\'s the one shown on the '
            'Reference Panel\'s compact cards while you write, instead of '
            'the full profile.',
      ),
      HelpEntry(
        icon: Icons.push_pin_outlined,
        title: 'Pin to Reference Panel',
        description:
            'Keeps this entry visible in the Reference Panel no matter what '
            'scene you\'re in. A series-level entry pins into every project '
            'in that series at once.',
      ),
      HelpEntry(
        icon: Icons.drive_file_move_outline,
        title: 'Move to series / Move to project…',
        description:
            'Promotes a project-only character or world entry up to the '
            'series (shared with every book in it), or demotes a series one '
            'back into a single project — the entry keeps its id, fields, '
            'and image either way.',
      ),
      HelpEntry(
        icon: Icons.delete_outline,
        title: 'Delete',
        description:
            'Removes the profile and its image. For a character, also '
            'drops any Relationship Diagram links to it.',
      ),
    ],
  ),
  HelpTopic(
    id: 'notes',
    title: 'Notes',
    icon: Icons.sticky_note_2_outlined,
    intro:
        'Freeform notes in folders, separate from Characters/World — for '
        'anything that doesn\'t fit a profile (plot ideas, research, '
        'reminders to yourself).',
    entries: [
      HelpEntry(
        icon: Icons.create_new_folder_outlined,
        title: 'Folders',
        description: 'Organize notes into folders; uncategorised notes sit at the top.',
      ),
      HelpEntry(
        icon: Icons.search,
        title: 'Search',
        description: 'Full-text search across every note.',
      ),
    ],
  ),
  HelpTopic(
    id: 'todos',
    title: 'To-dos',
    icon: Icons.checklist,
    intro:
        'A simple checklist per project (or per series, for series-wide '
        'tasks) — plot threads to resolve, research to do, edits to '
        'revisit.',
  ),
  HelpTopic(
    id: 'referencePanel',
    title: 'Reference Panel',
    icon: Icons.menu_open,
    intro:
        'The dock on the right of the manuscript, showing character/world '
        'cards while you write — context without leaving the page.',
    entries: [
      HelpEntry(
        icon: Icons.push_pin,
        title: 'Pinned',
        description: 'Entries you\'ve explicitly pinned — always shown, regardless of scene.',
      ),
      HelpEntry(
        icon: Icons.alternate_email,
        title: 'Mentions',
        description:
            'Type [[Name]] in a scene and, if it matches a character or '
            'world entry, its card appears here automatically for as long '
            'as that scene is open.',
      ),
      HelpEntry(
        icon: Icons.help_outline,
        title: 'Unresolved mention',
        description:
            'A [[Name]] that matched nothing — offers a one-click "Create" '
            'to make the profile on the spot.',
      ),
      HelpEntry(
        icon: Icons.tab,
        title: 'Project / Series tabs',
        description:
            'Shown only when the project belongs to a series: "Project" is '
            'this book\'s own pins and mentions; "Series" is the series-wide '
            'ones, shared across every book in it.',
      ),
    ],
  ),
  HelpTopic(
    id: 'projectToolbar',
    title: 'Project Toolbar',
    icon: Icons.more_horiz,
    intro:
        'The icon row along the top of an open project — one launch point '
        'each for the project\'s other tools.',
    entries: [
      HelpEntry(
        icon: Icons.lightbulb_outline,
        title: 'New Idea',
        description: 'Quick-capture an idea against this project.',
      ),
      HelpEntry(
        icon: Icons.flag_outlined,
        title: 'Goals',
        description: 'Set and track a writing goal (word count/time) for this project.',
      ),
      HelpEntry(
        icon: Icons.grid_on_outlined,
        title: 'Plot Grid',
        description:
            'A spreadsheet-style grid of plotlines vs. scenes — track which '
            'threads run through which scenes at a glance.',
      ),
      HelpEntry(
        icon: Icons.timeline,
        title: 'Timeline',
        description:
            'A visual, draggable timeline of events across one or more '
            'tracks — for keeping story chronology straight.',
      ),
      HelpEntry(
        icon: Icons.hub_outlined,
        title: 'Relationships',
        description:
            'A diagram of how your characters connect — family, romantic, '
            'rivalry, and other typed, colour-coded links.',
      ),
      HelpEntry(
        icon: Icons.rate_review_outlined,
        title: 'Export / Import for Review',
        description:
            'Send scenes out for external/AI review and bring the feedback '
            'back in — a separate workflow from day-to-day writing.',
      ),
      HelpEntry(
        icon: Icons.ios_share,
        title: 'Export',
        description:
            'Export the manuscript as PDF, DOCX, EPUB, TXT, or KDP-ready '
            'paperback/hardcover.',
      ),
      HelpEntry(
        icon: Icons.text_fields,
        title: 'Editor settings',
        description: 'Quick access to the typeface/size used while writing (Settings > Editor).',
      ),
      HelpEntry(
        icon: Icons.menu_open,
        title: 'Show/Hide Reference Panel',
        description: 'Toggles the right-hand Reference Panel.',
      ),
      HelpEntry(
        icon: Icons.center_focus_strong,
        title: 'Focus Mode',
        description:
            'Hides everything but the page you\'re writing on — press Esc '
            'to exit.',
      ),
    ],
  ),
  HelpTopic(
    id: 'goals',
    title: 'Goals',
    icon: Icons.flag_outlined,
    intro:
        'Track a writing goal for this project — a word-count target or a '
        'deadline — with a daily target and progress shown as you write.',
    entries: [
      HelpEntry(
        icon: Icons.add,
        title: 'New Goal',
        description:
            'Walks you through setting a word-count or deadline goal for '
            'this project.',
      ),
    ],
  ),
  HelpTopic(
    id: 'plotGrid',
    title: 'Plot Grid',
    icon: Icons.grid_on_outlined,
    intro:
        'A spreadsheet-style grid: plotlines down the side, scenes across '
        'the top — track which threads run through which scenes at a '
        'glance, colour-coded per plotline.',
    entries: [
      HelpEntry(
        icon: Icons.add,
        title: 'New Plotline',
        description: 'Adds a new row/thread to the grid.',
      ),
      HelpEntry(
        icon: Icons.delete_outline,
        title: 'Delete Plotline',
        description: 'Removes a plotline and its plot points from the grid.',
      ),
    ],
  ),
  HelpTopic(
    id: 'timeline',
    title: 'Timeline',
    icon: Icons.timeline,
    intro:
        'A visual, draggable timeline of events, organised into tracks — '
        'for keeping story chronology straight, especially across multiple '
        'POVs or a non-linear structure.',
    entries: [
      HelpEntry(
        icon: Icons.add,
        title: 'New Track',
        description:
            'Adds a new row for events — one per POV, location, or '
            'whatever grouping makes sense for this story.',
      ),
      HelpEntry(
        icon: Icons.add_circle_outline,
        title: 'New Event',
        description:
            'Adds an event to a track; drag it along the timeline to '
            'reposition. An event can link to scenes, characters, and world '
            'entries.',
      ),
      HelpEntry(
        icon: Icons.visibility_outlined,
        title: 'Show/Hide track',
        description: 'Temporarily hides a track\'s events without deleting them.',
      ),
      HelpEntry(
        icon: Icons.delete_outline,
        title: 'Delete Track',
        description: 'Removes a track and every event on it.',
      ),
    ],
  ),
  HelpTopic(
    id: 'relationshipDiagram',
    title: 'Relationships',
    icon: Icons.hub_outlined,
    intro:
        'A diagram of how your characters connect — drag nodes to arrange '
        'them, and draw typed, colour-coded links (family, romantic, '
        'rivalry, and more) between them.',
    entries: [
      HelpEntry(
        icon: Icons.person_add_alt_1,
        title: 'New Character',
        description:
            'Creates a character profile without leaving the diagram — '
            'appears in the project\'s own Characters tab too.',
      ),
      HelpEntry(
        icon: Icons.add_link,
        title: 'New Relationship',
        description:
            'Draws a typed link between two characters (family, romantic, '
            'rivalry, …), with an optional label.',
      ),
    ],
  ),
  HelpTopic(
    id: 'export',
    title: 'Export',
    icon: Icons.ios_share,
    intro:
        'Export the finished manuscript as PDF, DOCX, EPUB, TXT, or a '
        'KDP-ready paperback/hardcover file, with format-specific options '
        '(e.g. bleed for print).',
  ),
  HelpTopic(
    id: 'reviewExport',
    title: 'Export / Import for Review',
    icon: Icons.rate_review_outlined,
    intro:
        'Send scenes out to an external or AI reviewer and bring their '
        'feedback back in — a separate workflow from Export, meant for '
        'round-tripping comments rather than producing a finished file.',
    entries: [
      HelpEntry(
        icon: Icons.download_outlined,
        title: 'Import Review Comments',
        description:
            'Brings a reviewer\'s returned comments back into the project '
            'against the scenes they refer to.',
      ),
    ],
  ),
  HelpTopic(
    id: 'statusBar',
    title: 'Status Bar',
    icon: Icons.info_outline,
    intro:
        'The thin bar pinned to the bottom of every screen — app identity '
        'on the left; on the right, a live snapshot of the things that '
        'affect your work: nearest-to-farthest, Thesaurus/Spell check, the '
        'Vault, then Google Drive. Tap any icon for a one-line status.',
    entries: [
      HelpEntry(
        icon: Icons.spellcheck,
        title: 'Thesaurus / Spell check',
        description:
            'Shows whether each is currently switched on (Settings > Spell '
            'Check & Language).',
      ),
      HelpEntry(
        icon: Icons.shield_outlined,
        title: 'Vault',
        description:
            'Colour shows whether backups are actively protecting your '
            'work right now, and whether they\'re password-encrypted or '
            'running as plain, unencrypted backups.',
      ),
      HelpEntry(
        icon: Icons.cloud_sync_outlined,
        title: 'Google Drive',
        description:
            'Shows connection status, and flickers green while a sync is '
            'actively happening.',
      ),
    ],
  ),
  HelpTopic(
    id: 'settingsOverview',
    title: 'Settings — What Each Category Covers',
    icon: Icons.settings_outlined,
    intro: 'A one-line pointer for each category in this Settings screen\'s side nav.',
    entries: [
      HelpEntry(
        icon: Icons.palette_outlined,
        title: 'Appearance',
        description: 'Light/Dark/System theme, plus the Library background.',
      ),
      HelpEntry(
        icon: Icons.edit_note,
        title: 'Editor',
        description: 'Typography used while writing (separate from export fonts).',
      ),
      HelpEntry(
        icon: Icons.mic_outlined,
        title: 'Dictation',
        description: 'Language, accuracy, and downloaded offline voice models.',
      ),
      HelpEntry(
        icon: Icons.volume_up_outlined,
        title: 'Read Aloud',
        description: 'Voice, speed, and pitch for reading a scene back to you.',
      ),
      HelpEntry(
        icon: Icons.shield_outlined,
        title: 'Backup & Vault',
        description:
            'Encrypted (or, if you opt in, plain) automatic backups and '
            'tamper-evident version history.',
      ),
      HelpEntry(
        icon: Icons.spellcheck,
        title: 'Spell Check & Language',
        description: 'Toggle spell check/thesaurus, and manage your custom dictionary.',
      ),
      HelpEntry(
        icon: Icons.cloud_sync_outlined,
        title: 'Google Drive Sync',
        description:
            'Connect Drive, choose what syncs, and trigger "Sync All Now" '
            'on demand.',
      ),
      HelpEntry(
        icon: Icons.feedback_outlined,
        title: 'Feedback',
        description: 'Report a bug or suggest a feature via GitHub Discussions.',
      ),
      HelpEntry(
        icon: Icons.info_outline,
        title: 'About',
        description: 'App version and build information.',
      ),
    ],
  ),
];

/// Looks up one topic by id — used by [openHelpTopic] and by anything that
/// wants to deep-link into a specific segment rather than the whole list.
HelpTopic? findHelpTopic(String id) {
  for (final topic in helpTopics) {
    if (topic.id == id) return topic;
  }
  return null;
}
