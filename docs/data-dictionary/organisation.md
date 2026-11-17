# Data dictionary: organisations and departments

The organisation dimension (Type 2 by release), the department dimension, the map that tells the facts
which version of each a release used, and the two authored files behind them. Built by
`ukfr build --scope committed` from the 31 in-year releases and from `authored/`. Every claim is labelled
**tested** (the command and where the result is) or **designed**.

Everything about *which* organisation or department a row belongs to comes from the real releases. The
only authored parts are the two files in `authored/`; they decide keys and display names, never amounts.

## Decisions

- **Departments are keyed on the three-digit department number**, which is the last three digits of
  every organisation code. The published department name is a label that alternates between releases
  (43 of 51 label changes in the profile are the same department under another name), so it is never a
  key. **Tested**: `sql/tests/202_department_number_has_one_label_per_release.sql` (a number has one
  label per release) and `205_published_department_labels_belong_to_their_period.sql` (every label a
  release publishes is listed in `published_labels` of the authored period that covers that release).
- **The durable key of an organisation is the three-letter prefix of its code**, unless a row in
  `authored/organisation_key_override.csv` covers that code in that release. 14 override rows cover
  the cases the profile found; `docs/profiling/organisation-keys.md` section 11 is the evidence.
- **A new version starts only when a tracked attribute really changes**: the organisation code (a move
  between departments changes the numeric suffix), the department (number or naming period) or a real
  name change. Nothing else makes a version.
- **Alias rule for names.** Publishers flip between spellings from release to release. A change from
  name X to name Y (compared after upper-casing, removing bracketed tags, and collapsing punctuation
  and spaces) at release r is a real name change only if X is never published again after r and Y was
  never published before r. Otherwise it is an alias flip and nothing is versioned. The display name of a
  version is the spelling published in most of its releases, the latest on a tie. A rename that is later
  reverted is therefore treated as an alias for organisations; for departments, where that happens for
  real (DLUHC back to MHCLG in 2024), the periods are authored by hand instead. **Tested**:
  `sql/tests/225_name_flips_do_not_start_versions.sql`, `224_every_version_start_has_a_tracked_change.sql`.
- **Versions tile the life of a key.** A version runs from the first release it is reported in to the release
  before the next version starts, so a body that is missing from some releases (dropped and back again)
  stays covered. The last version ends at the last release the key is reported in. **Tested**:
  `220_version_ranges_tile_each_durable_key.sql`.
- **Only organisations with non-zero rows exist.** The dimension is built from the (code, release)
  pairs in `stg.inyear_snapshot`, so a code that only ever has zero-amount rows has no row. One such code
  exists: `PPP048` (**tested**: the SQL count of codes in `raw.oscar_inyear` is 301, in the dimension's
  input 300).

## Tables

| Table | Rows | Grain | Key |
|---|---|---|---|
| `authored.department_name` | 71 | one department number and naming period | `_load_order` |
| `authored.organisation_key_override` | 14 | one code and period | `_load_order` |
| `stg.organisation_release` | 6,853 | one organisation code and release | (`release_seq`, `organisation_code`) |
| `stg.department_period` | 71 | typed `authored.department_name` | (`department_number`, `valid_from_seq`) |
| `stg.organisation_key_override` | 14 | typed `authored.organisation_key_override` | `override_id` |
| `stg.organisation_release_key` | 6,853 | one code and release, with its durable key | (`release_seq`, `organisation_code`) |
| `stg.organisation_version_row` | 6,852 | one durable key and release, with the change flags and version number | (`durable_key`, `release_seq`) |
| `dw.dim_department` | 72 | one department number and naming period, plus Unknown | `department_key` |
| `dw.dim_organisation` | 409 | one version of an organisation, plus Unknown | `organisation_key` |
| `dw.organisation_name_alias` | 587 | one spelling of a name within a version | (`organisation_key`, `organisation_name`) |
| `dw.organisation_release_map` | 6,853 | one organisation code and release in the snapshot | (`release`, `organisation_code`) |
| `stg.current_structure_map` (view) | 5,480 | one organisation version and sub-segment | (`organisation_key`, `sub_segment_code`) |

Row counts are from the build in `evidence/build/table_counts.csv` (the view is counted from the
database, not in that file).

## dw.dim_department

One row per department number and naming period, plus `-1` Unknown.

| Column | Meaning |
|---|---|
| `department_key` | `-1` = Unknown, then 1.. in (department number, period start) order |
| `department_number` | three digits, as in the organisation code (`UNK` for Unknown) |
| `department_name` | the display name for the period, from `authored/department_name.csv` |
| `member_type` | `Department`, `Unallocated` or `Unknown`. A later task adds Unallocated members by adding rows to `department_name.csv` with that member type; nothing in the SQL changes |
| `valid_from_release_seq`, `valid_to_release_seq` | release sequence, 1 = March 2019 .. 31 = September 2026; an open period ends at the latest release |
| `valid_from_release`, `valid_to_release` | the same as labels (`2023-06`) |
| `is_current` | the period covers the latest release and, for a Department, the number is reported in it |

