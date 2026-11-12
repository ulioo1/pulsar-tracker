class Task {
  final String id;
  final String title;
  final String category; // 'Trabajo', 'Clipping', 'Ejercicio'
  bool isCompleted;

  Task({
    required this.id,
    required this.title,
    required this.category,
    this.isCompleted = false,
  });
}