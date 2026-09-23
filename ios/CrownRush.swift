// CrownRush.swift — v2
// Zamana karşı taç yerleştirme bulmacası – SwiftUI, iOS 17+
// Özellikler: tek çözümlü bulmaca üretici, kademeli büyüyen tahtalar,
// günlük can sistemi + ödüllü reklamla can kazanma, ipucu, liderlik tablosu.
//
// Kurulum: Xcode → New Project → iOS App (SwiftUI, iOS 17).
// Şablonun <Proje>App.swift ve ContentView.swift dosyalarını silip bu dosyayı ekleyin.
// Xcode 26 kullanıyorsanız: Build Settings → Default Actor Isolation → nonisolated.

import SwiftUI
import UIKit

// MARK: - App

@main
struct CrownRushApp: App {
    @StateObject private var lives = LivesStore()
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(lives)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Ayarlar

enum Config {
    static let startTime: Double = 60
    static let freeLives = 3
    static let adDailyLimit = 5
    static let adSeconds = 5
    static let hintsPerRun = 3
    static let hintPenalty: Double = 5
}

enum Difficulty: String, CaseIterable, Identifiable, Codable, Hashable {
    case easy, medium, hard, expert
    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Kolay"
        case .medium: return "Orta"
        case .hard: return "Zor"
        case .expert: return "Uzman"
        }
    }
    var bonus: Double {
        switch self {
        case .easy: return 10
        case .medium: return 7
        case .hard: return 5
        case .expert: return 3
        }
    }
    var startSize: Int {
        switch self {
        case .easy: return 5
        case .medium: return 6
        case .hard: return 7
        case .expert: return 8
        }
    }
    /// Kaç çözümde bir tahta büyür
    var step: Int { self == .expert ? 1 : 2 }
    var maxSize: Int { self == .easy ? 9 : 10 }

    /// k. bulmacanın (0'dan başlar) tahta boyutu
    func size(forPuzzle k: Int) -> Int { min(maxSize, startSize + k / step) }

    var tint: Color {
        switch self {
        case .easy: return .green
        case .medium: return .blue
        case .hard: return .orange
        case .expert: return .red
        }
    }
    var sizeLabel: String { "\(startSize)×\(startSize) → \(maxSize)×\(maxSize)" }
    var growText: String { step == 1 ? "her çözümde büyür" : "her \(step) çözümde büyür" }
}

// MARK: - Bulmaca

struct Puzzle: Identifiable, Sendable {
    let id = UUID()
    let size: Int
    let regions: [Int]   // regions[r*size+c]
    let solution: [Int]  // solution[satır] = sütun
}

enum PuzzleGenerator {

    static func generate(size n: Int) -> Puzzle {
        while true {
            guard let queens = randomQueens(n) else { continue }
            var regions = growRegions(n: n, queens: queens)
            if makeUnique(n: n, regions: &regions, queens: queens) {
                let perm = Array(0..<n).shuffled()   // renk sırası ipucu vermesin
                return Puzzle(size: n, regions: regions.map { perm[$0] }, solution: queens)
            }
        }
    }

    static func randomQueens(_ n: Int) -> [Int]? {
        var cols = [Int](repeating: -1, count: n)
        var used = [Bool](repeating: false, count: n)
        func place(_ r: Int) -> Bool {
            if r == n { return true }
            for c in Array(0..<n).shuffled() where !used[c] {
                if r > 0 && abs(cols[r - 1] - c) <= 1 { continue }
                cols[r] = c; used[c] = true
                if place(r + 1) { return true }
                used[c] = false
            }
            return false
        }
        return place(0) ? cols : nil
    }

    static func neighbors4(_ i: Int, _ n: Int) -> [Int] {
        let r = i / n, c = i % n
        var out: [Int] = []
        if r > 0 { out.append(i - n) }
        if r < n - 1 { out.append(i + n) }
        if c > 0 { out.append(i - 1) }
        if c < n - 1 { out.append(i + 1) }
        return out
    }

    static func growRegions(n: Int, queens: [Int]) -> [Int] {
        var g = [Int](repeating: -1, count: n * n)
        for r in 0..<n { g[r * n + queens[r]] = r }
        var remaining = n * n - n
        while remaining > 0 {
            var candidates: [(Int, Int)] = []
            for i in 0..<(n * n) where g[i] == -1 {
                for nb in neighbors4(i, n) where g[nb] != -1 { candidates.append((i, g[nb])) }
            }
            guard let pick = candidates.randomElement() else { break }
            g[pick.0] = pick.1
            remaining -= 1
        }
        return g
    }

    static func solve(n: Int, regions: [Int], limit: Int) -> [[Int]] {
        var results: [[Int]] = []
        var cols = [Int](repeating: -1, count: n)
        var colUsed = [Bool](repeating: false, count: n)
        var regUsed = [Bool](repeating: false, count: n)
        func bt(_ r: Int) {
            if results.count >= limit { return }
            if r == n { results.append(cols); return }
            for c in 0..<n {
                if colUsed[c] { continue }
                let reg = regions[r * n + c]
                if regUsed[reg] { continue }
                if r > 0 && abs(cols[r - 1] - c) <= 1 { continue }
                cols[r] = c; colUsed[c] = true; regUsed[reg] = true
                bt(r + 1)
                colUsed[c] = false; regUsed[reg] = false
                if results.count >= limit { return }
            }
        }
        bt(0)
        return results
    }

