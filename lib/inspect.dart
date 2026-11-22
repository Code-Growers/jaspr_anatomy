/// Reads anatomy snapshots from a running Jaspr server.
///
/// VM only: uses `dart:io`. Never import this from code that runs in a browser.
library;

import 'dart:convert';
import 'dart:io';

import 'snapshot.dart';

export 'snapshot.dart';
export 'src/core/analysis.dart';
export 'src/core/report.dart';

/// Thrown when a page cannot be inspected.
class InspectException implements Exception {
  InspectException(this.message);

  final String message;

  @override
  String toString() => message;
}

final RegExp _dataScript = RegExp(
  '<script[^>]*\\bid="$anatomyDataId"[^>]*>(.*?)</script>',
  dotAll: true,
);

/// Returns the snapshot embedded in [html], or null when there is none.
AnatomySnapshot? extractSnapshot(String html) {
  final match = _dataScript.firstMatch(html);
  return match == null ? null : AnatomySnapshot.decode(match.group(1)!);
}

/// A fetched page: its snapshot and the links it contains.
typedef InspectedPage = ({Uri url, AnatomySnapshot snapshot, List<Uri> links});

/// Fetches pages from a server that renders them inside `Anatomy`.
class Inspector {
  Inspector({this.headers = const {}, HttpClient? client}) : _client = client ?? HttpClient();

  /// Extra headers sent with every request, such as a session cookie.
  final Map<String, String> headers;
  final HttpClient _client;

  void close() => _client.close(force: true);

  /// Fetches [url] and reads its snapshot.
  Future<InspectedPage> fetch(Uri url) async {
    final String html;
    final int status;
    try {
      final request = await _client.getUrl(url);
      request.followRedirects = true;
      request.headers.set(anatomyHeader, 'data');
      headers.forEach(request.headers.set);
      final response = await request.close();
      status = response.statusCode;
      html = await response.transform(utf8.decoder).join();
    } on SocketException catch (error) {
      throw InspectException('Could not reach $url: ${error.message}. Is the server running?');
    }

    final snapshot = extractSnapshot(html);
    if (snapshot == null) {
      throw InspectException(
        'No anatomy data in the response from $url (HTTP $status).\n'
        'Check that the page body is wrapped in Anatomy(child: ...), that the server runs in debug mode '
        '(or passes enabled: true), and that the page is rendered by Jaspr.',
      );
    }
    // The page is known by the address that was asked for.
    final page = AnatomySnapshot(
      types: snapshot.types,
      roots: snapshot.roots,
      url: url.hasQuery ? '${url.path}?${url.query}' : url.path,
      framework: snapshot.framework,
    );
    return (url: url, snapshot: page, links: _links(html, url));
  }

  /// Fetches [start] and then pages it links to on the same origin, breadth
  /// first, until [limit] pages have been read.
  ///
  /// Pages that carry no anatomy data are skipped and reported through [onSkip].
  Future<List<InspectedPage>> crawl(
    List<Uri> start, {
    required int limit,
    void Function(Uri url, String reason)? onSkip,
  }) async {
    final queue = [...start];
    final seen = {for (final url in start) _identity(url)};
    final pages = <InspectedPage>[];
    while (queue.isNotEmpty && pages.length < limit) {
      final url = queue.removeAt(0);
      final InspectedPage page;
      try {
        page = await fetch(url);
      } on InspectException catch (error) {
        // The pages that were asked for by name must work.
        if (start.contains(url)) rethrow;
        onSkip?.call(url, error.message.split('\n').first);
        continue;
      }
      pages.add(page);
      for (final link in page.links) {
        if (seen.add(_identity(link))) queue.add(link);
      }
    }
    return pages;
  }

  static String _identity(Uri url) => url.replace(fragment: '').toString().replaceFirst(RegExp(r'#$'), '');

  static final RegExp _anchor = RegExp(r'''<a\b[^>]*\bhref\s*=\s*("([^"]*)"|'([^']*)')''', caseSensitive: false);
  static final RegExp _asset = RegExp(r'\.(png|jpe?g|gif|svg|webp|ico|css|js|json|xml|pdf|zip|txt|woff2?|ttf)$');

  /// Same-origin page links in [html].
  static List<Uri> _links(String html, Uri base) {
    final links = <Uri>[];
    final seen = <String>{};
    for (final match in _anchor.allMatches(html)) {
      final href = match.group(2) ?? match.group(3) ?? '';
      if (href.isEmpty || href.startsWith('#')) continue;
      final Uri resolved;
      try {
        resolved = base.resolve(href.replaceAll('&amp;', '&'));
      } on FormatException {
        continue;
      }
      if (!resolved.isScheme('http') && !resolved.isScheme('https')) continue;
      if (resolved.host != base.host || resolved.port != base.port) continue;
      if (_asset.hasMatch(resolved.path.toLowerCase())) continue;
      final clean = resolved.replace(fragment: '');
      final key = _identity(clean);
      if (seen.add(key)) links.add(Uri.parse(key));
    }
    return links;
  }
}
