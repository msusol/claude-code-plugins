# Plan: wordfreq CLI
1. wordfreq.py: top_words(text, n) returns the n most common words,
   lowercased, punctuation stripped, ties alphabetical.
2. test_wordfreq.py: pytest tests for empty input, ties, punctuation, n > distinct words.
3. CLI: `python wordfreq.py file.txt -n 5` prints "word count" lines.
4. README.md with usage and one example.
Done = pytest passes, CLI works on a sample file.
