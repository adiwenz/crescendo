import 'package:flutter/material.dart';

import '../../services/range_store.dart';
import '../../services/vocal_range_service.dart';
import '../../utils/pitch_math.dart';

class SelectVocalRangeScreen extends StatefulWidget {
  const SelectVocalRangeScreen({super.key});

  @override
  State<SelectVocalRangeScreen> createState() => _SelectVocalRangeScreenState();
}

class _SelectVocalRangeScreenState extends State<SelectVocalRangeScreen> {
  final VocalRangeService _vocalRangeService = VocalRangeService();
  final RangeStore _rangeStore = RangeStore();
  
  // Generate list of notes from C2 to C6 (MIDI 36-96) in descending order
  final List<int> _availableNotes = List.generate(61, (i) => 96 - i); // 96 down to 36
  
  int? _selectedLowestMidi;
  int? _selectedHighestMidi;
  int? _initialLowestMidi;
  int? _initialHighestMidi;
  bool _loading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentRange();
  }

  Future<void> _loadCurrentRange() async {
    final (lowest, highest) = await _vocalRangeService.getRange();
    setState(() {
      _selectedLowestMidi = lowest;
      _selectedHighestMidi = highest;
      _initialLowestMidi = lowest;
      _initialHighestMidi = highest;
      _loading = false;
    });
  }

  String _getNoteLabel(int midi) {
    return PitchMath.midiToName(midi);
  }

  Future<void> _saveRange() async {
    if (_selectedLowestMidi == null || _selectedHighestMidi == null) {
      return; // Don't save if not both selected
    }
    
    if (_selectedLowestMidi! >= _selectedHighestMidi!) {
      return; // Don't save if invalid
    }
    
    // Check if range has changed
    if (_selectedLowestMidi != _initialLowestMidi || _selectedHighestMidi != _initialHighestMidi) {
      _hasChanges = true;
    }
    
    // Silently auto-save - no snackbar or navigation
    await _rangeStore.saveRange(
      lowestMidi: _selectedLowestMidi!,
      highestMidi: _selectedHighestMidi!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Vocal Range'),
        leading: BackButton(
          onPressed: () {
            Navigator.of(context).pop(_hasChanges);
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select your vocal range',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose the lowest and highest notes you can comfortably sing. Exercises will be adjusted to fit within this range.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 32),
                  // Lowest note dropdown
                  Text(
                    'Lowest Note',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _selectedLowestMidi,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    items: _availableNotes
                        .where((midi) => _selectedHighestMidi == null || midi < _selectedHighestMidi!)
                        .map((midi) {
                      return DropdownMenuItem<int>(
                        value: midi,
                        child: Text(_getNoteLabel(midi)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedLowestMidi = value;
                        // Ensure highest is still higher than lowest
                        if (_selectedHighestMidi != null && value != null && _selectedHighestMidi! <= value) {
                          _selectedHighestMidi = null;
                        }
                      });
                      // Auto-save if both are selected and valid
                      if (value != null && _selectedHighestMidi != null && _selectedHighestMidi! > value) {
                        _saveRange();
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  // Highest note dropdown
                  Text(
                    'Highest Note',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _selectedHighestMidi,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    items: _availableNotes
                        .where((midi) => _selectedLowestMidi == null || midi > _selectedLowestMidi!)
                        .map((midi) {
                      return DropdownMenuItem<int>(
                        value: midi,
                        child: Text(_getNoteLabel(midi)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedHighestMidi = value;
                      });
                      // Auto-save if both are selected and valid
                      if (value != null && _selectedLowestMidi != null && value > _selectedLowestMidi!) {
                        _saveRange();
                      }
                    },
                  ),
                  // Range preview - right under the dropdowns
                  if (_selectedLowestMidi != null && _selectedHighestMidi != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Range: ',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            '${_getNoteLabel(_selectedLowestMidi!)} – ${_getNoteLabel(_selectedHighestMidi!)}',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
    );
  }
}