    static func isConnected(region: Int, _ g: [Int], _ n: Int) -> Bool {
        let cells = g.indices.filter { g[$0] == region }
        guard let first = cells.first else { return false }
        var seen: Set<Int> = [first]
        var stack = [first]
        while let cur = stack.popLast() {
            for nb in neighbors4(cur, n) where g[nb] == region && !seen.contains(nb) {
                seen.insert(nb); stack.append(nb)
            }
        }
        return seen.count == cells.count
    }

    /// Alternatif çözümleri, onların taç hücrelerini komşu bölgelere kaydırarak bozar.
    static func makeUnique(n: Int, regions: inout [Int], queens: [Int]) -> Bool {
        let queenCells = Set((0..<n).map { $0 * n + queens[$0] })
        for _ in 0..<(n * 40) {
            let sols = solve(n: n, regions: regions, limit: 2)
            if sols.count == 1 { return true }
            guard let alt = sols.first(where: { $0 != queens }) else { return false }
            let diffCells = (0..<n).filter { alt[$0] != queens[$0] }.map { $0 * n + alt[$0] }.shuffled()
            var changed = false
            outer: for cell in diffCells where !queenCells.contains(cell) {
                let current = regions[cell]
                let options = Set(neighbors4(cell, n).map { regions[$0] }).subtracting([current]).shuffled()
                for newReg in options {
                    regions[cell] = newReg
                    if isConnected(region: current, regions, n) { changed = true; break outer }
                    regions[cell] = current
                }
            }
            if !changed { return false }
        }
        return false
    }
}

// MARK: - Skorlar

struct RunResult: Codable, Identifiable {
    var id = UUID()
    let difficulty: Difficulty
    let solved: Int
    let avgSolve: Double
    let maxSize: Int
    let date: Date
}

final class ScoreStore: ObservableObject {
    static let shared = ScoreStore()
    @Published private(set) var results: [RunResult] = []
    private let key = "crownrush.results.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RunResult].self, from: data) {
            results = decoded
        }
    }

    func add(_ r: RunResult) {
        results.append(r)
        if let data = try? JSONEncoder().encode(results) { UserDefaults.standard.set(data, forKey: key) }
    }

    func top(for d: Difficulty, thisWeekOnly: Bool, limit: Int = 10) -> [RunResult] {
        results
            .filter { $0.difficulty == d && $0.solved > 0 }
            .filter { !thisWeekOnly || Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }
            .sorted { ($0.solved, -$0.avgSolve) > ($1.solved, -$1.avgSolve) }
            .prefix(limit)
            .map { $0 }
    }

    func best(for d: Difficulty) -> RunResult? { top(for: d, thisWeekOnly: false, limit: 1).first }
}

// MARK: - Can sistemi

final class LivesStore: ObservableObject {
    @Published private(set) var lives: Int
    @Published private(set) var adsToday: Int
    private var day: String
    private let defaults = UserDefaults.standard

    init() {
        lives = defaults.object(forKey: "cr.lives") as? Int ?? Config.freeLives
        adsToday = defaults.integer(forKey: "cr.ads")
        day = defaults.string(forKey: "cr.day") ?? ""
        refillIfNewDay()
    }

    static func today() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Gece yarısından sonra canları en az 3'e tamamlar, reklam hakkını sıfırlar.
    func refillIfNewDay() {
        let t = Self.today()
        guard day != t else { return }
        day = t
        lives = max(lives, Config.freeLives)
        adsToday = 0
        save()
    }

    var canWatchAd: Bool { adsToday < Config.adDailyLimit }
    var adsRemaining: Int { max(0, Config.adDailyLimit - adsToday) }

    /// Koşu başlarken 1 can düşer (çıkıp canı korumayı engeller).
    func consume() -> Bool {
        refillIfNewDay()
        guard lives > 0 else { return false }
        lives -= 1
        save()
        return true
    }

    func grantFromAd() {
        guard canWatchAd else { return }
        lives += 1
        adsToday += 1
        save()
    }

    private func save() {
        defaults.set(lives, forKey: "cr.lives")
        defaults.set(adsToday, forKey: "cr.ads")
        defaults.set(day, forKey: "cr.day")
    }

    static func untilMidnight() -> String {
        let cal = Calendar.current
        let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let mins = max(1, Int(ceil(next.timeIntervalSinceNow / 60)))
        let h = mins / 60
        return h > 0 ? "\(h)sa \(mins % 60)dk" : "\(mins)dk"
    }
}

// MARK: - Haptik

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Oyun durumu

enum CellMark { case empty, x, queen }
enum Phase { case countdown, playing, paused, over }

struct Flash: Equatable { let id = UUID(); let text: String; let isPenalty: Bool }
struct Toast: Equatable { let id = UUID(); let text: String }
struct HintMark: Equatable { let id = UUID(); let index: Int }

@MainActor
final class GameModel: ObservableObject {
    let difficulty: Difficulty

