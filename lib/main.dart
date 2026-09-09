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

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const String baseUrl = 'https://rc.majlis.ir';
  static const String searchPageUrl =
      '$baseUrl/fa/law/search';

  final TextEditingController searchController =
      TextEditingController();

  late final WebViewController webController;

  bool searching = false;
  bool webReady = false;

  String status = 'در حال اتصال به سامانه مجلس...';

  List<LawItem> items = <LawItem>[];

  @override
  void initState() {
    super.initState();

    webController = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (!mounted) return;

            setState(() {
              webReady = true;

              if (!searching) {
                status = 'عبارت موردنظر را وارد کنید';
              }
            });
          },
          onWebResourceError: (WebResourceError error) {
            if (!mounted) return;

            setState(() {
              status =
                  'ارتباط با سامانه مجلس برقرار نشد';
            });
          },
        ),
      )
      ..loadRequest(
        Uri.parse(searchPageUrl),
      );
  }

  Future<bool> _callSiteSearch(String term) async {
    final String safeTerm = jsonEncode(term);

    try {
      final Object? result =
          await webController.runJavaScriptReturningResult(
        '''
(() => {
  try {
    if (typeof serachInElastic !== 'function') {
      return JSON.stringify({
        "ok": false,
        "error": "تابع جستجوی سایت هنوز بارگذاری نشده است"
      });
    }

    serachInElastic(
      $safeTerm,
      0,
      0,
      1,
      0,
      0
    );

    return JSON.stringify({
      "ok": true
    });
  } catch (e) {
    return JSON.stringify({
      "ok": false,
      "error": String(e)
    });
  }
})()
''',
      );

      String text = result?.toString() ?? '';

      if (text.startsWith('"') &&
          text.endsWith('"')) {
        try {
          text = jsonDecode(text) as String;
        } catch (_) {}
      }

      final dynamic data = jsonDecode(text);

      if (data is Map && data['ok'] == true) {
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<LawItem>> _readResults() async {
    final Object? result =
        await webController.runJavaScriptReturningResult(
      '''
(() => {
  try {
    const rows = Array.from(
      document.querySelectorAll('#result tr')
    );

    return JSON.stringify(
      rows.map((row) => {
        const link =
          row.querySelector('a[href]');

        const cells =
          Array.from(row.querySelectorAll('td'))
            .map(
              (cell) =>
                (cell.innerText ||
                 cell.textContent ||
                 '')
                  .trim()
            );

        return {
          title:
            link
              ? (
                  link.innerText ||
                  link.textContent ||
                  ''
                ).trim()
              : '',

          href:
            link
              ? (link.href || '')
              : '',

          date:
            cells.length > 2
              ? cells[2]
              : '',

          type:
            cells.length > 3
              ? cells[3]
              : ''
        };
      })
    );
  } catch (e) {
    return '[]';
  }
})()
''',
    );

    String text = result?.toString() ?? '[]';

    if (text.startsWith('"') &&
        text.endsWith('"')) {
      try {
        text = jsonDecode(text) as String;
      } catch (_) {}
    }

    try {
      final dynamic decoded =
          jsonDecode(text);

      if (decoded is! List) {
        return <LawItem>[];
      }

      final List<LawItem> parsed =
          <LawItem>[];

      for (final dynamic item in decoded) {
        if (item is! Map) continue;

        final String title =
            item['title']
                    ?.toString()
                    .trim() ??
                '';

        String href =
            item['href']
                    ?.toString()
                    .trim() ??
                '';

        final String date =
            item['date']
                    ?.toString()
                    .trim() ??
                '';

        final String type =
            item['type']
                    ?.toString()
                    .trim() ??
                '';

        if (title.isEmpty || href.isEmpty) {
          continue;
        }

        if (href.startsWith('/')) {
          href = '$baseUrl$href';
        }

        parsed.add(
          LawItem(
            title: title,
            date: date,
            type: type,
            link: href,
          ),
        );
      }

      return parsed;
    } catch (_) {
      return <LawItem>[];
    }
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
      status = 'در حال جستجو...';
    });

    try {
      if (!webReady) {
        await webController.loadRequest(
          Uri.parse(searchPageUrl),
        );

        await Future<void>.delayed(
          const Duration(seconds: 3),
        );
      }

      bool started = false;

      // چند بار تلاش می‌کنیم تا اسکریپت سایت آماده شده باشد.
      for (int attempt = 0; attempt < 5; attempt++) {
        started =
            await _callSiteSearch(term);

        if (started) {
          break;
        }

        await Future<void>.delayed(
          const Duration(seconds: 1),
        );
      }

      if (!started) {
        throw Exception(
          'تابع جستجوی سایت بارگذاری نشد',
        );
      }

      List<LawItem> results =
          <LawItem>[];

      // منتظر می‌مانیم AJAX سایت نتیجه‌ها را
      // داخل #result قرار دهد.
      for (int i = 0; i < 15; i++) {
        await Future<void>.delayed(
          const Duration(seconds: 1),
        );

        results = await _readResults();

        if (results.isNotEmpty) {
          break;
        }
      }

      if (!mounted) return;

      setState(() {
        items = results;

        if (results.isEmpty) {
          status =
              'برای «$term» نتیجه‌ای پیدا نشد';
        } else {
          status =
              '${results.length} نتیجه پیدا شد';
        }
      });
    } catch (error) {
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

  void openLaw(LawItem item) {
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
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
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
                    controller: webController,
                  ),
                ),
              ),
            ),

            Container(
              color:
                  Theme.of(context)
                      .scaffoldBackgroundColor,
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.all(16),
                    child: TextField(
                      controller:
                          searchController,
                      textInputAction:
                          TextInputAction.search,
                      onSubmitted: (_) =>
                          search(),
                      decoration:
                          InputDecoration(
                        hintText:
                            'مثلاً مهندس ناظر',
                        prefixIcon:
                            const Icon(
                          Icons.search,
                        ),
                        suffixIcon:
                            IconButton(
                          icon: const Icon(
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

                  const SizedBox(height: 10),

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
                                    (context, index) =>
                                        const SizedBox(
                                  height: 8,
                                ),
                                itemBuilder:
                                    (context, index) {
                                  final LawItem item =
                                      items[index];

                                  return Card(
                                    elevation: 2,
                                    child:
                                        ListTile(
                                      contentPadding:
                                          const EdgeInsets
                                              .symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      title:
                                          Text(
                                        item.title,
                                        style:
                                            const TextStyle(
                                          fontWeight:
                                              FontWeight.bold,
                                          fontSize: 16,
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
                                      onTap: () =>
                                          openLaw(
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

class _LawPageState extends State<LawPage> {
  late final WebViewController controller;

  bool loading = true;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (!mounted) return;

            setState(() {
              loading = true;
            });
          },
          onPageFinished: (String url) {
            if (!mounted) return;

            setState(() {
              loading = false;
            });
          },
          onWebResourceError:
              (WebResourceError error) {
            if (!mounted) return;

            setState(() {
              loading = false;
            });
          },
        ),
      )
      ..loadRequest(
        Uri.parse(widget.url),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'متن قانون',
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(
              controller: controller,
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
