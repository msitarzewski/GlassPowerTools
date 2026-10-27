//
//  FocusEnvironmentArt.swift
//  Glass Power Tools — GlassTerminal
//
//  The built-in environments' pictures, drawn here in code so the app carries no image for them
//  (the owner, 2026-10-26: "can you make a few that will become part of the library of environments
//  by default?"). Each is a sky, wrapped around the person as a 360° photo is, and a floor under
//  their feet whose edge is the sky's own ground colour, so the two meet without a seam.
//
//  A sky is equirectangular: longitude across, the front — where the person faces as Focus Mode
//  opens, −Z — at the middle, and +X, their right, to the right of it. Pure CoreGraphics and
//  arithmetic, the same on every device and in tests, from a fixed seed: the same sky every time.
//

import Foundation
import CoreGraphics

nonisolated enum FocusEnvironmentArt {
    /// An sRGB colour, each part 0…1.
    struct Color: Equatable, Sendable {
        var r: Double, g: Double, b: Double

        init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r; self.g = g; self.b = b
        }

        static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
            Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
        }

        static func + (a: Color, b: Color) -> Color { Color(a.r + b.r, a.g + b.g, a.b + b.b) }
        static func * (a: Color, k: Double) -> Color { Color(a.r * k, a.g * k, a.b * k) }
    }

    /// Colours by altitude, in degrees from −90 (straight down) to 90 (straight up), ascending.
    struct Gradient: Sendable {
        let stops: [(altitude: Double, color: Color)]

        func at(_ altitude: Double) -> Color {
            guard let first = stops.first, let last = stops.last else { return Color(0, 0, 0) }
            if altitude <= first.altitude { return first.color }
            if altitude >= last.altitude { return last.color }
            for index in 1..<stops.count where altitude <= stops[index].altitude {
                let low = stops[index - 1], high = stops[index]
                let t = (altitude - low.altitude) / (high.altitude - low.altitude)
                return Color.mix(low.color, high.color, smooth(t))
            }
            return last.color
        }
    }

    // MARK: - Geometry the scenes share

    /// The floor under a built-in: a square this many metres from the person to each edge.
    static let floorHalfWidth: Float = 40
    /// Grid's floor reaches further, to the horizon's glow.
    static let gridHalfWidth: Float = 300
    /// Grid's lines are this many metres apart.
    static let gridSpacing: Float = 2
    /// Where a standing person's eyes are, for the previews.
    static let eyeHeight = 1.6

    /// How wide a sky is drawn on this device: sharp stars on the headset; a Debug build, slow at
    /// drawing, half as wide.
    static var skyWidth: Int {
        #if DEBUG
        4096
        #else
        8192
        #endif
    }

    // MARK: - Each environment's colours

    /// The sky's ground just below the horizon, which is also the floor's edge.
    static func groundColor(_ environment: FocusBuiltInEnvironment) -> Color {
        switch environment {
        case .dimmed: Color(0.12, 0.12, 0.13)
        case .nightSky: Color(0.030, 0.034, 0.048)
        case .dusk: Color(0.085, 0.070, 0.110)
        case .grid: Color(0.012, 0.025, 0.040)
        case .studio: Color(0.165, 0.170, 0.185)
        }
    }

    /// The floor where the person stands, lighter than its edge, as if lit from above.
    static func floorCenterColor(_ environment: FocusBuiltInEnvironment) -> Color {
        switch environment {
        case .dimmed: Color(0.14, 0.14, 0.15)
        case .nightSky: Color(0.060, 0.066, 0.086)
        case .dusk: Color(0.135, 0.110, 0.160)
        case .grid: Color(0.020, 0.040, 0.060)
        case .studio: Color(0.235, 0.240, 0.258)
        }
    }

    static let gridLineColor = Color(0.12, 0.62, 0.72)

    private static func skyGradient(_ environment: FocusBuiltInEnvironment) -> Gradient {
        let ground = groundColor(environment)
        switch environment {
        case .dimmed:
            return Gradient(stops: [(-90, ground), (90, ground)])
        case .nightSky:
            return Gradient(stops: [
                (-90, Color(0.018, 0.020, 0.028)), (-12, ground), (-0.4, ground),
                (0, Color(0.075, 0.110, 0.180)), (4, Color(0.050, 0.078, 0.135)),
                (14, Color(0.028, 0.045, 0.085)), (40, Color(0.016, 0.026, 0.052)),
                (90, Color(0.010, 0.016, 0.036)),
            ])
        case .dusk:
            return Gradient(stops: [
                (-90, Color(0.050, 0.040, 0.070)), (-15, ground), (-0.3, ground),
                (0, Color(0.470, 0.360, 0.500)), (6, Color(0.345, 0.300, 0.490)),
                (20, Color(0.205, 0.220, 0.410)), (50, Color(0.094, 0.125, 0.275)),
                (90, Color(0.047, 0.067, 0.165)),
            ])
        case .grid:
            return Gradient(stops: [
                (-90, Color(0.008, 0.016, 0.026)), (-0.5, ground),
                (0, Color(0.10, 0.36, 0.42)), (2, Color(0.07, 0.25, 0.32)),
                (10, Color(0.030, 0.090, 0.140)), (35, Color(0.015, 0.030, 0.065)),
                (90, Color(0.008, 0.012, 0.030)),
            ])
        case .studio:
            return Gradient(stops: [
                (-90, Color(0.140, 0.145, 0.160)), (-20, ground), (-0.5, ground), (0, Color(0.170, 0.175, 0.190)),
                (8, Color(0.160, 0.165, 0.180)), (40, Color(0.110, 0.115, 0.130)),
                (90, Color(0.070, 0.075, 0.085)),
            ])
        }
    }

    /// Dusk's sky toward the sun, which has just set in front of the person.
    private static let duskWarm = Gradient(stops: [
        (-90, Color(0.050, 0.040, 0.070)), (-0.3, groundColor(.dusk)),
        (0, Color(0.980, 0.620, 0.350)), (4, Color(0.940, 0.470, 0.390)),
        (12, Color(0.740, 0.370, 0.470)), (30, Color(0.350, 0.270, 0.490)),
        (90, Color(0.047, 0.067, 0.165)),
    ])
    private static let duskSunAltitude = -4.0

    // MARK: - Skies

    /// A built-in's sky, `width` pixels wide and half as tall; nil for Dimmed Room, which has none.
    static func sky(_ environment: FocusBuiltInEnvironment, width: Int) -> CGImage? {
        guard environment != .dimmed else { return nil }
        let pixels = skyPixels(environment, width: max(64, width))
        return image(pixels, width: max(64, width), height: max(64, width) / 2)
    }

    /// The sky's pixels, RGBA, rows from the top (straight up) down.
    static func skyPixels(_ environment: FocusBuiltInEnvironment, width: Int) -> [UInt8] {
        let height = width / 2
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let gradient = skyGradient(environment)
        let mountains = environment == .dusk ? duskMountains(width: width) : nil
        let galaxy = environment == .nightSky ? Galaxy() : nil
        // Each column's longitude and each row's altitude, worked out once.
        let longitudes = (0..<width).map { (Double($0) + 0.5) / Double(width) * 360 - 180 }
        let cosLongitude = longitudes.map { cos($0 * .pi / 180) }
        let sinLongitude = longitudes.map { sin($0 * .pi / 180) }
        let sunSin = sin(duskSunAltitude * .pi / 180), sunCos = cos(duskSunAltitude * .pi / 180)

        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let altitude = 90 - (Double(y) + 0.5) / Double(height) * 180
                let radians = altitude * .pi / 180
                let sinAltitude = sin(radians), cosAltitude = cos(radians)
                let base = gradient.at(altitude)
                let warm = environment == .dusk ? duskWarm.at(altitude) : base
                for x in 0..<width {
                    var color = base
                    switch environment {
                    case .dusk:
                        // Toward the sun the sky warms, and glows where it set.
                        let toSun = min(1, max(-1, sinAltitude * sunSin + cosAltitude * sunCos * cosLongitude[x]))
                        let distance = acos(toSun) * 180 / .pi
                        color = Color.mix(base, warm, exp(-pow(distance / 55, 2)))
                        if altitude > -0.3 {
                            color = color + Color(1.0, 0.78, 0.55) * (0.55 * exp(-pow(distance / 7, 2)))
                        }
                        if let mountains, altitude >= -0.3 {
                            color = mountains.color(column: x, altitude: altitude, sky: color,
                                                    sunward: exp(-pow(distance / 45, 2)))
                        }
                    case .nightSky:
                        if let galaxy, altitude > -1 {
                            let direction = (cosAltitude * sinLongitude[x], sinAltitude, -cosAltitude * cosLongitude[x])
                            let glow = galaxy.brightness(direction) * smooth((altitude + 1) / 14)
                            color = color + Color(0.55, 0.58, 0.72) * (0.22 * glow)
                        }
                    default:
                        break
                    }
                    let index = (y * width + x) * 4
                    let dither = dither(x, y)
                    buffer[index] = byte(color.r + dither)
                    buffer[index + 1] = byte(color.g + dither)
                    buffer[index + 2] = byte(color.b + dither)
                }
            }
        }

        switch environment {
        case .nightSky:
            var random = SplitMix64(seed: 0x6E69_6768_74)
            scatterStars(into: &pixels, width: width, count: 9000, random: &random, minimumAltitude: 0)
            if let galaxy {
                scatterStars(into: &pixels, width: width, count: 7000, random: &random, minimumAltitude: 0,
                             faintest: 0.18, brightest: 0.45, place: { galaxy.nearbyDirection(&$0) })
            }
        case .dusk:
            var random = SplitMix64(seed: 0x6475_736B)
            scatterStars(into: &pixels, width: width, count: 900, random: &random, minimumAltitude: 18,
                         faintest: 0.15, brightest: 0.55, dimToward: (0, duskSunAltitude, 110))
        case .grid:
            var random = SplitMix64(seed: 0x6772_6964)
            scatterStars(into: &pixels, width: width, count: 1800, random: &random, minimumAltitude: 16,
                         faintest: 0.12, brightest: 0.4)
        case .dimmed, .studio:
            break
        }
        return pixels
    }

    // MARK: - Floors

    /// The floor's colour `distance` metres from where the person stands.
    static func floorColor(_ environment: FocusBuiltInEnvironment, distance: Double) -> Color {
        let edge = Double(environment == .grid ? gridHalfWidth : floorHalfWidth)
        let t = min(1, distance / (edge * 0.8))
        return Color.mix(floorCenterColor(environment), groundColor(environment), smooth(t))
    }

    /// The floor's picture, from its middle (where the person stands) to its edges, which are the
    /// sky's ground colour.
    static func floor(_ environment: FocusBuiltInEnvironment, size: Int = 512) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let half = Double(floorHalfWidth)
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) + 0.5) / Double(size) * 2 - 1, dz = (Double(y) + 0.5) / Double(size) * 2 - 1
                let color = floorColor(environment, distance: (dx * dx + dz * dz).squareRoot() * half)
                let index = (y * size + x) * 4, dither = dither(x, y)
                pixels[index] = byte(color.r + dither)
                pixels[index + 1] = byte(color.g + dither)
                pixels[index + 2] = byte(color.b + dither)
            }
        }
        return image(pixels, width: size, height: size)
    }

    /// One cell of Grid's floor, repeated across it: its lines along two edges.
    static func gridTile(size: Int = 256) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let line = Double(size) / 64
        let base = groundColor(.grid)
        for y in 0..<size {
            for x in 0..<size {
                // Distance to the nearest line, which runs along the tile's edges, so neighbours share it.
                let dx = min(Double(x) + 0.5, Double(size) - Double(x) - 0.5)
                let dy = min(Double(y) + 0.5, Double(size) - Double(y) - 0.5)
                let coverage = max(0, min(1, line - min(dx, dy) + 0.5))
                let color = Color.mix(base, gridLineColor, coverage)
                let index = (y * size + x) * 4
                pixels[index] = byte(color.r)
                pixels[index + 1] = byte(color.g)
                pixels[index + 2] = byte(color.b)
            }
        }
        return image(pixels, width: size, height: size)
    }

    // MARK: - Previews

    /// What the person sees as the environment opens, `width` wide, for the library: a camera at
    /// a standing person's eyes, looking ahead and a little up.
    static func preview(_ environment: FocusBuiltInEnvironment, width: Int = 480) -> CGImage? {
        let height = width / 2
        let skyWidth = 2048, skyHeight = 1024
        let sky = environment == .dimmed ? [] : skyPixels(environment, width: skyWidth)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let fieldOfView = 100.0 * .pi / 180, pitch = 8.0 * .pi / 180
        let focal = Double(width) / 2 / tan(fieldOfView / 2)
        for y in 0..<height {
            for x in 0..<width {
                // A ray through this pixel, turned up by the pitch.
                let px = Double(x) + 0.5 - Double(width) / 2, py = Double(height) / 2 - Double(y) - 0.5
                let ray = (px, py * cos(pitch) + focal * sin(pitch), -(focal * cos(pitch) - py * sin(pitch)))
                let length = (ray.0 * ray.0 + ray.1 * ray.1 + ray.2 * ray.2).squareRoot()
                let direction = (ray.0 / length, ray.1 / length, ray.2 / length)
                var color: Color
                if environment == .dimmed {
                    color = Color.mix(Color(0.10, 0.10, 0.11), Color(0.20, 0.20, 0.22), Double(y) / Double(height))
                } else if direction.1 < 0, let hit = floorHit(environment, direction) {
                    color = hit
                } else {
                    let altitude = asin(direction.1) * 180 / .pi
                    let longitude = atan2(direction.0, -direction.2) * 180 / .pi
                    color = sample(sky, width: skyWidth, height: skyHeight, longitude: longitude, altitude: altitude)
                }
                let index = (y * width + x) * 4
                pixels[index] = byte(color.r)
                pixels[index + 1] = byte(color.g)
                pixels[index + 2] = byte(color.b)
            }
        }
        return image(pixels, width: width, height: height)
    }

    /// Where a ray from the person's eyes meets the floor, and its colour there.
    private static func floorHit(_ environment: FocusBuiltInEnvironment,
                                 _ direction: (Double, Double, Double)) -> Color? {
        let distance = eyeHeight / -direction.1
        let x = direction.0 * distance, z = direction.2 * distance
        let edge = Double(environment == .grid ? gridHalfWidth : floorHalfWidth)
        guard abs(x) <= edge, abs(z) <= edge else { return nil }
        guard environment == .grid else {
            return floorColor(environment, distance: (x * x + z * z).squareRoot())
        }
        // Grid's lines, thinning with distance as the floor's mipmaps do.
        let spacing = Double(gridSpacing)
        let fx = abs(x / spacing - (x / spacing).rounded()), fz = abs(z / spacing - (z / spacing).rounded())
        let width = (1.0 / 64) * max(1, distance / 6)
        let coverage = min(1, (fx < width ? 1 : 0) + (fz < width ? 1 : 0)) * min(1, 6 / max(distance, 6))
        return Color.mix(groundColor(.grid), gridLineColor, coverage)
    }

    private static func sample(_ sky: [UInt8], width: Int, height: Int, longitude: Double, altitude: Double) -> Color {
        guard !sky.isEmpty else { return Color(0, 0, 0) }
        let x = min(width - 1, max(0, Int((longitude + 180) / 360 * Double(width))))
        let y = min(height - 1, max(0, Int((90 - altitude) / 180 * Double(height))))
        let index = (y * width + x) * 4
        return Color(Double(sky[index]) / 255, Double(sky[index + 1]) / 255, Double(sky[index + 2]) / 255)
    }

    // MARK: - Stars

    /// Stars over the sky: most faint, a few bright, each round however high it stands (a sky's
    /// rows stretch toward the poles, so a star is drawn wider there).
    private static func scatterStars(into pixels: inout [UInt8], width: Int, count: Int, random: inout SplitMix64,
                                     minimumAltitude: Double, faintest: Double = 0.2, brightest: Double = 1,
                                     dimToward: (longitude: Double, altitude: Double, radius: Double)? = nil,
                                     place: ((inout SplitMix64) -> (Double, Double, Double))? = nil) {
        let height = width / 2
        let pixelsPerDegree = Double(width) / 360
        for _ in 0..<count {
            // An even spread over the sphere, or where `place` puts it.
            let direction: (Double, Double, Double)
            if let place {
                direction = place(&random)
            } else {
                let up = random.unit() * 2 - 1, around = random.unit() * 2 * .pi
                let flat = (1 - up * up).squareRoot()
                direction = (flat * sin(around), up, -flat * cos(around))
            }
            let altitude = asin(min(1, max(-1, direction.1))) * 180 / .pi
            guard altitude > minimumAltitude else { continue }
            let longitude = atan2(direction.0, -direction.2) * 180 / .pi
            let magnitude = pow(random.unit(), 7)
            var brightness = faintest + (brightest - faintest) * magnitude
            brightness *= smooth((altitude - minimumAltitude) / 12)
            if let dimToward {
                let a = altitude * .pi / 180, b = dimToward.altitude * .pi / 180
                let toward = sin(a) * sin(b) + cos(a) * cos(b) * cos((longitude - dimToward.longitude) * .pi / 180)
                let distance = acos(min(1, max(-1, toward))) * 180 / .pi
                brightness *= smooth(distance / dimToward.radius)
            }
            let tint: Color = switch random.unit() {
            case ..<0.7: Color(0.86, 0.90, 1.0)
            case ..<0.9: Color(1.0, 0.88, 0.76)
            default: Color(0.74, 0.84, 1.0)
            }
            let sigma = (0.018 + 0.05 * magnitude) * pixelsPerDegree
            let cx = (longitude + 180) / 360 * Double(width), cy = (90 - altitude) / 180 * Double(height)
            let stretch = 1 / max(0.05, cos(altitude * .pi / 180))
            splat(&pixels, width: width, height: height, x: cx, y: cy, sigma: sigma, stretch: stretch,
                  color: tint * brightness)
            if magnitude > 0.35 {
                splat(&pixels, width: width, height: height, x: cx, y: cy, sigma: sigma * 4, stretch: stretch,
                      color: tint * (brightness * 0.06))
            }
        }
    }

    /// Adds a soft round spot, its light kept the same however small it is drawn.
    private static func splat(_ pixels: inout [UInt8], width: Int, height: Int, x: Double, y: Double,
                              sigma requested: Double, stretch: Double, color: Color) {
        let sigma = max(0.6, requested)
        let flux = pow(requested / sigma, 2)
        let reachY = Int((sigma * 3).rounded(.up)), reachX = Int((sigma * 3 * stretch).rounded(.up))
        let cx = Int(x), cy = Int(y)
        for dy in -reachY...reachY {
            let row = cy + dy
            guard row >= 0, row < height else { continue }
            let offsetY = Double(row) + 0.5 - y
            for dx in -reachX...reachX {
                let offsetX = (Double(cx + dx) + 0.5 - x) / stretch
                let weight = flux * exp(-(offsetX * offsetX + offsetY * offsetY) / (2 * sigma * sigma))
                guard weight > 0.002 else { continue }
                let column = ((cx + dx) % width + width) % width
                let index = (row * width + column) * 4
                pixels[index] = add(pixels[index], color.r * weight)
                pixels[index + 1] = add(pixels[index + 1], color.g * weight)
                pixels[index + 2] = add(pixels[index + 2], color.b * weight)
            }
        }
    }

    // MARK: - The Milky Way

    /// Night Sky's Milky Way: a band of light across the sky, rising on the person's right, highest
    /// ahead of them, and setting behind on their left, clumped and split by a dark lane.
    private struct Galaxy {
        /// The band is the great circle at right angles to this.
        let normal: (Double, Double, Double)
        let along: (Double, Double, Double)
        let across: (Double, Double, Double)

        init() {
            let n = (0.30, 0.50, 0.81)
            let length = (n.0 * n.0 + n.1 * n.1 + n.2 * n.2).squareRoot()
            normal = (n.0 / length, n.1 / length, n.2 / length)
            // Two directions in the band's plane.
            let a = (0.81, 0.0, -0.30)
            let la = (a.0 * a.0 + a.2 * a.2).squareRoot()
            along = (a.0 / la, 0, a.2 / la)
            across = (normal.1 * along.2 - normal.2 * along.1, normal.2 * along.0 - normal.0 * along.2,
                      normal.0 * along.1 - normal.1 * along.0)
        }

        func brightness(_ d: (Double, Double, Double)) -> Double {
            let height = d.0 * normal.0 + d.1 * normal.1 + d.2 * normal.2
            let distance = asin(min(1, max(-1, height))) * 180 / .pi
            guard abs(distance) < 40 else { return 0 }
            let angle = atan2(d.0 * across.0 + d.1 * across.1 + d.2 * across.2,
                              d.0 * along.0 + d.1 * along.1 + d.2 * along.2)
            let position = (angle + .pi) / (2 * .pi) * 48
            let clumps = 0.5 + 0.5 * fractalNoise(position, distance / 5, period: 48)
            let core = exp(-pow(distance / 7, 2) / 2), haze = exp(-pow(distance / 18, 2) / 2)
            let lane = 1 - 0.55 * exp(-pow((distance - 1.2) / 1.6, 2)) * fractalNoise(position * 2, 3, period: 96)
            return (0.65 * core + 0.35 * haze) * clumps * lane
        }

        /// A direction near the band, for its crowd of faint stars.
        func nearbyDirection(_ random: inout SplitMix64) -> (Double, Double, Double) {
            let angle = random.unit() * 2 * .pi
            let offset = random.gaussian() * 6 * .pi / 180
            let onBand = (cos(angle) * along.0 + sin(angle) * across.0,
                          cos(angle) * along.1 + sin(angle) * across.1,
                          cos(angle) * along.2 + sin(angle) * across.2)
            return (cos(offset) * onBand.0 + sin(offset) * normal.0,
                    cos(offset) * onBand.1 + sin(offset) * normal.1,
                    cos(offset) * onBand.2 + sin(offset) * normal.2)
        }
    }

    // MARK: - Dusk's mountains

    /// Three ridges, far to near, each a height for every column of the sky that wraps around
    /// without a seam.
    private struct Mountains {
        let far: [Double], middle: [Double], near: [Double]

        func color(column: Int, altitude: Double, sky: Color, sunward: Double) -> Color {
            if altitude < near[column] { return Color(0.100, 0.080, 0.130) }
            if altitude < middle[column] {
                return Color.mix(Color(0.200, 0.150, 0.245), Color(0.300, 0.190, 0.260), sunward * 0.5)
            }
            if altitude < far[column] {
                let haze = Color.mix(Color(0.330, 0.250, 0.370), Color(0.560, 0.360, 0.400), sunward * 0.6)
                return Color.mix(haze, sky, 0.35)
            }
            return sky
        }
    }

    private static func duskMountains(width: Int) -> Mountains {
        var random = SplitMix64(seed: 0x6D6F_756E_74)
        func ridge(_ low: Double, _ high: Double, roughness: Double) -> [Double] {
            let waves = (1...40).map { k in (k, pow(Double(k), -roughness) * (0.5 + random.unit()), random.unit() * 2 * .pi) }
            let raw = (0..<width).map { x -> Double in
                let longitude = (Double(x) + 0.5) / Double(width) * 2 * .pi
                return waves.reduce(0) { $0 + $1.1 * sin(Double($1.0) * longitude + $1.2) }
            }
            let lowest = raw.min() ?? 0, highest = raw.max() ?? 1
            return raw.map { low + (high - low) * pow(($0 - lowest) / max(highest - lowest, 1e-9), 1.6) }
        }
        return Mountains(far: ridge(1.8, 8.5, roughness: 1.05),
                         middle: ridge(0.8, 4.6, roughness: 1.15),
                         near: ridge(-1.4, 2.4, roughness: 1.25))
    }

    // MARK: - Arithmetic

    private static func smooth(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return c * c * (3 - 2 * c)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

    private static func add(_ value: UInt8, _ amount: Double) -> UInt8 {
        UInt8(max(0, min(255, (Double(value) + amount * 255).rounded())))
    }

    /// Half a step of noise, so a dark gradient doesn't show bands.
    private static func dither(_ x: Int, _ y: Int) -> Double {
        (hash(x, y) - 0.5) / 255
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= h >> 31
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 29
        return Double(h >> 11) / Double(1 << 53)
    }

    /// Smooth noise, 0…1, repeating every `period` across.
    private static func valueNoise(_ x: Double, _ y: Double, period: Int) -> Double {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        func corner(_ i: Int, _ j: Int) -> Double { hash(((i % period) + period) % period, j) }
        let top = corner(x0, y0) + (corner(x0 + 1, y0) - corner(x0, y0)) * smooth(fx)
        let bottom = corner(x0, y0 + 1) + (corner(x0 + 1, y0 + 1) - corner(x0, y0 + 1)) * smooth(fx)
        return top + (bottom - top) * smooth(fy)
    }

    private static func fractalNoise(_ x: Double, _ y: Double, period: Int) -> Double {
        (valueNoise(x, y, period: period) * 0.55 + valueNoise(x * 2, y * 2, period: period * 2) * 0.3
            + valueNoise(x * 4, y * 4, period: period * 4) * 0.15)
    }

    private static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A small, fast random sequence from a seed, the same on every device.
nonisolated struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 up to, not including, 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// Normally spread, around 0, mostly within ±1.
    mutating func gaussian() -> Double {
        let u = max(unit(), 1e-12), v = unit()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}
