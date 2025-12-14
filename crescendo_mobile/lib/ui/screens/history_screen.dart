import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../models/take.dart';
import '../../services/storage/take_repository.dart';
import '../state.dart';
import '../widgets/pitch_graph.dart';
import '../widgets/take_list_item.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final repo = TakeRepository();
  final _player = AudioPlayer();
  final appState = AppState();
  late final VoidCallback _takesListener;
  List<Take> takes = [];
  Take? selected;
  Take? compare;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _takesListener = () => _load();
    appState.takesVersion.addListener(_takesListener);
    _load();
  }

  @override
  void dispose() {
    appState.takesVersion.removeListener(_takesListener);
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await repo.fetchAll();
    setState(() {
      takes = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : takes.isEmpty
                      ? const Center(child: Text('No takes yet. Save a take to see it here.'))
                      : ListView.builder(
                          itemCount: takes.length,
                          itemBuilder: (context, idx) {
                            final t = takes[idx];
                            return TakeListItem(
                              take: t,
                              selected: selected?.id == t.id,
                              onTap: () => setState(() {
                                if (selected == null) {
                                  selected = t;
                                } else if (compare == null && t.id != selected!.id) {
                                  compare = t;
                                } else {
                                  selected = t;
                                  compare = null;
                                }
                              }),
                            );
                          },
                        ),
            ),
          ),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Selected: ${selected!.name} (${selected!.metrics.score.toStringAsFixed(1)})'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final path = selected!.audioPath;
                          if (!await File(path).exists()) {
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('Audio file not found at $path')));
                            }
                            return;
                          }
                          await _player.stop();
                          await _player.setReleaseMode(ReleaseMode.stop);
                          await _player.play(DeviceFileSource(path));
                        },
                        child: const Text('Play'),
                      ),
                      if (compare != null)
                        Text('Compare vs ${compare!.name} (Δ ${(selected!.metrics.score - compare!.metrics.score).toStringAsFixed(1)})'),
                      IconButton(
                        tooltip: 'Refresh history',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: PitchGraph(
                      frames: selected!.frames,
                      reference: const [],
                      playheadTime: 0,
                    ),
                  ),
                  if (compare != null)
                    SizedBox(
                      height: 160,
                      child: PitchGraph(
                        frames: compare!.frames,
                        reference: const [],
                        playheadTime: 0,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
