# progress_tool

A short Ruby script I use for tracking my writing and revising progress.

To set up:

1. git clone this repo
1. create a new directory for your writing project
1. in that directory, start your your story or novel in file named `story.txt`
1. in that directory, run `rake init` ; this creates a file `.rakefile.yaml`.  
1. start each chapter with a string like "* chapter 1: intro"
1. customize the `rakefile.yaml` as you see fit.  You can change target words, start date, chapter headings, etc.  

Configuration meanings:

- :target_file: what file holds the story?
- :title: what story title should be reported in the statistics?
- :target_words: how long you expect the story to be
- :date_start: the date you started working on the project
- :chapter_head_tag: a string that marks the begining of each chapter
- :scene_markers: `dinkus` (the default) renders `*** label: ...` as `* * *`; set `heading` to retain it as a heading
- :size_cuttoff_chapter: a number of words under which the script can conclude the chapter is incomplete
- :size_cutoff_force_done: an optional string that tells the script that an overly short (see line above) chapter is actually complete
- :size_cutoff_force_incomplete: an optional string that tells the script that an overly long chapter should still be treated as incomplete

### Generate upload files

Run `rake generate` in an edition directory. It uses `:edition_format` from
`.rakefile.yaml`: ebooks produce DOCX; print editions produce PDF.
Override the retained formats when needed:

```yaml
:edition_format: ebook
:generated_files: [docx] # or [pdf], or [docx, pdf]; leading dots also accepted
```

Successful DOCX/PDF builds remove their intermediate HTML. A PDF-only
`rake generate` also removes the intermediate DOCX after the PDF succeeds.
If conversion fails, the intermediate for the failed step remains for diagnosis.
Only this title/edition/draft's build files are cleaned; historical outputs remain.

Explicit `rake docx` and `rake pdf` still request those formats (`rake pdf`
retains its DOCX). `rake interleave_html` explicitly creates a retained HTML file.
Plain `rake` continues to show writing-progress statistics.

### Generated filenames

Generated TXT, HTML, DOCX, and PDF files include the edition before the draft number:

- `:edition_format: ebook` → `Glomar_Extractor_ebook_draft_2.docx`
- `:edition_format: print` (the default) → `Glomar_Extractor_tpb_draft_2.docx`

The name follows the configuration, not the directory name. Existing files with
older names are not automatically deleted when you regenerate.

### Chapter epigraphs

Put a blockquote immediately after a chapter heading to make it a DOCX epigraph.
It is styled separately from the heading and does not appear in the table of contents.

```
** chapter 1: The Great Project

> So great a task it was to found a people.
> —Virgil, _Aeneid_ 1.33
```

The `chapter_epigraph` and `chapter_epigraph_attribution` entries in
`.docx_styles.yaml` control its appearance. Only an opening blockquote is treated
as an epigraph; later blockquotes are left as-is.

### Scene markers

Use `*** label: ...` for an author-facing scene marker. By default, every
interleaved output replaces it with a centered `* * *` dinkus; a raw `***` or
`* * *` line also becomes that dinkus. To retain the
text as an organization-level heading instead, set this in `.rakefile.yaml`:

```
:scene_markers: heading
```

### Sub-chapters

Within a chapter in `story.txt`, use `## Section title` on its own line for a
level-3 heading. It appears indented beneath that chapter in the DOCX table of
contents; `***` remains a dinkus.

### Preventing word hyphenation

To keep proper nouns intact in DOCX output, list exact words in
`.rakefile.yaml`:

```
:never_hyphenate:
  - Aristillus
  - Bollstadt
```

`:never_hyphenate` applies only to print. Ebook output leaves words intact because
Kindle conversion can render inserted word joiners as visible letter spacing.


The word can still move as a whole to the next line, but automatic hyphenation
will not split it. Source text remains unchanged.

### Standard front matter

Use the named file slots for standard book matter. In DOCX they are placed as
dedication, epigraph, timeline, Dramatis personae, Kickstarter backers, and table of contents, with
each present item on a recto and a blank verso after it. A missing or empty
dedication is omitted without leaving its blank verso.

```
:dedication: ./matter_front_dedication.md
:epigraph: ./matter_front_quote.md
:timeline: ./matter_front_timeline.md
:dramatis_personae: ./matter_front_dramatis_personae.md
:kickstarter_backers: ./matter_front_kickstarter_backers.md
:toc: true
:other_books: ./matter_front_other_books.md
:frontmatter_layout: full # full (default) or condensed
:matter_qr_codes:
  - ./matter_after_stay_connected.md
```

