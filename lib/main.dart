import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const AssetTrackerApp());
}

class AssetTrackerApp extends StatelessWidget {
  const AssetTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Asset QR Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const QRScanScreen(),
    );
  }
}

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  bool isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asset QR Scanner')),
      body: MobileScanner(
        onDetect: (capture) {
          if (isScanned) return;
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String code = barcode.rawValue ?? 'Unknown';
            setState(() {
              isScanned = true;
            });

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AssetActionScreen(assetId: code),
              ),
            ).then((_) {
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

class AssetActionScreen extends StatefulWidget {
  final String assetId;
  const AssetActionScreen({super.key, required this.assetId});

  @override
  State<AssetActionScreen> createState() => _AssetActionScreenState();
}

class _AssetActionScreenState extends State<AssetActionScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _sellPriceController = TextEditingController();

  String selectedLocation = 'Office';
  final List<String> locationList = [
    'Dirc Camp',
    'Nirvana Camp',
    'Jafza Camp',
    'Al quoz Camp',
    'Office'
  ];

  String selectedStatus = 'Active';
  final List<String> statusList = ['Active', 'Damage', 'Repair', 'Transfer'];

  bool isExisting = false; // सामान पहिले नै छ कि छैन छुट्याउन
  bool isSending = false;
  bool isLoading = false; // 🟢 तुरुन्तै पप-अप खुलाउन फल्स राखिएको

  // 🔴 आफ्नो Google Apps Script को Deployed Web App URL यहाँ राख्नुहोला
  final String scriptUrl =
      "https://script.google.com/macros/s/AKfycbxaz4ozn8qajBQCTx2cBQoP2uabvbVyXaTyqgqF3RRYBAJTnbVrd8p56HvBmeS6HXNd/exec";

  @override
  void initState() {
    super.initState();
    // पेज खुल्नेबित्तिकै लोडिङ नरोकी, ब्याकग्राउन्डमा डेटा चेक गर्ने
    checkExistingAssetInBackground();
  }

  // 🟢 ब्याकग्राउन्डमा गुगल शीटबाट डेटा चेक गर्ने फंक्सन
  Future<void> checkExistingAssetInBackground() async {
    try {
      final response =
          await http.get(Uri.parse('$scriptUrl?assetId=${widget.assetId}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['exists'] == true) {
          if (!mounted) return;
          setState(() {
            isExisting = true; // पुरानो सामान (Duplicate) हो
            _nameController.text = data['assetName'] ?? '';
            _priceController.text = data['price'].toString();

            if (locationList.contains(data['location'])) {
              selectedLocation = data['location'];
            }

            if (statusList.contains(data['status'])) {
              selectedStatus = data['status'];
            }
          });
        } else {
          if (!mounted) return;
          setState(() {
            isExisting = false; // नयाँ सामान हो
            selectedStatus = 'Active';
          });
        }
      }
    } catch (e) {
      // त्रुटि आएमा बेवास्ता गर्ने
    }
  }

  Future<void> submitData() async {
    setState(() {
      isSending = true;
    });

    String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String currentTime = DateFormat('HH:mm:ss').format(DateTime.now());

    String finalPrice = _priceController.text.trim();
    String finalSellPrice = "0";
    if (selectedStatus == 'Damage') {
      finalSellPrice = _sellPriceController.text.trim().isEmpty
          ? "0"
          : _sellPriceController.text.trim();
    }

    Map<String, dynamic> formData = {
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
      final response = await http.post(
        Uri.parse(scriptUrl),
        body: jsonEncode(formData),
      );

      if (response.statusCode == 200 ||
          response.statusCode == 302 ||
          response.statusCode == 301) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('डेटा सफलतापूर्वक सेभ/अपडेट भयो!')),
        );
        Navigator.pop(context);
      } else {
        throw Exception('Failed to save');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटी भयो: $e')),
      );
    } finally {
      setState(() {
        isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Asset Details: ${widget.assetId}')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  Text(
                    'Scanned ID: ${widget.assetId}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Asset Name (सामानको नाम)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status ड्रपडाउन
                  DropdownButtonFormField<String>(
                    value: statusList.contains(selectedStatus)
                        ? selectedStatus
                        : 'Active',
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: statusList.map((String status) {
                      return DropdownMenuItem(
                          value: status, child: Text(status));
                    }).toList(),
                    onChanged: (String? val) {
                      setState(() {
                        selectedStatus = val!;
                      });
                    },
                  ),

                  // Location देखाउने वा नलुकाउने नियम
                  if (!isExisting || selectedStatus == 'Transfer') ...[
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: selectedLocation,
                      decoration: InputDecoration(
                        labelText: selectedStatus == 'Transfer'
                            ? 'Transfer to Location (नयाँ ठाउँ)'
                            : 'Asset Location (लोकेशन)',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(
                          selectedStatus == 'Transfer'
                              ? Icons.swap_horiz
                              : Icons.location_on,
                          color: selectedStatus == 'Transfer'
                              ? Colors.orange
                              : Colors.blue,
                        ),
                      ),
                      items: locationList.map((String loc) {
                        return DropdownMenuItem(value: loc, child: Text(loc));
                      }).toList(),
                      onChanged: (String? val) {
                        setState(() {
                          selectedLocation = val!;
                        });
                      },
                    ),
                  ],

                  const SizedBox(height: 20),
                  TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Original Price (मूल मूल्य)',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  if (selectedStatus == 'Damage') ...[
                    const SizedBox(height: 20),
                    TextField(
                      controller: _sellPriceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Sell Price (डामेज भएर बेचेको मूल्य)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.sell, color: Colors.red),
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isSending ? null : submitData,
                    child: isSending
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Save to Google Sheet',
                            style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
    );
  }
}
