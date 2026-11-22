---
name: jaspr-anatomy
description: Find out which Jaspr components make up a rendered page and where components could be reused more, using the jaspr_anatomy command-line tools. Use when asked what a page is built from, to review component reuse, to find duplicated markup or unused components, or before extracting or merging components in a Jaspr app.
---

# Jaspr anatomy

`jaspr_anatomy` describes rendered Jaspr pages as component trees and reports
where reuse is missing. Two commands, run from the app's package directory.
Neither needs a browser.

Requirements: the app depends on `jaspr_anatomy` and wraps its page body in
`Anatomy(child: ...)`. If it does not, say so and stop; do not add it unasked.

## Start with source: scan

```sh
dart run jaspr_anatomy:scan            # Markdown
dart run jaspr_anatomy:scan --json     # every component with every construction site
```

Reads the app and the local packages it depends on. The app does not have to
run. Reports:

- **Never constructed**: nothing in the scanned packages constructs the class.
  Check for uses in other apps of the same repository, in tests, and in
  generated code before calling it dead.
- **Constructed in one place**: often page-level components, which is fine.
  A small leaf component used once may not need to exist.
- **Most used**, and per shared package how many of its components the app uses.

The result is saved to `.dart_tool/jaspr_anatomy/scan.json`.

## Then look at rendered pages: inspect

The app must be running in debug mode. Find the URL in the project's run
instructions; do not guess ports.

```sh
dart run jaspr_anatomy:inspect http://localhost:8080/
dart run jaspr_anatomy:inspect http://localhost:8080/ --crawl 20     # follow links
dart run jaspr_anatomy:inspect <url> <url> --no-tree                 # findings only
dart run jaspr_anatomy:inspect <url> --json                          # for further processing
dart run jaspr_anatomy:inspect <url> --json --snapshot               # plus the full tree
```

- Pages behind a login: `--cookie 'name=value'`. Servers that check the host
  name: `-H 'Host: <name>'`.
- `--scope project` (default) reports components written in the repository,
  including local path packages. `--scope packages` adds hosted packages.
- `--elements` shows the HTML elements between components in the tree.
- "No anatomy data in the response" means the page is not wrapped in `Anatomy`,
  the server is not in debug mode, or the URL is not rendered by Jaspr.

Read several pages at once. Totals and findings across pages are worth more
than one page alone, and a component with one instance on one page may have
many on others.

## Reading the report

- **Own elements** is how many elements a component writes itself, not counting
  nested components. A page-level component with a large number is where inline
  markup accumulates.
- **From reused components** is the share of elements written by components
  with more than one instance in the pages read.
- **In code** (after a scan) is how many places construct the class.

Repeated markup compares structure: root element and its direct children, by
tag and class. Deeper content may differ.

| Finding | What to do |
|---|---|
| Inline markup duplicates `X` | Replace the inline copy with `X`. Open both first: the copy may differ in ways the classes do not show. |
| `X`, `Y` render the same markup | Candidates for merging. Check their parameters and call sites. |
| Inline markup repeats N times within `X` | Usually a loop or a helper method in `X`: extract a component if it carries meaning of its own. |
| Inline markup repeats in `X`, `Y` | Copied between components: the strongest case for a shared component. |

The findings are evidence, not instructions. Markup can look alike and mean
different things. Before changing code, read the files the report names, and
confirm with the user which findings to act on.

## Limits to keep in mind

- The tree is the page as the server rendered it. Content a client component
  draws later in the browser is missing.
- Raw HTML is opaque.
- Source locations need a server run from source (`jaspr serve`, `dart run`).
- In a browser session with the overlay on, `window.__jasprAnatomy.snapshot()`
  returns the same tree with element positions, and `.report()` the Markdown
  report of the current page.
