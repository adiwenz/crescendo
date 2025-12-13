import 'package:flutter/material.dart';

import '../../models/take.dart';

class TakeListItem extends StatelessWidget {
  final Take take;
  final bool selected;
  final VoidCallback onTap;

  const TakeListItem({super.key, required this.take, required this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      title: Text(take.name.isNotEmpty ? take.name : take.warmupName),
      subtitle: Text('${take.warmupName} · ${take.createdAt.toLocal()}'),
      trailing: Text('${take.metrics.score.toStringAsFixed(1)}'),
      onTap: onTap,
    );
  }
}