71 periods for 63 numbers: 013, 030, 048, 079, 084 and 907 have two periods, 085 has three (MHCLG,
DLUHC, MHCLG again). 56 of the periods are current. The real renames I authored as periods are the ones
where a different department exists afterwards or the name really changed (DIT to DBT, BEIS to DSIT, DFID
to FCDO, the Parliament works body, DCMS losing "Digital", the DLUHC years). Alternating labels
(Welsh Assembly Government and Welsh Government, ECGD and UK Export Finance, and so on) are listed under
one period in `published_labels` and are not periods.

## dw.dim_organisation

One row per version of an organisation, plus `-1` Unknown.

| Column | Meaning |
|---|---|
| `organisation_key` | surrogate, `-1` = Unknown, then 1.. in (durable key, version) order |
| `durable_key` | the three-letter prefix, or the authored key (for example `BIS.BEIS`, `UKG087`) |
| `version_no` | 1.. within the key |
| `organisation_code` | the code of this version; all rows of a version have one code |
| `organisation_name` | display name (see the alias rule); an override's `display_name` where the published names are wrong for the body (BEIS core) |
| `department_key` | the department, as the releases of this version report it |
| `valid_from_release_seq`, `valid_to_release_seq`, `valid_from_release`, `valid_to_release` | first release of the version to the release before the next version; the last version ends at the last release the key is reported in |
| `n_releases_reported` | releases in the range in which the code has non-zero rows |
| `version_reason` | `first release of the key`, or the changes that started the version: `code change`, `department change` (the number changed), `department renamed` (the naming period changed), `name change` |
| `change_code`, `change_department`, `change_department_move`, `change_name` | the same as flags; `change_department` is true for a move and for a rename of the department |
| `durable_key_rule` | `prefix`, or the override's reason |
| `successor_durable_key` | where the body went when it ended, if authored (FCO core into `DID.FCDO`); otherwise NULL |
| `is_current` | the key's last version, and the key is reported in the latest release |
| `is_latest_version` | the key's last version, current or not |

A code that moves between departments changes its numeric suffix, so every department move shows as
`code change; department change`. A department rename (DCMS losing "Digital" in 2023-09, MHCLG becoming
DLUHC in 2021-12) changes the department key of every organisation in it, so it starts a version for each
(`department renamed`). That is the as-reported view of "which department did this release put the
organisation under": **designed** so that a fact joined on the release's version carries the department
name of that period.

### Counts (tested: `ukfr build --scope committed --recreate --yes`, then the queries in the report)

- 277 durable keys, 408 versions (plus the Unknown row), 222 current versions.
- Versions after the first, by what started them: 131. `code change` and `department change` together 25
  (17 with only that, 8 together with a name change); `department renamed` only 60; `department renamed` with
  `name change` 2; `name change` only 44. In total 25 code changes, 87 department changes (25 moves, 62
  renames) and 54 name changes. A version can have more than one reason.
- Names: 587 spellings across the 408 versions. 6 are alias names (a different name that alternates with the
  display name, for example UK Export Finance and ECGD) and 173 are spelling variants (case, punctuation,
  brackets). Between consecutive releases of a key, 207 raw name changes started no version; 39 of them
  changed the normalised name too (the alias flips that the profile counted), and 168 were spelling only.
- Overrides: 14 rows, every one used at least once (**tested**:
  `sql/tests/211_every_override_is_used.sql`).

## authored/organisation_key_override.csv

| Column | Meaning |
|---|---|
| `organisation_code` | the code the row covers |
| `valid_from_release`, `valid_to_release` | optional bounds, as release labels |
| `durable_key` | the key the code gets in that period |
| `merge_into_code` | optional: in that period the code is a second spelling of this code (a coding error). It is mapped to that code's version |
| `successor_durable_key` | optional: where the body went when it ended |
| `display_name` | optional: the display name shown for the versions in that period |
| `reason` | `prefix_collision`, `prefix_change`, `reused_code`, `coding_error` or `merger` |
| `evidence`, `note` | where the fact comes from; why I decided it |

The rows, with my reasoning:

- **UKG084, UKG087, UKG066 (prefix collision).** UKG is shared by UK Green Investment Platform (BEIS) and UK
  Government Investments (HM Treasury) in 17 releases. They are different bodies, so each keeps its full
  code. UKG066 (2024-06 only, under DESNZ) is treated as the green investment body after BEIS became
  DESNZ and is keyed UKG084. Confidence medium: one release, a one-word name difference.
