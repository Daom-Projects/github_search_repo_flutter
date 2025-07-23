import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/repo_model.dart';

class SearchView extends StatelessWidget {
  final TextEditingController searchController;
  final List<Repo> allRepos;
  final List<Repo> filteredRepos;
  final List<String> recentSearches;
  final Function(String) onAddRecentSearch;
  final Function(String) onFilter;

  const SearchView({
    super.key,
    required this.searchController,
    required this.allRepos,
    required this.filteredRepos,
    required this.recentSearches,
    required this.onAddRecentSearch,
    required this.onFilter,
  });

  Future<void> _launchURL(BuildContext context, String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la URL: $url'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          decoration: const InputDecoration(
            labelText: "Buscar repositorio",
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => onAddRecentSearch(value),
        ),
        const SizedBox(height: 12),
        _buildRecentSearches(context),
        const SizedBox(height: 12),
        Text(
          "Mostrando ${filteredRepos.length} de ${allRepos.length} repositorios",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(height: 20),
        Expanded(
          child: filteredRepos.isEmpty && searchController.text.isNotEmpty
              ? const Center(
                  child: Text("No se encontraron repositorios con ese filtro."),
                )
              : ListView.builder(
                  itemCount: filteredRepos.length,
                  itemBuilder: (context, index) {
                    final repo = filteredRepos[index];
                    return ListTile(
                      title: Text(repo.fullName),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_browser),
                        tooltip: "Abrir en GitHub",
                        onPressed: () => _launchURL(context, repo.htmlUrl),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecentSearches(BuildContext context) {
    if (recentSearches.isEmpty) return const SizedBox.shrink();
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
          children: recentSearches
              .map(
                (term) => ActionChip(
                  label: Text(term),
                  onPressed: () {
                    searchController.text = term;
                    searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: searchController.text.length),
                    );
                    onFilter(term);
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