The named Timeline and Dramatis files receive their corresponding DOCX styles.
Dramatis Personae uses a centered, bold 15-point title and left-aligned, bold
11-point subsection headings, with 12 points of space above each subsection.
The first heading is the title; subsequent headings are subsections, regardless
of their Markdown level. Only the title appears in the ebook contents.
Character entries use 11-point type, exact 13-point leading, 3 points of space
between entries, and a 0.15-inch hanging indent (first line flush left).
Entries stay together across page breaks and do not automatically hyphenate.
These defaults are configurable through `frontmatter_dramatis_heading`,
`frontmatter_dramatis_subheading`, and `frontmatter_dramatis` in `.docx_styles.yaml`.
Legacy frontmatter whose first heading reads “Dramatis Personae” or
“Dramatis Personæ” receives the same heading and entry styles, preserving inline
emphasis and wording.
`other_books` is set on the half-title verso, the conventional “also by this
author” location. For ebooks, set `:title_page: {show_half_title: false}` to
omit the half-title and move Other Books to the back, after Stay Connected and
before About the Author. The full title and copyright pages remain. By default the half-title
is included. `full` gives every present front-matter item a recto and a
blank verso. `condensed` keeps the title/copyright spread, then places the
remaining items on consecutive pages; the book proper still begins recto.
`matter_qr_codes` is an optional allowlist: each listed matter file receives a
centered QR code immediately below every standalone `http` or `https` URL.
The URL remains printed, and no other files (including the copyright page) are
affected. It requires the local `qrencode` command.
For additional or legacy front matter, use `:frontmatter`; its entries follow
the epigraph and precede the table of contents. A legacy styled entry such as
`file: matter.md, style: dramatis` remains supported.

Keep book titles and Kindle URLs together in the shared bibliography using
ordinary Markdown links, e.g. `[The Team](https://www.amazon.com/dp/B081PBXBMB)`.
Set `:edition_format: ebook` to preserve these hyperlinks, or
`:edition_format: print` (the default) to render the titles without hyperlink
styling or destinations. This setting is independent of TOC and half-title
layout. Only bibliography links are suppressed; links elsewhere and the
separately configured author-store link or QR code are unaffected.

To add a destination below the Other Books list, configure it separately from
the shared bibliography file. Use `link` for a clickable ebook caption or `qr`
for a centered 0.75-inch QR code with a caption in print:

```yaml
:other_books_link:
  url: https://www.amazon.com/stores/Travis-J-I-Corcoran/author/B06XF15CC8
  format: link # link or qr
  label: Find all my books on Amazon
```

The URL must be absolute HTTP(S). Omitting the setting or leaving `url` blank
adds nothing. The default format is `link`, and the default caption is
“Find more books.” QR output uses the existing `qrencode` dependency. This
works with Other Books at the front or back of the document and does not
require listing the bibliography in `:matter_qr_codes`.

### Standard endmatter

Use these named fields for material after the manuscript. `aftermatter_other`
is a YAML list, in reading order; About the Author is automatically headed and
uses its dedicated DOCX style. Supplementary `aftermatter_other` headings use
the compact back matter heading style, rather than the oversized manuscript
part-title style; body paragraphs and lists retain their formatting.

```
:aftermatter_about_the_author: ./matter_after_about_the_author.md
:aftermatter_stay_connected: ./matter_after_stay_connected.md
:aftermatter_other: []
```

Stay Connected precedes the closing bibliography. About the Author is always
last, after the calls to action and bibliography, in DOCX, HTML, and text exports.
Both named sections use dedicated DOCX page styling. The older `:about_author` and `:aftermatter` fields remain supported
for existing projects.

### Shared universe catalog

Use one ordered catalog across related ebooks:

```yaml
:book_id: staking_a_claim
:more_in_this_universe: ../../../aftermatter_aristillus_books.yaml
```

The catalog contains `heading`, optional `intro`, and a `books` list. Each
book has a unique `id`, a `title`, optional `description`, and `amazon_url`.
The current `book_id` must exist in the catalog; that entry is automatically
omitted from the invitation. Other entries retain catalog order. Blank URLs
render plain titles, allowing forthcoming books to remain in the list with an
appropriate description. Nonblank URLs must point to Amazon.com.

