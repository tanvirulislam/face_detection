import 'dart:io';

import 'package:flutter/material.dart';
import 'camera_widget.dart';
import 'models.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _verificationStatus = "Not verified";
  VerificationResult? _verificationResult;

  Future<void> _startFaceVerification() async {
    final result = await Navigator.push<VerificationResult>(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen(faceType: FaceType.front)),
    );

    if (result != null) {
      setState(() {
        _verificationStatus = "Verified Successfully ✓";
        _verificationResult = result;
      });
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Flexible(child: Text('Verification Complete', style: TextStyle(fontSize: 20))),
          ],
        ),
        content: const Text('Your face has been successfully verified!', style: TextStyle(fontSize: 16)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVerified = _verificationStatus.contains("Successfully");

    return Scaffold(
      appBar: AppBar(title: const Text('Face Verification'), centerTitle: true, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Header Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                child: Icon(Icons.face_retouching_natural, size: 50, color: Colors.blue.shade700),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                'Verify Your Identity',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              Text(
                'We need to verify your identity using face recognition',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),

              const SizedBox(height: 32),

              // Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isVerified ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isVerified ? Colors.green : Colors.grey.shade300),
                ),
                child: Text(
                  'Status: $_verificationStatus',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isVerified ? Colors.green.shade700 : Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 32),

              // DISPLAY 3 CAPTURED IMAGES
              if (_verificationResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Captured Images',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildImagePreview('Front', _verificationResult!.frontImage.path),
                          _buildImagePreview('Left', _verificationResult!.leftImage.path),
                          _buildImagePreview('Right', _verificationResult!.rightImage.path),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _startFaceVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt, size: 22),
                      SizedBox(width: 10),
                      Text('Start Face Verification', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Instructions
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instructions:',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                    ),
                    const SizedBox(height: 8),
                    _buildInstruction('1. Position your face in the frame'),
                    _buildInstruction('2. Follow on-screen instructions'),
                    _buildInstruction('3. Keep your face clearly visible'),
                    _buildInstruction('4. Ensure good lighting'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(String label, String imagePath) {
    return Column(
      children: [
        Container(
          width: 90,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade300, width: 2),
            image: DecorationImage(image: FileImage(File(imagePath)), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade900),
        ),
      ],
    );
  }

  Widget _buildInstruction(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: Colors.blue.shade900, height: 1.3)),
          ),
        ],
      ),
    );
  }
}
