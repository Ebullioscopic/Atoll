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

/// Whether a track's metadata names a particular song at all.
///
/// A ripper that cannot identify a disc writes "Unknown Artist" and numbers the
/// tracks, so every unidentified rip ever made shares the same title and artist.
/// lrclib holds twenty different songs filed under `Track 7` by `Unknown Artist`
/// — searching for that returns an *exact* match on both fields, and none of
/// them is the track playing. Scoring the results cannot help, because the
/// scores are perfect; the question has to be asked before the search.
enum LyricsMetadata {

    /// Artist names that mean "nobody filled this in".
    private static let placeholderArtists: Set<String> = [
        "unknown artist",
        "unknown",
        "unknown artists",
        "artist unknown",
        "no artist",
        "untitled artist"
    ]

    /// Titles that mean "this is the nth file on a disc", which names a
    /// position rather than a song.
    ///
    /// Anchored, so a real song called "Untitled" by a known artist is still
    /// looked up — that is a title someone chose, and the artist identifies it.
    private static let placeholderTitlePatterns: [String] = [
        "^(audio[ _-]*)?track[ _-]*[0-9]+$",
        "^track$",
        "^untitled[ _-]*[0-9]+$",
        "^unknown([ _-]*track)?([ _-]*[0-9]+)?$"
    ]

    /// True when the metadata could belong to any number of different songs, so
    /// any lyrics found for it would be somebody else's.
    static func namesNoParticularTrack(title: String, artist: String) -> Bool {
        let normalizedTitle = normalize(title)
        let normalizedArtist = normalize(artist)

        if normalizedTitle.isEmpty || normalizedArtist.isEmpty { return true }
        if placeholderArtists.contains(normalizedArtist) { return true }

        // An unnamed artist is the stronger signal, but a title that is only a
        // track number cannot identify a song either, whoever recorded it.
        return placeholderTitlePatterns.contains { pattern in
            normalizedTitle.range(of: pattern, options: [.regularExpression]) != nil
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

/// Picking the right row out of an lrclib search response.
///
/// Two things have to be true of the row that wins: it has to be the best of
/// the candidates, and it has to be a candidate at all. Search *ranks*, it does
/// not filter — lrclib returns its closest guess even when that guess shares
/// nothing with the track playing, so without a floor the best of a bad set is
/// accepted silently.
enum LyricsSearchResults {

    static func bestMatch(
        in results: [[String: Any]],
        artist: String,
        title: String,
        album: String
    ) -> [String: Any]? {
        let artist = normalizedForMatching(artist)
        let title = normalizedForMatching(title)
        let album = normalizedForMatching(album)

        // Filter first, then rank. Ranking first and checking the winner
        // afterwards throws away a good row whenever a bad one outscores it --
        // a wrong artist with an exactly matching title, album and synced
        // lyrics outscores a right artist matched only by containment.
        return results
            .filter { agreesOnTitleAndArtist($0, artist: artist, title: title) }
            .max { lhs, rhs in
                score(for: lhs, artist: artist, title: title, album: album)
                    < score(for: rhs, artist: artist, title: title, album: album)
            }
    }

    /// Whether a result is plausibly the same recording, rather than merely the
    /// closest thing lrclib had. Both fields have to land: agreeing on the
    /// title alone is how covers, remixes and karaoke tracks get through.
    static func agreesOnTitleAndArtist(_ result: [String: Any], artist: String, title: String) -> Bool {
        let resultTitle = field(result, "trackName")

        guard overlaps(resultTitle, title),
              overlaps(field(result, "artistName"), artist),
              !carriesUnrequestedVersion(resultTitle, requested: title)
        else { return false }

        return true
    }

    /// Re-recordings whose words are the requested song's but whose *timings*
    /// are not.
    ///
    /// Containment is deliberately loose, so "Crimewave (Sped Up)" agrees with a
    /// request for "Crimewave". Usually harmless -- an exact title outscores a
    /// suffixed one, so the plain row wins when it exists -- but when the
    /// variant is all lrclib has, every line lands at the wrong moment. Better
    /// no lyrics than lyrics that drift.
    ///
    /// Only markers absent from the request count, so playing the sped-up
    /// version still finds the sped-up lyrics.
    private static func carriesUnrequestedVersion(_ resultTitle: String, requested: String) -> Bool {
        versionMarkers.contains { marker in
            containsWord(resultTitle, marker) && !containsWord(requested, marker)
        }
    }

    /// Deliberately excludes remaster, live, mono and stereo: the request title
    /// has those stripped before it ever gets here, so treating them as markers
    /// would reject the very rows they were stripped to find.
    private static let versionMarkers: [String] = [
        "karaoke",
        "instrumental",
        "sped up",
        "spedup",
        "slowed",
        "nightcore",
        "remix",
        "cover",
        "tribute",
        "acapella",
        "a cappella",
        "made popular by",
        "originally performed by"
    ]

    /// Whole-word matching, so "undercover" is not a cover and "remixed" still
    /// is.
    private static func containsWord(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: "\\b" + NSRegularExpression.escapedPattern(for: needle), options: [.regularExpression]) != nil
    }

    static func score(for result: [String: Any], artist: String, title: String, album: String) -> Int {
        let resultArtist = field(result, "artistName")
        let resultTitle = field(result, "trackName")
        let resultAlbum = field(result, "albumName")

        var score = 0

        if resultTitle == title { score += 8 }
        else if resultTitle.contains(title) || title.contains(resultTitle) { score += 4 }

        if resultArtist == artist { score += 8 }
        else if resultArtist.contains(artist) || artist.contains(resultArtist) { score += 4 }

        // Both sides have to carry text. The title and artist are already
        // non-empty by the time a result is a candidate, but nothing filters on
        // the album, and containment against an empty needle is a coin flip
        // decided by which overload resolves.
        if !album.isEmpty, !resultAlbum.isEmpty {
            if resultAlbum == album { score += 4 }
            else if resultAlbum.contains(album) || album.contains(resultAlbum) { score += 2 }
        }

        if !(result["syncedLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 3
        }

        return score
    }

    private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    private static func field(_ result: [String: Any], _ key: String) -> String {
        normalizedForMatching((result[key] as? String) ?? "")
    }

    /// Both sides of every comparison have to come through here.
    ///
    /// The request is diacritic-folded before it is sent -- lrclib is searched
    /// for "Beyonce" -- but the response comes back spelled "Beyoncé". Folding
    /// only one side made the two disagree, which cost a scoring bonus quietly
    /// and, once agreement became mandatory, rejected the correct lyrics
    /// outright.
    static func normalizedForMatching(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