- **DOH004, DOH033 (prefix collision).** DOHL under Transport against the Department of Health NHS line.
  Different bodies, full codes.
- **EHR030 in June 2019 (coding error).** The Equality and Human Rights Commission is reported under two codes
  in one release (EHR030 with one row, EHR034). It keeps the key `EHR` but takes EHR034's version, so the key has
  one version per release and the amount stays on the body. In the release map it still carries its own reported
  department. I did not give it a key of its own because that would put a ghost body in the dimension.
- **OCM084 (prefix change).** Ofcom, `OFC048` then `OCM084`: one key, `OFC`.
- **BIS084, UKT013, DID030 (reused core codes).** Each is two rows with bounds, so BEIS history does not merge
  into DSIT, DIT into DBT, or DFID into FCDO. Keys `BIS.BEIS`/`BIS.DSIT`, `UKT.DIT`/`UKT.DBT`,
  `DID.DFID`/`DID.FCDO`. The profile proposed `BIS.DBIS` for the BEIS period because the file publishes the line
  as the Department for Business, Innovation and Skills in 13 of 18 releases; I key it `BIS.BEIS` and set the display
  name. DID030 is cut at 2020-12, when the organisation row is renamed, which is a release earlier than the
  department label in the files changes (2021-06), so the version of `DID.FCDO` that still has department
  DFID (2020-12 to 2021-03) is real and visible.
- **FCO027 (merger).** FCO core is absorbed into the FCDO core code. It keeps its own key `FCO` for its whole
  life because both codes are reported together from 2020-12 to 2021-06 (one key would then have two codes in
  one release). `successor_durable_key = DID.FCDO` records where it went.

## dw.organisation_name_alias

Every spelling a version was published under, with the releases it appears in. `is_display_name` marks the
spelling the display name was chosen from; `same_name_as_display` is 1 where the spelling differs only in case,
punctuation or bracketed tags. It is a lookup for review, not part of any total.

## dw.organisation_release_map

One row per (organisation code, release) found in `stg.inyear_snapshot`: 6,853 rows, one for each distinct pair.
The revision-delta fact joins to it on (`release`, `organisation_code`).

| Column | Meaning |
|---|---|
| `release`, `release_seq` | the release |
| `organisation_code` | as published |
| `organisation_key` | the version in force in that release (for EHR030 in 2019-06, the EHR034 version) |
| `department_key` | the department as that release reports it for this code |
| `durable_key` | the durable key |

**Tested**: `sql/tests/230_every_snapshot_code_and_release_resolves_to_one_organisation_key.sql` (every pair
has exactly one row and no row is extra), `231_no_snapshot_row_is_left_unmapped.sql` (all 1,328,986 snapshot
rows join, none to Unknown), `232_mapped_version_covers_the_release.sql`,
`233_release_map_department_is_the_one_the_release_reports.sql`,
`207_department_key_in_use_exists_and_unknown_is_reserved.sql`.

## stg.current_structure_map (view)

Which department a sub-segment of an organisation version belongs to in the current structure. The column
contract is fixed; a later task replaces the rule behind it with one based on sub-segments.

| Column | Meaning |
|---|---|
| `organisation_key` | `dw.dim_organisation` |
| `sub_segment_code` | as published |
| `current_department_key` | `dw.dim_department` |
| `method` | `durable key latest version`, or `department not current` |
| `is_estimated` | 0 for both methods here; a later method may set 1 |

Rule now: the department of the durable key's latest version. Where that department is not current (BEIS
core, whose latest version is under the BEIS period of number 084), the department is kept and the method says
`department not current`: 292 of the 5,480 rows. The view is in schema `stg` and its file is in `sql/dw/`
because it reads dw tables and the runner builds a layer's files in order. **Tested**:
`240_current_structure_map_covers_each_pair_once.sql` (exactly one row per pair), `241_current_structure_map_follows_its_contract.sql`.

## Named cases

`pipeline/tests/test_dim_organisation.py` asserts, for a release before and a release after, the durable key and
department of: BEIS and DSIT, DIT and DBT, DFID and FCDO, the FCO027 merger, Ofcom, UKG, DOH and EHR; and that
each of the 23 bodies that moved department and kept their prefix has one durable key across the move (read
from `docs/profiling/data/org_durable_key_candidates.csv`, finding `b0_suffix_change`).

## Not done

- I did not judge the 40 alias rows in the profile one by one; the rule above decides and the alias table
  lets a reviewer look.
- Department names are authored from the labels and the profile, not from a government source, so the
  display names are mine, written in plain title case.
- Organisation display names are the published spellings (often upper case, sometimes with department
  tags). I did not tidy them.
