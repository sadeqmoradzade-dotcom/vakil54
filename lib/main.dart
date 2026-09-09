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
  final String link;

  const LawItem({
    required this.title,
    required this.date,
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

  final TextEditingController searchController =
      TextEditingController();

  late final WebViewController webController;

  bool pageReady = false;
  bool searching = false;

  String status = 'در حال آماده‌سازی...';

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
              pageReady = true;

              if (!searching) {
                status = 'عبارت موردنظر را وارد کنید';
              }
            });
          },

          // عمداً چیزی اینجا نمایش نمی‌دهیم.
          // خطای یک فایل جانبی سایت نباید کل برنامه را خطادار کند.
          onWebResourceError: (WebResourceError error) {
            // ignore
          },
        ),
      )
      ..loadRequest(
        Uri.parse('$baseUrl/fa/law/search'),
      );
  }

  Future<List<LawItem>> readResults() async {
    final Object? result =
        await webController.runJavaScriptReturningResult(
      '''
(() => {
  try {
    const links = Array.from(
      document.querySelectorAll(
        'a[href*="/fa/law/show/"]'
      )
    );

    return JSON.stringify(
      links.slice(0, 100).map((a) => {
        const row =
          a.closest("tr") ||
          a.closest(".card") ||
          a.parentElement;

        const text = row
          ? (
              row.innerText ||
              row.textContent ||
              ""
            ).replace(/\\\\s+/g, " ").trim()
          : "";

        return {
          title:
            (
              a.innerText ||
              a.textContent ||
              ""
            ).trim(),

          link:
            a.href || "",

          text: text
        };
      })
    );
  } catch (e) {
    return "[]";
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
      final dynamic decoded = jsonDecode(text);

      if (decoded is! List) {
        return <LawItem>[];
      }

      final List<LawItem> resultItems =
          <LawItem>[];

      for (final dynamic row in decoded) {
        if (row is! Map) {
          continue;
        }

        final String title =
            row['title']?.toString().trim() ?? '';

        String link =
            row['link']?.toString().trim() ?? '';

        final String rowText =
            row['text']?.toString() ?? '';

        if (title.isEmpty || link.isEmpty) {
          continue;
        }

        if (link.startsWith('/')) {
          link = '$baseUrl$link';
        }

        final Match? dateMatch = RegExp(
          r'1\d{3}/\d{1,2}/\d{1,2}',
        ).firstMatch(rowText);

        resultItems.add(
          LawItem(
            title: title,
            date: dateMatch?.group(0) ?? '',
            link: link,
          ),
        );
      }

      return resultItems;
    } catch (_) {
      return <LawItem>[];
    }
  }

  Future<void> search() async {
    final String term =
        searchController.text.trim();

    if (term.isEmpty) {
      setState(() {
        status = 'عبارت جستجو را وارد کنید';
        items = <LawItem>[];
      });
      return;
    }

    if (term.length < 2) {
      setState(() {
        status = 'حداقل ۲ حرف وارد کنید';
        items = <LawItem>[];
      });
      return;
    }

    setState(() {
      searching = true;
      items = <LawItem>[];
      status = 'در حال جستجوی «$term»...';
    });

    try {
      final String encoded =
          Uri.encodeQueryComponent(term);

      final String url =
          '$baseUrl/fa/law/search'
          '?keyword=$encoded'
          '&only_title=0'
          '&lu_approve_reference='
          '&from_app_date='
          '&to_app_date='
          '&from_communique_date='
          '&to_communique_date='
          '&communique_no='
          '&lu_parliament_year='
          '&lu_biannual='
          '&o='
          '&ot=d';

      await webController.loadRequest(
        Uri.parse(url),
      );

      // تا 20 ثانیه برای ظاهر شدن نتایج صبر می‌کنیم.
      List<LawItem> results =
          <LawItem>[];

      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(
          const Duration(seconds: 1),
        );

        results = await readResults();

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
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status =
            'خطا در جستجو\n$e';
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
              color: Theme.of(context)
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
                      onSubmitted: (_) => search(),
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
                                    child:
                                        ListTile(
                                      title:
                                          Text(
                                        item.title,
                                        style:
                                            const TextStyle(
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      ),
                                      subtitle:
                                          item.date.isEmpty
                                              ? null
                                              : Text(
                                                  'تاریخ: ${item.date}',
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
            // خطاهای منابع جانبی را نادیده می‌گیریم.
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
          title: const Text('متن قانون'),
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
