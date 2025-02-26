import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:musify/helper/formatter.dart';
import 'package:musify/helper/mediaitem.dart';
import 'package:musify/services/audio_handler.dart';
import 'package:musify/services/audio_manager.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/ext_storage.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final yt = YoutubeExplode();
final OnAudioQuery _audioQuery = OnAudioQuery();

List ytplaylists = [];
List searchedList = [];
List playlists = [];
List userPlaylists = Hive.box('user').get('playlists', defaultValue: []);
List userLikedSongsList = Hive.box('user').get('likedSongs', defaultValue: []);
List suggestedPlaylists = [];
List activePlaylist = [];
List<SongModel> localSongs = [];

final lyrics = ValueNotifier<String>('null');
String _lastLyricsUrl = '';

int id = 0;

Future<List> fetchSongsList(String searchQuery) async {
  final List list = await yt.search.search(searchQuery);
  searchedList = [];
  for (final s in list) {
    searchedList.add(
      returnSongLayout(
        0,
        s.id.toString(),
        formatSongTitle(
          s.title.split('-')[s.title.split('-').length - 1].toString(),
        ),
        s.thumbnails.standardResUrl.toString(),
        s.thumbnails.lowResUrl.toString(),
        s.thumbnails.maxResUrl.toString(),
        s.title.split('-')[0].toString(),
      ),
    );
  }
  return searchedList;
}

Future get10Music(dynamic playlistid) async {
  final List playlistSongs =
      await getData('cache', 'playlist10Songs$playlistid') ?? [];
  if (playlistSongs.isEmpty) {
    int index = 0;
    await for (final song in yt.playlists.getVideos(playlistid).take(10)) {
      playlistSongs.add(
        returnSongLayout(
          index,
          song.id.toString(),
          formatSongTitle(
            song.title.split('-')[song.title.split('-').length - 1],
          ),
          song.thumbnails.standardResUrl,
          song.thumbnails.lowResUrl,
          song.thumbnails.maxResUrl,
          song.title.split('-')[0],
        ),
      );
      index += 1;
    }

    addOrUpdateData('cache', 'playlist10Songs$playlistid', playlistSongs);
  }

  return playlistSongs;
}

Future<List<dynamic>> getUserPlaylists() async {
  final playlistsByUser = [];
  for (final playlistID in userPlaylists) {
    final plist = await yt.playlists.get(playlistID);
    playlistsByUser.add({
      'ytid': plist.id,
      'title': plist.title,
      'subtitle': 'Just Updated',
      'header_desc': plist.description.length < 120
          ? plist.description
          : plist.description.substring(0, 120),
      'type': 'playlist',
      'image': '',
      'list': []
    });
  }
  return playlistsByUser;
}

void addUserPlaylist(String playlistId) {
  userPlaylists.add(playlistId);
  addOrUpdateData('user', 'playlists', userPlaylists);
}

void removeUserPlaylist(String playlistId) {
  userPlaylists.remove(playlistId);
  addOrUpdateData('user', 'playlists', userPlaylists);
}

Future<void> addUserLikedSong(dynamic songId) async {
  userLikedSongsList
      .add(await getSongDetails(userLikedSongsList.length, songId));
  addOrUpdateData('user', 'likedSongs', userLikedSongsList);
}

void removeUserLikedSong(dynamic songId) {
  userLikedSongsList.removeWhere((song) => song['ytid'] == songId);
  addOrUpdateData('user', 'likedSongs', userLikedSongsList);
}

bool isSongAlreadyLiked(dynamic songId) {
  return userLikedSongsList.where((song) => song['ytid'] == songId).isNotEmpty;
}

Future<List> getPlaylists([int? playlistsNum]) async {
  if (playlists.isEmpty) {
    final localplaylists =
        json.decode(await rootBundle.loadString('assets/db/playlists.db.json'))
            as List;
    playlists = localplaylists;
  }

  if (playlistsNum != null) {
    if (suggestedPlaylists.isEmpty) {
      suggestedPlaylists =
          (playlists.toList()..shuffle()).take(playlistsNum).toList();
    }
    return suggestedPlaylists;
  } else {
    return playlists;
  }
}

Future<List> searchPlaylist(String query) async {
  if (playlists.isEmpty) {
    final localplaylists =
        json.decode(await rootBundle.loadString('assets/db/playlists.db.json'))
            as List;
    playlists = localplaylists;
  }

  return playlists
      .where((playlist) =>
          playlist['title'].toLowerCase().contains(query.toLowerCase()))
      .toList();
}

Future<Map> getRandomSong() async {
  if (playlists.isEmpty) {
    playlists =
        json.decode(await rootBundle.loadString('assets/db/playlists.db.json'))
            as List;
  }
  final random = Random();
  final playlistId = playlists[random.nextInt(playlists.length)]['ytid'];
  final playlistSongs =
      await getData('cache', 'playlistSongs$playlistId') ?? [];

  if (playlistSongs.isEmpty) {
    final songs = await yt.playlists.getVideos(playlistId).take(5).toList();
    final choosedSong = songs[random.nextInt(playlistSongs.length)];

    return returnSongLayout(
      0,
      choosedSong.id.toString(),
      formatSongTitle(
        choosedSong.title.split('-')[choosedSong.title.split('-').length - 1],
      ),
      choosedSong.thumbnails.standardResUrl,
      choosedSong.thumbnails.lowResUrl,
      choosedSong.thumbnails.maxResUrl,
      choosedSong.title.split('-')[0],
    );
  } else {
    return playlistSongs[random.nextInt(playlistSongs.length)];
  }
}