    @Published private(set) var puzzle: Puzzle?
    @Published private(set) var marks: [CellMark] = []
    @Published private(set) var timeLeft: Double
    @Published private(set) var solved = 0
    @Published private(set) var phase: Phase = .countdown
    @Published private(set) var countdown = 3
    @Published private(set) var flash: Flash?
    @Published private(set) var toast: Toast?
    @Published private(set) var hintCell: HintMark?
    @Published private(set) var justSolved = false
    @Published private(set) var isNewBest = false
    @Published private(set) var hintsLeft = Config.hintsPerRun
    @Published private(set) var maxSize = 0
    @Published var autoX: Bool {
        didSet { UserDefaults.standard.set(autoX, forKey: "autoX") }
    }

    private var undoStack: [[CellMark]] = []
    private var prefetchTask: Task<Puzzle, Never>?
    private var ticker: Timer?
    private var lastTick = Date()
    private var puzzleStart = Date()
    private var solveTimes: [Double] = []
    private var isBusy = true

    init(difficulty: Difficulty) {
        self.difficulty = difficulty
        self.timeLeft = Config.startTime
        self.autoX = UserDefaults.standard.object(forKey: "autoX") as? Bool ?? true
        prefetch(forPuzzle: 0)
    }

    var avgSolve: Double { solveTimes.isEmpty ? 0 : solveTimes.reduce(0, +) / Double(solveTimes.count) }
    var canInteract: Bool { phase == .playing && !isBusy }

    // MARK: Akış

    func start() async {
        phase = .countdown
        isBusy = true
        for i in stride(from: 3, through: 1, by: -1) {
            countdown = i
            Haptics.tick()
            try? await Task.sleep(nanoseconds: 750_000_000)
            if Task.isCancelled { return }
        }
        await loadNext()
        phase = .playing
        isBusy = false
        lastTick = Date()
        startTicker()
    }

    func restart() {
        ticker?.invalidate()
        timeLeft = Config.startTime
        solved = 0
        solveTimes = []
        isNewBest = false
        hintsLeft = Config.hintsPerRun
        maxSize = 0
        puzzle = nil
        marks = []
        hintCell = nil
        prefetch(forPuzzle: 0)
        Task { await start() }
    }

    func pause() { if phase == .playing { phase = .paused } }
    func resume() { if phase == .paused { lastTick = Date(); phase = .playing } }
    func quit() { ticker?.invalidate(); ticker = nil }

    private func prefetch(forPuzzle k: Int) {
        let n = difficulty.size(forPuzzle: k)
        prefetchTask = Task.detached(priority: .userInitiated) {
            PuzzleGenerator.generate(size: n)
        }
    }

    private func loadNext() async {
        guard let task = prefetchTask else { return }
        let prevN = puzzle?.size ?? 0
        let p = await task.value
        marks = Array(repeating: .empty, count: p.size * p.size)
        undoStack = []
        hintCell = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { puzzle = p }
        maxSize = max(maxSize, p.size)
        if prevN > 0 && p.size > prevN {
            toast = Toast(text: "Tahta büyüdü! \(p.size)×\(p.size)")
        }
        puzzleStart = Date()
        prefetch(forPuzzle: solved + 1)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        defer { lastTick = now }
        guard phase == .playing, !isBusy else { return }
        timeLeft -= now.timeIntervalSince(lastTick)
        if timeLeft <= 0 { timeLeft = 0; endRun() }
    }

    private func endRun() {
        ticker?.invalidate()
        ticker = nil
        phase = .over
        Haptics.error()
        let prevBest = ScoreStore.shared.best(for: difficulty)?.solved ?? 0
        isNewBest = solved > prevBest
        ScoreStore.shared.add(RunResult(difficulty: difficulty, solved: solved, avgSolve: avgSolve,
                                        maxSize: maxSize, date: Date()))
    }

    // MARK: Hücre işlemleri

    func tap(_ i: Int) {
        guard canInteract, marks.indices.contains(i) else { return }
        pushUndo()
        switch marks[i] {
        case .empty: marks[i] = .x
        case .x: marks[i] = .queen
        case .queen: marks[i] = .empty
        }
        Haptics.light()
        checkSolved()
    }

    func beginPaint(at i: Int) -> CellMark {
        guard canInteract, marks.indices.contains(i) else { return .x }
        pushUndo()
        let target: CellMark = marks[i] == .x ? .empty : .x
        paint(i, to: target)
        return target
    }

    func paint(_ i: Int, to target: CellMark) {
        guard canInteract, marks.indices.contains(i), marks[i] != .queen, marks[i] != target else { return }
        marks[i] = target
        Haptics.tick()
    }

    func undo() {
        guard canInteract, let last = undoStack.popLast() else { return }
        marks = last
    }

    func clear() {
        guard canInteract else { return }
        pushUndo()
        marks = Array(repeating: .empty, count: marks.count)
    }

    private func pushUndo() {
        undoStack.append(marks)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }

    // MARK: İpucu
    // Öncelik: 1) yanlış taçı düzelt  2) çözüm hücresindeki ✕'i düzelt  3) doğru bir taç koy

