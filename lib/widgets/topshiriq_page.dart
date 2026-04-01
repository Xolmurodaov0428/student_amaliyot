import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_downloader/flutter_file_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SubmissionStatus {
  submitted,
  pending,
  unknown;

  static SubmissionStatus fromString(String? value) {
    switch (value) {
      case 'submitted':
        return SubmissionStatus.submitted;
      case 'pending':
        return SubmissionStatus.pending;
      default:
        return SubmissionStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case SubmissionStatus.submitted:
        return 'submitted';
      case SubmissionStatus.pending:
        return 'pending';
      case SubmissionStatus.unknown:
        return 'unknown';
    }
  }

  Color get color {
    switch (this) {
      case SubmissionStatus.submitted:
        return Colors.green;
      case SubmissionStatus.pending:
        return Colors.orange;
      case SubmissionStatus.unknown:
        return Colors.blueGrey;
    }
  }
}

class AppConstants {
  static const String baseUrl = 'https://shaxa.mycoder.uz/api';
  static const String tokenKey = 'token';
  static const int maxFileSizeBytes = 10 * 1024 * 1024;
  static const String storageBaseUrl = 'https://shaxa.mycoder.uz/storage';
}

class TopshiriqlarPage extends StatefulWidget {
  const TopshiriqlarPage({super.key});

  @override
  State<TopshiriqlarPage> createState() => _TopshiriqlarPageState();
}

