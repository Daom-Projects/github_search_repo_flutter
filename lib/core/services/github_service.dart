import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../features/repo_finder/models/repo_model.dart';

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
