// English letter bigram frequencies
// Source: Derived from English text corpus analysis
// Values represent relative frequency (higher = more common)
//
// These frequencies indicate how often each letter follows another.
// For example, englishBigrams['T']['H'] = 0.28 means H follows T
// about 28% of the time in English text.

const Map<String, Map<String, double>> englishBigrams = {
  'A': {
    'N': 0.21, 'L': 0.13, 'T': 0.12, 'R': 0.11, 'S': 0.10,
    'D': 0.07, 'I': 0.06, 'C': 0.05, 'M': 0.04, 'Y': 0.03,
    'B': 0.02, 'G': 0.02, 'P': 0.01, 'V': 0.01, 'K': 0.01,
    'U': 0.01,
  },
  'B': {
    'E': 0.28, 'L': 0.15, 'O': 0.14, 'U': 0.12, 'A': 0.10,
    'I': 0.08, 'R': 0.05, 'Y': 0.04, 'S': 0.02,
  },
  'C': {
    'O': 0.22, 'H': 0.18, 'E': 0.15, 'A': 0.14, 'I': 0.10,
    'T': 0.08, 'K': 0.05, 'R': 0.04, 'U': 0.03, 'L': 0.01,
  },
  'D': {
    'E': 0.20, 'I': 0.15, 'O': 0.12, 'A': 0.10, 'S': 0.08,
    'U': 0.08, 'R': 0.06, 'Y': 0.05, 'L': 0.04, 'N': 0.03,
    'G': 0.03, 'D': 0.02, 'W': 0.02, 'M': 0.01,
  },
  'E': {
    'R': 0.18, 'S': 0.14, 'D': 0.12, 'N': 0.11, 'A': 0.08,
    'T': 0.07, 'L': 0.06, 'E': 0.05, 'C': 0.04, 'I': 0.04,
    'M': 0.03, 'X': 0.02, 'V': 0.02, 'P': 0.02, 'W': 0.01,
  },
  'F': {
    'O': 0.25, 'I': 0.18, 'E': 0.14, 'A': 0.12, 'U': 0.10,
    'R': 0.08, 'F': 0.05, 'T': 0.04, 'L': 0.03,
  },
  'G': {
    'E': 0.22, 'H': 0.15, 'O': 0.14, 'A': 0.12, 'I': 0.10,
    'R': 0.08, 'U': 0.06, 'S': 0.05, 'L': 0.04, 'N': 0.03,
  },
  'H': {
    'E': 0.42, 'A': 0.18, 'I': 0.12, 'O': 0.10, 'T': 0.06,
    'U': 0.04, 'R': 0.03, 'Y': 0.02, 'S': 0.02,
  },
  'I': {
    'N': 0.22, 'S': 0.14, 'T': 0.12, 'O': 0.10, 'C': 0.08,
    'E': 0.07, 'L': 0.06, 'D': 0.05, 'A': 0.04, 'R': 0.04,
    'M': 0.03, 'G': 0.02, 'F': 0.02, 'V': 0.01,
  },
  'J': {
    'U': 0.35, 'O': 0.25, 'A': 0.15, 'E': 0.12, 'I': 0.08,
    'S': 0.03,
  },
  'K': {
    'E': 0.28, 'I': 0.20, 'S': 0.15, 'N': 0.10, 'A': 0.08,
    'O': 0.06, 'L': 0.05, 'Y': 0.04, 'W': 0.03,
  },
  'L': {
    'E': 0.22, 'I': 0.16, 'L': 0.12, 'A': 0.10, 'O': 0.10,
    'Y': 0.08, 'D': 0.06, 'U': 0.05, 'S': 0.04, 'T': 0.03,
  },
  'M': {
    'E': 0.25, 'A': 0.18, 'I': 0.14, 'O': 0.12, 'P': 0.08,
    'U': 0.06, 'B': 0.05, 'S': 0.04, 'Y': 0.04, 'M': 0.03,
  },
  'N': {
    'G': 0.18, 'E': 0.16, 'D': 0.14, 'T': 0.12, 'S': 0.10,
    'O': 0.08, 'I': 0.06, 'A': 0.05, 'C': 0.04, 'N': 0.03,
    'Y': 0.02, 'K': 0.01,
  },
  'O': {
    'N': 0.18, 'R': 0.14, 'U': 0.12, 'F': 0.10, 'T': 0.08,
    'W': 0.07, 'M': 0.06, 'L': 0.05, 'O': 0.05, 'S': 0.04,
    'P': 0.03, 'D': 0.03, 'K': 0.02, 'V': 0.02,
  },
  'P': {
    'E': 0.22, 'O': 0.18, 'R': 0.15, 'A': 0.12, 'L': 0.10,
    'P': 0.08, 'I': 0.06, 'H': 0.04, 'U': 0.03, 'T': 0.02,
  },
  'Q': {
    'U': 0.95, 'I': 0.03, 'A': 0.02,
  },
  'R': {
    'E': 0.22, 'O': 0.14, 'I': 0.12, 'A': 0.11, 'S': 0.08,
    'Y': 0.07, 'N': 0.06, 'T': 0.05, 'U': 0.04, 'D': 0.03,
    'R': 0.03, 'L': 0.02, 'M': 0.02,
  },
  'S': {
    'T': 0.20, 'E': 0.16, 'I': 0.12, 'O': 0.10, 'S': 0.08,
    'A': 0.07, 'H': 0.06, 'U': 0.05, 'P': 0.04, 'C': 0.04,
    'W': 0.03, 'K': 0.02, 'L': 0.02, 'M': 0.01,
  },
  'T': {
    'H': 0.28, 'O': 0.15, 'I': 0.12, 'A': 0.10, 'E': 0.10,
    'R': 0.06, 'S': 0.05, 'T': 0.04, 'U': 0.04, 'Y': 0.03,
    'W': 0.02, 'L': 0.01,
  },
  'U': {
    'R': 0.18, 'S': 0.15, 'L': 0.12, 'N': 0.11, 'T': 0.10,
    'P': 0.08, 'C': 0.06, 'M': 0.05, 'G': 0.04, 'E': 0.03,
    'I': 0.03, 'A': 0.02, 'B': 0.02,
  },
  'V': {
    'E': 0.45, 'I': 0.20, 'A': 0.15, 'O': 0.10, 'Y': 0.05,
    'U': 0.03,
  },
  'W': {
    'A': 0.22, 'I': 0.18, 'O': 0.16, 'E': 0.14, 'H': 0.10,
    'N': 0.06, 'S': 0.05, 'R': 0.04, 'L': 0.03,
  },
  'X': {
    'P': 0.25, 'I': 0.20, 'T': 0.18, 'A': 0.12, 'C': 0.10,
    'E': 0.08, 'O': 0.04, 'U': 0.02,
  },
  'Y': {
    'O': 0.22, 'E': 0.18, 'S': 0.14, 'I': 0.10, 'A': 0.08,
    'T': 0.06, 'L': 0.05, 'P': 0.04, 'M': 0.04, 'N': 0.03,
    'W': 0.03, 'C': 0.02,
  },
  'Z': {
    'E': 0.35, 'A': 0.20, 'O': 0.15, 'I': 0.12, 'Z': 0.08,
    'U': 0.05, 'Y': 0.03,
  },
};

