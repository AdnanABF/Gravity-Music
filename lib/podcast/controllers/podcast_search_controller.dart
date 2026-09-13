// podcast/controllers/podcast_search_controller.dart
//
// Podcast search state. Owns its own TextEditingController and FocusNode (the
// music SearchUiController owns music's, and the two never meet).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../services/podcast_search_service.dart';

class PodcastSearchController extends GetxController {
  final query = ''.obs;
  final results = PodcastSearchResults.empty.obs;
  final loading = false.obs;

  final textController = TextEditingController();
  final focusNode = FocusNode();

  Timer? _debounce;

  void onChanged(String value) {
    query.value = value;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      results.value = PodcastSearchResults.empty;
      loading.value = false;
      return;
    }
    loading.value = true;
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(value));
  }

  /// Runs a query immediately (topic chips), mirroring it into the field.
  void runQuery(String value) {
    query.value = value;
    textController.text = value;
    textController.selection =
        TextSelection.collapsed(offset: value.length);
    _debounce?.cancel();
    loading.value = true;
    _run(value);
  }

  Future<void> _run(String value) async {
    final res = await PodcastSearchService.search(value);
    if (query.value.trim() != value.trim()) return; // superseded
    results.value = res;
    loading.value = false;
  }

  void clear() {
    textController.clear();
    onChanged('');
  }

  @override
  void onClose() {
    _debounce?.cancel();
    textController.dispose();
    focusNode.dispose();
    super.onClose();
  }
}
