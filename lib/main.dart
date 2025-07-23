import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart' as pc;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buscador de Repositorios de GitHub',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      debugShowCheckedModeBanner: false,
      home: RepoFinderPage(onToggleTheme: _toggleTheme),
    );
  }
}

// --- Servicio de Encriptación Profesional ---
class EncryptionService {
  // --- MEJORA: La derivación de clave ahora es asíncrona para no bloquear la UI ---
  Future<Uint8List> _deriveKey(String password, Uint8List salt) async {
    // Cedemos el control al event loop para que la UI pueda actualizarse (mostrar un loader).
    await Future.delayed(Duration.zero);

    // La operación intensiva de CPU se ejecuta después de ceder el control.
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, 100000, 32));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  Uint8List generateSalt() {
    final secureRandom = pc.FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom.nextBytes(16);
  }

  // --- MEJORA: El método ahora es un Future porque depende de _deriveKey ---
  Future<String> encryptText(
    String plainText,
    String password,
    Uint8List salt,
  ) async {
    final derivedKey = await _deriveKey(password, salt);
    final key = encrypt.Key(derivedKey);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return "${iv.base64}:${encrypted.base64}";
  }

  // --- MEJORA: El método ahora es un Future porque depende de _deriveKey ---
  Future<String?> decryptText(
    String combined,
    String password,
    Uint8List salt,
  ) async {
    try {
      final parts = combined.split(':');
      if (parts.length != 2) return null;

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
      final derivedKey = await _deriveKey(password, salt);
      final key = encrypt.Key(derivedKey);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print("Error de desencriptación: $e");
      return null;
    }
  }
}

// --- Modelo de Datos y Servicio de API ---
class Repo {
  final String fullName;
  final String htmlUrl;
  Repo({required this.fullName, required this.htmlUrl});
  factory Repo.fromJson(Map<String, dynamic> json) => Repo(
    fullName: json['full_name'] ?? 'Sin nombre',
    htmlUrl: json['html_url'] ?? '',
  );
}

class GitHubService {
  static const String _githubApiUrl = "https://api.github.com";

  Future<List<Repo>> getUserRepos(String token) async {
    final List<Repo> allRepos = [];
    final headers = {
      "Authorization": "token $token",
      "Accept": "application/vnd.github.v3+json",
    };
    String? url =
        "$_githubApiUrl/user/repos?affiliation=owner,collaborator,organization_member&per_page=100";

    while (url != null) {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) {
        throw Exception(
          'Error de API: ${response.statusCode}. Revisa tu token y permisos.',
        );
      }
      final List<dynamic> reposData = json.decode(response.body);
      allRepos.addAll(reposData.map((data) => Repo.fromJson(data)));
      final linkHeader = response.headers['link'];
      url = linkHeader != null ? _parseNextPageUrl(linkHeader) : null;
    }
    return allRepos;
  }

  String? _parseNextPageUrl(String linkHeader) {
    final links = linkHeader.split(',');
    for (final link in links) {
      final segments = link.split(';');
      if (segments.length > 1 && segments[1].trim() == 'rel="next"') {
        return segments[0].trim().replaceAll(RegExp(r'[<>]'), '');
      }
    }
    return null;
  }
}

enum AppState { initializing, noToken, locked, unlocked }

class RepoFinderPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const RepoFinderPage({super.key, required this.onToggleTheme});
  @override
  State<RepoFinderPage> createState() => _RepoFinderPageState();
}

class _RepoFinderPageState extends State<RepoFinderPage> {
  final GitHubService _githubService = GitHubService();
  final EncryptionService _encryptionService = EncryptionService();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  AppState _appState = AppState.initializing;
  bool _isLoading = false;
  List<Repo> _allRepos = [];
  List<Repo> _filteredRepos = [];
  List<String> _recentSearches = [];
  String? _decryptedToken;

