import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:io';

// Constants
class AppConstants {
  static const String baseUrl = 'http://localhost:5001';
  static const int pageSize = 20;
  static const String appTitle = 'Edge Forestry';
  static const Color primaryGreen = Color.fromARGB(255, 0, 47, 10);
  static const Color darkGreen = Color(0xFF388E3C);
}

// Models
class ImageResult {
  final String filename;
  final String classification;
  final String prediction;
  final String? latitude;
  final String? longitude;

  ImageResult({
    required this.filename,
    required this.classification,
    required this.prediction,
    this.latitude,
    this.longitude,
  });

  factory ImageResult.fromJson(Map<String, dynamic> json) {
    return ImageResult(
      filename: json['filename']?.toString() ?? '',
      classification: json['classification']?.toString() ?? '',
      prediction: json['prediction']?.toString() ?? '',
      latitude: json['latitude']?.toString(),
      longitude: json['longitude']?.toString(),
    );
  }

  bool get hasGpsData => latitude != null && longitude != null;
}

// Services
class ApiService {
  // scan and process server- contacts backend and awaits results to parse and output
  static Future<List<ImageResult>> scanAndProcess() async {
    final uri = Uri.parse('${AppConstants.baseUrl}/scan-and-process');
    final response = await http.get(uri);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List allResults = data['all_results'];
      return allResults.map((item) => ImageResult.fromJson(item)).toList();
    } else {
      throw HttpException('Error ${response.statusCode}: ${response.body}');
    }
  }

  // retrieves image url for image popups
  static String getImageUrl(String filename) {
    final encodedFilename = Uri.encodeComponent(filename);
    return '${AppConstants.baseUrl}/images/$encodedFilename';
  }

  static String getAlternativeImageUrl(String filename) {
    final encodedFilename = Uri.encodeComponent(filename);
    return '${AppConstants.baseUrl}/get-image?name=$encodedFilename';
  }
}

// converts CSV data to a list in order to be parsed into result cards
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  // base page design 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
          elevation: 4,
          centerTitle: true,
        ),
      ),
      home: const FileUploadPage(),
    );
  }
}

class FileUploadPage extends StatefulWidget {
  const FileUploadPage({super.key});
  
  @override
  FileUploadPageState createState() => FileUploadPageState();
}

class FileUploadPageState extends State<FileUploadPage> {
  String? _statusMessage; // feedback output
  bool _isLoading = false;

  // calls scan and process to connect to backend
  Future<void> _scanAndAnalyze() async {
    setState(() {
      _statusMessage = null;
      _isLoading = true;
    });

    try {
      final results = await ApiService.scanAndProcess();
      
      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsPage(results: results),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = e is HttpException ? e.message : 'Request failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // home page build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          AppConstants.appTitle,
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 24),
        ),
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background image
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              width: double.infinity,
              height: 400,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
          
          // Main content
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
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Click to scan pictures from today and analyze them through our model.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: AppConstants.primaryGreen,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // error messages displayed- full stack connection complications
                      if (_statusMessage != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(
                            _statusMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      // Main scan button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _scanAndAnalyze,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 6,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Scan & Analyze',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      
                      const SizedBox(height: 16),
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
  final List<ImageResult> results;
  const ResultsPage({super.key, required this.results});

  @override
  ResultsPageState createState() => ResultsPageState();
}

class ResultsPageState extends State<ResultsPage> {
  int currentPage = 0;
  String selectedFilter = 'All';
  
  // maps displayed categories to proper filtering
  static const Map<String, String?> filterMap = {
    'All': null,
    'No Condition: <70%': 'DOES NOT HAVE OAK WILT',
    'Possibility: 70-90%': 'POSSIBILITY OF OAK WILT',
    'High Chance: 90-99.5%': "THERE'S A HIGH CHANCE OF OAK WILT",
    'Has Condition: >99.5%': 'THIS PICTURE HAS OAK WILT',
  };

  // filters results to display desired category
  List<ImageResult> get filteredResults {
    final selectedValue = filterMap[selectedFilter];
    if (selectedValue == null) return widget.results;
    return widget.results.where((item) => item.classification == selectedValue).toList();
  }

  // determines amount of cards on a page
  List<ImageResult> get currentPageItems {
    final results = filteredResults;
    final start = currentPage * AppConstants.pageSize;
    final end = (start + AppConstants.pageSize) > results.length 
        ? results.length 
        : (start + AppConstants.pageSize);
    return results.sublist(start, end);
  }

  int get totalPages => (filteredResults.length / AppConstants.pageSize).ceil();

  void _showImagePopup(BuildContext context, ImageResult result) {
  final imageUrl = ApiService.getImageUrl(result.filename);
  final alternativeUrl = ApiService.getAlternativeImageUrl(result.filename);

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Center(
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  cacheWidth: 400, 
                  cacheHeight: 400,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Image.network(
                      fallbackUrl,
                      fit: BoxFit.contain,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildImageWidget(String primaryUrl, String alternativeUrl, String filename) {
    return Image.network(
      primaryUrl,
      fit: BoxFit.contain,
      cacheWidth: 400, 
      cacheHeight: 400,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          height: 200,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.green[700],
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        // Try alternative URL
        return Image.network(
          alternativeUrl,
          fit: BoxFit.contain,
          cacheWidth: 400, 
          cacheHeight: 400,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              height: 200,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.green),
              ),
            );
          },
          errorBuilder: (context, altError, altStackTrace) {
            return Container(
              height: 200,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Image failed to load',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'File: $filename',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

 
            


  
         

   
