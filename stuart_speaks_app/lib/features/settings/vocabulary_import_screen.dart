import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/text_analyzer.dart';
import '../../core/services/word_usage_tracker.dart';

/// Screen for importing text files to train word usage
class VocabularyImportScreen extends StatefulWidget {
  const VocabularyImportScreen({super.key});

  @override
  State<VocabularyImportScreen> createState() => _VocabularyImportScreenState();
}

class _VocabularyImportScreenState extends State<VocabularyImportScreen> {
  final TextAnalyzer _analyzer = TextAnalyzer();
  bool _isProcessing = false;
  ImportStats? _lastImportStats;

  Future<void> _importTextFile() async {
    try {
      // Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'text'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return; // User canceled
      }

      setState(() {
        _isProcessing = true;
        _lastImportStats = null;
      });

      final file = File(result.files.single.path!);

      // Read raw text for position-aware import
      final rawText = await file.readAsString();

      // Analyze text for preview purposes
      final analysisResult = await _analyzer.analyzeFile(
        file,
        excludeStopWords: true,
        minWordLength: 2,
        maxWords: 10000, // Import up to 10,000 unique words
      );

      // Show preview dialog
      if (mounted) {
        final confirm = await _showPreviewDialog(analysisResult);

        if (confirm == true) {
          await _importWordsFromText(rawText);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<bool?> _showPreviewDialog(TextAnalysisResult result) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Word Usage'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.totalWords} total words found\n'
                '${result.uniqueWords} unique words',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Top 10 words:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...result.getTopN(10).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.key),
                          Text(
                            '${entry.value}x',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              Text(
                'This will add/update these words in your vocabulary to improve word suggestions.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  /// Import words from raw text with position tracking
  Future<void> _importWordsFromText(String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracker = WordUsageTracker(prefs);
      await tracker.initialize();

      final stats = await tracker.importFromText(
        text,
        minFrequency: 1, // Import all words
      );

      setState(() {
        _lastImportStats = stats;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Imported: ${stats.added} new words, ${stats.updated} updated (with position data)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Done',
              textColor: Colors.white,
              onPressed: () {
                // Pop with result indicating successful import
                Navigator.pop(context, true);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Legacy method - kept for compatibility
  Future<void> _importWords(TextAnalysisResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracker = WordUsageTracker(prefs);
      await tracker.initialize();

      final stats = await tracker.importFromTextAnalysis(
        result.topWords,
        minFrequency: 1, // Import all words
      );

      setState(() {
        _lastImportStats = stats;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Imported: ${stats.added} new words, ${stats.updated} updated',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Done',
              textColor: Colors.white,
              onPressed: () {
                // Pop with result indicating successful import
                Navigator.pop(context, true);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Vocabulary'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'About Text Import',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Import text files to train the word suggestion system on your vocabulary. '
                      'This is helpful for adding specialized terminology, names, or frequently used words.',
                      style: TextStyle(fontSize: 14, color: Colors.blue[900]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Common stop words (the, and, is, etc.) are automatically filtered out.',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Import button
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _importTextFile,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.file_upload, size: 28),
                  label: Text(
                    _isProcessing ? 'Processing...' : 'Import Text File',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Last import stats
              if (_lastImportStats != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Last Import Results',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[900],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildStatRow('New words added', _lastImportStats!.added),
                      _buildStatRow('Words updated', _lastImportStats!.updated),
                      _buildStatRow('Words skipped', _lastImportStats!.skipped),
                      const Divider(height: 16),
                      _buildStatRow('Total analyzed', _lastImportStats!.total,
                          isBold: true),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isBold ? const Color(0xFF2563EB) : null,
            ),
          ),
        ],
      ),
    );
  }
}