    func useHint() {
        guard canInteract, hintsLeft > 0, let p = puzzle else { return }
        let n = p.size
        let sol = Set((0..<n).map { $0 * n + p.solution[$0] })
        let wrongQ = marks.indices.filter { marks[$0] == .queen && !sol.contains($0) }
        let wrongX = marks.indices.filter { marks[$0] == .x && sol.contains($0) }
        let open = sol.filter { marks[$0] != .queen }

        pushUndo()
        let target: Int
        let msg: String
        if let t = wrongQ.randomElement() {
            marks[t] = .x; target = t; msg = "Bu taç yanlış yerdeydi"
        } else if let t = wrongX.randomElement() {
            marks[t] = .queen; target = t; msg = "Buraya taç gelmeli"
        } else if let t = open.randomElement() {
            marks[t] = .queen; target = t; msg = "Buraya taç gelmeli"
        } else {
            undoStack.removeLast()
            return
        }
        hintsLeft -= 1
        timeLeft = max(0.1, timeLeft - Config.hintPenalty)
        hintCell = HintMark(index: target)
        flash = Flash(text: "−\(Int(Config.hintPenalty))s", isPenalty: true)
        toast = Toast(text: "💡 " + msg)
        Haptics.light()
        checkSolved()
    }

    // MARK: Kurallar

    var conflicts: Set<Int> {
        guard let p = puzzle else { return [] }
        let n = p.size
        let qs = marks.indices.filter { marks[$0] == .queen }
        var bad = Set<Int>()
        for a in 0..<qs.count {
            for b in (a + 1)..<qs.count {
                let i = qs[a], j = qs[b]
                let r1 = i / n, c1 = i % n, r2 = j / n, c2 = j % n
                if r1 == r2 || c1 == c2 || p.regions[i] == p.regions[j]
                    || (abs(r1 - r2) <= 1 && abs(c1 - c2) <= 1) {
                    bad.insert(i); bad.insert(j)
                }
            }
        }
        return bad
    }

    var autoMarked: Set<Int> {
        guard autoX, let p = puzzle else { return [] }
        let n = p.size
        var out = Set<Int>()
        for q in marks.indices where marks[q] == .queen {
            let qr = q / n, qc = q % n
            for i in 0..<(n * n) where marks[i] == .empty {
                let r = i / n, c = i % n
                if r == qr || c == qc || p.regions[i] == p.regions[q]
                    || (abs(r - qr) <= 1 && abs(c - qc) <= 1) {
                    out.insert(i)
                }
            }
        }
        return out
    }

    private func checkSolved() {
        guard let p = puzzle else { return }
        guard marks.filter({ $0 == .queen }).count == p.size, conflicts.isEmpty else { return }

        solveTimes.append(Date().timeIntervalSince(puzzleStart))
        solved += 1
        timeLeft += difficulty.bonus
        flash = Flash(text: "+\(Int(difficulty.bonus))s", isPenalty: false)
        justSolved = true
        isBusy = true
        Haptics.success()

        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            justSolved = false
            await loadNext()
            isBusy = false
            lastTick = Date()
        }
    }
}

// MARK: - Görsel yardımcılar

let regionPalette: [Color] = [
    Color(red: 0.99, green: 0.80, blue: 0.60),
    Color(red: 0.70, green: 0.82, blue: 0.98),
    Color(red: 0.78, green: 0.93, blue: 0.70),
    Color(red: 0.87, green: 0.76, blue: 0.97),
    Color(red: 0.99, green: 0.93, blue: 0.58),
    Color(red: 0.98, green: 0.70, blue: 0.72),
    Color(red: 0.72, green: 0.90, blue: 0.90),
    Color(red: 0.86, green: 0.86, blue: 0.86),
    Color(red: 0.95, green: 0.78, blue: 0.90),
    Color(red: 0.80, green: 0.88, blue: 0.62)
]

let appBackground = LinearGradient(
    colors: [Color(red: 0.08, green: 0.07, blue: 0.14), Color(red: 0.14, green: 0.10, blue: 0.24)],
    startPoint: .top, endPoint: .bottom
)
let cardColor = Color(red: 0.13, green: 0.11, blue: 0.22)

func formatTime(_ t: Double) -> String {
    let t = max(0, t)
    let m = Int(t) / 60, s = Int(t) % 60
    if t < 10 { return String(format: "%d.%d", s, Int((t - floor(t)) * 10)) }
    return String(format: "%d:%02d", m, s)
}

struct PrimaryButton: View {
    let title: String
    var dim = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(dim ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(dim ? AnyShapeStyle(Color.gray.opacity(0.45)) : AnyShapeStyle(Color.yellow.gradient)))
        }
    }
}

struct HeartsRow: View {
    let count: Int
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(Config.freeLives, count), id: \.self) { i in
                Image(systemName: "heart.fill")
                    .font(.system(size: size))
                    .foregroundStyle(i < count ? Color.red : Color.white.opacity(0.18))
                    .shadow(color: i < count ? .red.opacity(0.5) : .clear, radius: 5)
            }
        }
    }
}

// MARK: - Can / Reklam akışı

enum LifeCard: Equatable { case noLives, reward }

struct LivesFlow: ViewModifier {
    @EnvironmentObject private var lives: LivesStore
    @Binding var card: LifeCard?
    @Binding var showAd: Bool
    let onPlay: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let current = card {
                    LifeCardView(
                        card: current,
                        onWatchAd: { card = nil; showAd = true },
                        onPlay: { card = nil; onPlay() },
                        onClose: { card = nil }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: card)
            .fullScreenCover(isPresented: $showAd) {
                RewardedAdView { success in
                    showAd = false
                    if success {
                        lives.grantFromAd()
                        card = .reward
                    }
                }
            }
    }
}

