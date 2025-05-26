import 'package:flutter/material.dart';
import 'dart:typed_data';

class MapDisplay extends StatelessWidget {
  final Uint8List? imageBytes;

  const MapDisplay({Key? key, this.imageBytes}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: imageBytes != null
              ? Image.memory(imageBytes!)
              : const Text(
            'Đang tải bản đồ...',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}