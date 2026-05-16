import Foundation

/// Swift port of simplex-noise.js 2.4.0 (Jonas Wagner).
///
/// 端到端对齐 v4 HTML 里用的 `new SimplexNoise('ostrich-x')` 输出。
/// 关键点：
/// 1. 字符串 seed 用 Alea PRNG 派生（v2.4.0 行为）。
/// 2. permutation table 构建顺序、洗牌算法、p / permMod12 表与 JS 完全一致。
/// 3. noise2D / noise3D 的 simplex 算法逐行翻译。
///
/// 参考：https://github.com/jwagner/simplex-noise.js/blob/v2.4.0/simplex-noise.js
public final class SimplexNoise {

    // MARK: - Tables

    private let p: [Int]          // size 256, permutation
    private let perm: [Int]       // size 512
    private let permMod12: [Int]  // size 512

    // MARK: - Init

    /// 使用字符串 seed —— 与 JS `new SimplexNoise(seed)` 行为对齐。
    public init(seed: String) {
        let random = Alea(seed: seed)
        self.p = SimplexNoise.buildPermutation(random: { random.next() })
        var perm = [Int](repeating: 0, count: 512)
        var permMod12 = [Int](repeating: 0, count: 512)
        for i in 0..<512 {
            perm[i] = p[i & 255]
            permMod12[i] = perm[i] % 12
        }
        self.perm = perm
        self.permMod12 = permMod12
    }

    /// 直接接受 [0,1) random 函数 —— 与 JS `new SimplexNoise(randomFn)` 行为对齐。
    public init(random: () -> Double) {
        self.p = SimplexNoise.buildPermutation(random: random)
        var perm = [Int](repeating: 0, count: 512)
        var permMod12 = [Int](repeating: 0, count: 512)
        for i in 0..<512 {
            perm[i] = p[i & 255]
            permMod12[i] = perm[i] % 12
        }
        self.perm = perm
        self.permMod12 = permMod12
    }

    /// JS 内 `buildPermutationTable(random)`：
    /// ```js
    /// var p = new Uint8Array(256);
    /// for (var i = 0; i < 256; i++) p[i] = i;
    /// for (var i = 0; i < 255; i++) {
    ///   var r = i + ~~(random() * (256 - i));
    ///   var aux = p[i]; p[i] = p[r]; p[r] = aux;
    /// }
    /// ```
    private static func buildPermutation(random: () -> Double) -> [Int] {
        var p = [Int](repeating: 0, count: 256)
        for i in 0..<256 { p[i] = i }
        for i in 0..<255 {
            // `~~` in JS = truncation toward zero (int32 cast)
            let r = i + Int(random() * Double(256 - i))
            let aux = p[i]
            p[i] = p[r]
            p[r] = aux
        }
        return p
    }

    // MARK: - Gradient tables (与 JS grad3 / grad4 字面量一致)

    private static let grad3: [Double] = [
        1, 1, 0, -1, 1, 0, 1, -1, 0,
        -1, -1, 0, 1, 0, 1, -1, 0, 1,
        1, 0, -1, -1, 0, -1, 0, 1, 1,
        0, -1, 1, 0, 1, -1, 0, -1, -1
    ]

    // MARK: - 2D noise (JS noise2D 逐行翻译)

    public func noise2D(_ xin: Double, _ yin: Double) -> Double {
        let F2 = 0.5 * (sqrt(3.0) - 1.0)
        let G2 = (3.0 - sqrt(3.0)) / 6.0
        let permMod12 = self.permMod12
        let perm = self.perm

        var n0: Double = 0, n1: Double = 0, n2: Double = 0

        let s = (xin + yin) * F2
        let i = Int(floor(xin + s))
        let j = Int(floor(yin + s))
        let t = Double(i + j) * G2
        let X0 = Double(i) - t
        let Y0 = Double(j) - t
        let x0 = xin - X0
        let y0 = yin - Y0

        let i1: Int
        let j1: Int
        if x0 > y0 { i1 = 1; j1 = 0 } else { i1 = 0; j1 = 1 }

        let x1 = x0 - Double(i1) + G2
        let y1 = y0 - Double(j1) + G2
        let x2 = x0 - 1.0 + 2.0 * G2
        let y2 = y0 - 1.0 + 2.0 * G2

        let ii = i & 255
        let jj = j & 255
        let gi0 = permMod12[ii + perm[jj]]
        let gi1 = permMod12[ii + i1 + perm[jj + j1]]
        let gi2 = permMod12[ii + 1 + perm[jj + 1]]

        var t0 = 0.5 - x0 * x0 - y0 * y0
        if t0 >= 0 {
            t0 *= t0
            n0 = t0 * t0 * (Self.grad3[gi0 * 3] * x0 + Self.grad3[gi0 * 3 + 1] * y0)
        }
        var t1 = 0.5 - x1 * x1 - y1 * y1
        if t1 >= 0 {
            t1 *= t1
            n1 = t1 * t1 * (Self.grad3[gi1 * 3] * x1 + Self.grad3[gi1 * 3 + 1] * y1)
        }
        var t2 = 0.5 - x2 * x2 - y2 * y2
        if t2 >= 0 {
            t2 *= t2
            n2 = t2 * t2 * (Self.grad3[gi2 * 3] * x2 + Self.grad3[gi2 * 3 + 1] * y2)
        }
        return 70.0 * (n0 + n1 + n2)
    }

