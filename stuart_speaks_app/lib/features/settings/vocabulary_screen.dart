import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/word_usage_tracker.dart';
import '../../core/models/word.dart';

/// Screen for viewing and managing vocabulary words
class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  WordUsageTracker? _tracker;
  List<Word> _words = [];
  List<Word> _filteredWords = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _sortBy = 'alpha_asc'; // 'alpha_asc', 'alpha_desc', 'freq_desc', 'freq_asc'

  @override
  void initState() {
    super.initState();
    _loadVocabulary();
  }

  Future<void> _loadVocabulary() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final tracker = WordUsageTracker(prefs);
    await tracker.initialize();

    final words = tracker.getAllWords();

    setState(() {
      _tracker = tracker;
      _words = words;
      _filteredWords = words;
      _isLoading = false;
    });

    _sortWords();
  }

  void _sortWords() {
    setState(() {
      switch (_sortBy) {
        case 'alpha_asc':
          _filteredWords.sort((a, b) => a.text.compareTo(b.text));
          break;
        case 'alpha_desc':
          _filteredWords.sort((a, b) => b.text.compareTo(a.text));
          break;
        case 'freq_desc':
          _filteredWords.sort((a, b) => b.usageCount.compareTo(a.usageCount));
          break;
        case 'freq_asc':
          _filteredWords.sort((a, b) => a.usageCount.compareTo(b.usageCount));
          break;
      }
    });
  }

  void _filterWords(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredWords = List.from(_words);
      } else {
        _filteredWords = _words
            .where((word) => word.text.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
    _sortWords();
  }

  Future<void> _addWord() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Word'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Word',
            hintText: 'Enter a word',
          ),
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
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
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && controller.text.isNotEmpty && _tracker != null) {
      final word = controller.text.trim().toLowerCase();
      await _tracker!.recordUsage(word);
      await _loadVocabulary();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "$word" to vocabulary'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _deleteWord(Word word) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Word'),
        content: Text('Are you sure you want to delete "${word.text}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && _tracker != null) {
      await _tracker!.removeWord(word.text);
      await _loadVocabulary();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${word.text}"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _toggleSort(String column) {
    setState(() {
      if (column == 'word') {
        // Toggle between alpha_asc and alpha_desc
        _sortBy = _sortBy == 'alpha_asc' ? 'alpha_desc' : 'alpha_asc';
      } else {
        // Toggle between freq_desc and freq_asc
        _sortBy = _sortBy == 'freq_desc' ? 'freq_asc' : 'freq_desc';
      }
    });
    _sortWords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vocabulary Dictionary'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search words...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _filterWords('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _filterWords,
            ),
          ),

          // Column headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _toggleSort('word'),
                    child: Row(
                      children: [
                        const Text(
                          'Word',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_sortBy == 'alpha_asc')
                          const Icon(Icons.arrow_upward, size: 16)
                        else if (_sortBy == 'alpha_desc')
                          const Icon(Icons.arrow_downward, size: 16),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _toggleSort('count'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Count',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_sortBy == 'freq_desc')
                        const Icon(Icons.arrow_downward, size: 16)
                      else if (_sortBy == 'freq_asc')
                        const Icon(Icons.arrow_upward, size: 16),
                    ],
                  ),
                ),
                const SizedBox(width: 48), // Space for delete button
              ],
            ),
          ),

          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${_filteredWords.length} words',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  const Text(
                    ' • ',
                    style: TextStyle(color: Colors.grey),
                  ),
                  Text(
                    'filtered from ${_words.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Word list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredWords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isEmpty ? Icons.book : Icons.search_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No words in vocabulary yet'
                                  : 'No words match your search',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredWords.length,
                        itemBuilder: (context, index) {
                          final word = _filteredWords[index];
                          return ListTile(
                            title: Text(
                              word.text,
                              style: const TextStyle(fontSize: 18),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${word.usageCount}x',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteWord(word),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addWord,
        backgroundColor: const Color(0xFF2563EB),
        child: const Icon(Icons.add),
      ),
    );
  }
}
