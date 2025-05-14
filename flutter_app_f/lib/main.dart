import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For json decoding
import 'package:path/path.dart' as p;

void main() {
  runApp(const FatigueDetectionApp());
}

class FatigueDetectionApp extends StatelessWidget {
  const FatigueDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fatigue Detection',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const FatigueHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FatigueHomePage extends StatefulWidget {
  const FatigueHomePage({super.key});

  @override
  State<FatigueHomePage> createState() => _FatigueHomePageState();
}

class _FatigueHomePageState extends State<FatigueHomePage> {
  String uploadStatus = "No file selected.";
  File? uploadedFile;
  bool isUploading = false;
  List<String> predictionList = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.storage.request();
  }

  Future<void> _uploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        uploadedFile = File(result.files.single.path!);
        uploadStatus = "File Uploaded: ${p.basename(uploadedFile!.path)}";
      });
    } else {
      setState(() {
        uploadStatus = "No file selected.";
      });
    }
  }

  Future<void> detectFatigue() async {
    if (uploadedFile == null) {
      setState(() {
        predictionList = ["Please upload a file first."];
      });
      return;
    }

    setState(() {
      isUploading = true;
      predictionList = ["Processing..."];
    });

    try {
      var uri = Uri.parse("https://fatigue-app-hhji.onrender.com/predict");
      var request = http.MultipartRequest('POST', uri);

      // Add the file to the request
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        uploadedFile!.path,
        filename: p.basename(uploadedFile!.path),
      ));

      // Send the request
      var response = await request.send();

      if (response.statusCode == 200) {
        var respStr = await response.stream.bytesToString();
        var jsonResp = json.decode(respStr);

        List<dynamic> predictions = jsonResp['predictions'];
        setState(() {
          predictionList = predictions.map((item) =>
          "Time ${item['start_time']} - ${item['end_time']}: ${item['label']}").toList();
        });
      } else {
        setState(() {
          predictionList = ["Error: Server returned ${response.statusCode}"];
        });
      }
    } catch (e) {
      setState(() {
        predictionList = ["Failed to connect to server: $e"];
      });
    } finally {
      setState(() {
        isUploading = false;
      });
    }
  }


  void reset() {
    setState(() {
      uploadedFile = null;
      predictionList = [];
      uploadStatus = "No file selected.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fatigue Detection from Speech'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Upload or Record Speech', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _uploadFile,
              icon: const Icon(Icons.upload_file),
              label: const Text("Upload Audio File"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            Text(uploadStatus, style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: detectFatigue,
              icon: const Icon(Icons.search),
              label: const Text("Detect Fatigue"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: reset,
              icon: const Icon(Icons.refresh),
              label: const Text("Reset"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 40),
            const Text('Detection Result:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            isUploading
                ? const CircularProgressIndicator()
                : Expanded(
              child: ListView.builder(
                itemCount: predictionList.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(Icons.access_time),
                    title: Text(
                      predictionList[index],
                      style: const TextStyle(fontSize: 16),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
