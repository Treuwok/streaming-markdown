/// Translates UTF-8 byte offsets into the code-unit offsets Dart strings use.
///
/// The native parser is tree-sitter, which counts bytes; a Dart `String` is
/// indexed in UTF-16 code units. For ASCII the two are the same number, which
/// is why one field carried both for as long as it did — and why nothing
/// noticed. A single CJK character makes them differ by two.
///
/// Built once per parse and consulted per block, so the cost is one pass over
/// the source rather than one pass per lookup.
class Utf8CodeUnitIndex {
  /// Indexes [source] so byte offsets into its UTF-8 encoding can be mapped
  /// back to code-unit offsets into the string itself.
  Utf8CodeUnitIndex(String source) : _byteAt = _buildByteAt(source);

  /// `_byteAt[i]` is the UTF-8 byte offset at which code unit `i` begins.
  /// Has one extra entry for the end of the string.
  final List<int> _byteAt;

  static List<int> _buildByteAt(String source) {
    final List<int> out = List<int>.filled(source.length + 1, 0);
    int bytes = 0;
    for (int i = 0; i < source.length; i++) {
      out[i] = bytes;
      final int unit = source.codeUnitAt(i);
      if (unit < 0x80) {
        bytes += 1;
      } else if (unit < 0x800) {
        bytes += 2;
      } else if (unit >= 0xD800 &&
          unit <= 0xDBFF &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) >= 0xDC00 &&
          source.codeUnitAt(i + 1) <= 0xDFFF) {
        // A surrogate pair is four bytes for the two code units together.
        // The low surrogate is not a boundary any byte offset can land on, so
        // it takes the end of the pair — which keeps the table increasing,
        // which is all the search below needs of it.
        bytes += 4;
        out[i + 1] = bytes;
        i++;
      } else {
        bytes += 3;
      }
    }
    out[source.length] = bytes;
    return out;
  }

  /// Total length of the source in UTF-8 bytes.
  int get byteLength => _byteAt.isEmpty ? 0 : _byteAt.last;

  /// Total length of the source in UTF-16 code units.
  int get codeUnitLength => _byteAt.length - 1;

  /// The code-unit offset for [byteOffset].
  ///
  /// A byte offset that lands inside a character rounds DOWN to that
  /// character's start — the alternative is returning an index that splits it,
  /// and a substring taken there is corrupt rather than merely wrong.
  int codeUnitFor(int byteOffset) {
    if (byteOffset <= 0) {
      return 0;
    }
    if (byteOffset >= byteLength) {
      return codeUnitLength;
    }
    int low = 0;
    int high = _byteAt.length - 1;
    while (low < high) {
      final int mid = (low + high + 1) >> 1;
      if (_byteAt[mid] <= byteOffset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}
