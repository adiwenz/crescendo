import 'dart:typed_data';
import 'dart:io';
import 'midi_score.dart';

/// Export MIDI score to Standard MIDI File (SMF) format
class MidiExporter {
  /// Export MIDI score to SMF bytes
  static Uint8List exportToSmf(MidiScore score) {
    final events = score.sortedEvents;
    final buffer = BytesBuilder();

    // SMF Header Chunk
    // "MThd" (4 bytes) + length (4 bytes) + format (2) + tracks (2) + division (2)
    buffer.addByte(0x4D); // 'M'
    buffer.addByte(0x54); // 'T'
    buffer.addByte(0x68); // 'h'
    buffer.addByte(0x64); // 'd'
    buffer.addByte(0x00);
    buffer.addByte(0x00);
    buffer.addByte(0x00);
    buffer.addByte(0x06); // Header length = 6
    buffer.addByte(0x00);
    buffer.addByte(0x01); // Format 1 (multi-track)
    buffer.addByte((score.numTracks >> 8) & 0xFF);
    buffer.addByte(score.numTracks & 0xFF);
    buffer.addByte((score.ppq >> 8) & 0xFF);
    buffer.addByte(score.ppq & 0xFF);

    // Track Chunk
    final trackData = BytesBuilder();
    int lastTick = 0;

    // Tempo meta event (microseconds per quarter note)
    final tempoMicroseconds = (60000000 / score.tempoBpm).round();
    final tempoTick = 0;
    final tempoDelta = tempoTick - lastTick;
    _writeVarLength(trackData, tempoDelta);
    trackData.addByte(0xFF); // Meta event
    trackData.addByte(0x51); // Set Tempo
    trackData.addByte(0x03); // Length
    trackData.addByte((tempoMicroseconds >> 16) & 0xFF);
    trackData.addByte((tempoMicroseconds >> 8) & 0xFF);
    trackData.addByte(tempoMicroseconds & 0xFF);
    lastTick = tempoTick;

    // Write all MIDI events
    for (final event in events) {
      final delta = event.tick - lastTick;
      _writeVarLength(trackData, delta);
      _writeMidiEvent(trackData, event);
      lastTick = event.tick;
    }

    // End of track
    _writeVarLength(trackData, 0);
    trackData.addByte(0xFF); // Meta event
    trackData.addByte(0x2F); // End of Track
    trackData.addByte(0x00); // Length

    final trackBytes = trackData.takeBytes();
    final trackLength = trackBytes.length;

    // Write track chunk header
    buffer.addByte(0x4D); // 'M'
    buffer.addByte(0x54); // 'T'
    buffer.addByte(0x72); // 'r'
    buffer.addByte(0x6B); // 'k'
    buffer.addByte((trackLength >> 24) & 0xFF);
    buffer.addByte((trackLength >> 16) & 0xFF);
    buffer.addByte((trackLength >> 8) & 0xFF);
    buffer.addByte(trackLength & 0xFF);
    buffer.add(trackBytes);

    return buffer.takeBytes();
  }

  /// Write variable-length quantity
  static void _writeVarLength(BytesBuilder buffer, int value) {
    if (value < 0) value = 0;
    final bytes = <int>[];
    var v = value;
    bytes.add(v & 0x7F);
    v >>= 7;
    while (v > 0) {
      bytes.insert(0, 0x80 | (v & 0x7F));
      v >>= 7;
    }
    for (final b in bytes) {
      buffer.addByte(b);
    }
  }

  /// Write MIDI event
  static void _writeMidiEvent(BytesBuilder buffer, MidiEvent event) {
    final statusByte = _getStatusByte(event.type, event.channel);
    buffer.addByte(statusByte);

    switch (event.type) {
      case MidiEventType.noteOn:
        buffer.addByte(event.data['note']! & 0x7F);
        buffer.addByte(event.data['velocity']! & 0x7F);
        break;
      case MidiEventType.noteOff:
        buffer.addByte(event.data['note']! & 0x7F);
        buffer.addByte(event.data['velocity']! & 0x7F);
        break;
      case MidiEventType.pitchBend:
        final value = event.data['value']!;
        final lsb = value & 0x7F;
        final msb = (value >> 7) & 0x7F;
        buffer.addByte(lsb);
        buffer.addByte(msb);
        break;
      case MidiEventType.controlChange:
        buffer.addByte(event.data['controller']! & 0x7F);
        buffer.addByte(event.data['value']! & 0x7F);
        break;
      case MidiEventType.programChange:
        buffer.addByte(event.data['program']! & 0x7F);
        break;
      case MidiEventType.rpnMsb:
        // CC 101 (RPN MSB)
        buffer.addByte(101);
        buffer.addByte(event.data['value']! & 0x7F);
        break;
      case MidiEventType.rpnLsb:
        // CC 100 (RPN LSB)
        buffer.addByte(100);
        buffer.addByte(event.data['value']! & 0x7F);
        break;
      case MidiEventType.dataEntryMsb:
        // CC 6 (Data Entry MSB)
        buffer.addByte(6);
        buffer.addByte(event.data['value']! & 0x7F);
        break;
      case MidiEventType.dataEntryLsb:
        // CC 38 (Data Entry LSB)
        buffer.addByte(38);
        buffer.addByte(event.data['value']! & 0x7F);
        break;
      case MidiEventType.rpnNull:
        // CC 101 = 127, CC 100 = 127 (null RPN)
        buffer.addByte(101);
        buffer.addByte(127);
        buffer.addByte(100);
        buffer.addByte(127);
        break;
    }
  }

  /// Get status byte for event type
  static int _getStatusByte(MidiEventType type, int channel) {
    final ch = channel & 0x0F;
    switch (type) {
      case MidiEventType.noteOn:
        return 0x90 | ch;
      case MidiEventType.noteOff:
        return 0x80 | ch;
      case MidiEventType.pitchBend:
        return 0xE0 | ch;
      case MidiEventType.controlChange:
        return 0xB0 | ch;
      case MidiEventType.programChange:
        return 0xC0 | ch;
      case MidiEventType.rpnMsb:
      case MidiEventType.rpnLsb:
      case MidiEventType.dataEntryMsb:
      case MidiEventType.dataEntryLsb:
      case MidiEventType.rpnNull:
        return 0xB0 | ch; // Control Change
    }
  }
}
