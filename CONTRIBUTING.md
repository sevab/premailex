# Contributing

Thanks for considering contributing to Premailex.

## Test suite

Premailex supports several HTML parsers. The parser is selected via the `HTML_PARSER` environment variable:

```bash
HTML_PARSER=Xmerl mix test
```

CI runs the [full matrix](.github/workflows/ci.yml) across `LazyHTML`, `Floki`, `Meeseeks`, and `:xmerl`.

## Code quality

Elixir formatter, `Credo`, and `:dialyzer` are used:

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
```

## Benchmarks

Performance-sensitive changes should be verified using the benchmark scripts in `benchmark/`. `HTML_PARSER` is required:

```bash
HTML_PARSER=Xmerl mix run benchmark/to_inline_css.exs
HTML_PARSER=Xmerl mix run benchmark/to_text.exs
```

## Submitting a PR

- Write a focused pull request description and link any related issue
- Update `CHANGELOG.md` under `## Unreleased`
- If behavior changes, add or update tests
- Ensure the full parser matrix passes locally before pushing