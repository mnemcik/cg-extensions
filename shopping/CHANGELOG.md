# Changelog

## 0.1.0

- **Added:** `cg shop add | list | order | receive | cancel | show`. One file per item under `shopping/`, grouped views by supplier or project, whole-supplier ordering with an order number, receiving by order number.
- **Added:** ids are `<date>-<slug>-<6 hex>`, so parallel sessions adding the same item never conflict; CRLF files read and update; ids are checked, so a path can't escape `shopping/`.
- **Added:** CLAUDE.md rule, workflow note and item template.
