import 'dart:async';
import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../main.dart';

/// Pantalla de llamada cifrada E2E sobre WebRTC.
/// La señalización viaja por la mix-network.
class CallScreen extends StatefulWidget {
  final Contact contact;
  final bool isVideo;

  const CallScreen({super.key, required this.contact, this.isVideo = false});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  String _callStatus = "Conectando...";
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isVideoEnabled = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.isVideo;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Simular conexión
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _callStatus = "Handshake Noise XX...");
      }
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _callStatus = "DTLS-SRTP activo");
      }
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _callStatus = "Llamada cifrada E2E");
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactName = widget.contact.alias.isNotEmpty
        ? widget.contact.alias
        : widget.contact.name;
    final initials = contactName[0].toUpperCase();

    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: WanadiBrand.pureWhite),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: WanadiBrand.safe.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WanadiBrand.safe.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock, color: WanadiBrand.safe, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          _callStatus,
                          style: const TextStyle(color: WanadiBrand.safe, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Avatar con pulse
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  padding: EdgeInsets.all(8 + (_pulseController.value * 12)),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: WanadiBrand.mintTech.withOpacity(0.2 + (_pulseController.value * 0.15)),
                      width: 2,
                    ),
                  ),
                  child: child,
                );
              },
              child: CircleAvatar(
                radius: 56,
                backgroundColor: WanadiBrand.mintTech.withOpacity(0.15),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: WanadiBrand.mintTech,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Nombre
            Text(
              contactName,
              style: const TextStyle(
                color: WanadiBrand.pureWhite,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Duración
            Text(
              _elapsedSeconds > 0 ? _formatDuration(_elapsedSeconds) : _callStatus,
              style: TextStyle(
                color: _elapsedSeconds > 0 ? WanadiBrand.mintTech : Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 8),

            // Crypto info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: WanadiBrand.surfaceDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield, color: WanadiBrand.mintTech, size: 14),
                  SizedBox(width: 6),
                  Text(
                    "ChaCha20-Poly1305 · DTLS-SRTP",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Controles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? "Silenciado" : "Micrófono",
                    color: _isMuted ? WanadiBrand.warning : Colors.grey,
                    onTap: () => setState(() => _isMuted = !_isMuted),
                  ),
                  _buildCallButton(
                    icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    label: _isVideoEnabled ? "Video On" : "Video Off",
                    color: _isVideoEnabled ? WanadiBrand.info : Colors.grey,
                    onTap: () => setState(() => _isVideoEnabled = !_isVideoEnabled),
                  ),
                  _buildCallButton(
                    icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                    label: _isSpeaker ? "Altavoz" : "Auricular",
                    color: _isSpeaker ? WanadiBrand.mintTech : Colors.grey,
                    onTap: () => setState(() => _isSpeaker = !_isSpeaker),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Botón colgar
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: WanadiBrand.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_end, color: WanadiBrand.pureWhite, size: 32),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}
