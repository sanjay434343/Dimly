class MorseService {
  static final Map<String, String> _characters = {
    'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.',
    'F': '..-.', 'G': '--.', 'H': '....', 'I': '..', 'J': '.---',
    'K': '-.-', 'L': '.-..', 'M': '--', 'N': '-.', 'O': '---',
    'P': '.--.', 'Q': '--.-', 'R': '.-.', 'S': '...', 'T': '-',
    'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-', 'Y': '-.--',
    'Z': '--..', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
    '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
    '0': '-----', ' ': ' '
  };

  static String toMorse(String text) {
    if (text.isEmpty) return '';
    return text
        .toUpperCase()
        .split('')
        .map((char) => _characters[char] ?? '')
        .where((code) => code.isNotEmpty)
        .join(' ');
  }

  static Duration getDotDuration(double wpm) {
    return Duration(milliseconds: (1200 / wpm).round());
  }

  static Duration getDashDuration(double wpm) {
    return getDotDuration(wpm) * 3;
  }

  static String getLetterCode(String letter) {
    return _characters[letter.toUpperCase()] ?? '';
  }
}
