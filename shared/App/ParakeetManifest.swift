import Foundation

// Pinned Hugging Face revision; hashes are SHA-256 (LFS) or Git blob SHA-1.
enum ParakeetManifest {
    static let revision = "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"
    struct File: Sendable {
        let path: String
        let size: Int64
        let hash: String
        let sha256: Bool
    }
    static let files: [File] = [
        File(
            path: "Decoder.mlmodelc/analytics/coremldata.bin", size: 243,
            hash: "4238c4e81ecd0dc94bd7dfbb60f7e2cc824107c1ffe0387b8607b72833dba350", sha256: true),
        File(
            path: "Decoder.mlmodelc/coremldata.bin", size: 554,
            hash: "18647af085d87bd8f3121c8a9b4d4564c1ede038dab63d295b4e745cf2d7fb99", sha256: true),
        File(
            path: "Decoder.mlmodelc/metadata.json", size: 3427, hash: "781350d40ed83511afc3bc31a804e6a543e69d04",
            sha256: false),
        File(
            path: "Decoder.mlmodelc/model.mil", size: 13110, hash: "95328ba81ca8dceb16c039e62f1a7d447ede43c2",
            sha256: false),
        File(
            path: "Decoder.mlmodelc/weights/weight.bin", size: 23_604_992,
            hash: "48adf0f0d47c406c8253d4f7fef967436a39da14f5a65e66d5a4b407be355d41", sha256: true),
        File(
            path: "Encoder_v2.mlmodelc/analytics/coremldata.bin", size: 243,
            hash: "af98d71151609799efbbffc00112fcba4bd91adf0b01135a982c574e91822f9c", sha256: true),
        File(
            path: "Encoder_v2.mlmodelc/coremldata.bin", size: 478,
            hash: "70628bd4fd25fb554cc0cebc31356723930c885480132bf3ecd1b5dbe71dd0a2", sha256: true),
        File(
            path: "Encoder_v2.mlmodelc/model.mil", size: 1_002_653, hash: "af2fb4d2179bdff0eb165993269a8a40eeae6580",
            sha256: false),
        File(
            path: "Encoder_v2.mlmodelc/weights/weight.bin", size: 594_211_328,
            hash: "8d2c79e15a4545e08fe3a21fe741e42b8bf24329db81de8fdfacd92388ea5a66", sha256: true),
        File(
            path: "JointDecisionv3.mlmodelc/analytics/coremldata.bin", size: 243,
            hash: "26def4bf73dd56d29dee21c8ef97cb8969e62f6120ed1adc91e46828e2737b6c", sha256: true),
        File(
            path: "JointDecisionv3.mlmodelc/coremldata.bin", size: 521,
            hash: "f5fc08b741400f0088492c9e839418b1e18522f19cba28d361dd030c5f398342", sha256: true),
        File(
            path: "JointDecisionv3.mlmodelc/metadata.json", size: 3453,
            hash: "0461ef9e55ba8e8ba0d2cb33b6e1a031b0d481d7", sha256: false),
        File(
            path: "JointDecisionv3.mlmodelc/model.mil", size: 11775, hash: "0a80fde4b1ec61093a03fc0fc3431172db34a4d2",
            sha256: false),
        File(
            path: "JointDecisionv3.mlmodelc/weights/weight.bin", size: 12_642_764,
            hash: "4e0e63d840032f7f07ddb1d64446051166281e5491bf22da8a945c41f6eedb3e", sha256: true),
        File(
            path: "Preprocessor.mlmodelc/analytics/coremldata.bin", size: 243,
            hash: "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d", sha256: true),
        File(
            path: "Preprocessor.mlmodelc/coremldata.bin", size: 486,
            hash: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d", sha256: true),
        File(
            path: "Preprocessor.mlmodelc/metadata.json", size: 2841, hash: "06162c58cf2f5343a0e60f36f843bcdf3cc58527",
            sha256: false),
        File(
            path: "Preprocessor.mlmodelc/model.mil", size: 28181, hash: "f987e2479228436c49189aa47edb376db74dcff5",
            sha256: false),
        File(
            path: "Preprocessor.mlmodelc/weights/weight.bin", size: 491072,
            hash: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea", sha256: true),
        File(
            path: "parakeet_vocab.json", size: 151122, hash: "c684822ec3b671ebc449c433a7012398d39b8bb0", sha256: false),
    ]
    static var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}
