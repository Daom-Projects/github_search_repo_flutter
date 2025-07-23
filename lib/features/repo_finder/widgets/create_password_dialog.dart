import 'package:flutter/material.dart';

Future<String?> showCreatePasswordDialog(BuildContext context) {
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Crear Contraseña Maestra'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Esta contraseña se usará para encriptar tu token. No la olvides, ¡no se puede recuperar!",
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                validator: (val) => val != null && val.length < 8
                    ? 'Mínimo 8 caracteres'
                    : null,
              ),
              TextFormField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar Contraseña',
                ),
                validator: (val) => val != passwordController.text
                    ? 'Las contraseñas no coinciden'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(passwordController.text);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      );
    },
  );
}
