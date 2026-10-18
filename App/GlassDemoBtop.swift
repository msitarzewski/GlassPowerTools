//
//  GlassDemoBtop.swift
//  Glass Power Tools
//
//  Screenshots only (App/GlassDemoMode.swift): a screen in the manner of btop, the system monitor,
//  for the terminal in the website's pictures (the owner, 2026-10-18: "run btop or something for
//  the terminal examples"). Like btop it draws the whole screen for the rows and columns its window
//  gives it, and again when they change: the CPU's graph and cores, memory and disks, the network,
//  and the processes of the made-up shop on alpha. Every number is invented. The colours are those
//  of btop's default theme, its boxes and dim text lifted to read on glass; the graphs are btop's
//  "block" style. The background is left to the terminal, so its glass shows through.
//

#if DEBUG
import Foundation

enum GlassDemoBtop {
    /// The screen for a window of `rows` × `columns`, as one write.
    static func screen(rows: Int, columns: Int) -> Data {
        var canvas = Canvas(rows: max(rows, 12), columns: max(columns, 40))
        canvas.draw()
        return Data(canvas.ansi().utf8)
    }

    struct RGB: Equatable {
        var r: Int, g: Int, b: Int
        init(_ hex: UInt32) { r = Int(hex >> 16 & 0xFF); g = Int(hex >> 8 & 0xFF); b = Int(hex & 0xFF) }
        init(r: Int, g: Int, b: Int) { self.r = r; self.g = g; self.b = b }

