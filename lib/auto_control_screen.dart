import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class AutoControlScreen extends StatefulWidget {
  @override
  _AutoControlScreenState createState() => _AutoControlScreenState();
}

class _AutoControlScreenState extends State<AutoControlScreen> {
  late MqttServerClient client;
  bool isConnected = false;
  Uint8List? imageBytes; // Dữ liệu bản đồ nhận từ MQTT
  final String mqttBroker = "103.146.22.13";
  final int mqttPort = 1883;
  final String mqttUser = "user1";
  final String mqttPassword = "12345678";
  final String topicMapImage = "home/map_image"; // Topic cho bản đồ

  // Các biến để quản lý diện tích được chọn
  late Offset startPosition;
  late Offset endPosition;

  @override
  void initState() {
    super.initState();
    startPosition = Offset(0, 0);
    endPosition = Offset(0, 0);
    _connectMQTT();
  }

  // Kết nối MQTT
  Future<void> _connectMQTT() async {
    client = MqttServerClient(mqttBroker, 'flutter_client');
    client.port = mqttPort;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onDisconnected = _onDisconnected;

    final connMessage = MqttConnectMessage()
        .authenticateAs(mqttUser, mqttPassword)
        .withClientIdentifier('flutter_client')
        .startClean();

    client.connectionMessage = connMessage;

    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        print('✅ MQTT Connected!');
        setState(() {
          isConnected = true;
        });

        client.subscribe(topicMapImage, MqttQos.atMostOnce);

        client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? messages) {
          for (var message in messages!) {
            final payload = message.payload as MqttPublishMessage;
            final List<int> payloadData = payload.payload.message;

            if (message.topic == topicMapImage) {
              setState(() {
                imageBytes = Uint8List.fromList(payloadData); // Lưu dữ liệu ảnh bản đồ
              });
            }
          }
        });
      } else {
        print('⚠️ MQTT Connection Failed');
      }
    } catch (e) {
      print('❌ Error connecting MQTT: $e');
    }
  }

  // Hàm khi mất kết nối MQTT
  void _onDisconnected() {
    print('⚠️ Disconnected from MQTT');
    setState(() {
      isConnected = false;
    });
  }

  // Hàm hiển thị chọn diện tích
  void _showSelectAreaDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Chọn diện tích'),
          content: const Text('Popup cho chọn diện tích.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  // Hàm để bắt đầu quét bản đồ
  void _startScan() {
    print("Bắt đầu quét bản đồ...");
  }

  // Hàm để khởi động quá trình
  void _startProcess() {
    print("Khởi động quá trình...");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Bên trái: Các nút điều khiển
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // Căn giữa theo trục dọc
              crossAxisAlignment: CrossAxisAlignment.center, // Căn giữa theo trục ngang
              children: [
                ElevatedButton(
                  onPressed: _startScan,
                  child: const Text('Chọn diện tích'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _startScan,
                  child: const Text('Bắt đầu quét map'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _startProcess,
                  child: const Text('Khởi động'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Quay lại'),
                ),
              ],
            ),
          ),
          // Bên phải: Hiển thị bản đồ
          Expanded(
            flex: 2,
            child: Center(
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: imageBytes != null
                    ? Image.memory(imageBytes!) // Hiển thị bản đồ nhận từ MQTT
                    : const Center(
                  child: Text(
                    'Đang tải bản đồ...',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}