struct LifeCardView: View {
    @EnvironmentObject private var lives: LivesStore
    let card: LifeCard
    let onWatchAd: () -> Void
    let onPlay: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                switch card {
                case .noLives:
                    Text("Canın Kalmadı")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text(lives.canWatchAd
                         ? "Yeni \(Config.freeLives) can \(LivesStore.untilMidnight()) sonra gelir. Beklemek istemiyorsan reklam izleyip hemen 1 can kazan."
                         : "Yeni canlar \(LivesStore.untilMidnight()) sonra gelir. Bugünlük reklam hakkın doldu.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if lives.canWatchAd {
                        PrimaryButton(title: "▶ Reklam İzle (+1 ❤)", action: onWatchAd)
                            .padding(.top, 6)
                        Text("Bugün kalan reklam hakkı: \(lives.adsRemaining)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .reward:
                    Text("+1 Can!")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    HeartsRow(count: lives.lives)
                    Text("Şu an \(lives.lives) canın var.").foregroundStyle(.secondary)
                    PrimaryButton(title: "Hemen Oyna (−1 ❤)", action: onPlay)
                        .padding(.top, 6)
                }
                Button(card == .reward ? "Sonra" : "Kapat", action: onClose)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 4)
            }
            .padding(26)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 28).fill(cardColor))
            .padding()
        }
    }
}

/// DEMO ödüllü reklam ekranı.
/// Yayına çıkmadan önce bunu Google Mobile Ads (AdMob) "Rewarded" reklamıyla değiştirin:
/// 1) Swift Package Manager ile Google Mobile Ads SDK'yı ekleyin.
/// 2) Info.plist'e GADApplicationIdentifier ve SKAdNetworkItems ekleyin.
/// 3) Uygulama açılışında SDK'yı başlatın, ödüllü reklamı önceden yükleyin.
/// 4) Kullanıcı ödülü kazandığında (reward handler) onFinish(true) çağırın.
/// Ayrıntılar: https://developers.google.com/admob/ios/rewarded
/// Geliştirme sırasında mutlaka Google'ın test reklam kimliklerini kullanın.
struct RewardedAdView: View {
    let onFinish: (Bool) -> Void
    @State private var left = Config.adSeconds
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Reklam · Demo")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.2)))
                Text("\(left)")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Ödül için sonuna kadar izle")
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .tint(.yellow)
                    .padding(.horizontal, 50)
                Text("Gerçek uygulamada burada ödüllü reklam oynatılır.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            for _ in 0..<Config.adSeconds {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                withAnimation {
                    left -= 1
                    progress = Double(Config.adSeconds - left) / Double(Config.adSeconds)
                }
            }
            onFinish(true)
        }
    }
}

// MARK: - Ana Ekran

struct HomeView: View {
    @EnvironmentObject private var lives: LivesStore
    @ObservedObject private var store = ScoreStore.shared
    @AppStorage("difficulty") private var diffRaw = Difficulty.easy.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var weekOnly = true
    @State private var showRules = false
    @State private var playing: Difficulty?
    @State private var lifeCard: LifeCard?
    @State private var showAd = false

