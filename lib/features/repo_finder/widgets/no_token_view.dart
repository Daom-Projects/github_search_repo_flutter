import 'package:flutter/material.dart';

class NoTokenView extends StatelessWidget {
  final bool isLoading;
  final TextEditingController tokenController;
  final VoidCallback onConnect;

  const NoTokenView({
    super.key,
    required this.isLoading,
    required this.tokenController,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Ingresa tu Token de Acceso Personal de GitHub.",
          style: TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          "La aplicación necesita permisos 'repo' y 'read:org'.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: tokenController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "GitHub Personal Access Token",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => onConnect(),
        ),
        const SizedBox(height: 20),
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton.icon(
                icon: const Icon(Icons.vpn_key),
                label: const Text("Configurar y Guardar Token"),
                onPressed: onConnect,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
      ],
    );
  }
}
