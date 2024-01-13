/// A (stateful) binary decoder.
struct Ocp1DecoderImpl: Decoder {
    private let state: Ocp1DecodingState

    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    let count: Int?

    init(state: Ocp1DecodingState, codingPath: [any CodingKey], count: Int? = nil) {
        self.state = state
        self.codingPath = codingPath
        self.count = count
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
        where Key: CodingKey
    {
        .init(KeyedOcp1DecodingContainer(state: state, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        UnkeyedOcp1DecodingContainer(state: state, codingPath: codingPath, count: count)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleValueOcp1DecodingContainer(state: state, codingPath: codingPath)
    }
}