Future getSongsFromPlaylist(dynamic playlistid) async {
  final List playlistSongs =
      await getData('cache', 'playlistSongs$playlistid') ?? [];
  if (playlistSongs.isEmpty) {
    int index = 0;
    await for (final song in yt.playlists.getVideos(playlistid)) {
      playlistSongs.add(
        returnSongLayout(
          index,
          song.id.toString(),
          formatSongTitle(
            song.title.split('-')[song.title.split('-').length - 1],
          ),
          song.thumbnails.standardResUrl,
          song.thumbnails.lowResUrl,
          song.thumbnails.maxResUrl,
          song.title.split('-')[0],
        ),
      );
      index += 1;
    }
    addOrUpdateData('cache', 'playlistSongs$playlistid', playlistSongs);
  }

  return playlistSongs;
}

Future<void> setActivePlaylist(List plist) async {
  if (plist is List<SongModel>) {
    activePlaylist = [];
    id = 0;
    final List<MediaItem> activeTempPlaylist = [];
    for (final song in plist) {
      activeTempPlaylist.add(songModelToMediaItem(song, song.data));
    }
    await MyAudioHandler().addQueueItems(activeTempPlaylist);

    await play();
  } else {
    activePlaylist = plist;
    id = 0;
    await playSong(activePlaylist[id]);
  }
}

Future getPlaylistInfoForWidget(dynamic id) async {
  var searchPlaylist = playlists.where((list) => list['ytid'] == id).toList();

  if (searchPlaylist.isEmpty) {
    final usPlaylists = await getUserPlaylists();
    searchPlaylist = usPlaylists.where((list) => list['ytid'] == id).toList();
  }

  final playlist = searchPlaylist[0];

  if (playlist['list'].length == 0) {
    searchPlaylist[searchPlaylist.indexOf(playlist)]['list'] =
        await getSongsFromPlaylist(playlist['ytid']);
  }

  return playlist;
}

Future<String> getSongUrl(dynamic songId) async {
  final manifest = await yt.videos.streamsClient.getManifest(songId);
  return manifest.audioOnly.withHighestBitrate().url.toString();
}

Future getSongStream(dynamic songId) async {
  final manifest = await yt.videos.streamsClient.getManifest(songId);
  return manifest.audioOnly.withHighestBitrate();
}

Future getSongDetails(dynamic songIndex, dynamic songId) async {
  final song = await yt.videos.get(songId);
  return returnSongLayout(
    songIndex,
    song.id.toString(),
    formatSongTitle(song.title.split('-')[song.title.split('-').length - 1]),
    song.thumbnails.standardResUrl,
    song.thumbnails.lowResUrl,
    song.thumbnails.maxResUrl,
    song.title.split('-')[0],
  );
}

Future<List<SongModel>> getLocalSongs() async {
  // DEFAULT:
  // SongSortType.TITLE,
  // OrderType.ASC_OR_SMALLER,
  // UriType.EXTERNAL,
  if (localSongs.isEmpty) {
    if (await Permission.storage.request().isGranted) {
      localSongs = await _audioQuery.querySongs(uriType: UriType.EXTERNAL);
      localSongs.addAll(await _audioQuery.querySongs(
          path: await ExtStorageProvider.getExtStorage(dirName: 'Musify')));
    }
  }

  return localSongs;
}

Future getSongLyrics(String artist, String title) async {
  if (_lastLyricsUrl !=
      'https://api.lyrics.ovh/v1/$artist/${title.split(" (")[0].split("|")[0].trim()}') {
    if (await getData('cache',
            'lyrics-https://api.lyrics.ovh/v1/$artist/${title.split(" (")[0].split("|")[0].trim()}') !=
        null) {
      lyrics.value = await getData('cache',
          'lyrics-https://api.lyrics.ovh/v1/$artist/${title.split(" (")[0].split("|")[0].trim()}');
    } else {
      lyrics.value = 'null';
      _lastLyricsUrl =
          'https://api.lyrics.ovh/v1/$artist/${title.split(" (")[0].split("|")[0].trim()}';
      final response = await http.get(
        Uri.parse(_lastLyricsUrl),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final lyricsResponse = await json.decode(response.body);
        if (lyricsResponse['lyrics'] != null) {
          lyrics.value = lyricsResponse['lyrics'].toString();
          addOrUpdateData('cache', 'lyrics-$_lastLyricsUrl',
              lyricsResponse['lyrics'].toString());
        } else {
          lyrics.value = 'not found';
        }
      } else {
        lyrics.value = 'not found';
        throw Exception('Failed to load lyrics');
      }
    }
  }
}
