import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

final String baseUrl = 'http://localhost:5001/images/';

Future<List<Map<String, String>>> loadCsvData() async {
  final raw = await rootBundle.loadString('assets/results.csv');
  final rows = const CsvToListConverter(eol: '\n').convert(raw);
  final headers = rows.first.map((e) => e.toString()).toList();
  return rows
      .skip(1)
      .map((row) => {
            for (int i = 0; i < headers.length; i++)
              headers[i]: row[i].toString()
          })
      .toList();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raspberry Pi File Uploader',
      debugShowCheckedModeBanner: false,
      home: FileUploadPage(),
    );
  }
}

class FileUploadPage extends StatefulWidget {
  const FileUploadPage({super.key});
  @override
  FileUploadPageState createState() => FileUploadPageState();
}

class FileUploadPageState extends State<FileUploadPage> {
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edge Forestry',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 24)),
        backgroundColor: Colors.green[700],
        centerTitle: true,
        elevation: 4,
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              width: double.infinity,
              height: 400,
            ),
          ),
          Column(
            children: [
              const Spacer(flex: 1),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Upload Files',
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w600,
                          color: Color.fromARGB(255, 0, 47, 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Click to scan pictures from today and analyze them through our model.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Color.fromARGB(255, 0, 47, 10),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            _statusMessage = null;
                          });

                          BuildContext? dialogContext;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext context) {
                              dialogContext = context;
                              return const Center(child: CircularProgressIndicator(color: Colors.green));
                            },
                          );

                          try {
                            final uri = Uri.parse('http://localhost:5001/scan-and-process');
                            final response = await http.get(uri);

                            if (!mounted) return;

                            if (dialogContext != null) {
                              Navigator.of(dialogContext!).pop();
                            }

                            if (response.statusCode == 200) {
                              final data = jsonDecode(response.body);
                              final List allResults = data['all_results'];
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => ResultsPage(results: allResults)),
                              );
                            } else {
                              setState(() {
                                _statusMessage = 'Error ${response.statusCode}: ${response.body}';
                              });
                            }
                          } catch (e) {
                            if (dialogContext != null) {
                              Navigator.of(dialogContext!).pop();
                            }
                            setState(() {
                              _statusMessage = 'Request failed: $e';
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 6,
                        ),
                        child: const Text(
                          'Scan & Analyze',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 20),
                        Text(_statusMessage!,
                            style: const TextStyle(color: Colors.black87), textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ],
      ),
    );
  }
}

class ResultsPage extends StatefulWidget {
  final List results;
  const ResultsPage({super.key, required this.results});

  @override
  ResultsPageState createState() => ResultsPageState();
}

class ResultsPageState extends State<ResultsPage> {
  static const int pageSize = 20;
  int currentPage = 0;
  String selectedFilter = 'All';
  late final List<String> filterOptions;
late Map<String, String?> filterMap;

@override
void initState() {
  super.initState();
  filterMap = {
    'All': null, // special case: show all
    'No Condition: <70%': 'DOES NOT HAVE OAK WILT',
    'Possibility: 70-90%': 'POSSIBILITY OF OAK WILT',
    'High Chance: 90-99.5%': "THERE'S A HIGH CHANCE OF OAK WILT",
    'Has Condition: >99.5%': 'THIS PICTURE HAS OAK WILT',
  };

  selectedFilter = 'All';
}

  List get filteredResults {
    final selectedValue = filterMap[selectedFilter];

    if (selectedValue == null) return widget.results;

    return widget.results.where((item) {
      return item['classification'] == selectedValue;
    }).toList();
  }


  List get currentPageItems {
    final results = filteredResults;
    final start = currentPage * pageSize;
    final end = (start + pageSize) > results.length ? results.length : (start + pageSize);
    return results.sublist(start, end);
  }

  int get totalPages => (filteredResults.length / pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edge Forestry',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 24),
        ),
        backgroundColor: Colors.green[700],
        centerTitle: true,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Center(
              child: Text(
                'Results',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: Color.fromARGB(255, 0, 47, 10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: selectedFilter,
              isExpanded: true,
              items: filterMap.keys.map((label) {
                return DropdownMenuItem<String>(
                  value: label,
                  child: Text(label),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedFilter = value!;
                  currentPage = 0;
                });
              },
            ),
            const SizedBox(height: 6),
            Text('${filteredResults.length} result(s)'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: filteredResults.length,
                itemBuilder: (context, index) {
                  final item = filteredResults[index];
                  final imageUrl = '$baseUrl${item['filename']}';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: GestureDetector(
                        onTap: () async {
                          if (await canLaunchUrl(Uri.parse(imageUrl))) {
                            await launchUrl(Uri.parse(imageUrl));
                          } else {
                            throw 'Could not launch $imageUrl';
                          }
                        },
                        child: Text(
                          item['filename'],
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      subtitle: Text(
                        '${item['classification']} - ${item['prediction']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 0, 47, 10),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: currentPage > 0 ? () => setState(() => currentPage--) : null,
                  child: const Text('Previous'),
                ),
                Text('Page ${currentPage + 1} of $totalPages'),
                ElevatedButton(
                  onPressed: currentPage < totalPages - 1 ? () => setState(() => currentPage++) : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
