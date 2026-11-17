"""Builds assets/word_vectors.bin, the word vectors the task categoriser runs on.

The vectors are spaCy's en_core_web_lg 3.8.0 vectors (Explosion Vectors, CC0): 343,000 vectors of
300 dimensions. This keeps the WORDS most frequent lowercase English words of 2 to 14 letters that
have a vector, ranked by wordfreq's English list (only used to choose the words; none of its data is
written out), reduces the vectors to 128 dimensions with PCA and stores them as int8, so the file
stays a few MB.

Reads the files directly, with numpy and msgpack only (no spaCy or wordfreq code is run):

    curl -LO https://github.com/explosion/spacy-models/releases/download/en_core_web_lg-3.8.0/en_core_web_lg-3.8.0-py3-none-any.whl
    unzip en_core_web_lg-3.8.0-py3-none-any.whl 'en_core_web_lg/*/vocab/*' -d lg
    pip download --no-deps wordfreq==3.1.1 && unzip wordfreq-3.1.1-py3-none-any.whl -d wordfreq
    python3 tool/build_word_vectors.py lg/en_core_web_lg/en_core_web_lg-3.8.0/vocab \
        wordfreq/wordfreq/data/large_en.msgpack.gz assets/word_vectors.bin

Format, little-endian: b'BMBV', u8 version (1), u16 dims, u32 rows, u32 words; rows x dims int8;
words x u16 row; then the words in UTF-8, joined by '\\n', in the same order as their rows.
"""
import gzip
import json
import re
import struct
import sys

import msgpack
import numpy as np

DIMS = 128
WORDS = 30000
_M = 0xC6A4A7935BD1E995
_MASK = (1 << 64) - 1


def murmur64a(data: bytes, seed: int = 1) -> int:
    """spaCy's string hash (MurmurHash64A, seed 1), to look words up in key2row."""
    h = (seed ^ (len(data) * _M)) & _MASK
    blocks = len(data) // 8
    for i in range(blocks):
        k = int.from_bytes(data[i * 8:i * 8 + 8], 'little')
        k = (k * _M) & _MASK
        k ^= k >> 47
        k = (k * _M) & _MASK
        h ^= k
        h = (h * _M) & _MASK
    tail = data[blocks * 8:]
    if tail:
        for i in range(len(tail) - 1, -1, -1):
            h ^= tail[i] << (8 * i)
        h = (h * _M) & _MASK
    h ^= h >> 47
    h = (h * _M) & _MASK
    h ^= h >> 47
    return h


def main(vocab: str, frequencies: str, out: str) -> None:
    key2row = msgpack.unpackb(open(f'{vocab}/key2row', 'rb').read(), strict_map_key=False)
    vectors = np.load(f'{vocab}/vectors', allow_pickle=False)
    # wordfreq's cBpack: a header, then lists of words from the most frequent down.
    buckets = msgpack.unpackb(gzip.open(frequencies).read())[1:]

    words = {}
    for bucket in buckets:
        for word in bucket:
            if len(words) == WORDS:
                break
            if word in words or not re.fullmatch(r'[a-z]{2,14}', word):
                continue
            row = key2row.get(murmur64a(word.encode()))
            if row is not None:
                words[word] = row

    used = sorted(set(words.values()))
    compact = {row: i for i, row in enumerate(used)}
    x = vectors[used] - vectors[used].mean(0)
    _, _, vt = np.linalg.svd(x, full_matrices=False)
    reduced = x @ vt[:DIMS].T
    scale = np.abs(reduced).max(1, keepdims=True)
    scale[scale == 0] = 1
    quantised = np.clip(np.round(reduced / scale * 127), -127, 127).astype(np.int8)

    ordered = sorted(words)
    with open(out, 'wb') as f:
        f.write(b'BMBV' + struct.pack('<BHII', 1, DIMS, len(used), len(ordered)))
        f.write(quantised.tobytes())
        f.write(np.array([compact[words[w]] for w in ordered], dtype='<u2').tobytes())
        f.write('\n'.join(ordered).encode())
    print(f'{len(ordered)} words, {len(used)} vectors of {DIMS} dimensions')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