    // MARK: - 3D noise (JS noise3D 逐行翻译)

    public func noise3D(_ xin: Double, _ yin: Double, _ zin: Double) -> Double {
        let permMod12 = self.permMod12
        let perm = self.perm

        var n0: Double = 0, n1: Double = 0, n2: Double = 0, n3: Double = 0

        let F3: Double = 1.0 / 3.0
        let G3: Double = 1.0 / 6.0

        let s = (xin + yin + zin) * F3
        let i = Int(floor(xin + s))
        let j = Int(floor(yin + s))
        let k = Int(floor(zin + s))
        let t = Double(i + j + k) * G3
        let X0 = Double(i) - t
        let Y0 = Double(j) - t
        let Z0 = Double(k) - t
        let x0 = xin - X0
        let y0 = yin - Y0
        let z0 = zin - Z0

        let i1: Int, j1: Int, k1: Int
        let i2: Int, j2: Int, k2: Int

        if x0 >= y0 {
            if y0 >= z0 {
                i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0
            } else if x0 >= z0 {
                i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1
            } else {
                i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1
            }
        } else {
            if y0 < z0 {
                i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1
            } else if x0 < z0 {
                i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1
            } else {
                i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0
            }
        }

        let x1 = x0 - Double(i1) + G3
        let y1 = y0 - Double(j1) + G3
        let z1 = z0 - Double(k1) + G3
        let x2 = x0 - Double(i2) + 2.0 * G3
        let y2 = y0 - Double(j2) + 2.0 * G3
        let z2 = z0 - Double(k2) + 2.0 * G3
        let x3 = x0 - 1.0 + 3.0 * G3
        let y3 = y0 - 1.0 + 3.0 * G3
        let z3 = z0 - 1.0 + 3.0 * G3

        let ii = i & 255
        let jj = j & 255
        let kk = k & 255
        let gi0 = permMod12[ii + perm[jj + perm[kk]]]
        let gi1 = permMod12[ii + i1 + perm[jj + j1 + perm[kk + k1]]]
        let gi2 = permMod12[ii + i2 + perm[jj + j2 + perm[kk + k2]]]
        let gi3 = permMod12[ii + 1 + perm[jj + 1 + perm[kk + 1]]]

        var t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0
        if t0 >= 0 {
            t0 *= t0
            n0 = t0 * t0 * (Self.grad3[gi0 * 3] * x0 + Self.grad3[gi0 * 3 + 1] * y0 + Self.grad3[gi0 * 3 + 2] * z0)
        }
        var t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
        if t1 >= 0 {
            t1 *= t1
            n1 = t1 * t1 * (Self.grad3[gi1 * 3] * x1 + Self.grad3[gi1 * 3 + 1] * y1 + Self.grad3[gi1 * 3 + 2] * z1)
        }
        var t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
        if t2 >= 0 {
            t2 *= t2
            n2 = t2 * t2 * (Self.grad3[gi2 * 3] * x2 + Self.grad3[gi2 * 3 + 1] * y2 + Self.grad3[gi2 * 3 + 2] * z2)
        }
        var t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
        if t3 >= 0 {
            t3 *= t3
            n3 = t3 * t3 * (Self.grad3[gi3 * 3] * x3 + Self.grad3[gi3 * 3 + 1] * y3 + Self.grad3[gi3 * 3 + 2] * z3)
        }
        return 32.0 * (n0 + n1 + n2 + n3)
    }
}

