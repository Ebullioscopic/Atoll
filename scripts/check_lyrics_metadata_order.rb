#!/usr/bin/env ruby

file = "DynamicIsland/managers/MusicManager.swift"
source = File.read(file, encoding: "UTF-8")

method_start = source.index("func updateFromPlaybackState(")
abort("could not locate updateFromPlaybackState") unless method_start

method_end = source.index("\n    @MainActor", method_start)
abort("could not locate end of updateFromPlaybackState") unless method_end

method = source[method_start...method_end]

prepare_idx = method.index("self.prepareLyricsForCurrentTrack()")
title_idx = method.index("self.songTitle = state.title")
artist_idx = method.index("self.artistName = state.artist")
album_idx = method.index("self.album = state.album")
duration_idx = method.index("self.songDuration = state.duration")

abort("missing expected snippets") unless [prepare_idx, title_idx, artist_idx, album_idx, duration_idx].all?

if prepare_idx < [title_idx, artist_idx, album_idx, duration_idx].max
  abort("FAIL: lyrics lookup runs before track metadata is updated; rapid track changes can reuse stale lyrics.")
end

puts "PASS: track metadata is updated before lyrics lookup."
