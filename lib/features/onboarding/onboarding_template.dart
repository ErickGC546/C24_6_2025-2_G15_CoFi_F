import 'package:flutter/material.dart';

class OnboardingTemplate extends StatelessWidget {
  final String imagePath;
  final String title;
  final String description;
  final String nextRoute;

  const OnboardingTemplate({
    Key? key,
    required this.imagePath,
    required this.title,
    required this.description,
    required this.nextRoute,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Imagen
              Center(
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.none, // mantiene el tamaño natural del asset
                ),
              ),

              const SizedBox(height: 48),

              // Título
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Descripción
              Text(
                description,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // Botones
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    child: const Text('Omitir'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, nextRoute);
                    },
                    child: const Text('Siguiente'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
