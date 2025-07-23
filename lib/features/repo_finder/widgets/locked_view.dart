import 'package:flutter/material.dart';

class LockedView extends StatelessWidget {
  final bool isLoading;
  final TextEditingController passwordController;
  final VoidCallback onUnlock;

  const LockedView({
    super.key,
    required this.isLoading,
    required this.passwordController,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Aplicación Bloqueada",
          style: TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          "Ingresa tu contraseña maestra para continuar.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Contraseña Maestra",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => onUnlock(),
        ),
        const SizedBox(height: 20),
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton.icon(
                icon: const Icon(Icons.lock_open),
                label: const Text("Desbloquear"),
                onPressed: onUnlock,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
      ],
    );
  }
}
