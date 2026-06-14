class GitChangedFile {
  const GitChangedFile({required this.status, required this.path});

  final String status;
  final String path;

  factory GitChangedFile.fromJson(Map<String, dynamic> json) {
    return GitChangedFile(
      status: json['status'] as String? ?? '?',
      path: json['path'] as String? ?? '',
    );
  }
}

class GitCommit {
  const GitCommit({
    required this.hash,
    required this.subject,
    required this.author,
    required this.date,
  });

  final String hash;
  final String subject;
  final String author;
  final String date;

  factory GitCommit.fromJson(Map<String, dynamic> json) {
    return GitCommit(
      hash: json['hash'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      author: json['author'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }
}
