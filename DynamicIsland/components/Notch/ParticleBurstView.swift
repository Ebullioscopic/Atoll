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

import SwiftUI

struct ParticleBurstView: View {
    let color: Color
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        var offset: CGSize
        var opacity: Double
        var scale: CGFloat
    }
    
    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .offset(p.offset)
                    .opacity(p.opacity)
                    .scaleEffect(p.scale)
            }
        }
        .onAppear {
            // Generate 25 particles shooting outwards
            for _ in 0..<25 {
                let angle = Double.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 20...120)
                let endOffset = CGSize(width: cos(angle) * distance, height: sin(angle) * distance)
                let startOffset = CGSize(width: cos(angle) * 10, height: sin(angle) * 10)
                
                let particle = Particle(offset: startOffset, opacity: 1.0, scale: 0.5)
                particles.append(particle)
            }
            
            // Animate them outwards and fade out
            for i in 0..<particles.count {
                let angle = Double.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 20...120)
                withAnimation(.easeOut(duration: 1.2)) {
                    particles[i].offset = CGSize(width: cos(angle) * distance, height: sin(angle) * distance)
                    particles[i].opacity = 0.0
                    particles[i].scale = 1.5
                }
            }
        }
    }
}
