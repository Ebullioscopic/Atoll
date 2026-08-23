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
