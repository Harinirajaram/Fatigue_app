import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() {
  runApp(MaterialApp(
    home: const FatigueDetectionScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class FatigueDetectionScreen extends StatefulWidget {
  const FatigueDetectionScreen({Key? key}) : super(key: key);

  @override
  _FatigueDetectionScreenState createState() => _FatigueDetectionScreenState();
}

class _FatigueDetectionScreenState extends State<FatigueDetectionScreen> {
  File? selectedFile;
  List<Map<String, String>> predictionResults = [];
  bool isLoading = false;
  AudioPlayer audioPlayer = AudioPlayer();

  Future<void> pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        selectedFile = File(result.files.single.path!);
        predictionResults = [];
      });
    }
  }

  Future<void> uploadAndPredict() async {
    if (selectedFile == null) return;

    setState(() {
      isLoading = true;
      predictionResults.clear();
    });

    var uri = Uri.parse("http://192.168.137.1:5000/predict");
    var request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', selectedFile!.path));

    try {
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var decodedResponse = json.decode(response.body);

        // Ensure that you're handling the "predictions" key correctly
        if (decodedResponse['predictions'] != null) {
          setState(() {
            predictionResults = List<Map<String, String>>.from(decodedResponse['predictions']);
          });
        } else {
          Fluttertoast.showToast(msg: "No predictions found in the response.");
        }
      } else {
        Fluttertoast.showToast(msg: "Server error: ${response.statusCode}");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Error: $e");
    }

    setState(() {
      isLoading = false;
    });
  }


  void clearResults() {
    setState(() {
      predictionResults.clear();
      selectedFile = null;
    });
  }

  Widget buildPredictionResult() {
    if (predictionResults.isEmpty) {
      return const Text("No predictions yet.");
    }

    return Column(
      children: predictionResults.map((result) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          elevation: 2,
          child: ListTile(
            title: Text('${result['start_time']} - ${result['end_time']}'),
            subtitle: Text('Label: ${result['label']}'),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fatigue Detection App'),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: pickAudioFile,
              icon: const Icon(Icons.upload_file),
              label: const Text("Pick Audio File"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
            const SizedBox(height: 10),
            if (selectedFile != null)
              Text('Selected File: ${path.basename(selectedFile!.path)}'),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: isLoading ? null : uploadAndPredict,
              icon: const Icon(Icons.send),
              label: const Text("Upload & Predict"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const SpinKitCircle(color: Colors.blue, size: 50),
            Expanded(child: buildPredictionResult()),
            if (predictionResults.isNotEmpty)
              ElevatedButton.icon(
                onPressed: clearResults,
                icon: const Icon(Icons.clear_all),
                label: const Text("Clear Results"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              ),
          ],
        ),
      ),
    );
  }
}
