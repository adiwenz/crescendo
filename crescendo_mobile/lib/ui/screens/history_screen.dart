import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../models/take.dart';
import '../../services/storage/take_repository.dart';
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
  List<Take> takes = [];
  Take? selected;
  Take? compare;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await repo.fetchAll();
    setState(() => takes = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
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
          if (selected != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Selected: ${selected!.name} (${selected!.metrics.score.toStringAsFixed(1)})'),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await _player.stop();
                          await _player.play(DeviceFileSource(selected!.audioPath));
                        },
                        child: const Text('Play'),
                      ),
                      const SizedBox(width: 8),
                      if (compare != null)
                        Text('Compare vs ${compare!.name} (Δ ${(selected!.metrics.score - compare!.metrics.score).toStringAsFixed(1)})'),
                    ],
                  ),
                  SizedBox(
                    height: 220,
                    child: PitchGraph(
                      frames: selected!.frames,
                      reference: const [],
                      playheadTime: 0,
                    ),
                  ),
                  if (compare != null)
                    SizedBox(
                      height: 220,
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
