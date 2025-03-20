import 'dart:io';
import 'package:flutter/material.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:convert';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final frontCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.front,
  );
  runApp(MyApp(frontCamera: frontCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription frontCamera;
  const MyApp({super.key, required this.frontCamera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter TCP Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 72, 1, 250)),
        useMaterial3: true,
      ),
      home: MyHomePage(title: 'Flutter TCP Client', frontCamera: frontCamera),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  final CameraDescription frontCamera;
  const MyHomePage({super.key, required this.title, required this.frontCamera});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Socket? _socket;
  final String serverIp = '192.168.2.102'; //10.180.46.55 //192.168.2.102
  final int serverPort = 50000;
  StreamSubscription<int>? _proximitySubscription;
  bool _isProximityDetected = false;
  String _status = "Esperando envio..."; // Status da imagem
  late CameraController _cameraController;

  @override
  void initState() {
    super.initState();
    _connectToServer();
    _startProximityDetection();
    _initializeCamera();
  }

  // Conectar ao servidor
  void _connectToServer() async {
    try {
      _socket = await Socket.connect(serverIp, serverPort);
      debugPrint("✅ Conectado ao servidor $serverIp:$serverPort");

      // Ouvindo a resposta do servidor para atualizar o status
      _socket!.listen((data) {
        String message = utf8.decode(data).trim();
        if (message == "IMAGEM_RECEBIDA") {
          setState(() {
            _status = "Foto enviada com sucesso!";
          });
        }
      });
    } catch (e) {
      debugPrint("❌ Erro ao conectar ao servidor: $e");
    }
  }

  // Enviar alerta
  void _sendAlert() {
    if (_socket != null) {
      _socket!.writeln("ALERTA");
      debugPrint("📤 Mensagem enviada: ALERTA");
    } else {
      debugPrint("⚠️ Conexão não estabelecida.");
    }
  }

  // Inicializar câmera
  Future<void> _initializeCamera() async {
      _cameraController =
          CameraController(widget.frontCamera, ResolutionPreset.medium);
      await _cameraController.initialize();
    }

    // Enviar imagem para o servidor
    // Enviar imagem em Base64
  Future<void> _sendImageToServer(XFile picture) async {
    if (_socket == null) {
      debugPrint("⚠️ Erro: Sem conexão com o servidor.");
      return;
    }
    try {
      List<int> imageBytes = await picture.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      _socket!.writeln("IMAGEM"); // Indica que uma imagem será enviada
      await Future.delayed(Duration(milliseconds: 100)); // Pequeno delay
      _socket!.writeln(base64Image); // Envia a imagem codificada
      _socket!.writeln("FIM_IMAGEM"); // Envia um marcador para indicar o fim

      debugPrint("📤 Imagem enviada ao servidor");
      setState(() {
        _status = "Imagem enviada com sucesso!";
      });
    } catch (e) {
      debugPrint("❌ Erro ao enviar imagem: $e");
      setState(() {
        _status = "Erro ao enviar imagem.";
      });
    }
  }

  // Detectar proximidade e capturar a foto automaticamente
  void _startProximityDetection() {
    _proximitySubscription = ProximitySensor.events.listen((int event) async {
      bool isNear = event > 0;
      if (isNear && !_isProximityDetected) {
        _sendAlert(); // Envia o alerta

        // Captura a foto automaticamente
        if (!_cameraController.value.isInitialized) return;
        try {
          final XFile picture = await _cameraController.takePicture();
          debugPrint("📸 Foto capturada automaticamente");

          // Envia a foto para o servidor
          await _sendImageToServer(picture);

          setState(() {
            _isProximityDetected = true;
          });
        } catch (e) {
          debugPrint("❌ Erro ao tirar foto automaticamente: $e");
        }
      } else if (!isNear) {
        setState(() {
          _isProximityDetected = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _socket?.close();
    _proximitySubscription?.cancel();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _isProximityDetected
                  ? '🔴 Segurança Ativada'
                  : '🟢 Segurança Desativada',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            // Removido o status de envio
            // Apenas exibe o status de sucesso ou erro ao enviar imagem
            Text(
              _status, // Status da imagem
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
