import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:file_picker/file_picker.dart'; // Thêm thư viện file picker

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Xe cắt cỏ tự động',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

enum ControlMode { manual, auto }

enum AutoMode { map, grass }

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String mqttBroker = "103.146.22.13";
  final int mqttPort = 1883;
  final String mqttUser = "user1";
  final String mqttPassword = "12345678";

  late MqttServerClient client;
  bool isConnected = false;

  double xValue = 0;
  double yValue = 0;
  int cuttingMachineSpeed = 0;
  double machineTemperature = 0; // Nhiệt độ máy

  Uint8List? imageBytes;

  // Thêm biến mode
  ControlMode mode = ControlMode.manual;
  AutoMode autoMode = AutoMode.map;

  String? mapFileName; // Lưu tên file bản đồ đã chọn
  Uint8List? mapFileBytes; // Lưu data file bản đồ

  @override
  void initState() {
    super.initState();
    _connectMQTT();
  }

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

        client.subscribe('home/map_image', MqttQos.atMostOnce);
        client.subscribe('home/machine_temperature', MqttQos.atMostOnce); // subscribe topic nhiệt độ máy

        client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? messages) {
          for (var message in messages!) {
            final payload = message.payload as MqttPublishMessage;
            final List<int> payloadData = payload.payload.message;

            if (message.topic == 'home/map_image') {
              setState(() {
                imageBytes = Uint8List.fromList(payloadData);
              });
            }
            if (message.topic == 'home/machine_temperature') {
              try {
                final tempStr = String.fromCharCodes(payloadData);
                final temp = double.tryParse(tempStr);
                if (temp != null) {
                  setState(() {
                    machineTemperature = temp;
                  });
                }
              } catch (_) {}
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

  void _onDisconnected() {
    print('⚠️ Disconnected from MQTT');
    setState(() {
      isConnected = false;
    });
  }

  void _disconnectMQTT() {
    client.disconnect();
    setState(() {
      isConnected = false;
    });
    print('🔌 MQTT Disconnected');
  }

  void _updateMotorSpeed() {
    int motorLeft = ((-yValue + xValue) * 255).toInt();
    int motorRight = ((-yValue - xValue) * 255).toInt();

    motorLeft = motorLeft.clamp(-255, 255);
    motorRight = motorRight.clamp(-255, 255);

    if (xValue == 0 && yValue == 0) {
      motorLeft = 0;
      motorRight = 0;
    }

    if (isConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString("$motorLeft,$motorRight,$cuttingMachineSpeed");
      client.publishMessage('robot/control', MqttQos.atMostOnce, builder.payload!);
      print('📡 Sent: $motorLeft,$motorRight,$cuttingMachineSpeed');
    } else {
      print('❌ MQTT not connected');
    }
  }

  void _sendAutoModeCommand() {
    if (!isConnected) return;
    final builder = MqttClientPayloadBuilder();
    if (autoMode == AutoMode.map) {
      builder.addString("AUTO_MAP");
      client.publishMessage('robot/auto_mode', MqttQos.atMostOnce, builder.payload!);
      print('📡 Sent: AUTO_MAP');
    } else {
      builder.addString("AUTO_GRASS");
      client.publishMessage('robot/auto_mode', MqttQos.atMostOnce, builder.payload!);
      print('📡 Sent: AUTO_GRASS');
    }
  }

  Future<void> _pickMapFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      withData: true,
      allowedExtensions: ['json', 'txt', 'yaml', 'map'],
      type: FileType.custom,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        mapFileName = result.files.first.name;
        mapFileBytes = result.files.first.bytes;
      });
    }
  }

  void _sendMapFile() {
    if (!isConnected || mapFileBytes == null) return;
    final builder = MqttClientPayloadBuilder();
    // builder.addBytes(mapFileBytes!);
    client.publishMessage('robot/map_file', MqttQos.atMostOnce, builder.payload!);
    print('📡 Sent map file: $mapFileName');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã gửi file bản đồ: $mapFileName')),
    );
  }

  Widget _buildMQTTControls() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: isConnected ? _disconnectMQTT : _connectMQTT,
          child: Text(isConnected ? 'Ngắt kết nối' : 'Kết nối MQTT'),
        ),
        const SizedBox(height: 10),
        Text(
          isConnected ? '✅ Đã kết nối' : '❌ Chưa kết nối',
          style: TextStyle(
            color: isConnected ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildManualControlTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildMQTTControls(),
          const SizedBox(height: 18),
          Center(child: VideoFeedDisplay()),
          const SizedBox(height: 18),
          Column(
            children: [
              Text('Tốc độ máy cắt: $cuttingMachineSpeed', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: cuttingMachineSpeed.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: cuttingMachineSpeed.toString(),
                onChanged: (value) {
                  setState(() {
                    cuttingMachineSpeed = value.toInt();
                  });
                  _updateMotorSpeed();
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Joystick(
              mode: JoystickMode.all,
              base: const CircleAvatar(radius: 55, backgroundColor: Colors.grey),
              stick: const CircleAvatar(radius: 30, backgroundColor: Colors.deepPurple),
              listener: (details) {
                setState(() {
                  xValue = details.x;
                  yValue = details.y;
                });
                _updateMotorSpeed();
              },
              period: const Duration(milliseconds: 100),
            ),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.thermostat, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                'Nhiệt độ máy: ${machineTemperature.toStringAsFixed(1)} °C',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildAutoTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildMQTTControls(),
          const SizedBox(height: 18),
          Center(child: VideoFeedDisplay()),
          const SizedBox(height: 18),
          // Chọn chế độ tự động
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              child: Column(
                children: [
                  const Text('Chọn chế độ tự động', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  ToggleButtons(
                    isSelected: [
                      autoMode == AutoMode.map,
                      autoMode == AutoMode.grass
                    ],
                    onPressed: (index) {
                      setState(() {
                        autoMode = index == 0 ? AutoMode.map : AutoMode.grass;
                        _sendAutoModeCommand();
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    selectedColor: Colors.white,
                    fillColor: Colors.deepPurple,
                    color: Colors.deepPurple,
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Theo bản đồ'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Theo dõi cỏ'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    autoMode == AutoMode.map ? 'Robot sẽ di chuyển theo bản đồ lập trình sẵn.' : 'Robot sẽ tự động phát hiện và cắt cỏ.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  // Nếu đang ở chế độ theo bản đồ thì cho chọn file bản đồ
                  if (autoMode == AutoMode.map) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Chọn file bản đồ'),
                          onPressed: _pickMapFile,
                        ),
                        const SizedBox(width: 10),
                        if (mapFileName != null)
                          Expanded(
                            child: Text(
                              mapFileName!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    if (mapFileBytes != null)
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.send),
                            label: const Text('Gửi file'),
                            onPressed: _sendMapFile,
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.thermostat, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                'Nhiệt độ máy: ${machineTemperature.toStringAsFixed(1)} °C',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Text(
                  'Xe cắt cỏ tự động',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
              const SizedBox(height: 12),
              // Nút chuyển đổi giữa chế độ tay và tự động
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text("Điều khiển tay"),
                    selected: mode == ControlMode.manual,
                    selectedColor: Colors.deepPurple,
                    labelStyle: TextStyle(
                        color: mode == ControlMode.manual ? Colors.white : Colors.deepPurple),
                    onSelected: (selected) {
                      if (selected) setState(() => mode = ControlMode.manual);
                    },
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text("Tự động"),
                    selected: mode == ControlMode.auto,
                    selectedColor: Colors.deepPurple,
                    labelStyle: TextStyle(
                        color: mode == ControlMode.auto ? Colors.white : Colors.deepPurple),
                    onSelected: (selected) {
                      if (selected) setState(() => mode = ControlMode.auto);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: mode == ControlMode.manual
                    ? _buildManualControlTab()
                    : _buildAutoTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoFeedDisplay extends StatelessWidget {
  const VideoFeedDisplay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 160,
      child: Mjpeg(
        stream: 'https://spkt.saveapp.cc/video_stream',
        isLive: true,
        timeout: const Duration(seconds: 5),
        error: (context, error, stack) {
          return const Center(
            child: Text(
              'Không thể tải video',
              style: TextStyle(color: Colors.red),
            ),
          );
        },
      ),
    );
  }
}