    private var difficulty: Difficulty { Difficulty(rawValue: diffRaw) ?? .easy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    livesCard
                    difficultyGrid
                    Text("\(difficulty.startSize)×\(difficulty.startSize) ile başlar, \(difficulty.growText) · +\(Int(difficulty.bonus))s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    PrimaryButton(
                        title: lives.lives > 0 ? "\(difficulty.title) Koşuyu Başlat (−1 ❤)" : "Can Kalmadı – Can Kazan",
                        dim: lives.lives <= 0,
                        action: tryStart
                    )
                    leaderboard
                }
                .padding()
            }
            .background(appBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRules = true } label: { Image(systemName: "questionmark.circle") }
                }
            }
            .sheet(isPresented: $showRules) { RulesView() }
            .navigationDestination(item: $playing) { d in
                GameView(difficulty: d)
            }
            .modifier(LivesFlow(card: $lifeCard, showAd: $showAd, onPlay: tryStart))
        }
        .tint(.yellow)
        .onAppear { lives.refillIfNewDay() }
        .onChange(of: scenePhase) { _, p in
            if p == .active { lives.refillIfNewDay() }
        }
    }

    private func tryStart() {
        if lives.consume() {
            playing = difficulty
        } else {
            lifeCard = .noLives
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 54))
                .foregroundStyle(.yellow.gradient)
                .shadow(color: .yellow.opacity(0.5), radius: 16)
            Text("Crown Rush")
                .font(.system(size: 38, weight: .black, design: .rounded))
            Text("Küçük tahtayla başla, çözdükçe tahta büyür.\nSüre bitmeden ne kadar ileri gidebilirsin?")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var livesCard: some View {
        HStack {
            HeartsRow(count: lives.lives, size: 26)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(lives.lives > 0
                         ? "\(lives.lives) can · yenilenme \(LivesStore.untilMidnight())"
                         : "Can yok · yenilenme \(LivesStore.untilMidnight())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button { showAd = true } label: {
                    Text(lives.canWatchAd ? "▶ Reklam izle +1 ❤ (\(lives.adsRemaining))" : "Reklam limiti doldu")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.yellow.opacity(0.16)))
                        .foregroundStyle(.yellow)
                }
                .disabled(!lives.canWatchAd)
                .opacity(lives.canWatchAd ? 1 : 0.5)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
    }

    private var difficultyGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Difficulty.allCases) { d in
                let selected = d == difficulty
                Button {
                    diffRaw = d.rawValue
                    Haptics.tick()
                } label: {
                    VStack(spacing: 4) {
                        Text(d.title).font(.headline)
                        Text("+\(Int(d.bonus))s")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(d.tint)
                        Text(d.sizeLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(selected ? d.tint.opacity(0.18) : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(selected ? d.tint : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var leaderboard: some View {
        let rows = store.top(for: difficulty, thisWeekOnly: weekOnly)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Liderlik Tablosu").font(.headline)
                Spacer()
                Text(difficulty.title).font(.subheadline).foregroundStyle(difficulty.tint)
            }
            Picker("", selection: $weekOnly) {
                Text("Bu Hafta").tag(true)
                Text("Tüm Zamanlar").tag(false)
            }
            .pickerStyle(.segmented)

            if rows.isEmpty {
                Text("Henüz skor yok. İlk koşunu yap!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    HStack {
                        Text("#\(idx + 1)")
                            .font(.system(.body, design: .rounded).bold())
                            .frame(width: 36, alignment: .leading)
                            .foregroundStyle(idx == 0 ? .yellow : .primary)
                        Text(r.date, format: .dateTime.day().month().hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(r.solved) çözüm").bold()
                        Text("\(r.maxSize)×\(r.maxSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.3)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Kurallar

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Kurallar") {
                    Label("Her satırda tam bir taç olmalı.", systemImage: "arrow.left.and.right")
                    Label("Her sütunda tam bir taç olmalı.", systemImage: "arrow.up.and.down")
                    Label("Her renkli bölgede tam bir taç olmalı.", systemImage: "square.grid.3x3.fill")
                    Label("Taçlar birbirine değemez (çapraz dahil).", systemImage: "hand.raised.fill")
                }
                Section("Kontroller") {
                    Label("Bir dokunuş: ✕ işareti", systemImage: "xmark")
                    Label("İki dokunuş: Taç", systemImage: "crown.fill")
                    Label("Üç dokunuş: Temizle", systemImage: "square")
                    Label("Sürükle: Birden çok hücreye ✕ koy / sil", systemImage: "hand.draw")
                    Label("İpucu: Her koşuda \(Config.hintsPerRun) hak, her biri −\(Int(Config.hintPenalty))s", systemImage: "lightbulb.fill")
                }
                Section("Zamana Karşı") {
                    Text("\(Int(Config.startTime)) saniyeyle başlarsın. Her çözülen tahta zorluğa göre +10 / +7 / +5 / +3 saniye ekler. Tahtalar çözdükçe büyür, süre bitince koşu sona erer.")
                }
                Section("Canlar") {
                    Text("Her gün \(Config.freeLives) can verilir ve her koşu 1 can harcar. Canlar gece yarısı yenilenir. Reklam izleyerek günde en fazla \(Config.adDailyLimit) ek can kazanabilirsin.")
                }
            }
            .navigationTitle("Nasıl Oynanır")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Tamam") { dismiss() } }
            }
        }
    }
}

// MARK: - Oyun Ekranı

struct GameView: View {
    @EnvironmentObject private var lives: LivesStore
    @StateObject private var game: GameModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var lifeCard: LifeCard?
    @State private var showAd = false

    init(difficulty: Difficulty) {
        _game = StateObject(wrappedValue: GameModel(difficulty: difficulty))
    }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            timerView
            levelBar
            boardArea
            controls
            Text("Dokun: ✕ → taç → boş · Sürükle: toplu ✕")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding()
        .background(appBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .task { await game.start() }
        .onDisappear { game.quit() }
        .onChange(of: scenePhase) { _, p in
            if p != .active { game.pause() }
        }
        .overlay {
            if game.phase == .over {
                GameOverView(game: game, onAgain: tryRestart, onHome: { dismiss() })
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.phase)
        .modifier(LivesFlow(card: $lifeCard, showAd: $showAd, onPlay: tryRestart))
    }

    private func tryRestart() {
        if lives.consume() {
            game.restart()
        } else if lives.canWatchAd {
            showAd = true
        } else {
            lifeCard = .noLives
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                game.quit()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            Spacer()
            Label("\(game.solved)", systemImage: "crown.fill")
                .font(.system(.title2, design: .rounded).bold())
                .foregroundStyle(.yellow)
                .contentTransition(.numericText())
                .animation(.spring, value: game.solved)
            Spacer()
            Button {
                game.phase == .paused ? game.resume() : game.pause()
            } label: {
                Image(systemName: game.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .disabled(game.phase != .playing && game.phase != .paused)
        }
        .foregroundStyle(.white)
    }

    private var timerView: some View {
        let low = game.timeLeft < 10 && game.phase == .playing
        let d = game.difficulty
        return VStack(spacing: 2) {
            Text(formatTime(game.timeLeft))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(low ? .red : .white)
                .scaleEffect(low ? 1.06 : 1)
                .animation(low ? .easeInOut(duration: 0.5).repeatForever() : .default, value: low)
            Text(game.puzzle.map { "\(d.title) · Tahta \($0.size)×\($0.size) · +\(Int(d.bonus))s" }
                 ?? "\(d.title) · çözüm başına +\(Int(d.bonus))s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var levelBar: some View {
        let d = game.difficulty
        let steps = d.maxSize - d.startSize + 1
        let cur = (game.puzzle?.size ?? d.startSize) - d.startSize
        return HStack(spacing: 4) {
            ForEach(0..<steps, id: \.self) { i in
                Capsule()
                    .fill(i <= cur ? Color.yellow : Color.white.opacity(0.15))
                    .frame(width: 18, height: 5)
            }
        }
        .animation(.spring, value: cur)
    }

    private var boardArea: some View {
        ZStack {
            if let p = game.puzzle {
                BoardView(game: game, puzzle: p)
                    .id(p.id)
                    .blur(radius: game.phase == .paused ? 22 : 0)
                    .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.05))
                    .aspectRatio(1, contentMode: .fit)
            }

            if game.phase == .countdown {
                Text("\(game.countdown)")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)
                    .id(game.countdown)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring, value: game.countdown)
            }

            if game.phase == .paused {
                Button { game.resume() } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "play.circle.fill").font(.system(size: 64))
                        Text("Devam Et").font(.title3.bold())
                    }
                    .foregroundStyle(.white)
                }
            }

            if let f = game.flash {
                FloatingText(text: f.text, color: f.isPenalty ? .red : .green)
                    .id(f.id)
                    .allowsHitTesting(false)
            }

            if let t = game.toast {
                ToastView(text: t.text)
                    .id(t.id)
                    .offset(y: -40)
            }
        }
        .frame(maxWidth: 560)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            ControlButton(icon: "arrow.uturn.backward", title: "Geri Al") { game.undo() }
            ControlButton(icon: "trash", title: "Temizle") { game.clear() }
            ControlButton(icon: game.autoX ? "checkmark.square.fill" : "square",
                          title: "Otomatik ✕", highlighted: game.autoX) {
                game.autoX.toggle()
                Haptics.tick()
            }
            ControlButton(icon: "lightbulb.fill", title: "İpucu (\(game.hintsLeft))") {
                game.useHint()
            }
            .disabled(game.hintsLeft == 0)
            .opacity(game.hintsLeft == 0 ? 0.45 : 1)
        }
        .disabled(game.phase != .playing)
        .opacity(game.phase == .playing ? 1 : 0.5)
    }
}

struct ControlButton: View {
    let icon: String
    let title: String
    var highlighted = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(highlighted ? Color.yellow.opacity(0.18) : .white.opacity(0.06)))
            .foregroundStyle(highlighted ? .yellow : .white)
        }
    }
}

