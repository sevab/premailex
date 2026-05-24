# Contributing

Thanks for thinking about contributing to Premailex.

## Test suite

Premailex supports several HTML parsers. The parser can be set with the `HTML_PARSER` environment variable:

```bash
HTML_PARSER=Xmerl mix test
```

CI runs the [full matrix](.github/workflows/ci.yml) across LazyHTML, Floki, Meeseeks, and Xmerl.

## Code quality

Elixir formatter, credo and dialyzer are used:

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
```

## Benchmarks

Performance-sensitive changes should be checked against the benchmark scripts in `benchmark/`. `HTML_PARSER` is required:

```bash
HTML_PARSER=Xmerl mix run benchmark/to_inline_css.exs
HTML_PARSER=Xmerl mix run benchmark/to_text.exs
```

## Submitting a PR

- Write a focused PR description and link related issue if any
- Update `CHANGELOG.md` under `## Unreleased`
- If you change behaviour, add or update a test
- Make sure the parser test matrix passes locally before pushing
