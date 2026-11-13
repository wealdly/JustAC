# Provenance and acknowledgments

## Project credit and upstream notices

New work in this project is credited to MythicSim contributors. The project is
maintained independently of wowsims. The wowsims copyright notice is retained for
upstream portions adapted or included here; it does not assign the new project
or its original contributions to the wowsims team. Both notices appear in
[LICENSE](LICENSE) under the standard MIT terms.

## Starting code and reference material

This repository starts with the bounded Rust prototype and matched benchmark
developed in [MythicSim](https://github.com/sage3648/mythicsim), commits
`fdcea74ae6` and `bd0f4af6`. Only engine code, fixtures, benchmark tools and reports
were extracted. Application configuration and private simulation data are excluded.

RNG behavior, combat semantics and the Go reference helper derive from the
MIT-licensed wowsims lineage, including
[ElliotWood/Forever](https://github.com/ElliotWood/Forever) and
[sage3648/mythicsim-forever-engine-go](https://github.com/sage3648/mythicsim-forever-engine-go).
Upstream copyright and permission notices are preserved in [LICENSE](LICENSE).

Fixtures use synthetic characters at revision
`a667dce8492bd9fb94269a9f864289cb74006775`. Historical reports and snapshots retain
the original experiment's date, compiler settings and source digest. Extracting
them does not constitute a new timing measurement.

## First-build inventory

The synthetic Frost reference and its recorded Go observation retain provenance
to the MythicSim application and pinned wowsims-derived Go engine in
`inventory/first-frost/manifest.json`. Spell and item identities, mechanic notes
and report semantics derive from those sources. The selected talent build is
credited to mixarxrt in the application reference catalog and inventory.
