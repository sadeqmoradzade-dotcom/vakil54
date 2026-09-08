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

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const String baseUrl = 'https://rc.majlis.ir';
  static const String ajaxUrl = '$baseUrl/fa/search/searchAjax';

  final TextEditingController searchController = TextEditingController();

  late final WebViewController webController;

  bool searching = false;
  bool webReady = false;

  String status = 'در حال اتصال به سامانه مجلس...';
  List<LawItem> items = <LawItem>[];

  @override
  void initState() {
    super.initState();

    webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
              if (!webReady) {
                status = 'اتصال به سامانه مجلس برقرار نشد';
              }
            });
          },
        ),
      )
      ..loadRequest(
        Uri.parse('$baseUrl/fa/law/search'),
      );
  }

  Future<void> search() async {
    final String term = searchController.text.trim();

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

    if (!webReady) {
      setState(() {
        status = 'سامانه هنوز در حال آماده‌سازی است...';
      });
      return;
    }

    setState(() {
      searching = true;
      status = 'در حال جستجو...';
      items = <LawItem>[];
    });

    try {
      final String escapedTerm = jsonEncode(term);
      final String escapedAjaxUrl = jsonEncode(ajaxUrl);

      final Object? result =
          await webController.runJavaScriptReturningResult(
        '''
(async () => {
  try {
    const url = $escapedAjaxUrl +
      '?q=' + encodeURIComponent($escapedTerm) +
      '&report=0' +
      '&news=0' +
      '&legal=0' +
      '&agenda=0' +
      '&law=1';

    const response = await fetch(url, {
      method: 'GET',
      credentials: 'same-origin',
      headers: {
        'Accept': 'application/json, text/plain, */*'
      }
    });

    const text = await response.text();

    return JSON.stringify({
      ok: response.ok,
      status: response.status,
      body: text
    });
  } catch (e) {
    return JSON.stringify({
      ok: false,
      error: String(e)
    });
  }
})()
''',
      );

      String resultText = result?.toString() ?? '';

      if (resultText.startsWith('"') && resultText.endsWith('"')) {
        try {
          resultText = jsonDecode(resultText) as String;
        } catch (_) {}
      }

      final dynamic wrapper = jsonDecode(resultText);

      if (wrapper is! Map) {
        throw Exception('پاسخ نامعتبر از سامانه');
      }

      if (wrapper['ok'] != true) {
        final String error =
            wrapper['error']?.toString() ??
            'خطا در دریافت اطلاعات';

        throw Exception(error);
      }

      final String body = wrapper['body']?.toString() ?? '';

      if (body.isEmpty) {
        throw Exception('پاسخ خالی از سامانه دریافت شد');
      }

      final dynamic decoded = jsonDecode(body);

      final List<LawItem> parsed = <LawItem>[];

      if (decoded is Map && decoded['result'] is List) {
        final List<dynamic> results = decoded['result'] as List<dynamic>;

        for (final dynamic entry in results) {
          if (entry is! Map) continue;

          final String title =
              entry['title']?.toString().trim() ?? '';

          final String link =
              entry['link']?.toString().trim() ?? '';

          final String date =
              entry['date_fa']?.toString().trim() ?? '';

          final String type =
              entry['tbl_value']?.toString().trim() ?? '';

          if (title.isEmpty || link.isEmpty) {
            continue;
          }

          String fullLink = link;

          if (fullLink.startsWith('/')) {
            fullLink = '$baseUrl$fullLink';
          }

          parsed.add(
            LawItem(
              title: title,
              date: date,
              type: type,
              link: fullLink,
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        items = parsed;
        status = parsed.isEmpty
            ? 'برای «$term» نتیجه‌ای پیدا نشد'
            : '${parsed.length} نتیجه پیدا شد';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        items = <LawItem>[];
        status = 'خطا در جستجو\n$error';
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
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                        hintText: 'مثلاً مهندس ناظر',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: searching || !webReady
                              ? null
                              : search,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        status,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Expanded(
                    child: searching
                        ? const Center(
                            child: CircularProgressIndicator(),
                          )
                        : items.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    status,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: items.length,
                                separatorBuilder: (
                                  context,
                                  index,
                                ) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final LawItem item = items[index];

                                  return Card(
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      title: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding:
                                            const EdgeInsets.only(top: 8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (item.date.isNotEmpty)
                                              Text(
                                                'تاریخ: ${item.date}',
                                              ),
                                            if (item.type.isNotEmpty)
                                              Text(
                                                'نوع: ${item.type}',
                                              ),
                                          ],
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_left,
                                      ),
                                      onTap: () => openLaw(item),
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
  State<LawPage> createState() => _LawPageState();
}

class _LawPageState extends State<LawPage> {
  late final WebViewController controller;
  bool loading = true;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(
              controller: controller,
            ),
            if (loading)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
