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
  static const String ajaxUrl =
      '$baseUrl/fa/search/searchAjax';

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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (!mounted) return;

            if (!searching) {
              setState(() {
                status =
                    'عبارت موردنظر را وارد کنید';
              });
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          '$baseUrl/fa/law/search',
        ),
      );
  }

  Future<List<LawItem>> getResults(
    String term,
  ) async {
    final String encoded =
        Uri.encodeQueryComponent(term);

    final String url =
        '$ajaxUrl'
        '?q=$encoded'
        '&report=0'
        '&news=0'
        '&legal=0'
        '&agenda=0'
        '&law=1';

    await webController.loadRequest(
      Uri.parse(url),
    );

    await Future<void>.delayed(
      const Duration(seconds: 3),
    );

    final Object? jsResult =
        await webController
            .runJavaScriptReturningResult(
      '''
(() => {
  try {
    const body = document.body;

    if (!body) {
      return "";
    }

    return body.innerText ||
           body.textContent ||
           "";
  } catch (e) {
    return "";
  }
})()
''',
    );

    String text =
        jsResult?.toString() ?? '';

    if (text.startsWith('"') &&
        text.endsWith('"')) {
      try {
        text = jsonDecode(text) as String;
      } catch (_) {}
    }

    text = text.trim();

    if (text.isEmpty) {
      throw Exception(
        'پاسخ خالی از سامانه',
      );
    }

    /*
     * حالت اول:
     * پاسخ مستقیماً JSON است.
     */
    try {
      final dynamic data =
          jsonDecode(text);

      return _parseJson(data);
    } catch (_) {
      // ادامه می‌دهیم؛ ممکن است متن JSON
      // داخل <pre> یا متن صفحه باشد.
    }

    /*
     * حالت دوم:
     * پیدا کردن اولین بلوک JSON
     * داخل پاسخ.
     */
    final int jsonStart =
        text.indexOf('{');

    final int jsonEnd =
        text.lastIndexOf('}');

    if (jsonStart >= 0 &&
        jsonEnd > jsonStart) {
      final String jsonPart =
          text.substring(
        jsonStart,
        jsonEnd + 1,
      );

      try {
        final dynamic data =
            jsonDecode(jsonPart);

        return _parseJson(data);
      } catch (_) {}
    }

    /*
     * حالت سوم:
     * پاسخ ممکن است به شکل جدول
     * متنی/Markdown برگشته باشد.
     */
    return _parseTextResponse(text);
  }

  List<LawItem> _parseJson(
    dynamic data,
  ) {
    final List<LawItem> output =
        <LawItem>[];

    if (data is! Map) {
      return output;
    }

    final dynamic result =
        data['result'];

    if (result is! List) {
      return output;
    }

    for (final dynamic row in result) {
      if (row is! Map) {
        continue;
      }

      final String title =
          row['pure_title']?.toString().trim() ??
              row['title']?.toString().trim() ??
              '';

      String link =
          row['link']?.toString().trim() ?? '';

      final String date =
          row['date_fa']?.toString().trim() ?? '';

      final String type =
          row['tbl_value']?.toString().trim() ?? '';

      if (title.isEmpty ||
          link.isEmpty) {
        continue;
      }

      /*
       * اگر لینک به شکل Markdown آمده باشد:
       * [https://...](https://...)
       */
      final RegExp markdownLink =
          RegExp(
        r'\]\((https?://[^)\s]+)',
      );

      final Match? match =
          markdownLink.firstMatch(link);

      if (match != null) {
        link =
            match.group(1) ?? link;
      }

      if (link.startsWith('/')) {
        link = '$baseUrl$link';
      }

      output.add(
        LawItem(
          title: _cleanHtml(title),
          date: date,
          type: type,
          link: link,
        ),
      );
    }

    return output;
  }

  List<LawItem> _parseTextResponse(
    String text,
  ) {
    final List<LawItem> output =
        <LawItem>[];

    /*
     * پاسخ تست واقعی سایت شامل خطوطی
     * مثل:
     *
     * title | ...
     * date_fa | ...
     * link | ...
     *
     * است. این parser تلاش می‌کند
     * از همان متن اطلاعات را بردارد.
     */

    final RegExp blockRegex = RegExp(
      r'oid\s*\|.*?\n'
      r'title\s*\|\s*(.*?)\n'
      r'date\s*\|\s*(.*?)\n'
      r'tbl_value\s*\|\s*(.*?)\n'
      r'tbl_index\s*\|\s*(.*?)\n'
      r'pure_title\s*\|\s*(.*?)\n'
      r'date_fa\s*\|\s*"?(.*?)"?\n'
      r'link\s*\|\s*.*?https?://rc\.majlis\.ir/fa/[^)\s]+',
      multiLine: true,
      dotAll: true,
    );

    for (final Match match
        in blockRegex.allMatches(text)) {
      String title =
          match.group(6)?.trim() ?? '';

      final String date =
          match.group(7)?.trim() ?? '';

      String fullBlock =
          match.group(0) ?? '';

      final RegExp linkRegex = RegExp(
        r'https?://rc\.majlis\.ir/fa/(?:law|news|legal|agenda)/show/\d+',
      );

      final Match? linkMatch =
          linkRegex.firstMatch(fullBlock);

      String link =
          linkMatch?.group(0) ?? '';

      title = _cleanHtml(
        _stripQuotes(title),
      );

      if (title.isEmpty ||
          link.isEmpty) {
        continue;
      }

      output.add(
        LawItem(
          title: title,
          date: date.replaceAll('"', ''),
          type: 'قانون',
          link: link,
        ),
      );
    }

    return output;
  }

  String _stripQuotes(String value) {
    String result = value.trim();

    if (result.startsWith("'") &&
        result.endsWith("'")) {
      result =
          result.substring(
        1,
        result.length - 1,
      );
    }

    if (result.startsWith('"') &&
        result.endsWith('"')) {
      result =
          result.substring(
        1,
        result.length - 1,
      );
    }

    return result;
  }

  String _cleanHtml(String value) {
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
        items = <LawItem>[];
        status =
            'عبارت جستجو را وارد کنید';
      });
      return;
    }

    if (term.length < 2) {
      setState(() {
        items = <LawItem>[];
        status =
            'حداقل ۲ حرف وارد کنید';
      });
      return;
    }

    setState(() {
      searching = true;
      items = <LawItem>[];
      status =
          'در حال جستجو برای «$term»...';
    });

    try {
      final List<LawItem> results =
          await getResults(term);

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
        items = <LawItem>[];
        status =
            'خطا در دریافت اطلاعات\n$e';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        searching = false;
      });
    }
  }

  void openLaw(LawItem item) {
    Navigator.push(
      context,
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
                  child:
                      WebViewWidget(
                    controller:
                        webController,
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
                        const EdgeInsets.all(
                      16,
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
                    height: 10,
                  ),

                  Expanded(
                    child: searching
                        ? const Center(
                            child:
                                CircularProgressIndicator(),
                          )
                        : items.isEmpty
                            ? Center(
                                child:
                                    Padding(
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
                                  context,
                                  index,
                                ) =>
                                        const SizedBox(
                                  height: 8,
                                ),
                                itemBuilder:
                                    (
                                  context,
                                  index,
                                ) {
                                  final LawItem
                                      item =
                                      items[index];

                                  return Card(
                                    elevation: 2,
                                    child:
                                        ListTile(
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
                                            const EdgeInsets.only(
                                          top: 6,
                                        ),
                                        child:
                                            Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (item.date
                                                .isNotEmpty)
                                              Text(
                                                'تاریخ: ${item.date}',
                                              ),
                                            if (item.type
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
                                          () =>
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

class _LawPageState
    extends State<LawPage> {
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
