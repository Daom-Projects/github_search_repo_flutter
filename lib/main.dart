import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- PASO 1: Agregar dependencias en pubspec.yaml ---
// Antes de ejecutar, asegúrate de que tu archivo `pubspec.yaml` contenga:
//
// dependencies:
//   flutter:
//     sdk: flutter
//   http: ^1.2.1
//   url_launcher: ^6.3.1
//   shared_preferences: ^2.2.3 // <--- AÑADIDO para almacenamiento local

void main() {
  runApp(const MyApp());
}

// --- MEJORA 3: Convertido a StatefulWidget para manejar el tema ---
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
      home: RepoFinderPage(onToggleTheme: _toggleTheme),
    );
  }
}

// --- Modelo de Datos (Sin cambios) ---
class Repo {
  final String fullName;
  final String htmlUrl;

  Repo({required this.fullName, required this.htmlUrl});

  factory Repo.fromJson(Map<String, dynamic> json) {
    return Repo(
      fullName: json['full_name'] ?? 'Sin nombre',
      htmlUrl: json['html_url'] ?? '',
    );
  }
}

// --- Servicio de API (Sin cambios) ---
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

class RepoFinderPage extends StatefulWidget {
  // --- MEJORA 3: Recibe la función para cambiar el tema ---
  final VoidCallback onToggleTheme;
  const RepoFinderPage({super.key, required this.onToggleTheme});

  @override
  State<RepoFinderPage> createState() => _RepoFinderPageState();
}

class _RepoFinderPageState extends State<RepoFinderPage> {
  final GitHubService _githubService = GitHubService();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  bool _showSearchView = false;
  List<Repo> _allRepos = [];
  List<Repo> _filteredRepos = [];

  // --- MEJORA 1: Clave para SharedPreferences ---
  static const String _tokenKey = 'github_token';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _filterRepos(_searchController.text);
    });
    // Carga el token guardado al iniciar la app
    _loadTokenAndFetch();
  }

  // --- MEJORA 1: Cargar token y (si existe) buscar repos ---
  Future<void> _loadTokenAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null && token.isNotEmpty) {
      _tokenController.text = token;
      _fetchRepos(); // Intenta conectar automáticamente si hay un token
    }
  }

  // --- MEJORA 1: Guardar token ---
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // --- MEJORA 1 y 4: Limpiar token y volver a la vista de conexión ---
  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _tokenController.clear();
    _searchController.clear();
    setState(() {
      _showSearchView = false;
      _allRepos.clear();
      _filteredRepos.clear();
    });
  }

  Future<void> _fetchRepos() async {
    if (_tokenController.text.isEmpty) {
      _showError("Por favor, ingresa un token de acceso.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final repos = await _githubService.getUserRepos(_tokenController.text);
      repos.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

      // --- MEJORA 1: Guarda el token solo si la conexión es exitosa ---
      await _saveToken(_tokenController.text);

      setState(() {
        _allRepos = repos;
        _filteredRepos = repos;
        _showSearchView = true;
      });
    } catch (e) {
      _showError(e.toString());
      // Si falla (ej. token inválido), no mostramos la vista de búsqueda
      setState(() {
        _showSearchView = false;
      });
    } finally {
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
    final uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      _showError('No se pudo abrir la URL: $url');
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscador de Repositorios GitHub'),
        // --- MEJORA 3 y 4: Acciones en la AppBar ---
        actions: [
          if (_showSearchView)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recargar Repositorios',
              onPressed: _fetchRepos,
            ),
          if (_showSearchView)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Limpiar Token y Salir',
              onPressed: _clearToken,
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
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: _showSearchView ? _buildSearchView() : _buildConnectView(),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectView() {
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
          controller: _tokenController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "GitHub Personal Access Token",
            border: OutlineInputBorder(),
          ),
          // --- MEJORA 2: Enviar con la tecla Enter ---
          onSubmitted: (_) => _fetchRepos(),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text("Conectar y Cargar Repositorios"),
                onPressed: _fetchRepos,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
      ],
    );
  }

  Widget _buildSearchView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: "Buscar repositorio (ej: 'owner/nombre-repo')",
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
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
}
