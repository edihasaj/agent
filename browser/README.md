# browser/ — moved to its own repo

`abx` now lives standalone at **[edihasaj/abx](https://github.com/edihasaj/abx)**
(extracted from this directory, history preserved).

Install / update it from Homebrew:

```sh
brew install edihasaj/abx/abx
abx install-browser     # fetch Chromium on first use
```

The code here is the pre-extraction snapshot and is no longer the source of
truth — make changes in `~/Projects/abx` and let its release pipeline ship
them. This directory can be removed once nothing local references
`browser/dist/abx` or `browser/scripts/*` directly.
