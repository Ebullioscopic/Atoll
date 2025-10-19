//
//  MediaControllerProtocol.swift
//  DynamicIsland
//
//  Created by Alexander Greco on 2025-03-29.
//

import Foundation
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var isWorking: Bool { get }
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func isActive() -> Bool
    func updatePlaybackInfo() async
}
