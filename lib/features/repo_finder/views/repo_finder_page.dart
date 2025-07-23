import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/enums/app_state.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/github_service.dart';
import '../models/repo_model.dart';
import '../widgets/create_password_dialog.dart';
import '../widgets/locked_view.dart';
import '../widgets/no_token_view.dart';
import '../widgets/search_view.dart';

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

    final password = await showCreatePasswordDialog(context);
    if (password == null || password.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _githubService.getUserRepos(_tokenController.text);
      final salt = _encryptionService.generateSalt();
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
        return NoTokenView(
          key: const ValueKey('noTokenView'),
          isLoading: _isLoading,
          tokenController: _tokenController,
          onConnect: _handleNewToken,
        );
      case AppState.locked:
        return LockedView(
          key: const ValueKey('lockedView'),
          isLoading: _isLoading,
          passwordController: _passwordController,
          onUnlock: _unlockApp,
        );
      case AppState.unlocked:
        return SearchView(
          key: const ValueKey('searchView'),
          searchController: _searchController,
          allRepos: _allRepos,
          filteredRepos: _filteredRepos,
          recentSearches: _recentSearches,
          onAddRecentSearch: _addRecentSearch,
          onFilter: _filterRepos,
        );
    }
  }
}
