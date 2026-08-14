/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import Network
import XCTest

@testable import Atoll

/// The peer check that keeps the extension RPC server local.
///
/// The listener is bound to loopback, so in practice nothing else should ever
/// reach this code — which is exactly why it is worth testing: a bug here would
/// only surface the day the bind changed.
@MainActor
final class ExtensionRPCServerTests: XCTestCase {
    private func endpoint(_ host: NWEndpoint.Host) -> NWEndpoint {
        .hostPort(host: host, port: 9_020)
    }

    func testLoopbackPeersAreAccepted() {
        XCTAssertTrue(ExtensionRPCServer.isLoopback(endpoint(.ipv4(.loopback))))
        XCTAssertTrue(ExtensionRPCServer.isLoopback(endpoint(.ipv6(.loopback))))
        XCTAssertTrue(ExtensionRPCServer.isLoopback(endpoint(.name("localhost", nil))))
    }

    /// The whole point of the fix: before it, this connection was served.
    func testALocalNetworkPeerIsRefused() {
        let lan = IPv4Address("192.168.1.105")!
        XCTAssertFalse(ExtensionRPCServer.isLoopback(endpoint(.ipv4(lan))))
    }

    func testAPublicAddressIsRefused() {
        XCTAssertFalse(ExtensionRPCServer.isLoopback(endpoint(.ipv4(IPv4Address("93.184.216.34")!))))
        XCTAssertFalse(ExtensionRPCServer.isLoopback(endpoint(.ipv6(IPv6Address("2606:2800:220:1::1")!))))
    }

    /// A dual-stack socket reports an IPv4 peer as `::ffff:127.0.0.1`, which is
    /// loopback however little it looks like one. Rejecting it would break every
    /// IPv4 client the day the listener accepted them on an IPv6 socket.
    func testAnIPv4MappedLoopbackPeerIsAccepted() {
        let mapped = IPv6Address("::ffff:127.0.0.1")!
        XCTAssertTrue(ExtensionRPCServer.isLoopback(endpoint(.ipv6(mapped))))
    }

    /// The mirror image: a mapped *LAN* address must not sneak through on the
    /// strength of being IPv6-shaped.
    func testAnIPv4MappedLocalNetworkPeerIsRefused() {
        let mapped = IPv6Address("::ffff:192.168.1.105")!
        XCTAssertFalse(ExtensionRPCServer.isLoopback(endpoint(.ipv6(mapped))))
    }

    /// Anything not addressed by host and port — a Bonjour service, say — is not
    /// something this server should be answering.
    func testAServiceEndpointIsRefused() {
        let service = NWEndpoint.service(
            name: "Atoll", type: "_atoll._tcp", domain: "local", interface: nil
        )
        XCTAssertFalse(ExtensionRPCServer.isLoopback(service))
    }

    /// The naive version of this check was a string comparison, which would have
    /// accepted a hostname merely *containing* "localhost".
    func testALookalikeHostnameIsRefused() {
        XCTAssertFalse(ExtensionRPCServer.isLoopback(endpoint(.name("localhost.evil.example", nil))))
        XCTAssertFalse(ExtensionRPCServer.isLoopback(endpoint(.name("notlocalhost", nil))))
    }
}
