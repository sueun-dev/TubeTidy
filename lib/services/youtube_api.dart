import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import '../models/video.dart';

class YouTubeApi {
  YouTubeApi({required this.authHeaders});

  final Map<String, String> authHeaders;
  static const String _baseUrl = 'https://www.googleapis.com/youtube/v3';

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

      final response = await http.get(uri, headers: authHeaders);
      if (response.statusCode != 200) {
        throw Exception('구독 채널을 불러오지 못했습니다. (${response.statusCode})');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      for (final item in items) {
        final snippet = item['snippet'] as Map<String, dynamic>?;
        if (snippet == null) continue;
        final resourceId = snippet['resourceId'] as Map<String, dynamic>?;
        final channelId = resourceId?['channelId'] as String?;
        final title = snippet['title'] as String?;
        if (channelId == null || title == null) continue;
        final thumbnailUrl = _pickThumbnail(snippet['thumbnails'] as Map<String, dynamic>?);

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
    final List<Video> videos = [];

    for (final channelId in channelIds) {
      final uri = Uri.parse('$_baseUrl/search').replace(
        queryParameters: {
          'part': 'snippet',
          'channelId': channelId,
          'maxResults': '6',
          'order': 'date',
          'type': 'video',
        },
      );

      final response = await http.get(uri, headers: authHeaders);
      if (response.statusCode != 200) {
        continue;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      for (final item in items) {
        final idMap = item['id'] as Map<String, dynamic>?;
        final snippet = item['snippet'] as Map<String, dynamic>?;
        final videoId = idMap?['videoId'] as String?;
        final title = snippet?['title'] as String?;
        final publishedAt = snippet?['publishedAt'] as String?;
        final snippetChannelId = snippet?['channelId'] as String? ?? channelId;

        if (videoId == null || title == null || publishedAt == null) continue;

        final thumbnailUrl = _pickThumbnail(snippet?['thumbnails'] as Map<String, dynamic>?);

        videos.add(
          Video(
            id: videoId,
            youtubeId: videoId,
            channelId: snippetChannelId,
            title: title,
            publishedAt: DateTime.tryParse(publishedAt) ?? DateTime.now(),
            thumbnailUrl: thumbnailUrl ?? '',
          ),
        );
      }
    }

    videos.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
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
}
