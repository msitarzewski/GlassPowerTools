import Foundation

enum Vectors {
    static let prime = "ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b139b22514a08798e3404ddef9519b3cd3a431b302b0a6df25f14374fe1356d6d51c245e485b576625e7ec6f44c42e9a637ed6b0bff5cb6f406b7edee386bfb5a899fa5ae9f24117c4b1fe649286651ece65381ffffffffffffffff"
    static let clientPrivate = "9056fdeb9d1103de4534afadb3431938a431df801927327f74a3f1628bc9638d9056fdeb9d1103de4534afadb3431938a431df801927327f74a3f1628bc9638d9056fdeb9d1103de4534afadb3431938a431df801927327f74a3f1628bc9638d9056fdeb9d1103de4534afadb3431938a431df801927327f74a3f1628bc9638d"
    static let serverPublic = "299882392f064762acc7cad9f6275d1144d5cdadc25fb05650925f7e96957906e9a40da2411099e8ba952d84b15d2891d582b9397770f7049eb76a1041819f06d2dfd617dcf64e99b014d2ce502658215d40dc2a2a35750fe18eba0e5145db313428afe3e7e07859c5816b0ade8641f4cc9a322242a512d0ca7e3291c8da0519"
    static let clientPublic = "3c87db5a309bad545162501f68ebadd52b4e90fec9fe4ec21968f601db79403f42d75c1a40f69eb0c7492d9d5a73721e9990158d0e9f3ee39f866d83f635f8da638bc67445e2735519d095693f9149e4ccf5266ae59126ee852d4f9b90cdc346496a5c3e39c292fe7a15948274c016412a49ea9c4e78e8bb2ea3a658c20220d8"
    static let shared = "9e4cfedbe1fb057a7bf694fbe016907482ac1c793e8cc42e75c25534ce82d5d02a3631153b74410cceecdcf24ed3a95b1ebba07b6c04822d498148f937ca16c61c8e139f6853f6cd39922293a629aa02cf30c24818c4cc1e0fde482009cd5df673991c60fcba766d47474b47d1f4387baf760addfe1665addabad5a41dec1634"
    static let aesKeyMD5 = "f37c02c9aa2988cf01bfb28dbd19192d"
    static let zrle1 = "789c6264646206000000ffff"
    static let zrle2 = "62e21291d330b2618082ff50d0c0cec1c90d000000ffff"
    static let zlibRaw = "789c626462666061656360e7e064e0e2e66100000000ffff"
    static let midModulus: UInt64 = 2305843009213693951
    static let midBase: UInt64 = 123456789
    static let midExponent: UInt64 = 987654321
    static let midResult: UInt64 = 50357601586279104
}

func hexBytes(_ hex: String) -> [UInt8] {
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        bytes.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return bytes
}

func bigEndianBytes(_ value: UInt64) -> [UInt8] {
    var bytes: [UInt8] = []
    var v = value
    while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
    return bytes.isEmpty ? [0] : bytes
}

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