struct FloatingText: View {
    let text: String
    let color: Color
    @State private var go = false
    var body: some View {
        Text(text)
            .font(.system(size: 48, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.5), radius: 6)
            .scaleEffect(go ? 1.3 : 0.7)
            .offset(y: go ? -90 : 0)
            .opacity(go ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.0)) { go = true } }
    }
}

struct ToastView: View {
    let text: String
    @State private var shown = false
    @State private var gone = false
    var body: some View {
        Text(text)
            .font(.system(.headline, design: .rounded).weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(Color.yellow))
            .shadow(color: .black.opacity(0.4), radius: 10)
            .scaleEffect(shown ? 1 : 0.5)
            .opacity(gone ? 0 : (shown ? 1 : 0))
            .offset(y: gone ? -30 : 0)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { shown = true } }
            .task {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                withAnimation(.easeOut(duration: 0.4)) { gone = true }
            }
    }
}

// MARK: - Tahta

struct BoardView: View {
    @ObservedObject var game: GameModel
    let puzzle: Puzzle

    @State private var dragStart: Int?
    @State private var lastCell: Int?
    @State private var isPainting = false
    @State private var paintTarget: CellMark = .x

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let n = puzzle.size
            let cs = side / CGFloat(n)
            let conflicts = game.conflicts
            let auto = game.autoMarked

