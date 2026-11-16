# 0002. Build and prove everything in Power BI Desktop

## Status

Accepted

## Context

The project has to be reproducible on one machine with no paid licences and no cloud tenant. A
reader should be able to check every claim from what is in the repository.

## Decision

I build and prove the project in Power BI Desktop against a local SQL Server 2022 Developer
instance. I do not use the Power BI service, Fabric or any cloud capacity.

## Consequences

- Service features (workspaces, an app, scheduled refresh, deployment pipelines, XMLA endpoints on
  a workspace, sensitivity labels) are described as designs and labelled "designed, not run".
  Nothing in the repository claims they were tested.
- DAX tests run locally against the model open in Desktop. Their results are committed, and CI
  checks the committed results rather than running the model.
