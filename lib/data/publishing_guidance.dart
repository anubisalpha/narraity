/// Static, curated content transcribed from `Publishing Guidance for
/// Writers' Software.md` — the brainstorm this whole Publishing Hub feature
/// is built from. Same "static curated content shown in a screen" pattern
/// as `lib/models/help_topic.dart`'s in-app help data.
library;

enum PublishingRoute { traditional, selfPublishing, webSerial, hybrid }

class PublishingRouteInfo {
  const PublishingRouteInfo({
    required this.label,
    required this.pitch,
    required this.metrics,
  });

  final String label;
  final String pitch;
  final String metrics;
}

const publishingRouteInfo = {
  PublishingRoute.traditional: PublishingRouteInfo(
    label: 'Traditional Publishing',
    pitch:
        'Higher prestige, zero upfront cost, but requires patience and agent querying.',
    metrics: 'Low upfront cost · 1–3 years · Royalties ~8–15%',
  ),
  PublishingRoute.selfPublishing: PublishingRouteInfo(
    label: 'Self-Publishing (Indie)',
    pitch:
        'Full creative control, high royalties, but you act as the publisher and project manager.',
    metrics: 'High upfront cost · Weeks/months · Royalties ~60–70%',
  ),
  PublishingRoute.webSerial: PublishingRouteInfo(
    label: 'Web Serials & Digital Subscriptions',
    pitch:
        'Iterative release, direct reader connection — ideal for Fantasy, Sci-Fi, LitRPG, Romance.',
    metrics: 'Low upfront cost · Ongoing release · Reader-funded',
  ),
  PublishingRoute.hybrid: PublishingRouteInfo(
    label: 'Hybrid Publishing',
    pitch:
        'A middle ground — you pay for publishing services upfront but get institutional distribution. Proceed with caution.',
    metrics: 'Vet carefully: IBPA-compliant vs. predatory vanity press',
  ),
};

/// A checklist item within a stage. [appliesToRoutes] empty means "shown for
/// every route" (Stage 1 items); non-empty restricts it to those routes
/// (Stage 2A/B/C). [whySearchQuery]/[aiPromptTemplate] may contain
/// `{genre}`/`{title}`/`{author}`/`{wordCount}` placeholders, filled in by
/// the Publishing Hub screen from the project + user-entered genre.
class ChecklistStageItem {
  const ChecklistStageItem({
    required this.id,
    required this.stage,
    this.appliesToRoutes = const [],
    required this.title,
    this.whySearchQuery,
    this.aiPromptTemplate,
  });

  final String id;
  final String stage;
  final List<PublishingRoute> appliesToRoutes;
  final String title;
  final String? whySearchQuery;
  final String? aiPromptTemplate;
}

const publishingChecklistItems = [
  // Stage 1: Manuscript Finalization (all routes)
  ChecklistStageItem(
    id: 'beta-reader-pass',
    stage: 'Stage 1: Manuscript Finalization',
    title: 'Beta Reader & Critique Pass',
    whySearchQuery: '{genre} beta readers forum Reddit',
    aiPromptTemplate:
        "I am finishing a {genre} novel titled '{title}' about [1-sentence premise]. "
        "Act as a developmental editor and write a 5-question survey I can send to my "
        "beta readers to test if my pacing, character motivations, and plot twist work well.",
  ),
  ChecklistStageItem(
    id: 'manuscript-polish',
    stage: 'Stage 1: Manuscript Finalization',
    title: 'Manuscript Polish & Word Count Audit',
    whySearchQuery: 'standard word count for {genre} novel',
    aiPromptTemplate:
        "Here is Chapter 1 of my {genre} novel (currently {wordCount} words total): "
        "[Insert Text]. Flag any instances of passive voice, repetitive crutch words, "
        "or 'telling instead of showing' that I should fix before publishing.",
  ),

  // Stage 2A: Traditional Publishing
  ChecklistStageItem(
    id: 'query-package',
    stage: 'Stage 2: Traditional Publishing',
    appliesToRoutes: [PublishingRoute.traditional],
    title: 'Crafting the Query Package',
    whySearchQuery: 'query letter examples that signed agents {genre}',
    aiPromptTemplate:
        "Here is a detailed summary of my {genre} novel '{title}': [Insert Summary]. "
        "Write a compelling 250-word query letter blurb using the hook-conflict-stakes "
        "structure to pitch to literary agents.",
  ),
  ChecklistStageItem(
    id: 'agent-list',
    stage: 'Stage 2: Traditional Publishing',
    appliesToRoutes: [PublishingRoute.traditional],
    title: 'Building the Agent List (20–30 agents)',
    whySearchQuery: 'site:querytracker.net literary agents accepting {genre}',
    aiPromptTemplate:
        "What are the top current tropes, themes, and sub-genres in {genre} that "
        "literary agents are actively looking for right now?",
  ),

  // Stage 2B: Self-Publishing
  ChecklistStageItem(
    id: 'editing-cover',
    stage: 'Stage 2: Self-Publishing',
    appliesToRoutes: [PublishingRoute.selfPublishing, PublishingRoute.hybrid],
    title: 'Professional Editing & Cover Design',
    whySearchQuery: 'book cover designers specializing in {genre}',
    aiPromptTemplate:
        "Act as an art director. Based on my book premise for '{title}': [Insert Premise], "
        "outline a detailed cover design brief for a designer, including typography style, "
        "focal point, color palette, and visual tone common in top-selling {genre} books.",
  ),
  ChecklistStageItem(
    id: 'metadata-blurb',
    stage: 'Stage 2: Self-Publishing',
    appliesToRoutes: [PublishingRoute.selfPublishing, PublishingRoute.hybrid],
    title: 'Metadata, Blurb & Keywords',
    whySearchQuery: 'how to find low competition Amazon KDP keywords for {genre}',
    aiPromptTemplate:
        "Write an irresistible, high-converting Amazon sales blurb for a {genre} book "
        "titled '{title}': [Insert Main Plot & Characters]. Include short punchy sentences, "
        "a bold hook, and bullet points highlighting key tropes.",
  ),

  // Stage 2C: Web Serial / Episodic
  ChecklistStageItem(
    id: 'chapter-buffer',
    stage: 'Stage 2: Web Serial / Episodic',
    appliesToRoutes: [PublishingRoute.webSerial],
    title: 'Chapter Structuring & Buffer Setup (10–20 chapters ahead)',
    whySearchQuery: 'best release schedule Royal Road {genre}',
    aiPromptTemplate:
        "Here is the summary of a chapter from my {genre} serial '{title}': [Insert Summary]. "
        "Suggest 3 different cliffhanger ending variations for this chapter that would "
        "entice web serial readers to click 'Next Chapter' immediately.",
  ),
];

const publishingGuardrails = [
  'The #1 Rule: money always flows TO the author in traditional publishing.',
  'Vanity press red flags: aggressive sales pitches, guaranteed publication for a fee, or taking your copyright.',
  'Know your rights: understand copyright, subsidiary rights, and non-exclusive vs. exclusive contracts before signing anything.',
  'Legit hybrid publishers are IBPA-compliant with a real, selective vetting process — not "pay us and we\'ll publish anyone".',
];
