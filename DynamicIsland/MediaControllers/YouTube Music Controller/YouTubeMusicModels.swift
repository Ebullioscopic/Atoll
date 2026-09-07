/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

// MARK: - Configuration
struct YouTubeMusicConfiguration: Sendable {
    let baseURL: String
    let bundleIdentifier: String
    let reconnectDelay: ClosedRange<TimeInterval>
    let updateInterval: TimeInterval
    
    static let `default` = YouTubeMusicConfiguration(
        baseURL: "http://localhost:26538",
        bundleIdentifier: "com.github.th-ch.youtube-music",
        reconnectDelay: 1...60,
        updateInterval: 2.0
    )
}

// MARK: - API Models
struct AuthResponse: Decodable, Sendable {
    let accessToken: String
}

struct PlaybackResponse: Decodable, Sendable {
    let isPaused: Bool
    let videoId: String?
    let title: String?
    let artist: String?
    let album: String?
    let elapsedSeconds: Double?
    let songDuration: Double?
    let imageSrc: String?
    let repeatMode: Int?
    let isShuffled: Bool?
}

// MARK: - WebSocket Message Types
enum WebSocketMessageType: String, Sendable {
    case playerInfo = "PLAYER_INFO"
    case videoChanged = "VIDEO_CHANGED"
    case playerStateChanged = "PLAYER_STATE_CHANGED"
    case positionChanged = "POSITION_CHANGED"
    case volumeChanged = "VOLUME_CHANGED"
    case repeatChanged = "REPEAT_CHANGED"
    case shuffleChanged = "SHUFFLE_CHANGED"
}

struct WebSocketMessage {
    let type: WebSocketMessageType
    let rawData: Data
    private let parsedJSON: [String: Any]?

    init?(from data: Data) {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        guard let typeString = json?["type"] as? String,
              let messageType = WebSocketMessageType(rawValue: typeString) else {
            return nil
        }

        self.type = messageType
        self.rawData = data
        self.parsedJSON = json
    }

    func extractData() -> [String: Any]? {
        parsedJSON
    }
}

// MARK: - Extensions
extension PlaybackResponse {
    static func from(websocketData: [String: Any]) -> PlaybackResponse? {
        let songData = websocketData["song"] as? [String: Any]
        
        let isPaused: Bool
        if let paused = songData?["isPaused"] as? Bool {
            isPaused = paused
        } else if let playing = websocketData["isPlaying"] as? Bool {
            isPaused = !playing
        } else {
            isPaused = true
        }
        
        let videoId = (songData?["videoId"] as? String) ?? (websocketData["videoId"] as? String)
        let title = (songData?["title"] as? String) ??
                   (songData?["alternativeTitle"] as? String) ??
                   (websocketData["title"] as? String)
        let artist = (songData?["artist"] as? String) ?? (websocketData["artist"] as? String)
        let album = songData?["album"] as? String

        let elapsed = extractDouble(from: songData, key: "elapsedSeconds") ??
                     extractDouble(from: websocketData, key: "position")

        let duration = extractDouble(from: songData, key: "songDuration") ??
                      extractDouble(from: websocketData, key: "songDuration")
        
        let imageSrc = (songData?["imageSrc"] as? String) ?? (websocketData["imageSrc"] as? String)
        let isShuffled = (websocketData["shuffle"] as? Bool) ?? (songData?["isShuffled"] as? Bool)

        var repeatModeInt: Int? = nil
        if let repeatVal = websocketData["repeat"] as? String {
            switch repeatVal.uppercased() {
            case "NONE": repeatModeInt = 0
            case "ALL": repeatModeInt = 1
            case "ONE": repeatModeInt = 2
            default: break
            }
        } else if let repeatStr = songData?["repeat"] as? String {
            switch repeatStr.uppercased() {
            case "NONE": repeatModeInt = 0
            case "ALL": repeatModeInt = 1
            case "ONE": repeatModeInt = 2
            default: break
            }
        }
        
        return PlaybackResponse(
            isPaused: isPaused,
            videoId: videoId,
            title: title,
            artist: artist,
            album: album,
            elapsedSeconds: elapsed,
            songDuration: duration,
            imageSrc: imageSrc,
            repeatMode: repeatModeInt,
            isShuffled: isShuffled
        )
    }
    
    func with(elapsedSeconds: Double) -> PlaybackResponse {
        PlaybackResponse(
            isPaused: isPaused,
            videoId: videoId,
            title: title,
            artist: artist,
            album: album,
            elapsedSeconds: elapsedSeconds,
            songDuration: songDuration,
            imageSrc: imageSrc,
            repeatMode: repeatMode,
            isShuffled: isShuffled
        )
    }
}

private func extractDouble(from dict: [String: Any]?, key: String) -> Double? {
    guard let dict = dict else { return nil }
    if let value = dict[key] as? Double {
        return value
    } else if let value = dict[key] as? Int {
        return Double(value)
    }
    return nil
}