The invitation appears immediately after the story and before other endmatter,
with edition-appropriate links or QR codes, and it is included in ebook navigation.
Text exports include the same catalog content and URLs. Updating the catalog
affects every referencing edition on its next rebuild; Amazon uploads still
need to be replaced explicitly. The full Other Books bibliography is separate.

### Closing calls to action

Use the same actions file in any book, including standalones without a universe
catalog. Each edition supplies its own Amazon product ASIN:

```yaml
:edition_format: ebook # ebook = links; print = labeled QR codes + readable URLs
:reader_actions: ../../../aftermatter_reader_actions.yaml
:reader_actions_lead: books # or patreon, for a standalone or latest installment
:reader_review_asin: B081MW4W4Z
```

The shared file contains:

```yaml
patreon_url: https://www.patreon.com/cw/morlockp
catalog_url: https://www.amazon.com/stores/author/B06XF15CC8
```

An inline mapping is also accepted. Omit either destination to omit that action.
With `books`, related books (from `:more_in_this_universe`) precede a Stay connected
page containing free Patreon chapters and a neutral star-rating request with
optional written feedback. `patreon` moves the entire Stay connected group before
related books. A missing universe catalog is simply skipped. No request asks for
five stars.

`catalog_url` links the top-level heading of the configured `:other_books`
bibliography in ebooks. In print, the caption, QR code, and readable URL stay together in a block anchored
to the bottom margin of the bibliography page, with clearance above the block. It replaces `:other_books_link` when both are configured;
there is no separate wider-catalog CTA page. Keep the bibliography heading in the
shared Markdown file (for example, `# Books by Travis Corcoran`).

`:reader_review_asin` generates
`https://www.amazon.com/review/create-review/?asin=ASIN`. Use the verified ASIN
for the edition (a paperback ISBN-10 may be its ASIN). The explicit
`:reader_review_url` remains supported as an alternative; do not set both.
Omit both to omit the rating request. Each book's title labels its rating link.

The sections follow the story, followed by the full bibliography and finally
About the Author. This order applies to every project using the tool.
Related books get their own page group; Patreon and rating requests share
Stay connected. Print QR codes, labels, descriptions, and fallback URLs stay
together. Blank catalog URLs remain unlinked, without a QR code. Plain-text
exports include all action URLs in the same order.

Remove redundant hand-written Patreon/review asks from configured Stay Connected
files when adopting the generated actions. All referencing books must be rebuilt
when the shared destinations change. Verify links and QR destinations, and check
Kindle navigation after Amazon conversion, before publishing.

### Ebook contents

Use `:toc: ebook` for a populated, clickable Word table of contents without
page numbers. The tool adds a `toc` bookmark and destination bookmarks, and
marks the story/chapter headings and major closing sections for navigation. Parts appear at the top level, with
chapters indented beneath them; chapters without parts remain at the top level.
Heading appearance is independent of TOC inclusion: the matching Patreon and
rating subheadings use `ReaderActionHeading` and are omitted from the TOC, which
links to their shared Stay connected heading instead. Bibliography category
headings are omitted, and its top-level entry uses the actual heading text.
Ebook mode preserves its populated TOC without running the print-only
LibreOffice field refresh. By default, a chapterless story gets its title above
the opening paragraph and one story entry; scene breaks are not listed. The contents page follows the same
`:frontmatter` placement rules as the print TOC. `:toc: true` retains the print
TOC, and `:toc: false` omits it.

Check the final Kindle navigation and links in KDP Previewer after conversion;
the DOCX is the source document, not a Kindle-converted file.

### Publication and revision history

Copyright pages can include an explicit publication history, independent of
`:draft` (which remains the output filename version):

```yaml
:copyright_page:
  year: 2019
  revision_history:
    - date: '2019-11'
      description: First published.
    - date: '2026-09'
      description: Typo fixes and updated bibliography.
```

