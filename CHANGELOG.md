# Changelog

## Unreleased

Requires Elixir 1.14 or higher.

This release contains significant performance improvements, with typical HTML emails seeing a 30x+ speedup when inlining styles. Premailex is also now zero dependency thanks to the new fallback HTML parser `Premailex.HTMLParser.Xmerl`.

### Architecture changes

The layers between parser, DOM operations, and the top-level API have been reshaped:

* `Premailex.HTMLParser` is now a thin behaviour with only `parse/1` and `to_html/1` callbacks
* `Premailex.DOM` is a new module that handles all selector matching, traversal, and tree manipulation
* `Premailex.Util` has been removed with functions moved into `Premailex.DOM`
* `Premailex.HTMLInlineStyles.process/2` is now a pure tree to tree transformation that accepts an explicit list of CSS rules

### Breaking changes

* `Premailex.HTMLInlineStyles` no longer exposes `process/3`, use `Premailex.HTMLInlineStyles.process/2`
* `Premailex.HTMLToPlainText.process/1` no longer accepts HTML string
* `Premailex.HTMLParser` behaviour callback `to_string/1` renamed to `to_html/1`
* `Premailex.HTMLParser` behaviour no longer requires `all/2`, `filter/2`, or `text/1` callbacks
* `Premailex.HTMLParser` no longer exposes `parse/1`, use `Premailex.parse/2` instead
* `Premailex.HTMLParser` no longer exposes `to_string/1`, use `Premailex.to_html/2` instead
* `Premailex.HTMLParser` no longer exposes `all/2`, use `Premailex.DOM.all/2` instead
* `Premailex.HTMLParser` no longer exposes `filter/2`, use `Premailex.DOM.reject/2` instead
* `Premailex.HTMLParser` no longer exposes `text/1`, use `Premailex.DOM.text_content/1` instead
* `Premailex.Util` has been removed:
  * `Premailex.Util.traverse/3` is now `Premailex.DOM.replace_all_matches/3`
  * `Premailex.Util.traverse_until_first/3` is now `Premailex.DOM.replace_first_match/3`
  * `Premailex.Util.traverse_and_update/2` is removed, use `Premailex.DOM.traverse_with_matching_items/3` for indexed single-walk updates
* Renamed `Premailex.CSSParser.parse_rules/1` to `Premailex.CSSParser.parse_declaration_block/1`
* Renamed `Premailex.CSSParser.merge/1` to `Premailex.CSSParser.cascade/1`
* `Premailex.HTTPAdapter` behaviour's `request/5` callback no longer requires the `Premailex.HTTPAdapter.HTTPResponse` struct in favor of using a map
* `Premailex.parse/2` now always returns a list
* `Floki` minimum version bumped from `~> 0.19` to `~> 0.24`
* `Premailex.to_inline_css/2` `:optimize` option has been replaced by a single boolean option `:remove_style_tags`

### Additions

* Added `Premailex.parse/2` and `Premailex.to_html/2`
* Added support for `LazyHTML`
* Added fallback support for `:xmerl`
* Added `Premailex.CSSParser.split_selector_groups/1` for selector group splitting
* Added `Premailex.DOM.traverse_with_matching_items/3` for indexed single-walk tree updates
* Added support for structural pseudo-classes: `:first-child`, `:last-child`, `:only-child`, `:last-of-type`, `:only-of-type`, `:nth-child`, `:nth-of-type`, `:nth-last-child`, `:nth-last-of-type`, `:empty`, `:root` (`An+B`, `odd`, and `even` arguments supported)

### Other

* `Floki` is now optional
* `Premailex.CSSParser` rewritten and no longer uses regular expressions to parse CSS
* `Premailex.CSSParser.parse_declaration_block/1` now does case insensitive, terminal `!important` detection
* `Premailex.HTMLInlineStyles.process/2` tree traversal performance changed from O(N^2) to O(N)
* Fixed compiler warnings in `Premailex.HTMLParser.Meeseeks`

## v0.3.20 (2025-01-20)

* Require Elixir 1.13
* `Premailex.CSSParser.parse/1` now ignores empty selectors

## v0.3.19 (2023-11-19)

* Ignore `@charset` CSS at-rule

## v0.3.18 (2023-04-07)

* Fixed bug in `Premailex.HTMLToPlainText.parse/3` with `<thread>`, `<tbody>`, `<tfoot>` being excluded if the HTML element had any attributes

## v0.3.17 (2023-02-21)

* `Premailex.HTMLInlineStyles.process/3` now warns when styles can't be loaded from URL's
* `Premailex.HTMLInlineStyles.process/1` now parses `<thead>` and `<tfoot>` elements
* `Premailex.CSSParser.parse/1` now handles escaped commas
* Require Elixir 1.11

## v0.3.16 (2022-07-01)

* `Premailex.CSSParser.to_string/1` now adds whitespace between inline style rules

## v0.3.15 (2022-03-24)

* Fixed invalid spec in `Premailex.Util.traverse/3`

## v0.3.14 (2022-03-08)

* Added horizontal rule parsing to `Premailex.HTMLToPlainText.process/1`
* `Premailex.Util.traverse/3` no longer strips comments
* `Premailex.HTMLInlineStyles.process/3` strips empty comments
* `Premailex.HTMLInlineStyles.process/3` now applies styles to `<html>` elements

## v0.3.13 (2020-11-24)

* Fixed spec and docs issues.

## v0.3.12 (2020-10-18)

* `Premailex.HTMLInlineStyles.process/3` now supports passing in CSS as an argument

## v0.3.11 (2020-10-08)

* Fixed bug where the inline styles where applied to more than the first match causing in some cases styles to be missing for subsequent parent elements
* Relax floki requirement
* Relax meeseeks requirement

## v0.3.10 (2020-01-09)

* Support floki up to `v0.24.x`

## v0.3.9 (2019-10-06)

* Ignore `@font-face` at-rule

## v0.3.8 (2019-08-22)

* Removed HTTPoison and use `:httpc` instead
* Fixed bug where HTML with no style tags resulted in all existing inline styles being removed
* Added `is_binary/1` guard to `Premailex.to_inline_css/2` and `Premailex.to_text/1`

## v0.3.7 (2019-07-05)

* Preserve downlevel-revealed conditional comments in `Premailex.Util.traverse/3`

## v0.3.6 (2019-06-22)

* Preserve conditional comments in `Premailex.Util.traverse/3` so they can show up in output from `Premailex.HTMLInlineStyles.process/2`

## v0.3.5 (2019-03-21)

* Accept `<table>` with `<th>` elements.

## v0.3.4

* HTTP adapter for HTTPoison that handles redirects #31 #32 (thanks Przemyslaw Mroczek @Lackoftactics)

## v0.3.3

* Ignore `@media` queries  #28 #29

## v0.3.2

* Remove bypass for tests and make http adapter configurable #27
* Test with updated dependencies #26

## v0.3.1

* Handle url values in CSS rules correctly #25

## v0.3.0

* Meeseeks `v0.8.0` no longer supported #23
* Ensure Elixir 1.7 support #22