  static const String _encryptedTokenKey = 'github_token_v2';
  static const String _saltKey = 'encryption_salt';
  static const String _recentSearchesKey = 'recent_searches';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => _filterRepos(_searchController.text));
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadRecentSearches(prefs);

    if (prefs.containsKey(_encryptedTokenKey) && prefs.containsKey(_saltKey)) {
      setState(() => _appState = AppState.locked);
    } else {
      setState(() => _appState = AppState.noToken);
    }
  }

  Future<void> _handleNewToken() async {
    if (_tokenController.text.isEmpty) {
      _showError("Por favor, ingresa un token de acceso.");
      return;
    }

    final password = await _showCreatePasswordDialog();
    if (password == null || password.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _githubService.getUserRepos(_tokenController.text);
      final salt = _encryptionService.generateSalt();
      // --- MEJORA: Se espera (await) la finalización de la encriptación ---
      final encryptedToken = await _encryptionService.encryptText(
        _tokenController.text,
        password,
        salt,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_encryptedTokenKey, encryptedToken);
      await prefs.setString(_saltKey, base64.encode(salt));

      _decryptedToken = _tokenController.text;
      await _fetchRepos();
    } catch (e) {
      _showError("Error al verificar el token: ${e.toString()}");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _unlockApp() async {
    if (_passwordController.text.isEmpty) {
      _showError("Por favor, ingresa tu contraseña maestra.");
      return;
    }
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final encryptedToken = prefs.getString(_encryptedTokenKey);
    final saltBase64 = prefs.getString(_saltKey);

    if (encryptedToken == null || saltBase64 == null) {
      _showError(
        "No se encontraron datos guardados. Por favor, configura de nuevo.",
      );
      await _logout();
      return;
    }

    final salt = base64.decode(saltBase64);
    // --- MEJORA: Se espera (await) la finalización de la desencriptación ---
    final token = await _encryptionService.decryptText(
      encryptedToken,
      _passwordController.text,
      salt,
    );
    _passwordController.clear();

    if (token != null) {
      _decryptedToken = token;
      await _fetchRepos();
    } else {
      _showError("Contraseña incorrecta.");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_encryptedTokenKey);
    await prefs.remove(_saltKey);
    _tokenController.clear();
    _searchController.clear();
    _decryptedToken = null;
    setState(() {
      _allRepos.clear();
      _filteredRepos.clear();
      _appState = AppState.noToken;
    });
  }

  Future<void> _fetchRepos() async {
    if (_decryptedToken == null) {
      _showError("La aplicación está bloqueada.");
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final repos = await _githubService.getUserRepos(_decryptedToken!);
      repos.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
      setState(() {
        _allRepos = repos;
        _filteredRepos = repos;
        _appState = AppState.unlocked;
        _isLoading = false;
      });
    } catch (e) {
      _showError(e.toString());
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterRepos(String searchTerm) {
    final term = searchTerm.toLowerCase();
    setState(() {
      _filteredRepos = _allRepos
          .where((repo) => repo.fullName.toLowerCase().contains(term))
          .toList();
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _launchURL(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      _showError('No se pudo abrir la URL: $url');
    }
  }

  Future<void> _loadRecentSearches(SharedPreferences prefs) async {
    setState(() {
      _recentSearches = prefs.getStringList(_recentSearchesKey) ?? [];
    });
  }

  Future<void> _addRecentSearch(String term) async {
    if (term.isEmpty) return;
    _recentSearches.remove(term);
    _recentSearches.insert(0, term);
    if (_recentSearches.length > 5) {
      _recentSearches = _recentSearches.sublist(0, 5);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscador de Repositorios GitHub'),
        actions: [
          if (_appState == AppState.unlocked)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recargar Repositorios',
              onPressed: _fetchRepos,
            ),
          if (_appState == AppState.unlocked || _appState == AppState.locked)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Bloquear y Salir',
              onPressed: _logout,
            ),
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            tooltip: 'Cambiar Tema',
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildCurrentView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_appState) {
      case AppState.initializing:
        return const CircularProgressIndicator(key: ValueKey('initializing'));
      case AppState.noToken:
        return _buildNoTokenView();
      case AppState.locked:
        return _buildLockedView();
      case AppState.unlocked:
        return _buildSearchView();
    }
  }

  Widget _buildNoTokenView() {
    return Column(
      key: const ValueKey('noTokenView'),
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
          controller: _tokenController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "GitHub Personal Access Token",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _handleNewToken(),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton.icon(
                icon: const Icon(Icons.vpn_key),
                label: const Text("Configurar y Guardar Token"),
                onPressed: _handleNewToken,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
      ],
    );
  }

  Widget _buildLockedView() {
    return Column(
      key: const ValueKey('lockedView'),
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
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Contraseña Maestra",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _unlockApp(),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton.icon(
                icon: const Icon(Icons.lock_open),
                label: const Text("Desbloquear"),
                onPressed: _unlockApp,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
      ],
    );
  }

  Widget _buildSearchView() {
    return Column(
      key: const ValueKey('searchView'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: "Buscar repositorio",
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => _addRecentSearch(value),
        ),
        const SizedBox(height: 12),
        _buildRecentSearches(),
        const SizedBox(height: 12),
        Text(
          "Mostrando ${_filteredRepos.length} de ${_allRepos.length} repositorios",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(height: 20),
        Expanded(
          child: _filteredRepos.isEmpty && _searchController.text.isNotEmpty
              ? const Center(
                  child: Text("No se encontraron repositorios con ese filtro."),
                )
              : ListView.builder(
                  itemCount: _filteredRepos.length,
                  itemBuilder: (context, index) {
                    final repo = _filteredRepos[index];
                    return ListTile(
                      title: Text(repo.fullName),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_browser),
                        tooltip: "Abrir en GitHub",
                        onPressed: () => _launchURL(repo.htmlUrl),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Búsquedas recientes:",
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: _recentSearches
              .map(
                (term) => ActionChip(
                  label: Text(term),
                  onPressed: () {
                    _searchController.text = term;
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _searchController.text.length),
                    );
                    _filterRepos(term);
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Future<String?> _showCreatePasswordDialog() {
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
}
