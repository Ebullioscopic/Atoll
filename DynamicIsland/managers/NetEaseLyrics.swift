/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// Lyrics from NetEase Cloud Music, asked only after LRCLIB has come up empty.
///
/// LRCLIB is a community catalogue and most Chinese-language releases were
/// never submitted to it, so a NetEase Cloud Music user with lyrics switched on
/// saw "No lyrics found" for most of what they played (#713). NetEase's own
/// lyric store covers its own catalogue, but the player publishes only title,
/// artist, album and duration through Now Playing -- never a song id -- so
/// the track has to be found again by search before its lyrics can be asked
/// for. The duration is what makes that search trustworthy: a title-and-artist
/// hit whose length is off by more than a couple of seconds is a different
/// recording, and its timestamps would land every line at the wrong moment.
enum NetEaseLyrics {

    struct Song: Equatable {
        let id: Int
        let name: String
        let artists: [String]
        /// Seconds. NetEase reports milliseconds; converted on parse.
        let duration: TimeInterval
    }

    /// How far a result's length may sit from the playing track's before it is
    /// taken for a different recording. Players round the duration they
    /// publish, so an exact comparison would reject the right song.
    static let durationTolerance: TimeInterval = 2

    /// Returns the LRC text for the closest matching track, or nil when NetEase
    /// has no plausible match or no lyrics for it. Throws only on transport
    /// failure, so the caller can tell "nothing there" from "could not ask".
    static func fetchLRC(
        title: String,
        artist: String,
        duration: TimeInterval,
        session: URLSession = .shared
    ) async throws -> String? {
        guard let searchURL = searchURL(title: title, artist: artist) else { return nil }

        let (searchData, searchResponse) = try await session.data(from: searchURL)
        guard (searchResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let songs = parseSearchResponse(searchData)
        guard let song = bestMatch(in: songs, title: title, artist: artist, duration: duration),
              let lyricURL = lyricURL(songID: song.id)
        else { return nil }

        let (lyricData, lyricResponse) = try await session.data(from: lyricURL)
        guard (lyricResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        return parseLyricResponse(lyricData)
    }

    // MARK: - Requests

    /// Characters allowed unescaped in a query *value*. `urlQueryAllowed` keeps
    /// `&`, `+`, `=` and `/` literal because they are structural in a query --
    /// which is exactly why a title containing one must have it escaped.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=/?#")
        return allowed
    }()

    static func searchURL(title: String, artist: String) -> URL? {
        // NetEase joins collaborating artists with "/" when it publishes the
        // track; as a search term that is one token nobody is filed under.
        let query = "\(title) \(artist.replacingOccurrences(of: "/", with: " "))"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        return URL(string: "https://music.163.com/api/search/get/web?s=\(encoded)&type=1&limit=10")
    }

    static func lyricURL(songID: Int) -> URL? {
        // lv, kv and tv name the line-synced, karaoke and translated versions
        // wanted; -1 is "whatever is current". A positive version number is a
        // comparison against that version, and for some tracks it comes back
        // with the body left empty. Only the LRC is shown.
        URL(string: "https://music.163.com/api/song/lyric?id=\(songID)&lv=-1&kv=-1&tv=-1")
    }

    // MARK: - Responses

    static func parseSearchResponse(_ data: Data) -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]]
        else { return [] }

        return songs.compactMap { song in
            guard let id = song["id"] as? Int, let name = song["name"] as? String else { return nil }
            let artists = (song["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let milliseconds = (song["duration"] as? Double) ?? 0
            return Song(id: id, name: name, artists: artists, duration: milliseconds / 1000)
        }
    }

    /// The LRC body, or nil when NetEase says there is none. The text is
    /// returned exactly as served: credit lines and all, since they carry
    /// timestamps and the parser treats them like any other line.
    static func parseLyricResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // `nolyric` marks an instrumental, `uncollected` a track NetEase has
        // never gathered lyrics for. Either may still carry a placeholder body,
        // which would show up as a one-line song.
        if json["nolyric"] as? Bool == true || json["uncollected"] as? Bool == true { return nil }

        guard let lrc = json["lrc"] as? [String: Any],
              let lyric = lrc["lyric"] as? String
        else { return nil }

        let trimmed = lyric.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Matching

    /// Filter first, then rank, for the same reason `LyricsSearchResults`
    /// does: search returns its closest guess even when that guess is another
    /// song, so the winner has to be a candidate before it can be the best one.
    static func bestMatch(in songs: [Song], title: String, artist: String, duration: TimeInterval) -> Song? {
        let title = LyricsSearchResults.normalizedForMatching(title)
        let artist = LyricsSearchResults.normalizedForMatching(artist)

        return songs
            .filter { agrees($0, title: title, artist: artist, duration: duration) }
            .max { lhs, rhs in
                let lhsScore = score(for: lhs, title: title, artist: artist)
                let rhsScore = score(for: rhs, title: title, artist: artist)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                // Equal on words: the one closer in length is the likelier
                // pressing of the same recording.
                return distance(lhs.duration, from: duration) > distance(rhs.duration, from: duration)
            }
    }

    static func agrees(_ song: Song, title: String, artist: String, duration: TimeInterval) -> Bool {
        let songTitle = LyricsSearchResults.normalizedForMatching(song.name)
        guard overlaps(songTitle, title),
              !LyricsSearchResults.carriesUnrequestedVersion(songTitle, requested: title)
        else { return false }

        // The request carries however the player joined the collaborators --
        // "A/B" from NetEase, "A & B" or "A, B" elsewhere -- and the result
        // lists them one by one. Any listed artist appearing in the request is
        // agreement; requiring the whole list would fail every duet.
        let songArtists = song.artists.map(LyricsSearchResults.normalizedForMatching)
        guard songArtists.contains(where: { overlaps($0, artist) }) else { return false }

        // A duration of zero on either side means "not reported", not "instant".
        guard duration > 0, song.duration > 0 else { return true }
        return distance(song.duration, from: duration) <= durationTolerance
    }

    static func score(for song: Song, title: String, artist: String) -> Int {
        let songTitle = LyricsSearchResults.normalizedForMatching(song.name)
        let songArtists = song.artists.map(LyricsSearchResults.normalizedForMatching)

        var score = 0

        if songTitle == title { score += 8 }
        else if overlaps(songTitle, title) { score += 4 }

        if songArtists.joined(separator: "/") == artist || songArtists == [artist] { score += 8 }
        else if songArtists.contains(where: { overlaps($0, artist) }) { score += 4 }

        return score
    }

    private static func distance(_ lhs: TimeInterval, from rhs: TimeInterval) -> TimeInterval {
        abs(lhs - rhs)
    }

    private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }
}
