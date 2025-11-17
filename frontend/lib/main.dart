import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:dropdown_button2/dropdown_button2.dart';


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
  final double prediction;
  final String predictedClass;
  final String classification;
  final String? latitude;
  final String? longitude;

  ImageResult({
    required this.filename,
    required this.prediction,
    required this.predictedClass,
    required this.classification,
    this.latitude,
    this.longitude,
  }); 

  // factory constructor to create an ImageResult List from JSON
factory ImageResult.fromJson(Map<String, dynamic> json) {
  return ImageResult(
    filename: json['filename']?.toString() ?? '',
    prediction: (json['prediction'] is num)
        ? (json['prediction'] as num).toDouble()
        : double.tryParse(json['prediction']?.toString() ?? '0') ?? 0.0,
    predictedClass: json['predictedClass']?.toString() ?? '',
    classification: json['classification']?.toString() ?? '',
    latitude: json['latitude']?.toString(),
    longitude: json['longitude']?.toString(),
  );
}

  bool get hasGpsData => latitude != null && longitude != null;
}

// Services
class ApiService {
  // scan and process server- contacts backend and awaits results to parse and output
  static Future<List<ImageResult>> scanAndProcess(String disease) async {
    final uri = Uri.parse('${AppConstants.baseUrl}/scan-and-process?disease=$disease');
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
  String? _statusMessage;
  bool _isLoading = false;
  String? _selectedDisease;

  // List of diseases to show in dropdown
  final List<String> _diseaseOptions = ['Oak Wilt', 'HWA'];

  Future<void> _scanAndAnalyze() async {
    if (_selectedDisease == null) return;

    setState(() {
      _statusMessage = null;
      _isLoading = true;
    });

    try {
      final results = await ApiService.scanAndProcess(_selectedDisease!);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsPage(
            results: results,
            selectedDisease: _selectedDisease!,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage =
              e is HttpException ? e.message : 'Request failed: $e';
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

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          AppConstants.appTitle,
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 26, fontFamily: 'helvetica'),
        ),
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
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
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
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Choose a disease, click to scan pictures from today, and analyze them through our model.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: AppConstants.primaryGreen,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // Error message
                      if (_statusMessage != null)
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

                        // ---------- Dropdown ----------
                        Container(
                          width: 240, 
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: Colors.green[700]!,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton2<String>(
                              isExpanded: true,
                              hint: const Text(
                                'Select Disease',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600, 
                                  color: AppConstants.primaryGreen,
                                ),
                              ),
                              value: _selectedDisease,
                              items: ['Oak Wilt', 'HWA']
                                  .map(
                                    (disease) => DropdownMenuItem<String>(
                                      value: disease,
                                      child: Text(
                                        disease,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600, 
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedDisease = value),

                              // --- Dropdown styling ---
                              buttonStyleData: const ButtonStyleData(
                                height: 60,
                                padding: EdgeInsets.symmetric(horizontal: 2),
                              ),
                              dropdownStyleData: DropdownStyleData(
                                width: 240,
                                maxHeight: 200,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                offset: const Offset(-18, -10), 
                              ),
                              iconStyleData: IconStyleData(
                                icon: Icon(
                                  Icons.arrow_drop_down_rounded,
                                  color: Colors.green[700],
                                  size: 28,
                                ),
                              ),
                              menuItemStyleData: const MenuItemStyleData(
                                height: 48,
                                padding: EdgeInsets.symmetric(horizontal: 16),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),

                      // ---------- Scan Button ----------
                      ElevatedButton(
                        onPressed: (_isLoading || _selectedDisease == null)
                            ? null
                            : _scanAndAnalyze,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          padding: const EdgeInsets.symmetric(
                              horizontal: 36, vertical: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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


class AppColors {
  // Returns the appropriate background color for each classification and confidence
  static Color getClassificationColor(String predictedClass, double prediction) {
    // Environment cases — always green
    if (predictedClass == 'Environment') {
      return const Color(0xFFE8F5E9);
    }

    // Sick or Dead cases — color depends on confidence level
    if (predictedClass == 'Sick' || predictedClass == 'Dead') {
      if (prediction < 70) {
        return const Color(0xFFE8F5E9); // light green
      } else if (prediction < 90) {
        return const Color(0xFFFFF9C4); // light yellow
      } else if (prediction < 99.5) {
        return const Color(0xFFFFE0B2); // light orange
      } else {
        return const Color(0xFFFFCDD2); // light red
      }
    }

    // Default fallback color (in case of an unexpected class)
    return Colors.grey.shade200;
  }
}


class ResultsPage extends StatefulWidget {
  final List<ImageResult> results;
  final String selectedDisease;
  const ResultsPage({super.key, required this.results, required this.selectedDisease});

  @override
  ResultsPageState createState() => ResultsPageState();
}

class ResultsPageState extends State<ResultsPage> {
  int currentPage = 0;
  String selectedFilter = 'All';
  final ScrollController _scrollController = ScrollController();
  
// Instead of static string mapping, use a Map of predicate functions
static final Map<String, bool Function(ImageResult)> filterMap = {
  'All': (_) => true,

  'No Condition: <70%': (item) {
    final prob = item.prediction;
    return prob < 70 || item.predictedClass.toLowerCase().contains('environment');
  },

  'Possibility: 70-90%': (item) {
    final prob = item.prediction;
    return prob >= 70 && prob < 90 && !item.predictedClass.toLowerCase().contains('environment');
  },

  'High Chance: 90-99.5%': (item) {
    final prob = item.prediction;
    return prob >= 90 && prob < 99.5 && !item.predictedClass.toLowerCase().contains('environment');
  },

  'Has Condition or Dead: >99.5%': (item) {
    final prob = item.prediction;
    return prob >= 99.5 && !item.predictedClass.toLowerCase().contains('environment');
  },
};

  // filters results to display desired category
List<ImageResult> get filteredResults {
  final filterFn = filterMap[selectedFilter];
  if (filterFn == null) return widget.results;
  return widget.results.where(filterFn).toList();
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
    barrierColor: Colors.black.withValues(alpha: 0.5), // dim background
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero, // full screen
      child: Stack(
        children: [
          // Blur everything behind
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(color: Colors.black.withValues(alpha: 0.2)),
          ),
          // Centered image container
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.7,
                height: MediaQuery.of(context).size.height * 0.7,
                color: Colors.transparent, 
                child: Stack(
                  children: [
                    // Image fills container completely
                    Positioned.fill(
                      child: InteractiveViewer(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover, // fills container without leaving whitespace
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                                child: CircularProgressIndicator());
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Image.network(
                              alternativeUrl,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      ),
                    ),
                    // Top bar remains
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        height: 50,
                        decoration: const BoxDecoration(
                          color: AppConstants.darkGreen,
                          borderRadius: BorderRadius.only(
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
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
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
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column( 
              children: [
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
            
            // Scroll buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, color: Colors.green, size: 28),
                  tooltip: 'Scroll Up',
                  onPressed: () {
                  final newOffset = (_scrollController.offset - 200).clamp(
                    0.0,
                    _scrollController.position.maxScrollExtent,
                  );
                  _scrollController.animateTo(
                    newOffset,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, color: Colors.green, size: 28),
                  tooltip: 'Scroll Down',
                  onPressed: () {
                    final newOffset = (_scrollController.offset + 200).clamp(
                      0.0,
                      _scrollController.position.maxScrollExtent,
                    );
                    _scrollController.animateTo(
                      newOffset,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Filter dropdown
            Container(
              width: 260, // match your disease dropdown
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.green[700]!, width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  isExpanded: true,
                  value: selectedFilter,
                  hint: const Text(
                    'Select Filter',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                  items: filterMap.keys.map((label) => DropdownMenuItem<String>(
                    value: label,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedFilter = value!;
                      currentPage = 0;
                    });
                  },
                  buttonStyleData: const ButtonStyleData(
                    height: 50,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    maxHeight: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    offset: const Offset(0, -10),
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 48,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                  ),
                  iconStyleData: IconStyleData(
                    icon: Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppConstants.darkGreen,
                      size: 28,
                    ),
                  ),
                ),
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
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: currentPageItems.length,
                itemBuilder: (context, index) {
                  final item = currentPageItems[index];
                  final imageUrl = ApiService.getImageUrl(item.filename);
                  // Card for each result
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    color: AppColors.getClassificationColor(
                      item.predictedClass,  // or item.classification depending on your model
                      item.prediction,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => _showImagePopup(context, item),
                                  child: Text(
                                    item.filename,
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.underline,  
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              
                              // Classification and prediction
                              Text(
                                '${item.classification}: Confidence - ${item.prediction.toStringAsFixed( 2 )}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
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
                               // Thumbnail on the right
                              const SizedBox(width: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageUrl,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    width: 64,
                                    height: 64,
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                ),
                              ),
                            ],
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
        ],
      ),
    );
  }
}
