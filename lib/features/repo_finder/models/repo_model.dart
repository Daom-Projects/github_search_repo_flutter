class Repo {
  final String fullName;
  final String htmlUrl;

  Repo({required this.fullName, required this.htmlUrl});

  factory Repo.fromJson(Map<String, dynamic> json) => Repo(
    fullName: json['full_name'] ?? 'Sin nombre',
    htmlUrl: json['html_url'] ?? '',
  );
}
