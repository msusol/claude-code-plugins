---
status: active
date: 2026-11-14
---

# Wordfreq CLI Implementation Plan

## Goal

A small Python CLI that prints the most common words in a text file.

## Context

Smoke-test plan for A/B runs. Same content as the plain `wordfreq` plan; only the docs/ layout differs.

## Tasks

- [ ] `wordfreq.py`: `top_words(text, n)` returns the n most common words, lowercased, punctuation stripped, ties alphabetical.
- [ ] `test_wordfreq.py`: pytest tests for empty input, ties, punctuation, n > distinct words.
- [ ] CLI: `python wordfreq.py file.txt -n 5` prints "word count" lines.
- [ ] `README.md` with usage and one example.

Done = pytest passes, CLI works on a sample file.
