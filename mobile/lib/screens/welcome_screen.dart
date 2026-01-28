import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'bench_map.dart';
import '../theme/app_theme.dart';


enum Handedness { left, right }

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final ApiService _apiService = ApiService();

  bool _serverOnline = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final online = await _apiService.checkServerHealth();
    if (!mounted) return;
    setState(() {
      _serverOnline = online;
      _loading = false;
    });
  }

  Future<void> _onHandSelected(Handedness hand) async {
    if (!_serverOnline) {
      _showOfflineDialog();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dominant_hand',
      hand == Handedness.left ? 'left' : 'right',
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BenchMap(handedness: hand),
      ),
    );
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Server offline'),
        content: const Text(
          'Server currently offline. Please try again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🔹 Background image
          Positioned.fill(
            child: Image.asset(
              'assets/Welcome_Screen.jpg',
              fit: BoxFit.cover,
            ),
          ),

          // 🔹 Dark overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.45),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 48),

                  const Text(
                    'Welcome to Sonnenbankerl',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Find your sunny spot in Graz',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),

                  const Spacer(),

                  const Text(
                    'For the best user experience,\nselect your dominant hand',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _onHandSelected(Handedness.left),
                        child: const Text('Left'),
                      ),
                      ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _onHandSelected(Handedness.right),
                        child: const Text('Right'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // 🔹 Server status
                  if (_loading)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Text(
                      _serverOnline ? 'Server online' : 'Server offline',
                      style: TextStyle(
                        color: _serverOnline ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