        /// Three stops, as btop's gradients have: `t` from 0 to 1.
        static func gradient(_ start: RGB, _ mid: RGB, _ end: RGB, _ t: Double) -> RGB {
            let t = min(1, max(0, t))
            let (a, b, u) = t < 0.5 ? (start, mid, t * 2) : (mid, end, (t - 0.5) * 2)
            func mix(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * u).rounded()) }
            return RGB(r: mix(a.r, b.r), g: mix(a.g, b.g), b: mix(a.b, b.b))
        }
    }

    /// btop's default theme, its boxes and dim greys lifted for glass.
    enum Theme {
        static let text = RGB(0xCCCCCC), title = RGB(0xEEEEEE), hi = RGB(0xE05050), inactive = RGB(0x404040)
        static let graphText = RGB(0x8A8A8A), meterBg = RGB(0x4A4A4A), divider = RGB(0x5A5A5A)
        static let selectedBg = RGB(0x6A2F2F), selected = RGB(0xEEEEEE), misc = RGB(0x0DE756)
        static let cpuBox = RGB(0x7FAE88), memBox = RGB(0xA6A46C), netBox = RGB(0x8E89CF), procBox = RGB(0xB87878)
        static let cpu = (RGB(0x50F095), RGB(0xF2E266), RGB(0xFA1E1E))
        static let temp = (RGB(0x4897D4), RGB(0x5474E8), RGB(0xFF40B6))
        static let used = (RGB(0x3B1F1C), RGB(0xD9626D), RGB(0xFF4769))
        static let available = (RGB(0x292107), RGB(0xFFD77A), RGB(0xFFB814))
        static let cached = (RGB(0x0B1A29), RGB(0x74E6FC), RGB(0x26C5FF))
        static let free = (RGB(0x223014), RGB(0xB5E685), RGB(0xDCFF85))
        static let download = (RGB(0x291F75), RGB(0x4F43A3), RGB(0xB0A9DE))
        static let upload = (RGB(0x620665), RGB(0x7D4180), RGB(0xDCAFDE))
        static let process = (RGB(0x80D0A3), RGB(0xDCD179), RGB(0xD45454))
    }

    struct Cell: Equatable {
        var character: Character = " "
        var foreground: RGB?
        var background: RGB?
        var bold = false
    }

    struct Canvas {
        let rows: Int, columns: Int
        var cells: [[Cell]]

        init(rows: Int, columns: Int) {
            self.rows = rows; self.columns = columns
            cells = Array(repeating: Array(repeating: Cell(), count: columns), count: rows)
        }

        mutating func put(_ text: String, _ row: Int, _ column: Int, _ color: RGB?, background: RGB? = nil,
                          bold: Bool = false) {
            guard cells.indices.contains(row) else { return }
            var x = column
            for character in text {
                if x >= 0 && x < columns {
                    cells[row][x] = Cell(character: character, foreground: color,
                                         background: background ?? cells[row][x].background, bold: bold)
                }
                x += 1
            }
        }

        /// A rounded box, with btop's numbered title at its top left.
        mutating func box(_ top: Int, _ left: Int, _ height: Int, _ width: Int, _ color: RGB,
                          number: String? = nil, title: String? = nil) {
            guard height >= 2, width >= 2 else { return }
            let bottom = top + height - 1, right = left + width - 1
            put("╭" + String(repeating: "─", count: width - 2) + "╮", top, left, color)
            put("╰" + String(repeating: "─", count: width - 2) + "╯", bottom, left, color)
            for row in (top + 1)..<bottom {
                put("│", row, left, color)
                put("│", row, right, color)
            }
            if let title { label(title, top, left + 1, color, number: number) }
        }

        /// `┐title┌` on a box's border.
        mutating func label(_ text: String, _ row: Int, _ column: Int, _ color: RGB, number: String? = nil,
                            textColor: RGB = Theme.title) {
            put("┐", row, column, color)
            var x = column + 1
            if let number {
                put(number, row, x, Theme.hi, bold: true)
                x += number.count
            }
            put(text, row, x, textColor, bold: true)
            put("┌", row, x + text.count, color)
        }

        /// btop's meter: `width` blocks, filled to `fraction` along a gradient.
        mutating func meter(_ row: Int, _ column: Int, _ width: Int, _ fraction: Double,
                            _ colors: (RGB, RGB, RGB)) {
            let filled = Int((Double(width) * fraction).rounded())
            for index in 0..<max(width, 0) {
                let color = index < filled ? RGB.gradient(colors.0, colors.1, colors.2, Double(index) / Double(max(width - 1, 1)))
                                           : Theme.meterBg
                put("■", row, column + index, color)
            }
        }

        /// A graph of `values` (0...1) in quarter blocks, btop's "block" style: two samples a cell
        /// and two levels a row, the newest at the right; upward, or hanging from the top when
        /// `downward`, coloured by height.
        mutating func graph(_ top: Int, _ left: Int, _ height: Int, _ width: Int, _ values: [Double],
                            _ colors: (RGB, RGB, RGB), downward: Bool = false) {
            guard height > 0, width > 0 else { return }
            let samples = Array(values.suffix(width * 2))
            let padded = Array(repeating: 0.0, count: max(0, width * 2 - samples.count)) + samples
            let levels = height * 2
            // Indexed by quadrants: top left 1, top right 2, bottom left 4, bottom right 8.
            let blocks: [Character] = [" ", "▘", "▝", "▀", "▖", "▌", "▞", "▛", "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█"]
            for column in 0..<width {
                let a = Int((padded[column * 2] * Double(levels)).rounded())
                let b = Int((padded[column * 2 + 1] * Double(levels)).rounded())
                for line in 0..<height {
                    // The levels this cell holds, counted from the graph's base.
                    let base = (downward ? line : height - 1 - line) * 2
                    let (near, far) = downward ? ((1, 2), (4, 8)) : ((4, 8), (1, 2))
                    var bits = 0
                    if a > base { bits |= near.0 }
                    if b > base { bits |= near.1 }
                    if a > base + 1 { bits |= far.0 }
                    if b > base + 1 { bits |= far.1 }
                    guard bits != 0 else { continue }
                    let level = Double(base + 1) / Double(levels)
                    put(String(blocks[bits]), top + line, left + column, RGB.gradient(colors.0, colors.1, colors.2, level))
                }
            }
        }

        /// A one-row graph of `values` (0...1) in eighth blocks, one sample a cell: a core's.
        mutating func spark(_ row: Int, _ column: Int, _ width: Int, _ values: [Double], _ colors: (RGB, RGB, RGB)) {
            let bars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
            for (index, value) in values.suffix(width).enumerated() {
                let level = min(7, max(0, Int((value * 8).rounded(.down))))
                put(String(bars[level]), row, column + index, RGB.gradient(colors.0, colors.1, colors.2, value))
            }
        }

        /// A made-up history, `count` samples between 0 and 1.
        static func history(_ count: Int, base: Double, swing: Double, seed: Double, spike: Bool = false) -> [Double] {
            (0..<count).map { index in
                let x = Double(index)
                var value = base + swing * (0.55 * sin(x * 0.17 + seed) + 0.3 * sin(x * 0.53 + seed * 2.1)
                                            + 0.15 * sin(x * 1.37 + seed * 3.7))
                if spike, index > count - 9 { value += 0.28 * Double(index - (count - 9)) / 8 }
                return min(0.97, max(0.02, value))
            }
        }

        mutating func draw() {
            let wide = columns >= 90
            let cpuHeight = max(8, Int(Double(rows) * (wide ? 0.42 : 0.32)))
            drawCPU(top: 0, height: cpuHeight)
            if wide {
                let leftWidth = max(40, Int(Double(columns) * 0.45))
                let memHeight = max(7, Int(Double(rows - cpuHeight) * 0.56))
                drawMemory(top: cpuHeight, left: 0, height: memHeight, width: leftWidth)
                drawNetwork(top: cpuHeight + memHeight, left: 0, height: rows - cpuHeight - memHeight, width: leftWidth)
                drawProcesses(top: cpuHeight, left: leftWidth, height: rows - cpuHeight, width: columns - leftWidth)
            } else {
                let memHeight = max(6, Int(Double(rows - cpuHeight) * 0.3))
                drawMemory(top: cpuHeight, left: 0, height: memHeight, width: columns)
                drawProcesses(top: cpuHeight + memHeight, left: 0, height: rows - cpuHeight - memHeight, width: columns)
            }
        }

        mutating func drawCPU(top: Int, height: Int) {
            box(top, 0, height, columns, Theme.cpuBox, number: "¹", title: "cpu")
            let clock = "09:41:12"
            label(clock, top, (columns - clock.count) / 2 - 1, Theme.cpuBox)
            if columns >= 60 { label("- 2000ms +", top, columns - 14, Theme.cpuBox, textColor: Theme.text) }
            let coresWidth = min(46, max(26, columns / 3))
            let coresLeft = columns - coresWidth - 1
            let inner = height - 2
            let graphWidth = coresLeft - 2
            graph(top + 1, 1, inner, graphWidth, Self.history(graphWidth * 2, base: 0.34, swing: 0.2, seed: 1, spike: true),
                  Theme.cpu)
            put("up 23d 04:02", top + height - 1, 2, Theme.graphText)
            // The cores, in a box of their own at the right.
            box(top + 1, coresLeft, inner, coresWidth, Theme.cpuBox)
            label("Ryzen 7 7700", top + 1, coresLeft + 1, Theme.cpuBox, textColor: Theme.text)
            let total = 0.42
            put("CPU", top + 2, coresLeft + 2, Theme.title, bold: true)
            let meterWidth = coresWidth - 15
            meter(top + 2, coresLeft + 6, meterWidth, total, Theme.cpu)
            put(String(format: "%3d%%", Int(total * 100)), top + 2, coresLeft + 7 + meterWidth, Theme.text)
            let loads = [0.21, 0.63, 0.34, 0.12, 0.48, 0.27, 0.71, 0.18, 0.39, 0.55, 0.09, 0.31, 0.44, 0.26, 0.58, 0.15]
            let lines = max(0, inner - 4)
            let perColumn = max(1, min(8, lines))
            let columnsOfCores = coresWidth >= 40 ? 2 : 1
            let cellWidth = (coresWidth - 3) / columnsOfCores
            for (index, load) in loads.prefix(perColumn * columnsOfCores).enumerated() {
                let row = top + 3 + index % perColumn
                let column = coresLeft + 2 + (index / perColumn) * cellWidth
                put("C\(index)", row, column, Theme.text)
                spark(row, column + 4, 5, Self.history(5, base: load, swing: 0.15, seed: Double(index)), Theme.cpu)
                put(String(format: "%3d%%", Int(load * 100)), row, column + 10, Theme.text)
                if cellWidth >= 20 {
                    put("\(44 + index % 7)°C", row, column + 15, RGB.gradient(Theme.temp.0, Theme.temp.1, Theme.temp.2, load))
                }
            }
            if inner >= 6 {
                let load = coresWidth >= 32 ? "Load AVG:  0.42  0.37  0.31" : "Load AVG: 0.42 0.37 0.31"
                put(load, top + inner, coresLeft + 2, Theme.text)
            }
        }

        mutating func drawMemory(top: Int, left: Int, height: Int, width: Int) {
            box(top, left, height, width, Theme.memBox, number: "²", title: "mem")
            let split = width >= 56
            let memWidth = split ? width / 2 : width
            let rows: [(String, String, Double, (RGB, RGB, RGB))] = [
                ("Used:", "18.4 GiB", 0.29, Theme.used),
                ("Available:", "44.3 GiB", 0.71, Theme.available),
                ("Cached:", "31.2 GiB", 0.50, Theme.cached),
                ("Free:", "13.1 GiB", 0.21, Theme.free),
            ]
            put("Total:", top + 1, left + 2, Theme.title, bold: true)
            put("62.7 GiB", top + 1, left + memWidth - 10, Theme.title)
            var row = top + 2
            for (name, amount, fraction, colors) in rows where row < top + height - 1 {
                put(name, row, left + 2, Theme.text)
                put(amount, row, left + memWidth - 10, Theme.text)
                if row + 1 < top + height - 1 {
                    meter(row + 1, left + 2, memWidth - 10, fraction, colors)
                    put(String(format: "%3d%%", Int(fraction * 100)), row + 1, left + memWidth - 7, Theme.text)
                    row += 2
                } else {
                    row += 1
                }
            }
            guard split else { return }
            let diskLeft = left + memWidth
            label("disks", top, diskLeft, Theme.memBox)
            for row in (top + 1)..<(top + height - 1) { put("│", row, diskLeft - 1, Theme.divider) }
            let disks: [(String, String, Double)] = [("root", "233 GiB", 0.41), ("/srv", "1.8 TiB", 0.63),
                                                     ("docker", "466 GiB", 0.37), ("swap", "8.0 GiB", 0.02)]
            var line = top + 1
            let diskWidth = width - memWidth - 3
            for (name, size, fraction) in disks where line + 1 < top + height - 1 {
                put(name, line, diskLeft + 1, Theme.title, bold: true)
                put(size, line, diskLeft + diskWidth - size.count, Theme.text)
                put("Used:", line + 1, diskLeft + 1, Theme.text)
                meter(line + 1, diskLeft + 7, diskWidth - 12, fraction, Theme.used)
                put(String(format: "%3d%%", Int(fraction * 100)), line + 1, diskLeft + diskWidth - 4, Theme.text)
                line += 2
            }
        }

        mutating func drawNetwork(top: Int, left: Int, height: Int, width: Int) {
            guard height >= 5 else { return }
            box(top, left, height, width, Theme.netBox, number: "³", title: "net")
            label("eth0", top, left + width - 8, Theme.netBox, textColor: Theme.text)
            let inner = height - 2
            let half = max(1, inner / 2)
            let graphWidth = width - 2
            graph(top + 1, left + 1, half, graphWidth, Self.history(graphWidth * 2, base: 0.32, swing: 0.25, seed: 4),
                  Theme.download)
            graph(top + 1 + half, left + 1, inner - half, graphWidth,
                  Self.history(graphWidth * 2, base: 0.18, swing: 0.14, seed: 7), Theme.upload, downward: true)
            put("▼ 1.24 MiB/s", top + 1, left + 3, Theme.title, bold: true)
            put("▲ 312 KiB/s", top + height - 2, left + 3, Theme.title, bold: true)
            if width >= 44 {
                put("Total: 48.2 GiB", top + 1, left + width - 18, Theme.text)
                put("Total: 9.7 GiB", top + height - 2, left + width - 18, Theme.text)
            }
        }

        mutating func drawProcesses(top: Int, left: Int, height: Int, width: Int) {
            guard height >= 4 else { return }
            box(top, left, height, width, Theme.procBox, number: "⁴", title: "proc")
            if width >= 50 { label("cpu lazy", top, left + width - 13, Theme.procBox, textColor: Theme.text) }
            let processes: [(pid: Int, program: String, command: String, threads: Int, user: String, memory: String, cpu: Double)] = [
                (2214, "postgres", "postgres: shop shop 172.18.0.4 SELECT", 1, "postgres", "412M", 12.4),
                (1987, "shop-web", "/srv/shop/bin/shop-web --port 8080", 24, "ann", "268M", 8.1),
                (2455, "shop-jobs", "/srv/shop/bin/shop-jobs --queue default", 12, "ann", "188M", 6.7),
                (2301, "valkey-server", "valkey-server *:6379", 6, "valkey", "96M", 3.2),
                (1203, "dockerd", "/usr/bin/dockerd -H fd://", 41, "root", "122M", 1.3),
                (2140, "nginx", "nginx: worker process", 1, "www-data", "18M", 0.9),
                (1188, "containerd", "/usr/bin/containerd", 18, "root", "64M", 0.6),
                (3310, "btop", "btop", 3, "ann", "9M", 0.5),
                (1420, "node_exporter", "/usr/local/bin/node_exporter", 7, "nobody", "22M", 0.3),
                (2911, "tmux: server", "tmux new-session -d -s glass-1", 1, "ann", "6M", 0.2),
                (905, "sshd", "sshd: ann@pts/0", 1, "ann", "11M", 0.1),
                (2216, "postgres", "postgres: walwriter", 1, "postgres", "38M", 0.1),
                (2217, "postgres", "postgres: autovacuum launcher", 1, "postgres", "41M", 0.0),
                (812, "systemd-journal", "/lib/systemd/systemd-journald", 1, "root", "48M", 0.0),
                (1, "systemd", "/sbin/init", 1, "root", "13M", 0.0),
                (640, "cron", "/usr/sbin/cron -f", 1, "root", "3M", 0.0),
                (702, "rsyslogd", "/usr/sbin/rsyslogd -n", 4, "syslog", "7M", 0.0),
                (2930, "zsh", "-zsh", 1, "ann", "8M", 0.0),
                (771, "systemd-resolve", "/lib/systemd/systemd-resolved", 1, "systemd+", "12M", 0.0),
                (2102, "containerd-shim", "/usr/bin/containerd-shim-runc-v2", 11, "root", "14M", 0.0),
                (2103, "containerd-shim", "/usr/bin/containerd-shim-runc-v2", 11, "root", "14M", 0.0),
                (690, "dbus-daemon", "/usr/bin/dbus-daemon --system", 1, "message+", "5M", 0.0),
            ]
            let showsCommand = width >= 74
            let showsUser = width >= 60
            let showsThreads = width >= 50
            let commandWidth = max(0, width - 2 - 8 - 16 - 9 - 10 - 7 - 7)
            var header = "Pid:".padding(toLength: 8, withPad: " ", startingAt: 0)
                + "Program:".padding(toLength: 16, withPad: " ", startingAt: 0)
            if showsCommand { header += "Command:".padding(toLength: commandWidth, withPad: " ", startingAt: 0) }
            if showsThreads { header += "Threads:".padding(toLength: 9, withPad: " ", startingAt: 0) }
            if showsUser { header += "User:".padding(toLength: 10, withPad: " ", startingAt: 0) }
            put(header, top + 1, left + 2, Theme.title, bold: true)
            put("MemB", top + 1, left + width - 14, Theme.title, bold: true)
            put("Cpu%", top + 1, left + width - 7, Theme.title, bold: true)
            let selected = 1
            for (index, process) in processes.enumerated() where top + 2 + index < top + height - 1 {
                let row = top + 2 + index
                let background = index == selected ? Theme.selectedBg : nil
                if let background { put(String(repeating: " ", count: width - 2), row, left + 1, nil, background: background) }
                let color = index == selected ? Theme.selected : Theme.text
                var line = String(process.pid).padding(toLength: 8, withPad: " ", startingAt: 0)
                    + String(process.program.prefix(15)).padding(toLength: 16, withPad: " ", startingAt: 0)
                if showsCommand {
                    line += String(process.command.prefix(commandWidth - 1)).padding(toLength: commandWidth, withPad: " ", startingAt: 0)
                }
                if showsThreads { line += String(process.threads).padding(toLength: 9, withPad: " ", startingAt: 0) }
                if showsUser { line += String(process.user.prefix(9)).padding(toLength: 10, withPad: " ", startingAt: 0) }
                put(line, row, left + 2, color, background: background)
                put(process.memory.leftPadding(to: 5), row, left + width - 15, color, background: background)
                let cpuColor = index == selected ? Theme.selected
                    : RGB.gradient(Theme.process.0, Theme.process.1, Theme.process.2, process.cpu / 14)
                put(String(format: "%5.1f", process.cpu), row, left + width - 8, cpuColor, background: background)
            }
            let bottom = top + height - 1
            label("↑ select ↓", bottom, left + 2, Theme.procBox, textColor: Theme.text)
            if width >= 40 { label("info ↵", bottom, left + 16, Theme.procBox, textColor: Theme.text) }
            if width >= 60 { label("2/214", bottom, left + width - 10, Theme.procBox, textColor: Theme.text) }
        }

        /// The screen as a terminal draws it: the alternate screen, no cursor, each row placed.
        func ansi() -> String {
            var out = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[0m\u{1B}[H\u{1B}[2J"
            for (index, row) in cells.enumerated() {
                out += "\u{1B}[\(index + 1);1H\u{1B}[0m"
                var current = Cell()
                for cell in row {
                    if cell.foreground != current.foreground || cell.background != current.background || cell.bold != current.bold {
                        out += "\u{1B}[0m"
                        if cell.bold { out += "\u{1B}[1m" }
                        if let color = cell.foreground { out += "\u{1B}[38;2;\(color.r);\(color.g);\(color.b)m" }
                        if let color = cell.background { out += "\u{1B}[48;2;\(color.r);\(color.g);\(color.b)m" }
                        current = Cell(character: " ", foreground: cell.foreground, background: cell.background, bold: cell.bold)
                    }
                    out.append(cell.character)
                }
            }
            return out + "\u{1B}[0m"
        }
    }
}

private extension String {
    func leftPadding(to length: Int) -> String {
        count >= length ? self : String(repeating: " ", count: length - count) + self
    }
}
#endif
