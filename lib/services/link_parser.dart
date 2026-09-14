/// Helpers shared by the home input and clipboard detector.
class LinkParser {
  static List<String> extractHttpLinks(String text) {
    final links = <String>[];
    final seen = <String>{};
    final pattern = RegExp(
      r'(https?://[^\s<>"\u200c]+)',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(text)) {
      var link = match.group(1)!.trim();
      link = link.replaceFirst(RegExp(r'''[)\],.;!?]+$'''), '');
      final uri = Uri.tryParse(link);
      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }
      if (seen.add(link)) links.add(link);
    }
    return links;
  }
}