            ZStack(alignment: .topLeading) {
                ForEach(0..<(n * n), id: \.self) { i in
                    CellView(
                        color: regionPalette[puzzle.regions[i] % regionPalette.count],
                        mark: i < game.marks.count ? game.marks[i] : .empty,
                        auto: auto.contains(i),
                        conflict: conflicts.contains(i),
                        size: cs
                    )
                    .frame(width: cs, height: cs)
                    .position(x: CGFloat(i % n) * cs + cs / 2, y: CGFloat(i / n) * cs + cs / 2)
                }
                GridLines(n: n)
                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
                    .frame(width: side, height: side)
                RegionBorders(puzzle: puzzle)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: max(2.5, cs * 0.07), lineCap: .square))
                    .frame(width: side, height: side)
                if let h = game.hintCell, h.index < n * n {
                    HintGlow(size: cs)
                        .id(h.id)
                        .position(x: CGFloat(h.index % n) * cs + cs / 2, y: CGFloat(h.index / n) * cs + cs / 2)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(game.justSolved ? Color.green : .black, lineWidth: game.justSolved ? 5 : 3))
            .shadow(color: game.justSolved ? .green.opacity(0.7) : .black.opacity(0.4), radius: 14)
            .contentShape(Rectangle())
            .gesture(dragGesture(cs: cs, n: n))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func index(at p: CGPoint, cs: CGFloat, n: Int) -> Int? {
        guard p.x >= 0, p.y >= 0 else { return nil }
        let c = Int(p.x / cs), r = Int(p.y / cs)
        guard r < n, c < n else { return nil }
        return r * n + c
    }

    private func dragGesture(cs: CGFloat, n: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard let i = index(at: v.location, cs: cs, n: n) else { return }
                guard let start = dragStart else {
                    dragStart = i; lastCell = i
                    return
                }
                if !isPainting && i != start {
                    isPainting = true
                    paintTarget = game.beginPaint(at: start)
                }
                if isPainting && i != lastCell {
                    game.paint(i, to: paintTarget)
                    lastCell = i
                }
            }
            .onEnded { _ in
                if !isPainting, let s = dragStart { game.tap(s) }
                dragStart = nil; lastCell = nil; isPainting = false
            }
    }
}

struct CellView: View {
    let color: Color
    let mark: CellMark
    let auto: Bool
    let conflict: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(color)
            if conflict { Rectangle().fill(Color.red.opacity(0.4)) }
            switch mark {
            case .queen:
                Image(systemName: "crown.fill")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(conflict ? Color.red : Color.black)
                    .transition(.scale.combined(with: .opacity))
            case .x:
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.32, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.8))
            case .empty:
                if auto {
                    Image(systemName: "xmark")
                        .font(.system(size: size * 0.24, weight: .bold))
                        .foregroundStyle(.black.opacity(0.35))
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: mark)
    }
}

struct HintGlow: View {
    let size: CGFloat
    @State private var on = false
    @State private var gone = false
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow.opacity(0.25))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.yellow, lineWidth: 4))
            .frame(width: size, height: size)
            .shadow(color: .yellow, radius: 8)
            .opacity(gone ? 0 : (on ? 1 : 0.25))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3).repeatCount(5, autoreverses: true)) { on = true }
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_700_000_000)
                withAnimation(.easeOut(duration: 0.4)) { gone = true }
            }
    }
}

struct GridLines: Shape {
    let n: Int
    func path(in rect: CGRect) -> Path {
        let cs = rect.width / CGFloat(n)
        var p = Path()
        for k in 1..<max(n, 2) where k < n {
            let v = CGFloat(k) * cs
            p.move(to: CGPoint(x: v, y: 0)); p.addLine(to: CGPoint(x: v, y: rect.height))
            p.move(to: CGPoint(x: 0, y: v)); p.addLine(to: CGPoint(x: rect.width, y: v))
        }
        return p
    }
}

struct RegionBorders: Shape {
    let puzzle: Puzzle
    func path(in rect: CGRect) -> Path {
        let n = puzzle.size
        let cs = rect.width / CGFloat(n)
        var p = Path()
        for r in 0..<n {
            for c in 0..<n {
                let reg = puzzle.regions[r * n + c]
                if c < n - 1 && puzzle.regions[r * n + c + 1] != reg {
                    p.move(to: CGPoint(x: CGFloat(c + 1) * cs, y: CGFloat(r) * cs))
                    p.addLine(to: CGPoint(x: CGFloat(c + 1) * cs, y: CGFloat(r + 1) * cs))
                }
                if r < n - 1 && puzzle.regions[(r + 1) * n + c] != reg {
                    p.move(to: CGPoint(x: CGFloat(c) * cs, y: CGFloat(r + 1) * cs))
                    p.addLine(to: CGPoint(x: CGFloat(c + 1) * cs, y: CGFloat(r + 1) * cs))
                }
            }
        }
        return p
    }
}

// MARK: - Oyun Sonu

struct GameOverView: View {
    @EnvironmentObject private var lives: LivesStore
    @ObservedObject var game: GameModel
    let onAgain: () -> Void
    let onHome: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Süre Doldu!")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                if game.isNewBest {
                    Label("Yeni Rekor!", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(.yellow))
                }
                HStack(spacing: 24) {
                    stat(value: "\(game.solved)", label: "Çözülen")
                    stat(value: game.maxSize > 0 ? "\(game.maxSize)×\(game.maxSize)" : "–", label: "Ulaşılan")
                    stat(value: String(format: "%.1fs", game.avgSolve), label: "Ort. Süre")
                }
                HeartsRow(count: lives.lives)
                Text(lives.lives > 0
                     ? "\(lives.lives) canın kaldı"
                     : "Canın kalmadı · yenilenme \(LivesStore.untilMidnight())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                PrimaryButton(
                    title: lives.lives > 0 ? "Tekrar Oyna (−1 ❤)"
                        : (lives.canWatchAd ? "▶ Reklam İzle, Can Kazan" : "Can Kalmadı"),
                    dim: lives.lives <= 0 && !lives.canWatchAd,
                    action: onAgain
                )
                Button("Ana Menü", action: onHome)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(26)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 28).fill(cardColor))
            .padding()
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.yellow)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