/// Starting letter frequencies (how often each letter starts a word)
const Map<String, double> startingLetterFrequencies = {
  'T': 0.16, 'A': 0.11, 'I': 0.08, 'S': 0.07, 'O': 0.07,
  'C': 0.06, 'M': 0.05, 'F': 0.05, 'P': 0.05, 'W': 0.04,
  'H': 0.04, 'B': 0.04, 'D': 0.04, 'L': 0.03, 'N': 0.03,
  'R': 0.02, 'G': 0.02, 'E': 0.02, 'U': 0.02, 'Y': 0.02,
  'J': 0.01, 'K': 0.01, 'V': 0.01, 'Q': 0.01, 'X': 0.01,
  'Z': 0.01,
};

/// Get the bigram frequencies for a given letter
/// Returns empty map if letter not found
Map<String, double> getBigramFrequencies(String letter) {
  return englishBigrams[letter.toUpperCase()] ?? {};
}

/// Get a sorted list of letters by frequency after the given letter
List<String> getLettersByFrequency(String letter) {
  final frequencies = getBigramFrequencies(letter);
  if (frequencies.isEmpty) {
    // Return all letters in default order if no data
    return 'ETAOINSHRDLCUMWFGYPBVKJXQZ'.split('');
  }

  // Start with letters that have frequencies
  final sorted = frequencies.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final result = sorted.map((e) => e.key).toList();

  // Add any missing letters at the end
  for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
    if (!result.contains(letter)) {
      result.add(letter);
    }
  }

  return result;
}
