#!/usr/bin/env python3
"""Builds next-word tables for the keyboard from a Tatoeba sentence export.

usage: build_ngrams.py SENTENCES.tsv.bz2 LANG OUT_DIR
Writes OUT_DIR/next_LANG.txt with lines:  context<TAB>word1 word2 word3 ...
  context is one word, two words ("w1 w2"), or "<s>" for the start of a sentence.
"""
import bz2
import re
import sys
from collections import Counter, defaultdict

src, lang, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]

if lang == "ar":
    strip = re.compile("[ً-ْـ]")
    token = re.compile("[ء-ي]+")
    def words(text):
        return token.findall(strip.sub("", text))
else:
    token = re.compile("[a-z]+(?:'[a-z]+)?")
    def words(text):
        return token.findall(text.lower())

bigrams = defaultdict(Counter)
trigrams = defaultdict(Counter)
sentences = 0
with bz2.open(src, "rt", encoding="utf-8", errors="ignore") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        for sentence in re.split(r"[.!?؟\n]+", parts[2]):
            w = words(sentence)
            if not w:
                continue
            sentences += 1
            seq = ["<s>"] + w
            for i in range(1, len(seq)):
                bigrams[seq[i - 1]][seq[i]] += 1
                if i >= 2:
                    trigrams[seq[i - 2] + " " + seq[i - 1]][seq[i]] += 1

def best(table, contexts, followers, min_count):
    ranked = sorted(table.items(), key=lambda kv: -sum(kv[1].values()))[:contexts]
    rows = []
    for ctx, counter in ranked:
        top = [w for w, c in counter.most_common(followers) if c >= min_count]
        if top:
            rows.append(f"{ctx}\t{' '.join(top)}")
    return rows

rows = best(bigrams, 25000, 6, 2) + best(trigrams, 40000, 4, 3)
with open(f"{out_dir}/next_{lang}.txt", "w", encoding="utf-8") as out:
    out.write("\n".join(rows) + "\n")
print(f"{lang}: {sentences} sentences -> {len(rows)} contexts")
