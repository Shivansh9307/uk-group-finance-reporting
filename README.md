# UK Group Finance Reporting

What would UK central government look like if it reported like a corporate group? In this project I
treat government departments as business units and their arm's-length bodies as legal entities, and
build the management reporting a group finance team would expect: a P&L with variance to plan and
forecast, a balance sheet and cash flow for the NHS provider sub-group, and the workforce drivers
behind the cost base. The data are HM Treasury OSCAR II releases, NHS trust accounts, departmental
workforce files and HM Treasury and ONS deflators, and every reported total is meant to tie back to
its published source.

## Status

The project is in setup. Nothing described below has been built yet. The work is planned in six
phases:

0. Setup and gates
1. Ingestion and star schema
2. Core model and P&L
3. Performance, security, CI
4. Depth
5. Scale and finish

## Data sources and licence

All source data are public sector information published under the Open Government Licence v3.0.
Sources, links and attribution are listed in [DATA_LICENCES.md](DATA_LICENCES.md). A
real-versus-synthetic register will be added to this README as soon as any authored or synthetic
data enters the project.

The code is released under the MIT licence; see [LICENSE](LICENSE).

## Tools

Power BI Desktop (PBIP with TMDL and PBIR), SQL Server 2022 Developer, Python, Tabular Editor 2,
DAX Studio.
