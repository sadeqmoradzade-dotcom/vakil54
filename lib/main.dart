import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VakilApp());
}

class VakilApp extends StatelessWidget {
  const VakilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'وکیل',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const SearchPage(),
    );
  }
}

class LawItem {
  final String title;
  final String date;
  final String type;
  final String link;

  const LawItem({
    required this.title,
    required this.date,
    required this.type,
    required this.link,
  });
}

class _SearchResponse {
  final int statusCode;
  final String body;
  final String? error;

  const _SearchResponse({
    required this.statusCode,
    required this.body,
    this.error,
  });
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const String baseUrl = 'https://rc.majlis.ir';
  static const String searchPageUrl = '$baseUrl/fa/law/search';
  static const String fallbackAjaxUrl =
      '$baseUrl/fa/search/searchAjax';

  final TextEditingController searchController =
      TextEditingController();

  late final WebViewController webController;

  Completer<_SearchResponse>? _pendingSearch;
  int _requestId = 0;

  bool searching = false;
  bool pageReady = false;

  String status = 'در حال اتصال به سامانه مجلس...';
  List<LawItem> items = <LawItem>[];

  @override
  void initState() {
    super.initState();

    webController = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'VakilSearch',
        onMessageReceived: _onSearchMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (!mounted) return;

            setState(() {
              pageReady = true;

              if (!searching) {
                status = 'عبارت موردنظر را وارد کنید';
              }
            });
          },
          onWebResourceError: (WebResourceError error) {
            // خطاهای منابع جانبی سایت باعث خطای کلی نمی‌شوند.
          },
        ),
      )
      ..loadRequest(
        Uri.parse(searchPageUrl),
      );
  }

  void _onSearchMessage(
    JavaScriptMessage message,
  ) {
    try {
      final dynamic decoded =
          jsonDecode(message.message);

      if (decoded is! Map) return;

      final int id =
          int.tryParse(
                decoded['id']?.toString() ?? '',
              ) ??
              -1;

      if (id != _requestId) return;

      final int statusCode =
          int.tryParse(
                decoded['status']?.toString() ?? '0',
              ) ??
              0;

      final String body =
          decoded['body']?.toString() ?? '';

      final String? error =
          decoded['error']?.toString();

      final Completer<_SearchResponse>? completer =
          _pendingSearch;

      if (completer == null ||
          completer.isCompleted) {
        return;
      }

      completer.complete(
        _SearchResponse(
          statusCode: statusCode,
          body: body,
          error: error,
        ),
      );
    } catch (_) {
      // پاسخ خراب یا قدیمی نادیده گرفته می‌شود.
    }
  }

  Future<bool> _waitForSearchPage({
    int timeoutSeconds = 20,
  }) async {
    for (int i = 0;
        i < timeoutSeconds;
        i++) {
      try {
        final Object? result =
            await webController
                .runJavaScriptReturningResult(
          '''
(() => JSON.stringify({
  ready: document.readyState,
  url: location.href,
  ajax: (() => {
    const el =
      document.getElementById('searchAjax');

    return el
      ? (el.value || '')
      : '';
  })(),
  title: document.title || ''
}))()
''',
        );

        String text =
            result?.toString() ?? '{}';

        if (text.startsWith('"') &&
            text.endsWith('"')) {
          try {
            text = jsonDecode(text) as String;
          } catch (_) {}
        }

        final dynamic data =
            jsonDecode(text);

        if (data is Map) {
          final String ajax =
              data['ajax']?.toString() ?? '';

          final String url =
              data['url']?.toString() ?? '';

          final String ready =
              data['ready']?.toString() ?? '';

          if (ready == 'complete' &&
              ajax.isNotEmpty &&
              url.contains(
                '/fa/law/search',
              )) {
            return true;
          }
        }
      } catch (_) {}

      await Future<void>.delayed(
        const Duration(seconds: 1),
      );
    }

    return false;
  }

  Future<_SearchResponse>
      _requestSearchInWebView(
    String term,
  ) async {
    final int id = ++_requestId;

    final Completer<_SearchResponse>
        completer =
        Completer<_SearchResponse>();

    _pendingSearch = completer;

    final String termJson =
        jsonEncode(term);

    final String idJson =
        jsonEncode(id);

    final String fallbackJson =
        jsonEncode(fallbackAjaxUrl);

    await webController.runJavaScript(
      '''
(() => {
  try {
    const searchTerm =
      $termJson;

    const requestId =
      $idJson;

    const fallback =
      $fallbackJson;

    const input =
      document.getElementById(
        'searchAjax'
      );

    let endpoint =
      input
        ? (input.value || '')
        : '';

    if (!endpoint) {
      endpoint = fallback;
    }

    try {
      endpoint =
        new URL(
          endpoint,
          location.origin
        ).href;
    } catch (_) {}

    const xhr =
      new XMLHttpRequest();

    xhr.open(
      'GET',
      endpoint +
        '?q=' +
        encodeURIComponent(
          searchTerm
        ) +
        '&report=0' +
        '&news=0' +
        '&legal=0' +
        '&agenda=0' +
        '&law=1',
      true
    );

    xhr.withCredentials = true;

    xhr.setRequestHeader(
      'Accept',
      'application/json, text/plain, */*'
    );

    xhr.setRequestHeader(
      'X-Requested-With',
      'XMLHttpRequest'
    );

    const send =
      (payload) => {
        try {
          window.VakilSearch.postMessage(
            JSON.stringify(
              payload
            )
          );
        } catch (_) {}
      };

    xhr.onreadystatechange =
      function() {
        if (
          xhr.readyState === 4
        ) {
          send({
            id: requestId,
            status:
              xhr.status || 0,
            body:
              xhr.responseText ||
              '',
            error:
              xhr.status === 0
                ? 'XHR status 0'
                : null
          });
        }
      };

    xhr.onerror =
      function() {
        send({
          id: requestId,
          status: 0,
          body: '',
          error:
            'XHR_NETWORK_ERROR'
        });
      };

    xhr.ontimeout =
      function() {
        send({
          id: requestId,
          status: 0,
          body: '',
          error:
            'XHR_TIMEOUT'
        });
      };

    xhr.timeout = 20000;

    xhr.send();
  } catch (e) {
    window.VakilSearch.postMessage(
      JSON.stringify({
        id: $idJson,
        status: 0,
        body: '',
        error: String(e)
      })
    );
  }
})();
''',
    );

    try {
      return await completer.future.timeout(
        const Duration(seconds: 25),
      );
    } on TimeoutException {
      if (!completer.isCompleted) {
        completer.complete(
          const _SearchResponse(
            statusCode: 0,
            body: '',
            error:
                'WEBVIEW_SEARCH_TIMEOUT',
          ),
        );
      }

      return completer.future;
    } finally {
      if (identical(
        _pendingSearch,
        completer,
      )) {
        _pendingSearch = null;
      }
    }
  }

  List<LawItem> _parseResponse(
    String body,
  ) {
    String text = body.trim();

    if (text.isEmpty) {
      return <LawItem>[];
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(text);
    } catch (_) {
      final int start =
          text.indexOf('{');

      final int end =
          text.lastIndexOf('}');

      if (start >= 0 &&
          end > start) {
        try {
          decoded = jsonDecode(
            text.substring(
              start,
              end + 1,
            ),
          );
        } catch (_) {
          return <LawItem>[];
        }
      } else {
        return <LawItem>[];
      }
    }

    if (decoded is! Map ||
        decoded['result'] is! List) {
      return <LawItem>[];
    }

    final List<LawItem> parsed =
        <LawItem>[];

    final Set<String> seenLinks =
        <String>{};

    for (final dynamic row
        in decoded['result'] as List) {
      if (row is! Map) {
        continue;
      }

      String title =
          row['pure_title']
                  ?.toString()
                  .trim() ??
              row['title']
                  ?.toString()
                  .trim() ??
              '';

      String link =
          row['link']
                  ?.toString()
                  .trim() ??
              '';

      final String date =
          row['date_fa']
                  ?.toString()
                  .trim() ??
              '';

      final String type =
          row['tbl_value']
                  ?.toString()
                  .trim() ??
              '';

      title = _cleanHtml(title);
      link = _normalizeLink(link);

      if (title.isEmpty ||
          link.isEmpty ||
          seenLinks.contains(link)) {
        continue;
      }

      seenLinks.add(link);

      parsed.add(
        LawItem(
          title: title,
          date: date,
          type: type,
          link: link,
        ),
      );
    }

    return parsed;
  }

  String _normalizeLink(
    String value,
  ) {
    String link = value.trim();

    final Match? markdown =
        RegExp(
      r'\]\((https?://[^)\s]+)',
    ).firstMatch(link);

    if (markdown != null) {
      link =
          markdown.group(1) ??
              link;
    }

    if (link.startsWith('/')) {
      link =
          '$baseUrl$link';
    }

    return link;
  }

  String _cleanHtml(
    String value,
  ) {
    return value
        .replaceAll(
          RegExp(r'<[^>]*>'),
          '',
        )
        .replaceAll(
          '&nbsp;',
          ' ',
        )
        .replaceAll(
          '&quot;',
          '"',
        )
        .replaceAll(
          '&#39;',
          "'",
        )
        .replaceAll(
          '&amp;',
          '&',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();
  }

  Future<void> search() async {
    final String term =
        searchController.text.trim();

    if (term.isEmpty) {
      setState(() {
        status =
            'عبارت جستجو را وارد کنید';

        items = <LawItem>[];
      });

      return;
    }

    if (term.length < 2) {
      setState(() {
        status =
            'حداقل ۲ حرف وارد کنید';

        items = <LawItem>[];
      });

      return;
    }

    setState(() {
      searching = true;

      items = <LawItem>[];

      status =
          'در حال آماده‌سازی سامانه...';
    });

    try {
      bool ready =
          await _waitForSearchPage();

      if (!ready) {
        await webController.loadRequest(
          Uri.parse(
            searchPageUrl,
          ),
        );

        ready =
            await _waitForSearchPage();
      }

      if (!ready) {
        throw Exception(
          'صفحه جستجوی سامانه در WebView آماده نشد',
        );
      }

      if (mounted) {
        setState(() {
          status =
              'در حال جستجو برای «$term»...';
        });
      }

      final _SearchResponse response =
          await _requestSearchInWebView(
        term,
      );

      debugPrint(
        'Vakil search HTTP status: '
        '${response.statusCode}',
      );

      final String debugBody =
          response.body.length > 4000
              ? response.body.substring(
                  0,
                  4000,
                )
              : response.body;

      debugPrint(
        'Vakil search response: '
        '$debugBody',
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw Exception(
          'سامانه کد HTTP '
          '${response.statusCode} برگرداند'
          '${response.error == null ? '' : '\n${response.error}'}',
        );
      }

      if (response.body.trim().isEmpty) {
        throw Exception(
          'پاسخ خالی از سامانه دریافت شد',
        );
      }

      final List<LawItem> results =
          _parseResponse(
        response.body,
      );

      if (!mounted) return;

      setState(() {
        items = results;

        status = results.isEmpty
            ? 'برای «$term» نتیجه‌ای پیدا نشد'
            : '${results.length} نتیجه پیدا شد';
      });
    } catch (error) {
      debugPrint(
        'Vakil search error: $error',
      );

      if (!mounted) return;

      setState(() {
        items = <LawItem>[];

        status =
            'خطا در جستجو\n$error';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        searching = false;
      });
    }
  }

  void openLaw(
    LawItem item,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LawPage(
          title: item.title,
          url: item.link,
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('وکیل'),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.01,
                  child: WebViewWidget(
                    controller:
                        webController,
                  ),
                ),
              ),
            ),
            Container(
              color: Theme.of(
                context,
              ).scaffoldBackgroundColor,
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      16,
                      18,
                      16,
                      10,
                    ),
                    child: TextField(
                      controller:
                          searchController,
                      textInputAction:
                          TextInputAction.search,
                      onSubmitted:
                          (_) => search(),
                      decoration:
                          InputDecoration(
                        hintText:
                            'مثلاً مهندس',
                        prefixIcon:
                            const Icon(
                          Icons.search,
                        ),
                        suffixIcon:
                            IconButton(
                          tooltip:
                              'جستجو',
                          icon:
                              const Icon(
                            Icons.search,
                          ),
                          onPressed:
                              searching
                                  ? null
                                  : search,
                        ),
                        border:
                            const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    child: Align(
                      alignment:
                          Alignment.centerRight,
                      child: Text(
                        status,
                        textAlign:
                            TextAlign.right,
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Expanded(
                    child: searching
                        ? const Center(
                            child:
                                CircularProgressIndicator(),
                          )
                        : items.isEmpty
                            ? Center(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(
                                    24,
                                  ),
                                  child: Text(
                                    status,
                                    textAlign:
                                        TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.all(
                                  12,
                                ),
                                itemCount:
                                    items.length,
                                separatorBuilder:
                                    (
                                  BuildContext
                                      context,
                                  int index,
                                ) =>
                                        const SizedBox(
                                  height: 8,
                                ),
                                itemBuilder:
                                    (
                                  BuildContext
                                      context,
                                  int index,
                                ) {
                                  final LawItem
                                      item =
                                      items[index];

                                  return Card(
                                    elevation: 2,
                                    child:
                                        ListTile(
                                      contentPadding:
                                          const EdgeInsets
                                              .symmetric(
                                        horizontal:
                                            16,
                                        vertical: 10,
                                      ),
                                      title:
                                          Text(
                                        item.title,
                                        style:
                                            const TextStyle(
                                          fontWeight:
                                              FontWeight.bold,
                                          fontSize:
                                              16,
                                        ),
                                      ),
                                      subtitle:
                                          Padding(
                                        padding:
                                            const EdgeInsets
                                                .only(
                                          top: 8,
                                        ),
                                        child:
                                            Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            if (item
                                                .date
                                                .isNotEmpty)
                                              Text(
                                                'تاریخ: ${item.date}',
                                              ),
                                            if (item
                                                .type
                                                .isNotEmpty)
                                              Text(
                                                'نوع: ${item.type}',
                                              ),
                                          ],
                                        ),
                                      ),
                                      trailing:
                                          const Icon(
                                        Icons
                                            .chevron_left,
                                      ),
                                      onTap:
                                          () => openLaw(
                                        item,
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LawPage extends StatefulWidget {
  final String title;
  final String url;

  const LawPage({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<LawPage> createState() =>
      _LawPageState();
}

class _LawPageState
    extends State<LawPage> {
  late final WebViewController
      controller;

  bool loading = true;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted:
              (String url) {
            if (!mounted) return;

            setState(() {
              loading = true;
            });
          },
          onPageFinished:
              (String url) {
            if (!mounted) return;

            setState(() {
              loading = false;
            });
          },
          onWebResourceError:
              (WebResourceError error) {
            // خطاهای منابع جانبی نادیده گرفته می‌شوند.
          },
        ),
      )
      ..loadRequest(
        Uri.parse(widget.url),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(
              controller:
                  controller,
            ),
            if (loading)
              const Center(
                child:
                    CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
