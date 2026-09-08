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

  bool searching = false;
  String status = 'عبارت موردنظر را وارد کنید';
  List<LawItem> items = <LawItem>[];

  @override
  void initState() {
    super.initState();

    webController = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..loadRequest(
        Uri.parse('$baseUrl/fa/law/search'),
      );
  }

  Future<void> search() async {
    final String term = searchController.text.trim();

    if (term.length < 3) {
      setState(() {
        status = 'حداقل ۳ حرف وارد کنید';
        items = <LawItem>[];
      });
      return;
    }

    setState(() {
      searching = true;
      status = 'در حال جستجو...';
      items = <LawItem>[];
    });

    try {
      final String encoded =
          Uri.encodeQueryComponent(term);

      final String url =
          '$baseUrl/fa/law/search?keyword=$encoded'
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

      await Future<void>.delayed(
        const Duration(seconds: 3),
      );

      final Object? result =
          await webController.runJavaScriptReturningResult(
        r'''
(() => {
  const links = Array.from(
    document.querySelectorAll('a[href*="/fa/law/show/"]')
  );

  return JSON.stringify(
    links.slice(0, 100).map((a) => {
      const box =
        a.closest("tr") ||
        a.closest(".card") ||
        a.parentElement;

      return {
        title: (a.innerText || a.textContent || "").trim(),
        href: a.href || "",
        text: box
          ? (box.innerText || "").replace(/\s+/g, " ").trim()
          : ""
      };
    })
  );
})()
''',
      );

      String jsonText = result.toString();

      if (jsonText.startsWith('"') &&
          jsonText.endsWith('"')) {
        try {
          jsonText =
              jsonDecode(jsonText) as String;
        } catch (_) {}
      }

      final dynamic decoded =
          jsonDecode(jsonText);

      final List<LawItem> parsed =
          <LawItem>[];

      if (decoded is List) {
        for (final dynamic entry in decoded) {
          if (entry is! Map) continue;

          final String title =
              entry['title']?.toString().trim() ?? '';

          final String href =
              entry['href']?.toString().trim() ?? '';

          final String fullText =
              entry['text']?.toString() ?? '';

          if (title.isEmpty || href.isEmpty) {
            continue;
          }

          final Match? dateMatch =
              RegExp(
                r'1\d{3}/\d{1,2}/\d{1,2}',
              ).firstMatch(fullText);

          parsed.add(
            LawItem(
              title: title,
              date: dateMatch?.group(0) ?? '',
              link: href,
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        items = parsed;
        status = parsed.isEmpty
            ? 'نتیجه‌ای پیدا نشد'
            : '${parsed.length} نتیجه پیدا شد';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        status =
            'خطا در دریافت اطلاعات از سامانه\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          searching = false;
        });
      }
    }
  }

  void openLaw(LawItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LawPage(
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
                  Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: searchController,
                      textInputAction:
                          TextInputAction.search,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                        hintText: 'مثلاً مهندس ناظر',
                        prefixIcon:
                            const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.search,
                          ),
                          onPressed:
                              searching ? null : search,
                        ),
                        border:
                            const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(status),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: searching
                        ? const Center(
                            child:
                                CircularProgressIndicator(),
                          )
                        : items.isEmpty
                            ? Center(
                                child: Text(
                                  status,
                                  textAlign:
                                      TextAlign.center,
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.all(
                                  12,
                                ),
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(
                                  height: 8,
                                ),
                                itemBuilder:
                                    (context, index) {
                                  final LawItem item =
                                      items[index];

                                  return Card(
                                    child: ListTile(
                                      title: Text(
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
                                                  item.date,
                                                ),
                                      trailing:
                                          const Icon(
                                        Icons.chevron_left,
                                      ),
                                      onTap: () =>
                                          openLaw(item),
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

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('متن قانون'),
      ),
      body: WebViewWidget(
        controller: controller,
      ),
    );
  }
}
