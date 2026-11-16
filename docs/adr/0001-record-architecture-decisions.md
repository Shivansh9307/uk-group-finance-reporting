# 0001. Record architecture decisions

## Status

Accepted

## Context

The model, the SQL layer and the report involve choices that are easy to forget the reasons for
and hard to reverse later.

## Decision

I keep one short architecture decision record per significant decision in `docs/adr/`, numbered in
order and written from `0000-template.md`. A decision that is replaced gets a new record, and the
old one is marked as superseded rather than edited.

## Consequences

Anyone reading the repository can see why the project is built the way it is. Writing a record
takes a few minutes per decision.