class _TopshiriqlarPageState extends State<TopshiriqlarPage> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _error = '';
  List<StudentTask> _tasks = [];

  final http.Client _httpClient = http.Client();

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.tokenKey);
  }

  String? _buildFileUrl(String? filePath) {
    if (filePath == null || filePath.trim().isEmpty) return null;

    final path = filePath.trim();

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    return '${AppConstants.storageBaseUrl}/$path';
  }

  String _extractFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isNotEmpty ? parts.last : 'file';
  }

  Future<void> _downloadFile(String? filePath) async {
    final url = _buildFileUrl(filePath);

    if (url == null || url.trim().isEmpty) {
      _showSnack('Fayl manzili topilmadi.', Colors.red);
      return;
    }

    try {
      final fileName = _extractFileName(filePath ?? url);

      _showSnack('Fayl yuklab olinmoqda...', Colors.blue);

      FileDownloader.downloadFile(
        url: url,
        name: fileName,
        downloadDestination: DownloadDestinations.appFiles,
        notificationType: NotificationType.all,
        onProgress: (fileName, progress) {
          debugPrint('Downloading $fileName : ${progress.toStringAsFixed(0)}%');
        },
        onDownloadCompleted: (String path) async {
          _showSnack('Fayl muvaffaqiyatli yuklab olindi ✅', Colors.green);

          if (path.isNotEmpty) {
            await OpenFilex.open(path);
          }
        },
        onDownloadError: (String error) {
          _showSnack('Yuklab olishda xato: $error', Colors.red);
        },
      );
    } catch (e) {
      _showSnack('Yuklab olishda xato: $e', Colors.red);
    }
  }
  Future<void> _loadTasks() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final token = await _getToken();

      if (token == null || token.isEmpty) {
        _setError('Token topilmadi. Qayta login qiling.');
        return;
      }

      final response = await _httpClient.get(
        Uri.parse('${AppConstants.baseUrl}/student/tasks'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (body['data'] as List<dynamic>? ?? []);

        final tasks = data
            .map((e) => StudentTask.fromJson(e as Map<String, dynamic>))
            .toList();

        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        _setError('Sessiya tugagan. Qayta login qiling.');
      } else {
        _setError('Topshiriqlarni yuklashda xato: ${response.statusCode}');
      }
    } on http.ClientException catch (e) {
      _setError('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      _setError('Kutilmagan xato: $e');
    }
  }

  void _setError(String message) {
    if (!mounted) return;

    setState(() {
      _error = message;
      _isLoading = false;
    });
  }

  Future<PlatformFile?> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
        withData: false,
        withReadStream: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        if (file.path == null || file.path!.isEmpty) {
          _showSnack('Fayl yo\'li topilmadi. Boshqa fayl tanlang.', Colors.red);
          return null;
        }

        if (file.size <= 0) {
          _showSnack('Fayl bo\'sh yoki noto\'g\'ri.', Colors.red);
          return null;
        }

        if (file.size > AppConstants.maxFileSizeBytes) {
          final sizeMb = (file.size / (1024 * 1024)).toStringAsFixed(2);
          _showSnack(
            'Fayl hajmi juda katta: $sizeMb MB. Maksimum 10 MB.',
            Colors.red,
          );
          return null;
        }

        return file;
      }
    } catch (e) {
      _showSnack('Fayl tanlashda xato: $e', Colors.red);
    }

    return null;
  }

  Future<void> _openSubmitDialog(StudentTask task) async {
    final feedbackController = TextEditingController(
      text: task.feedback ?? '',
    );
    final selectedFileNotifier = ValueNotifier<PlatformFile?>(null);

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        useRootNavigator: true,
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Topshiriq yuborish',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: feedbackController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Izoh / feedback',
                      hintText: 'Men ishni bajarib topshirdim...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<PlatformFile?>(
                    valueListenable: selectedFileNotifier,
                    builder: (_, selectedFile, __) {
                      final fileText = selectedFile == null
                          ? 'Fayl tanlash'
                          : '${selectedFile.name} '
                          '(${(selectedFile.size / 1024 / 1024).toStringAsFixed(2)} MB)';

                      return InkWell(
                        onTap: () async {
                          final file = await _pickFile();
                          if (file != null) {
                            selectedFileNotifier.value = file;
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.teal.shade200),
                            borderRadius: BorderRadius.circular(14),
                            color: Colors.teal.shade50,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.attach_file,
                                color: Colors.teal,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  fileText,
                                  style: TextStyle(
                                    color: selectedFile == null
                                        ? Colors.grey.shade700
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (selectedFile != null)
                                GestureDetector(
                                  onTap: () {
                                    selectedFileNotifier.value = null;
                                  },
                                  child: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                        final feedback = feedbackController.text.trim();
                        final file = selectedFileNotifier.value;

                        if (file != null &&
                            file.size > AppConstants.maxFileSizeBytes) {
                          _showSnack(
                            'Fayl 10 MB dan katta bo\'lmasligi kerak.',
                            Colors.red,
                          );
                          return;
                        }

                        Navigator.of(ctx).pop();

                        _submitTask(
                          taskId: task.id,
                          feedback: feedback,
                          file: file,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Yuborish',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      feedbackController.dispose();
      selectedFileNotifier.dispose();
    }
  }

  Future<void> _submitTask({
    required int taskId,
    required String feedback,
    PlatformFile? file,
  }) async {
    if (!mounted) return;

    if (file != null) {
      if (file.path == null || file.path!.isEmpty) {
        _showSnack('Fayl yo\'li topilmadi.', Colors.red);
        return;
      }

      if (file.size <= 0) {
        _showSnack('Fayl noto\'g\'ri yoki bo\'sh.', Colors.red);
        return;
      }

      if (file.size > AppConstants.maxFileSizeBytes) {
        final sizeMb = (file.size / (1024 * 1024)).toStringAsFixed(2);
        _showSnack(
          'Fayl juda katta: $sizeMb MB. Maksimum 10 MB fayl yuboring.',
          Colors.red,
        );
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final token = await _getToken();

      if (token == null || token.isEmpty) {
        _showSnack('Token topilmadi.', Colors.red);
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.baseUrl}/student/tasks'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      request.fields['task_id'] = taskId.toString();
      request.fields['feedback'] = feedback;

      if (file != null && file.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
            filename: file.name,
          ),
        );
      }

      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnack('Topshiriq muvaffaqiyatli yuborildi ✅', Colors.green);
        await _loadTasks();
        return;
      }

      if (response.statusCode == 401) {
        _showSnack('Sessiya tugagan. Qayta login qiling.', Colors.red);
        return;
      }

      if (response.statusCode == 413) {
        _showSnack(
          'Server faylni qabul qilmadi. Fayl hajmi juda katta. 10 MB dan kichik fayl yuboring.',
          Colors.red,
        );
        return;
      }

      if (response.statusCode == 422) {
        String validationMessage = 'Ma\'lumotlarda xato bor.';
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;

          if (errorBody['message'] != null) {
            validationMessage = errorBody['message'].toString();
          }

          if (errorBody['errors'] is Map<String, dynamic>) {
            final errors = errorBody['errors'] as Map<String, dynamic>;
            if (errors.isNotEmpty) {
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                validationMessage = firstError.first.toString();
              }
            }
          }
        } catch (_) {}

        _showSnack(validationMessage, Colors.red);
        return;
      }

      String errorMessage = 'Yuborishda xato: ${response.statusCode}';
      try {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
        if (errorBody['message'] != null) {
          errorMessage = errorBody['message'].toString();
        }
      } catch (_) {}

      _showSnack(errorMessage, Colors.red);
    } on http.ClientException catch (e) {
      _showSnack('Tarmoq xatosi: ${e.message}', Colors.red);
    } catch (e) {
      _showSnack('Kutilmagan xato: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSnack(String text, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';

    try {
      final dt = DateTime.parse(raw.replaceFirst(' ', 'T'));
      return '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')}.'
          '${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadTasks,
                icon: const Icon(Icons.refresh),
                label: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Topshiriqlar mavjud emas',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];

          return _TaskCard(
            task: task,
            isSubmitting: _isSubmitting,
            onSubmit: () => _openSubmitDialog(task),
            formatDate: _formatDate,
            onOpenTaskFile: () => _downloadFile(task.taskFilePath),
            onOpenSubmissionFile: () => _downloadFile(task.submissionFilePath),
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isSubmitting,
    required this.onSubmit,
    required this.formatDate,
    required this.onOpenTaskFile,
    required this.onOpenSubmissionFile,
  });

  final StudentTask task;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final String Function(String?) formatDate;
  final VoidCallback onOpenTaskFile;
  final VoidCallback onOpenSubmissionFile;

  @override
  Widget build(BuildContext context) {
    final status = SubmissionStatus.fromString(task.submissionStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 10),
          if (task.description != null && task.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                task.description!,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          _InfoRow(label: 'Deadline', value: formatDate(task.dueDate)),
          _InfoRow(label: 'Rahbar', value: task.supervisorName ?? '-'),
          _InfoRow(label: 'Guruh', value: task.groupName ?? '-'),
          _InfoRow(label: 'Feedback', value: task.feedback ?? '-'),

          if (task.taskFilePath != null && task.taskFilePath!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FileRow(
              label: 'Topshiriq fayli',
              filePath: task.taskFilePath!,
              buttonText: 'Yuklab olish',
              onTap: onOpenTaskFile,
            ),
          ],

          if (task.submissionFilePath != null &&
              task.submissionFilePath!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FileRow(
              label: 'Yuborilgan fayl',
              filePath: task.submissionFilePath!,
              buttonText: 'Yuklab olish',
              onTap: onOpenSubmissionFile,
            ),
          ],

          if (task.score != null) _InfoRow(label: 'Ball', value: task.score!),

          if (task.submittedAt != null)
            _InfoRow(
              label: 'Yuborilgan vaqt',
              value: formatDate(task.submittedAt),
            ),

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: isSubmitting ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: isSubmitting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.upload_file, color: Colors.white),
              label: Text(
                isSubmitting ? 'Yuborilmoqda...' : 'Topshiriq yuborish',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final SubmissionStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 14),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.label,
    required this.filePath,
    required this.buttonText,
    required this.onTap,
  });

  final String label;
  final String filePath;
  final String buttonText;
  final VoidCallback onTap;

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isNotEmpty ? parts.last : path;
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _fileNameFromPath(filePath);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blueGrey.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, color: Colors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fileName,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.download, size: 18),
            label: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

