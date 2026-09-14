import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _musicChannel = MethodChannel('com.example.floating_downloader/music');
const _musicEvents = EventChannel('com.example.floating_downloader/music/events');

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.uri,
    this.albumArtUri,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String uri;
  final String? albumArtUri;

  factory MusicTrack.fromMap(Map<dynamic, dynamic> map) => MusicTrack(
        id: '${map['id']}',
        title: (map['title'] as String?)?.trim().isNotEmpty == true
            ? map['title'] as String
            : 'Unknown title',
        artist: (map['artist'] as String?)?.trim().isNotEmpty == true
            ? map['artist'] as String
            : 'Unknown artist',
        album: (map['album'] as String?)?.trim().isNotEmpty == true
            ? map['album'] as String
            : 'Unknown album',
        durationMs: ((map['durationMs'] ?? map['duration']) as num?)?.toInt() ?? 0,
        uri: (map['uri'] ?? map['contentUri']) as String,
        albumArtUri: map['albumArtUri'] as String?,
      );
}

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  List<MusicTrack> _tracks = const [];
  MusicTrack? _current;
  bool _loading = true;
  bool _permissionGranted = false;
  bool _playing = false;
  bool _shuffle = false;
  int _loopMode = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<dynamic>? _events;

  @override
  void initState() {
    super.initState();
    _events = _musicEvents.receiveBroadcastStream().listen(_onEvent);
    _load();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _onEvent(dynamic value) {
    if (value is! Map) return;
    final event = value['event'];
    if (event == 'state') {
      setState(() {
        _playing = value['playing'] == true;
        _position = Duration(milliseconds: (value['positionMs'] as num?)?.toInt() ?? 0);
        _duration = Duration(milliseconds: (value['durationMs'] as num?)?.toInt() ?? 0);
      });
    } else if (event == 'trackChanged' && value['track'] is Map) {
      setState(() => _current = MusicTrack.fromMap(value['track'] as Map));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final granted = await _musicChannel.invokeMethod<bool>('hasAudioPermission') ?? false;
      final result = granted
          ? await _musicChannel.invokeMethod<List<dynamic>>('scanAudio')
          : const <dynamic>[];
      setState(() {
        _permissionGranted = granted;
        _tracks = (result ?? const []).map((e) => MusicTrack.fromMap(e as Map)).toList();
      });
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Unable to scan music.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _grantAndScan() async {
    final granted = await _musicChannel.invokeMethod<bool>('requestAudioPermission') ?? false;
    if (mounted) setState(() => _permissionGranted = granted);
    if (granted) await _load();
  }

  Future<void> _playAt(int index) async {
    await _musicChannel.invokeMethod('play', {
      'tracks': _tracks.map((track) => {
            'id': track.id,
            'title': track.title,
            'artist': track.artist,
            'album': track.album,
            'durationMs': track.durationMs,
            'uri': track.uri,
            'albumArtUri': track.albumArtUri,
          }).toList(),
      'index': index,
      'shuffle': _shuffle,
    });
    setState(() => _current = _tracks[index]);
  }

  Future<void> _togglePlayback() async {
    await _musicChannel.invokeMethod(_playing ? 'pause' : 'resume');
  }

  String _format(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        const _DreamGradient(),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Aetheria Music',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      tooltip: 'Audio Studio',
                      onPressed: () => _showStudio(context),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                    IconButton(
                      tooltip: 'Scan',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body(theme)),
              if (_current != null) _miniPlayer(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_permissionGranted || _tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.16),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.white.withOpacity(.28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.library_music_rounded, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 18),
                Text(
                  !_permissionGranted ? 'Your music library is private' : 'No music found yet',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  !_permissionGranted
                      ? 'Grant audio access to discover songs stored on this device.'
                      : 'Songs longer than 30 seconds will appear here.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _grantAndScan,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(!_permissionGranted ? 'Grant Permission' : 'Scan Music'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _TrackTile(track: track, onTap: () => _playAt(index)),
        );
      },
    );
  }

  Widget _miniPlayer(ThemeData theme) {
    final max = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.18),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(.3)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.music_note_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${_current!.title}\n${_current!.artist}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              IconButton(onPressed: () => _musicChannel.invokeMethod('previous'), icon: const Icon(Icons.skip_previous_rounded)),
              IconButton(onPressed: _togglePlayback, icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
              IconButton(onPressed: () => _musicChannel.invokeMethod('next'), icon: const Icon(Icons.skip_next_rounded)),
              IconButton(
                tooltip: 'Shuffle',
                onPressed: () {
                  setState(() => _shuffle = !_shuffle);
                  _musicChannel.invokeMethod('setShuffle', _shuffle);
                },
                icon: Icon(Icons.shuffle_rounded,
                    color: _shuffle ? theme.colorScheme.primary : null),
              ),
              IconButton(
                tooltip: 'Loop',
                onPressed: () {
                  setState(() => _loopMode = (_loopMode + 1) % 3);
                  _musicChannel.invokeMethod('setLoop', _loopMode);
                },
                icon: Icon(
                  _loopMode == 1 ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: _loopMode != 0 ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(_format(_position), style: theme.textTheme.labelSmall),
              Expanded(
                child: Slider(
                  min: 0,
                  max: max,
                  value: _position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                  onChanged: (value) => setState(() => _position = Duration(milliseconds: value.toInt())),
                  onChangeEnd: (value) => _musicChannel.invokeMethod('seek', {'positionMs': value.toInt()}),
                ),
              ),
              Text(_format(_duration), style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showStudio(BuildContext context) async {
    final bands = List<double>.filled(10, 0);
    var bass = false;
    var loudness = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) {
        return Container(
          height: MediaQuery.sizeOf(context).height * .82,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: Column(
            children: [
              const Text('Audio Studio', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['Flat', 'Bass Booster', 'Rock', 'Pop', 'Classical', 'Jazz']
                    .map((preset) => ActionChip(
                          label: Text(preset),
                          onPressed: () => _musicChannel.invokeMethod(
                              'setEqualizerPreset', {'preset': _presetIndex(preset)}),
                        ))
                    .toList(),
              ),
              SwitchListTile(
                title: const Text('Bass Boost'),
                value: bass,
                onChanged: (value) {
                  setSheetState(() => bass = value);
                  _musicChannel.invokeMethod('setBassBoost', {'enabled': value});
                },
              ),
              SwitchListTile(
                title: const Text('Loudness Enhancer'),
                value: loudness,
                onChanged: (value) {
                  setSheetState(() => loudness = value);
                  _musicChannel.invokeMethod('setLoudnessEnhancer', {'enabled': value});
                },
              ),
              const Align(alignment: Alignment.centerLeft, child: Text('10-band equalizer')),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(10, (index) => Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            min: -12,
                            max: 12,
                            value: bands[index],
                            onChanged: (value) {
                              setSheetState(() => bands[index] = value);
                              _musicChannel.invokeMethod('setEqualizerBand', {'band': index, 'level': value});
                            },
                          ),
                        ),
                      )),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  int _presetIndex(String preset) => const {
        'Flat': 0,
        'Bass Booster': 1,
        'Rock': 2,
        'Pop': 3,
        'Classical': 4,
        'Jazz': 5,
      }[preset]!;
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.onTap});
  final MusicTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withOpacity(.16),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.album_rounded, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${track.artist} · ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(onPressed: onTap, icon: const Icon(Icons.play_circle_fill_rounded, size: 34)),
              ],
            ),
          ),
        ),
      );
}

class _DreamGradient extends StatelessWidget {
  const _DreamGradient();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-.8, -.9),
            radius: 1.35,
            colors: [
              const Color(0xFFDEC8FF).withOpacity(.55),
              const Color(0xFFB8F2F0).withOpacity(.35),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      );
}
