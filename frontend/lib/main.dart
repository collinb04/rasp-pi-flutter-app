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
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); // fixated screen orientation
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

    // displays images associated with result card values
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      result.filename,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            
            // image container
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: _buildImageWidget(imageUrl, alternativeUrl, result.filename),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(String primaryUrl, String alternativeUrl, String filename) {
    return Image.network(
      primaryUrl,
      fit: BoxFit.contain,
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

  // results page contents(title, filter dropdown, cards, pagination)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          AppConstants.appTitle,
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 24),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Title
            const Center(
              child: Text(
                'Results',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Filter dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: selectedFilter,
                isExpanded: true,
                underline: const SizedBox.shrink(),
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
            ),
            
            const SizedBox(height: 8),
            Text(
              '${filteredResults.length} result(s)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            
            // Results list
            Expanded(
              child: ListView.builder(
                itemCount: currentPageItems.length,
                itemBuilder: (context, index) {
                  final item = currentPageItems[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: InkWell(
                      onTap: () => _showImagePopup(context, item),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Filename
                            Text(
                              item.filename,
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            
                            // Classification and prediction
                            Text(
                              '${item.classification} - ${item.prediction}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primaryGreen,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            
                            // GPS coordinates
                            Row(
                              children: [
                                Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: item.hasGpsData
                                      ? Text(
                                          'Lat: ${item.latitude}, Lon: ${item.longitude}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : Text(
                                          'No GPS data available',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Pagination
            if (totalPages > 1) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: currentPage > 0 
                        ? () => setState(() => currentPage--) 
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Previous'),
                  ),
                  Text(
                    'Page ${currentPage + 1} of $totalPages',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  ElevatedButton(
                    onPressed: currentPage < totalPages - 1 
                        ? () => setState(() => currentPage++) 
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}