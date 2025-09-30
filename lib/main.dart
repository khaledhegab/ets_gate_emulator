import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(

        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Gate Emulator'),
    );
  }
}

class Gate {
  final String id;
  final String stationId;
  final String type;
  final String stationNameAr;
  final String stationNameEn;
  final String gateToken;

  Gate({
    required this.id,
    required this.stationId,
    required this.type,
    required this.stationNameAr,
    required this.stationNameEn,
    required this.gateToken,
  });
}

Future<List<Gate>> loadGates() async {
  final csvString = await rootBundle.loadString('lib/gates_rows.csv');
  final lines = LineSplitter.split(csvString).skip(1); // skip header
  return lines.map((line) {
    final parts = line.split(',');
    return Gate(
      id: parts[0],
      stationId: parts[2],
      type: parts[4],
      stationNameAr: parts[5],
      stationNameEn: parts[6],
      gateToken: 'my_auth_token', // Placeholder, update if token is in CSV
    );
  }).toList();
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Gate> gates = [];
  Gate? selectedGate;
  String selectedType = 'entry';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadGates().then((gatesList) {
      setState(() {
        gates = gatesList;
        loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final stations = gates.map((g) => g.stationNameEn).toSet().toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<String>(
              value: selectedGate?.stationNameEn,
              hint: Text('Select Station'),
              items: stations.map((station) {
                return DropdownMenuItem(
                  value: station,
                  child: Text(station),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedGate = gates.firstWhere((g) => g.stationNameEn == value && g.type == selectedType);
                });
              },
            ),
            DropdownButton<String>(
              value: selectedType,
              items: ['entry', 'exit'].map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.toUpperCase()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedType = value!;
                  if (selectedGate != null) {
                    selectedGate = gates.firstWhere((g) => g.stationNameEn == selectedGate!.stationNameEn && g.type == selectedType);
                  }
                });
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: selectedGate == null ? null : () {
                print(selectedGate?.id);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => QRScanScreen(
                      gate: selectedGate!,
                      type: selectedType,
                    ),
                  ),
                );
              },
              child: Text('Scan QR'),
            ),
          ],
        ),
      ),
    );
  }
}

class QRScanScreen extends StatefulWidget {
  final Gate gate;
  final String type;
  const QRScanScreen({required this.gate, required this.type, Key? key}) : super(key: key);

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  bool scanned = false;
  String? responseText;
  MobileScannerController controller = MobileScannerController();

  void _onDetect(BarcodeCapture capture) async {
    if (scanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    setState(() { scanned = true; });
    final qrData = barcodes.first.rawValue;

    final url = Uri.parse('https://ets-backend-1022146078615.me-central1.run.app/api/gates/${widget.type == "entry"? 'start-trip' : 'end-trip'}');
    final headers = {
      'x-gate-id': widget.gate.id,
      'x-station-token': widget.gate.gateToken,
      'Content-Type': 'application/json',
    };
    final body = widget.type == 'entry'
        ? jsonEncode({ 'access_key': qrData })
        : jsonEncode({ 'trip_id': qrData });

    try {
      final res = await http.post(url, headers: headers, body: body);
      setState(() { responseText = res.body; });
    } catch (e) {
      setState(() { responseText = 'Error: $e'; });
    }

    await Future.delayed(Duration(seconds: 10));
    if (mounted) {
      Navigator.pop(context, responseText);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Scan QR')),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: MobileScanner(
              controller: controller,
              onDetect: _onDetect,
            ),
          ),
          if (responseText != null)
            Expanded(
              flex: 1,
              child: Center(child: Text(responseText!)),
            ),
        ],
      ),
    );
  }
}
