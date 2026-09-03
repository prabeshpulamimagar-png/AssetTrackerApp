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

  String selectedLocation = 'Office';
  final List<String> locationList = ['Camp1', 'Camp2', 'Camp3', 'Office'];

  String selectedStatus = 'Active';
  final List<String> statusList = ['Active', 'Damage', 'Repair'];

  bool isSending = false;

  // गुगल शीटको Apps Script URL
  final String scriptUrl =
      "https://script.google.com/macros/s/AKfycbz0I4Hr4omETY9voUj13DAop3Fo0XGoF0pUmi9KZr8D3mJXcvDAL7BPYV0BQdvYuhe8/exec";

  Future<void> submitData() async {
    setState(() {
      isSending = true;
    });

    String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    Map<String, dynamic> formData = {
      "date": currentDate,
      "time": currentTime,
      "assetId": widget.assetId,
      "assetName": _nameController.text.trim().isEmpty
          ? "Unknown Asset"
          : _nameController.text.trim(),
      "location": selectedLocation,
      "price": _priceController.text.trim().isEmpty
          ? "0"
          : _priceController.text.trim(),
      "status": selectedStatus,
    };

    try {
      final response = await http.post(
        Uri.parse(scriptUrl),
        body: jsonEncode(formData),
      );

      // Google Apps Script को 302 Redirect र 200 दुवैलाई सफल मानेको
      if (response.statusCode == 200 ||
          response.statusCode == 302 ||
          response.statusCode == 301) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('डेटा सफलतापूर्वक सेभ भयो!')),
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
      body: Padding(
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
            DropdownButtonFormField<String>(
              value: selectedLocation,
              decoration: const InputDecoration(
                labelText: 'Asset Location',
                border: OutlineInputBorder(),
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
            const SizedBox(height: 20),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Price (मूल्य)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: statusList.map((String status) {
                return DropdownMenuItem(value: status, child: Text(status));
              }).toList(),
              onChanged: (String? val) {
                setState(() {
                  selectedStatus = val!;
                });
              },
            ),
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