// MARK: - Alea PRNG (Johannes Baagøe, used by simplex-noise.js 2.4.0)

/// Swift port of the Alea PRNG. simplex-noise.js 2.4.0 internalises this
/// for string seeds via `new Alea(seed)`.
///
/// 参考：https://github.com/coverslide/node-alea/blob/master/alea.js
final class Alea {
    private var s0: Double = 0
    private var s1: Double = 0
    private var s2: Double = 0
    private var c: Double = 1

    init(seed: String) {
        // Mash 状态
        var mash = Mash()
        s0 = mash.run(" ")
        s1 = mash.run(" ")
        s2 = mash.run(" ")

        let value = mash.run(seed)
        s0 -= value
        if s0 < 0 { s0 += 1 }

        let v2 = mash.run(seed)
        s1 -= v2
        if s1 < 0 { s1 += 1 }

        let v3 = mash.run(seed)
        s2 -= v3
        if s2 < 0 { s2 += 1 }
    }

    /// 返回 [0, 1) 双精度浮点 —— 与 JS Alea() 调用结果一致。
    /// JS: `this.s2 = t - (this.c = t | 0);`
    ///   c 赋值为 t 的 int32 截断；
    ///   s2 赋值为 t - c (即 t 的小数部分)。
    func next() -> Double {
        let t = 2091639.0 * s0 + c * 2.3283064365386963e-10  // 2^-32
        s0 = s1
        s1 = s2
        // `t | 0` —— int32 截断（signed，mod 2^32）。
        let tInt = Self.toInt32(t)
        c = Double(tInt)
        s2 = t - c
        return s2
    }

    /// JS `t | 0`：先把 Number cast 成 int32（mod 2^32，再 signed 解释）。
    private static func toInt32(_ x: Double) -> Int32 {
        // toInt32 from ECMA-262: discard NaN/Inf -> 0, mod 2^32, signed.
        if !x.isFinite { return 0 }
        let trunc = x.rounded(.towardZero)
        let mod = trunc.truncatingRemainder(dividingBy: 4_294_967_296.0)
        var u = mod
        if u < 0 { u += 4_294_967_296.0 }
        if u >= 2_147_483_648.0 { u -= 4_294_967_296.0 }
        return Int32(u)
    }
}

/// JS `Mash` —— 用 UInt32 算术哈希字符串成 [0,1) double。
struct Mash {
    private var n: UInt32 = 0xefc8_249d  // = 4022871197

    mutating func run(_ data: String) -> Double {
        // 操作 UTF-16 code units，与 JS charCodeAt 一致
        let codeUnits = Array(data.utf16)
        var n = self.n
        for codeUnit in codeUnits {
            // n += data.charCodeAt(i)
            // var h = 0.02519603282416938 * n
            // n = h >>> 0
            // h -= n
            // h *= n
            // n = h >>> 0
            // h -= n
            // n += h * 0x100000000  // 2^32
            // The whole loop runs in double precision, with `>>> 0` doing unsigned-int32 cast.
            var nD = nDouble(n) + Double(codeUnit)
            var h = 0.02519603282416938 * nD
            nD = Self.toUInt32D(h)
            h -= nD
            h *= nD
            nD = Self.toUInt32D(h)
            h -= nD
            nD = nD + h * 4_294_967_296.0  // 2^32
            n = Self.toUInt32(nD)
        }
        self.n = n
        // return (n >>> 0) * 2.3283064365386963e-10
        return Double(n) * 2.3283064365386963e-10
    }

    private func nDouble(_ x: UInt32) -> Double { Double(x) }

    /// JS `x >>> 0` —— Number 转 uint32（mod 2^32，无符号）。
    static func toUInt32(_ x: Double) -> UInt32 {
        if !x.isFinite { return 0 }
        let trunc = x.rounded(.towardZero)
        var mod = trunc.truncatingRemainder(dividingBy: 4_294_967_296.0)
        if mod < 0 { mod += 4_294_967_296.0 }
        return UInt32(mod)
    }

    /// 同上但保留为 double（避免不必要的 UInt32 round-trip 精度损失）。
    static func toUInt32D(_ x: Double) -> Double {
        if !x.isFinite { return 0 }
        let trunc = x.rounded(.towardZero)
        var mod = trunc.truncatingRemainder(dividingBy: 4_294_967_296.0)
        if mod < 0 { mod += 4_294_967_296.0 }
        return mod
    }
}
