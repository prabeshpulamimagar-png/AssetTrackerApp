import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App start हुँदा pending data sync गर्ने
  await DatabaseHelper.instance.syncPendingData();

  runApp(const AssetTrackerApp());
}

// ============================================================
// DATABASE HELPER - OFFLINE DATA
// ============================================================

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('assets_local.db');

    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            time TEXT,
            assetId TEXT,
            assetName TEXT,
            location TEXT,
            price TEXT,
            status TEXT,
            sellPrice TEXT
          )
        ''');
      },
    );
  }

  // Offline data save
  Future<int> insertPendingAsset(Map<String, dynamic> row) async {
    final db = await instance.database;

    return await db.insert(
      'pending_assets',
      row,
    );
  }

  // Pending data निकाल्ने
  Future<List<Map<String, dynamic>>> getPendingAssets() async {
    final db = await instance.database;

    return await db.query(
      'pending_assets',
    );
  }

  // Sync भएपछि local data delete गर्ने
  Future<int> deletePendingAsset(int id) async {
    final db = await instance.database;

    return await db.delete(
      'pending_assets',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // OFFLINE DATA -> GOOGLE SHEET SYNC
  // ============================================================

  Future<void> syncPendingData() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult.contains(ConnectivityResult.none)) {
        return;
      }

      const String scriptUrl =
          "https://script.google.com/macros/s/AKfycbxaz4ozn8qajBQCTx2cBQoP2uabvbVyXaTyqgqF3RRYBAJTnbVrd8p56HvBmeS6HXNd/exec";

      final List<Map<String, dynamic>> pendingList = await getPendingAssets();

      if (pendingList.isEmpty) {
        return;
      }

      for (final item in pendingList) {
        try {
          final Map<String, dynamic> formData = {
            "date": item['date'],
            "time": item['time'],
            "assetId": item['assetId'],
            "assetName": item['assetName'],
            "location": item['location'],
            "price": item['price'],
            "status": item['status'],
            "sellPrice": item['sellPrice'],
          };

          final response = await http
              .post(
                Uri.parse(scriptUrl),
                headers: {
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(formData),
              )
              .timeout(
                const Duration(seconds: 15),
              );

          if (response.statusCode == 200 ||
              response.statusCode == 301 ||
              response.statusCode == 302) {
            await deletePendingAsset(
              item['id'],
            );
          }
        } catch (e) {
          // एउटा data fail भए बाँकीलाई रोक्ने
          break;
        }
      }
    } catch (e) {
      // Internet/database error भए app crash हुन नदिने
    }
  }
}

// ============================================================
// MAIN APP
// ============================================================

class AssetTrackerApp extends StatelessWidget {
  const AssetTrackerApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Asset QR Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const QRScanScreen(),
    );
  }
}

// ============================================================
// QR SCANNER SCREEN
// ============================================================

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({
    super.key,
  });

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  bool isScanned = false;

  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;

  @override
  void initState() {
    super.initState();

    // App खोल्दा pending data sync
    DatabaseHelper.instance.syncPendingData();

    // Internet फर्किएपछि automatic sync
    connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        if (results.contains(ConnectivityResult.none)) {
          return;
        }

        await DatabaseHelper.instance.syncPendingData();
      },
    );
  }

  @override
  void dispose() {
    connectivitySubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Asset QR Scanner',
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.sync,
            ),
            onPressed: () async {
              await DatabaseHelper.instance.syncPendingData();

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'सिंक गर्ने प्रयास गरियो!',
                  ),
                ),
              );
            },
          ),
        ],
      ),

      // Automatic QR scanner
      body: MobileScanner(
        onDetect: (capture) {
          if (isScanned) {
            return;
          }

          final List<Barcode> barcodes = capture.barcodes;

          for (final barcode in barcodes) {
            final String code = barcode.rawValue ?? '';

            if (code.isEmpty) {
              continue;
            }

            setState(() {
              isScanned = true;
            });

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AssetActionScreen(
                  assetId: code,
                ),
              ),
            ).then((_) {
              if (!mounted) return;

              // Details screen बाट फर्किएपछि
              // फेरि automatic scan ready
              setState(() {
                isScanned = false;
              });
            });

            break;
          }
        },
      ),
    );
  }
}

// ============================================================
// ASSET DETAILS SCREEN
// ============================================================

class AssetActionScreen extends StatefulWidget {
  final String assetId;

  const AssetActionScreen({
    super.key,
    required this.assetId,
  });

  @override
  State<AssetActionScreen> createState() => _AssetActionScreenState();
}

class _AssetActionScreenState extends State<AssetActionScreen> {
  // Controllers
  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _priceController = TextEditingController();

  final TextEditingController _sellPriceController = TextEditingController();

  // ============================================================
  // LOCATION
  // ============================================================

  String selectedLocation = 'Office';

  final List<String> locationList = [
    'Dirc Camp',
    'Nirvana Camp',
    'Jafza Camp',
    'Al quoz Camp',
    'Office',
  ];

  // ============================================================
  // STATUS
  // ============================================================

  String selectedStatus = 'Active';

  final List<String> statusList = [
    'Active',
    'Damage',
    'Repair',
    'Transfer',
  ];

  bool isExisting = false;
  bool isSending = false;
  bool isLoading = false;

  // ============================================================
  // GOOGLE APPS SCRIPT URL
  // ============================================================

  final String scriptUrl =
      "https://script.google.com/macros/s/AKfycbxaz4ozn8qajBQCTx2cBQoP2uabvbVyXaTyqgqF3RRYBAJTnbVrd8p56HvBmeS6HXNd/exec";

  @override
  void initState() {
    super.initState();

    checkExistingAssetInBackground();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _sellPriceController.dispose();

    super.dispose();
  }

  // ============================================================
  // CHECK EXISTING ASSET
  // ============================================================

  Future<void> checkExistingAssetInBackground() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (!mounted) return;

      if (connectivityResult.contains(ConnectivityResult.none)) {
        return;
      }

      final response = await http
          .get(
            Uri.parse(
              '$scriptUrl?assetId=${Uri.encodeComponent(widget.assetId)}',
            ),
          )
          .timeout(
            const Duration(seconds: 15),
          );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['exists'] == true) {
          setState(() {
            isExisting = true;

            // Asset Name
            _nameController.text = data['assetName'] ?? '';

            // Original Price
            _priceController.text = data['price']?.toString() ?? '';

            // Location
            if (locationList.contains(
              data['location'],
            )) {
              selectedLocation = data['location'];
            }

            // Status
            if (statusList.contains(
              data['status'],
            )) {
              selectedStatus = data['status'];
            }
          });
        }
      }
    } catch (e) {
      // Internet नभए ignore गर्ने
    }
  }

  // ============================================================
  // SAVE DATA
  // ============================================================

  Future<void> submitData() async {
    if (isSending) {
      return;
    }

    final BuildContext pageContext = this.context;

    setState(() {
      isSending = true;
    });

    final String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final String currentTime = DateFormat('HH:mm:ss').format(DateTime.now());

    // Original Price
    final String finalPrice = _priceController.text.trim();

    // Sell Price
    String finalSellPrice = "0";

    if (selectedStatus == 'Damage') {
      finalSellPrice = _sellPriceController.text.trim().isEmpty
          ? "0"
          : _sellPriceController.text.trim();
    }

    // ============================================================
    // FORM DATA
    // ============================================================

    final Map<String, dynamic> formData = {
      "date": currentDate,
      "time": currentTime,
      "assetId": widget.assetId,
      "assetName": _nameController.text.trim().isEmpty
          ? "Unknown Asset"
          : _nameController.text.trim(),
      "location": selectedLocation,
      "price": finalPrice,
      "status": selectedStatus,
      "sellPrice": finalSellPrice,
    };

    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (!mounted) return;

      final bool isOnline =
          !connectivityResult.contains(ConnectivityResult.none);

      // ========================================================
      // ONLINE
      // ========================================================

      if (isOnline) {
        final response = await http
            .post(
              Uri.parse(scriptUrl),
              headers: {
                'Content-Type': 'application/json',
              },
              body: jsonEncode(formData),
            )
            .timeout(
              const Duration(seconds: 15),
            );

        if (!mounted) return;

        if (response.statusCode == 200 ||
            response.statusCode == 301 ||
            response.statusCode == 302) {
          if (!mounted) return;

          ScaffoldMessenger.of(pageContext).showSnackBar(
            const SnackBar(
              content: Text(
                'डेटा सफलतापूर्वक गुगल शीटमा सेभ भयो!',
              ),
            ),
          );

          Navigator.of(pageContext).pop();
        } else {
          throw Exception(
            'Google Sheet save failed',
          );
        }
      }

      // ========================================================
      // OFFLINE
      // ========================================================

      else {
        await DatabaseHelper.instance.insertPendingAsset(
          formData,
        );

        if (!mounted) return;

        if (!mounted) return;

        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text(
              'इन्टरनेट छैन! डेटा अफलाइन सेभ भयो, अनलाइन हुँदा स्वतः सिंक हुनेछ।',
            ),
          ),
        );

        Navigator.of(pageContext).pop();
      }
    }

    // ==========================================================
    // NETWORK ERROR -> SAVE LOCALLY
    // ==========================================================

    catch (e) {
      await DatabaseHelper.instance.insertPendingAsset(
        formData,
      );

      if (!mounted) return;

      if (!mounted) return;

      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'नेटवर्क समस्या! डेटा अफलाइन सेभ गरियो।',
          ),
        ),
      );

      Navigator.of(pageContext).pop();
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
        });
      }
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Asset Details: ${widget.assetId}',
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  // ==================================================
                  // SCANNED ID
                  // ==================================================

                  Text(
                    'Scanned ID: ${widget.assetId}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                  // ==================================================
                  // 1. ASSET NAME
                  // ==================================================

                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Asset Name (सामानको नाम)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                  // ==================================================
                  // 2. STATUS
                  // ==================================================

                  DropdownButtonFormField<String>(
                    initialValue: statusList.contains(
                      selectedStatus,
                    )
                        ? selectedStatus
                        : 'Active',
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: statusList.map(
                      (String status) {
                        return DropdownMenuItem<String>(
                          value: status,
                          child: Text(status),
                        );
                      },
                    ).toList(),
                    onChanged: (String? val) {
                      if (val == null) {
                        return;
                      }

                      setState(() {
                        selectedStatus = val;
                      });
                    },
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                  // ==================================================
                  // 3. LOCATION
                  // ==================================================
                  // अब Existing Asset भए पनि Location सधैं देखिन्छ
                  // ==================================================

                  DropdownButtonFormField<String>(
                    initialValue: locationList.contains(
                      selectedLocation,
                    )
                        ? selectedLocation
                        : 'Office',
                    decoration: const InputDecoration(
                      labelText: 'Asset Location (लोकेशन)',
                      border: OutlineInputBorder(),
                    ),
                    items: locationList.map(
                      (String loc) {
                        return DropdownMenuItem<String>(
                          value: loc,
                          child: Text(loc),
                        );
                      },
                    ).toList(),
                    onChanged: (String? val) {
                      if (val == null) {
                        return;
                      }

                      setState(() {
                        selectedLocation = val;
                      });
                    },
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                  // ==================================================
                  // 4. ORIGINAL PRICE
                  // ==================================================

                  TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Original Price (मूल मूल्य)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  // ==================================================
                  // 5. SELL PRICE
                  // ==================================================
                  // Damage select गरेपछि मात्र देखिन्छ
                  // ==================================================

                  if (selectedStatus == 'Damage') ...[
                    const SizedBox(
                      height: 20,
                    ),
                    TextField(
                      controller: _sellPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Sell Price (डामेज भएर बेचेको मूल्य)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(
                    height: 30,
                  ),

                  // ==================================================
                  // SAVE BUTTON
                  // ==================================================

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: isSending ? null : submitData,
                      child: isSending
                          ? const SizedBox(
                              height: 25,
                              width: 25,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save Asset',
                              style: TextStyle(
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
