import 'dart:convert';
import 'dart:collection';
import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import '../models/video.dart';

class YouTubeApiException implements Exception {
  YouTubeApiException(this.message, this.statusCode);

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

class YouTubeApi {
  YouTubeApi({required this.authHeaders});

  final Map<String, String> authHeaders;
  static const String _baseUrl = 'https://www.googleapis.com/youtube/v3';
  static const Duration _timeout = Duration(seconds: 15);

  Future<List<Channel>> fetchSubscriptions() async {
    final List<Channel> channels = [];
    String? pageToken;

    do {
      final uri = Uri.parse('$_baseUrl/subscriptions').replace(
        queryParameters: {
          'part': 'snippet',
          'mine': 'true',
          'maxResults': '50',
          if (pageToken != null) 'pageToken': pageToken,
        },
      );

      http.Response response;
      try {
        response = await http.get(uri, headers: authHeaders).timeout(_timeout);
      } on TimeoutException {
        throw YouTubeApiException('구독 채널 요청 시간이 초과되었습니다.', 408);
      } catch (_) {
        throw YouTubeApiException('구독 채널 요청에 실패했습니다.', 0);
      }
      if (response.statusCode != 200) {
        throw YouTubeApiException(
          '구독 채널을 불러오지 못했습니다. (${response.statusCode})',
          response.statusCode,
        );
      }

      Map<String, dynamic> data;
      try {
        data = json.decode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw YouTubeApiException('구독 채널 응답 파싱에 실패했습니다.', 0);
      }
      final items =
          (data['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      for (final item in items) {
        final snippet = item['snippet'] as Map<String, dynamic>?;
        if (snippet == null) continue;
        final resourceId = snippet['resourceId'] as Map<String, dynamic>?;
        final channelId = resourceId?['channelId'] as String?;
        final title = snippet['title'] as String?;
        if (channelId == null || title == null) continue;
        final thumbnailUrl =
            _pickThumbnail(snippet['thumbnails'] as Map<String, dynamic>?);

        channels.add(
          Channel(
            id: channelId,
            youtubeChannelId: channelId,
            title: title,
            thumbnailUrl: thumbnailUrl ?? '',
          ),
        );
      }

      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    return channels;
  }

  Future<List<Video>> fetchLatestVideos(List<String> channelIds) async {
    final uniqueChannelIds = LinkedHashSet<String>.from(
      channelIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    ).toList();
    if (uniqueChannelIds.isEmpty) {
      return <Video>[];
    }

    // Avoid flooding YouTube API while still reducing total wait time.
    const batchSize = 4;
    final videosById = <String, Video>{};
    for (var start = 0; start < uniqueChannelIds.length; start += batchSize) {
      final end = min(start + batchSize, uniqueChannelIds.length);
      final batch = uniqueChannelIds.sublist(start, end);
      final batchResults = await Future.wait(
        batch.map(_fetchLatestVideosByChannel),
        eagerError: true,
      );
      for (final channelVideos in batchResults) {
        for (final video in channelVideos) {
          videosById[video.id] = video;
        }
      }
    }

    final videos = videosById.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return videos;
  }

  String? _pickThumbnail(Map<String, dynamic>? thumbnails) {
    if (thumbnails == null) return null;
    final order = ['high', 'medium', 'default'];
    for (final key in order) {
      final data = thumbnails[key] as Map<String, dynamic>?;
      final url = data?['url'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  Future<List<Video>> _fetchLatestVideosByChannel(String channelId) async {
    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {
        'part': 'snippet',
        'channelId': channelId,
        'maxResults': '6',
        'order': 'date',
        'type': 'video',
      },
    );

    http.Response response;
    try {
      response = await http.get(uri, headers: authHeaders).timeout(_timeout);
    } on TimeoutException {
      return <Video>[];
    } catch (_) {
      return <Video>[];
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw YouTubeApiException(
          '영상 목록을 불러오지 못했습니다. (${response.statusCode})',
          response.statusCode,
        );
      }
      return <Video>[];
    }

    Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return <Video>[];
    }
    final items =
        (data['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final videos = <Video>[];

    for (final item in items) {
      final idMap = item['id'] as Map<String, dynamic>?;
      final snippet = item['snippet'] as Map<String, dynamic>?;
      final videoId = idMap?['videoId'] as String?;
      final title = (snippet?['title'] as String?)?.trim();
      final publishedAt = snippet?['publishedAt'] as String?;
      final parsedPublishedAt =
          publishedAt == null ? null : DateTime.tryParse(publishedAt);
      final snippetChannelId = snippet?['channelId'] as String? ?? channelId;

      if (videoId == null ||
          title == null ||
          title.isEmpty ||
          parsedPublishedAt == null) {
        continue;
      }

      final thumbnailUrl =
          _pickThumbnail(snippet?['thumbnails'] as Map<String, dynamic>?);

      videos.add(
        Video(
          id: videoId,
          youtubeId: videoId,
          channelId: snippetChannelId,
          title: title,
          publishedAt: parsedPublishedAt,
          thumbnailUrl: thumbnailUrl ?? '',
        ),
      );
    }

    return videos;
  }
}