Entries appear chronologically after credits, ISBNs, and printing details,
immediately before the publisher block, under “Revision history:” with one
indented paragraph per entry. Dates use three-letter months, followed by a colon
and a tab to a fixed description column one inch after the date's start.
Wrapped descriptions align beneath the description, not beneath the date.
Use sentence case and a final period for descriptions (for example,
“Typo fixes and updated bibliography.”); the tool preserves supplied wording.
Keep descriptions short enough for the chosen page width.
The publisher name and URLs form a horizontally centered block near 80% down the
DOCX copyright page, leaving whitespace beneath it; they remain document content rather than a recurring footer. Dates accept `YYYY-MM` or `YYYY-MM-DD` and
render as “Nov 2019” or “Sep 27, 2026.” Each entry needs a nonblank
`description`; invalid dates or malformed entries stop the build with an error.
Omit `revision_history` or use `[]` to leave it out. Add entries deliberately
when publishing an update; builds do not invent or append history. If the old
`note` already states the original publication date, move that information into
the history to avoid repeating it.

## Multi-file Interleaving with Pragmas

When using multiple input files (plot threads), you can enforce ordering constraints using pragmas:

### Defining and Requiring Tags

In any chapter, add pragmas as comments:

```
** chapter 5: The Setup
# DEFINE-TAG: lopez-turning-point

Content of the chapter...
```

In another file's chapter, require that tag:

```
** chapter 8: The Convergence
# MUST-BE-AFTER: lopez-turning-point

Content of the chapter...
```

You can also specify that a chapter must come before another:

```
** chapter 3: Early Conflict
# MUST-BE-BEFORE: lopez-turning-point

Content of the chapter...
```

N.B. the pound signs are mandatory

### Multiple Dependencies

A single chapter can depend on multiple tags:

```
** chapter 12: The Finale
# MUST-BE-AFTER: lopez-turning-point, mackenzie-revelation

Content...
```

### Validation

The interleave tasks will:
- ✅ Enforce ordering: chapters with dependencies appear after their required tags
- ✅ Detect undefined tags: error if a tag is required but never defined
- ✅ Detect circular dependencies: error if tags form a cycle
- ⚠️ Warn on unused tags: tags defined but never required

If constraints are impossible to satisfy or invalid, the task will abort with a clear error message.

## To use on your first (writing) pass

1. to see a compact view progress stats, run from the command line `rake`
1. to get an overview of your chapter sizes run `rake chapters`

N.B. that if you change text

> Tom said wryly

to

> Tom said innocently

that this should be appear in the statistics as

 today's word delta: +0   (+1 -1)

Note two minor features:

