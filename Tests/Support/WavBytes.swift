import Foundation

/// Little-endian 32-bit read, for walking WAV chunk headers by hand. The point
/// of the byte-level assertions is the stored file itself, so no `AVAudioFile`.
func le32(_ data: Data, at offset: Int) -> Int {
    Int(data[offset]) | Int(data[offset + 1]) << 8
        | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
}