class StudentTask {
  final int id;
  final String title;
  final String? description;
  final String? dueDate;
  final String taskStatus;
  final String? taskFilePath;
  final String submissionStatus;
  final String? submissionFilePath;
  final String? score;
  final String? feedback;
  final String? submittedAt;
  final String? supervisorName;
  final String? groupName;

  const StudentTask({
    required this.id,
    required this.title,
    this.description,
    this.dueDate,
    required this.taskStatus,
    this.taskFilePath,
    required this.submissionStatus,
    this.submissionFilePath,
    this.score,
    this.feedback,
    this.submittedAt,
    this.supervisorName,
    this.groupName,
  });

  factory StudentTask.fromJson(Map<String, dynamic> json) {
    final supervisor = json['supervisor'] as Map<String, dynamic>?;
    final group = json['group'] as Map<String, dynamic>?;

    return StudentTask(
      id: int.tryParse(json['id'].toString()) ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      dueDate: json['due_date']?.toString(),
      taskStatus: json['task_status']?.toString() ?? '',
      taskFilePath: json['task_file_path']?.toString(),
      submissionStatus: json['submission_status']?.toString() ?? 'pending',
      submissionFilePath: json['submission_file_path']?.toString(),
      score: json['score']?.toString(),
      feedback: json['feedback']?.toString(),
      submittedAt: json['submitted_at']?.toString(),
      supervisorName: supervisor?['name']?.toString(),
      groupName: group?['name']?.toString(),
    );
  }
}