1. you can sprinkle "XXX", "YYY", and "ZZZ" throughout your story file ; these tag open issues of various types (the tool does not define what these issue types are; you can use "XXX"  for "add more details here", "YYY" for "problem w the timeline, etc.).  If one or more of these is present, `rake` stats will refer to these.
1. you can create a file `unused_text.txt` and move chunks of stuff from your story file to here.  This way you "get credit" for writing stuff, even if you end up not using it in your draft.

Use this process until you finish writing the first draft of your story.

After that you will likely want to edit your story, so ...

## To use on a revision pass

1. Begin revising at the top of oyur story. 
1. Put the string "<---" in your story file to mark how far you've progressed in revising.
1. Having done this, invocations of `rake` and `rake chapters` will generate expanded output

## To contribute

After making changes, please run `rake self_test`.

Thanks!

### Stories without chapters

Set `:chapterless: true` to render each source file as continuous story text,
without requiring or printing a chapter heading. The separate `:opening_title`
setting controls whether the book title is repeated above the opening paragraph,
using the chapter-heading style in both print and ebook DOCX and HTML:

```yaml
:chapterless: true
:opening_title: auto # default: add the title when all story sections are chapterless
```

Use `true` to force an opening title or `false` to suppress it. Automatic mode
uses the parsed story structure (including `:chapterless`), not the number of
TOC entries or Markdown headings in front/back matter. It adds the title once,
even when a chapterless story spans multiple source files. Chaptered books keep
their chapter headings without a repeated book title by default. This setting
does not change manuscript parsing or the separate title/half-title pages.
A suppressed opening title also omits that title's ebook TOC entry.

Set `:toc: false` to omit the
DOCX table of contents. For an ebook-source DOCX, `.docx_styles.yaml` can disable
print pagination with `page_numbers: {enabled: false}` and
`page: {body_start_on_recto: false, mirror_margins: false, even_odd_headers: false, auto_hyphenation: false}`.

DOCX typography defaults to **EB Garamond**, using the installed font family by
that exact name. A project can override `font` in `.docx_styles.yaml`. Existing
explicit font choices are retained; cached default references refresh when the
configured font differs. Install the regular, italic, bold, and bold italic faces
on each machine used to render print interiors.

Fiction body text defaults to 12-point EB Garamond Regular, black, with
indented paragraphs and no extra paragraph gap. Existing print edition configs
use 15-point leading for Normal, FirstParagraph, and Compact. Ebook-source
configs use single/automatic spacing; Kindle readers retain control of their
font, size, and spacing. DOCX font naming alone does not embed an ebook font.
Escape the City's legacy nonfiction layout is excluded from this rollout.
Manuscript-specific double spacing remains where explicitly configured.

`line_spacing_points: 15` means exactly 15 points in DOCX. Otherwise
`line_spacing` accepts `single`, `double`, or a positive numeric multiple such
as `1.25`. Cached `.default.docx` styles refresh when effective typography
changes, including inherited defaults. Rebuild and proof print interiors and
recheck cover spine widths after a typography change.

### Paperback margins

For 6×9 print editions, `rake generate`, `rake pdf`, and `rake docx` automatically
use mirrored margins based on the rendered page count:

| Pages | Inside | Outside |
| --- | --- | --- |
| 1–199 | 0.70″ | 0.65″ |
| 200–399 | 0.80″ | 0.65″ |
| 400–499 | 0.90″ | 0.65″ |
| 500+ | 0.95″ | 0.65″ |

The build starts with the smallest allowance and increases it if the rendered
page count needs a larger one, re-rendering until no increase is needed. This
also measures print DOCX builds using a temporary PDF; LibreOffice and `pdfinfo`
are required. Final PDFs replace the previous output only after success.
Top/bottom margins remain unchanged. Automatic margins supersede the legacy
left/right values in `.docx_styles.yaml`; the file itself is not rewritten.
Ebooks and other trim sizes retain their existing margins.

In `.rakefile.yaml`, use one of:

```yaml
:print_margins: auto # default for 6×9 paperbacks
# :print_margins: {inside: 0.95, outside: 0.65} # fixed override, inches
# :print_margins: false # retain the margins in .docx_styles.yaml
:print_binding: paperback # default; hardcover also enforces its page limits
```

A fixed override can also be used for other print trim sizes or bindings.
Review final pagination and cover spine dimensions after changing margins.

### Hardcover generation

Set `:edition_format: print`, `:print_binding: hardcover`, and
`:generated_files: [pdf]` in the hardcover edition directory. Output filenames
use `_hc_`. Reuse the manuscript and shared matter paths, and supply the
hardcover ISBN under `copyright_page: isbn: hardcover`; do not copy the
paperback ISBN into that field. The cover must be sized separately for the
final hardcover page count and paper.

Hardcover builds first try the configured paperback typography. At 6×9 they
inherit the same page-count-based mirrored margins; explicit `print_margins`
overrides still apply. If the baseline fits 75–550 printed pages, it is kept.
Otherwise the following presets are tried in order, stopping at the first fit:

| Preset | Body / leading (pt) | Top / bottom (in) |
| --- | --- | --- |
| tighter_spacing | 12 / 14.5 | 0.70 / 0.80 |
| compact_spacing | 12 / 14 | 0.70 / 0.80 |
| smaller_type | 11.5 / 14 | 0.70 / 0.80 |
| minimum_type | 11 / 13.5 | 0.70 / 0.80 |

Font family, inside/outside margins, headings, and dedicated front/back-matter
styles are retained. Only Normal, FirstParagraph and Compact body styles change.
The footer moves with the bottom margin, keeping 0.20″ clearance. Automatic
inside margins never decrease during fitting. Candidates and the selected
layout are reported in the build log. A fitting result may leave a few pages
of headroom; no arbitrary shrinking to hit an exact page count is performed.

Optional `.rakefile.yaml` overrides:

```yaml
:hardcover_layout:
  min_pages: 75
  max_pages: 550
  presets:
  - name: compact
    body_size: 11.5
    leading: 14
    top_margin: 0.70
    bottom_margin: 0.80
```

Omitted fields use the defaults; a supplied preset list replaces the default
list. `presets: []` checks the baseline without compression. Body sizes must
be at least 11pt in half-point steps; leading must be at least 13.5pt and at
least 1.5pt greater than body size. These are conservative defaults for our
fiction, with final visual review still required. Page counts are measured
from rendered PDFs and rounded up to an even printed count. Too-short books
and books exceeding the limit after all presets fail with a clear error;
no padding is added, and the previous final PDF is preserved. This check also
runs for `rake docx`. Ebooks and paperback output selection are unaffected.
