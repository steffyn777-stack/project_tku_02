import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

typedef SignalingCallback = void Function(Map<String, dynamic> signal);

class WebRtcService {
  static final WebRtcService _instance = WebRtcService._internal();
  factory WebRtcService() => _instance;
  WebRtcService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get onLocalStream => _localStreamController.stream;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;

  MediaStream? get currentLocalStream => _localStream;
  MediaStream? get currentRemoteStream => _remoteStream;

  SignalingCallback? onSignalingMessage;

  final List<RTCIceCandidate> _remoteIceCandidates = [];
  bool _remoteDescriptionSet = false;

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  Future<void> init(
      {required bool isController, bool captureVideo = true}) async {
    try {
      if (_peerConnection != null) {
        await dispose();
      }

      _peerConnection =
          await createPeerConnection(_configuration, _constraints);
      _remoteDescriptionSet = false;
      _remoteIceCandidates.clear();

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (onSignalingMessage != null) {
          onSignalingMessage!({
            'type': 'candidate',
            'candidate': candidate.toMap(),
          });
        }
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteStreamController.add(_remoteStream);
        }
      };

      if (isController && captureVideo) {
        final Map<String, dynamic> mediaConstraints = {
          'audio': false,
          'video': {
            'facingMode': 'user',
            'width': 640,
            'height': 480,
            'frameRate': 30,
          }
        };

        _localStream =
            await navigator.mediaDevices.getUserMedia(mediaConstraints);
        _localStreamController.add(_localStream);

        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });

        RTCSessionDescription offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);

        if (onSignalingMessage != null) {
          onSignalingMessage!({
            'type': 'offer',
            'sdp': offer.sdp,
          });
        }
      }
    } catch (e) {
      debugPrint('WebRtcService init Error: $e');
    }
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    if (_peerConnection == null) {
      debugPrint('WebRtcService: handleSignal called before init. Ignoring.');
      return;
    }

    try {
      final String type = signal['type'];
      if (type == 'offer') {
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(signal['sdp'], 'offer'));
        _remoteDescriptionSet = true;

        for (var cand in _remoteIceCandidates) {
          await _peerConnection!.addCandidate(cand);
        }
        _remoteIceCandidates.clear();

        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        if (onSignalingMessage != null) {
          onSignalingMessage!({
            'type': 'answer',
            'sdp': answer.sdp,
          });
        }
      } else if (type == 'answer') {
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(signal['sdp'], 'answer'));
        _remoteDescriptionSet = true;

        for (var cand in _remoteIceCandidates) {
          await _peerConnection!.addCandidate(cand);
        }
        _remoteIceCandidates.clear();
      } else if (type == 'candidate') {
        final candidateMap = signal['candidate'];
        final candidate = RTCIceCandidate(
          candidateMap['candidate'],
          candidateMap['sdpMid'],
          candidateMap['sdpMLineIndex'],
        );

        if (_remoteDescriptionSet) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _remoteIceCandidates.add(candidate);
        }
      }
    } catch (e) {
      debugPrint('WebRtcService handleSignal Error: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _localStream?.dispose();
      _localStream = null;
      _remoteStream = null;
      await _peerConnection?.dispose();
      _peerConnection = null;
      _remoteDescriptionSet = false;
      _remoteIceCandidates.clear();
      _localStreamController.add(null);
      _remoteStreamController.add(null);
    } catch (e) {
      debugPrint('WebRtcService dispose Error: $e');
    }
  }
}