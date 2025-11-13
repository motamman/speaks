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
  String _sortBy = 'alpha_asc'; // 'alpha_asc', 'alpha_desc', 'first_desc', 'first_asc', 'second_desc', 'second_asc', 'other_desc', 'other_asc', 'total_desc', 'total_asc'

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
    print('DEBUG VocabScreen: Loaded ${words.length} words');

    // Filter out numerals
    final filteredWords = words.where((word) => !_isNumeral(word.text)).toList();
    print('DEBUG VocabScreen: After filtering: ${filteredWords.length} words');

    setState(() {
      _tracker = tracker;
      _words = filteredWords;
      _filteredWords = filteredWords;
      _isLoading = false;
    });

    _sortWords();
  }

  /// Check if a word is a numeral
  bool _isNumeral(String text) {
    // Check if the entire word is numeric
    return RegExp(r'^\d+$').hasMatch(text);
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
        case 'first_desc':
          _filteredWords.sort((a, b) => b.firstWordCount.compareTo(a.firstWordCount));
          break;
        case 'first_asc':
          _filteredWords.sort((a, b) => a.firstWordCount.compareTo(b.firstWordCount));
          break;
        case 'second_desc':
          _filteredWords.sort((a, b) => b.secondWordCount.compareTo(a.secondWordCount));
          break;
        case 'second_asc':
          _filteredWords.sort((a, b) => a.secondWordCount.compareTo(b.secondWordCount));
          break;
        case 'other_desc':
          _filteredWords.sort((a, b) => b.otherWordCount.compareTo(a.otherWordCount));
          break;
        case 'other_asc':
          _filteredWords.sort((a, b) => a.otherWordCount.compareTo(b.otherWordCount));
          break;
        case 'total_desc':
          _filteredWords.sort((a, b) => b.usageCount.compareTo(a.usageCount));
          break;
        case 'total_asc':
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
      switch (column) {
        case 'word':
          _sortBy = _sortBy == 'alpha_asc' ? 'alpha_desc' : 'alpha_asc';
          break;
        case 'first':
          _sortBy = _sortBy == 'first_desc' ? 'first_asc' : 'first_desc';
          break;
        case 'second':
          _sortBy = _sortBy == 'second_desc' ? 'second_asc' : 'second_desc';
          break;
        case 'other':
          _sortBy = _sortBy == 'other_desc' ? 'other_asc' : 'other_desc';
          break;
        case 'total':
          _sortBy = _sortBy == 'total_desc' ? 'total_asc' : 'total_desc';
          break;
      }
    });
    _sortWords();
  }

  Future<void> _resetVocabulary() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Vocabulary?'),
        content: const Text(
          'This will delete all vocabulary words and statistics. '
          'This action cannot be undone.\n\n'
          'The core vocabulary will be restored.',
        ),
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
            child: const Text('Reset All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
        _searchQuery = '';
      });

      // Reset statistics
      if (_tracker != null) {
        await _tracker!.resetStatistics();
      }

      // Force reload from SharedPreferences
      await _loadVocabulary();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All vocabulary has been reset to core words'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
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
                  flex: 3,
                  child: InkWell(
                    onTap: () => _toggleSort('word'),
                    child: Row(
                      children: [
                        const Text(
                          'Word',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_sortBy == 'alpha_asc')
                          const Icon(Icons.arrow_upward, size: 14)
                        else if (_sortBy == 'alpha_desc')
                          const Icon(Icons.arrow_downward, size: 14),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _toggleSort('first'),
                  child: SizedBox(
                    width: 40,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '1st',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (_sortBy == 'first_desc')
                          const Icon(Icons.arrow_downward, size: 10)
                        else if (_sortBy == 'first_asc')
                          const Icon(Icons.arrow_upward, size: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _toggleSort('second'),
                  child: SizedBox(
                    width: 40,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '2nd',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (_sortBy == 'second_desc')
                          const Icon(Icons.arrow_downward, size: 10)
                        else if (_sortBy == 'second_asc')
                          const Icon(Icons.arrow_upward, size: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _toggleSort('other'),
                  child: SizedBox(
                    width: 40,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '3+',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (_sortBy == 'other_desc')
                          const Icon(Icons.arrow_downward, size: 10)
                        else if (_sortBy == 'other_asc')
                          const Icon(Icons.arrow_upward, size: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _toggleSort('total'),
                  child: SizedBox(
                    width: 50,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 2),
                        if (_sortBy == 'total_desc')
                          const Icon(Icons.arrow_downward, size: 12)
                        else if (_sortBy == 'total_asc')
                          const Icon(Icons.arrow_upward, size: 12),
                      ],
                    ),
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
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey[200]!),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    word.text,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    '${word.firstWordCount}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    '${word.secondWordCount}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    '${word.otherWordCount}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 50,
                                  child: Text(
                                    '${word.usageCount}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[800],
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  color: Colors.red[400],
                                  onPressed: () => _deleteWord(word),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Reset button at bottom
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _resetVocabulary,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Reset All Vocabulary'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
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
